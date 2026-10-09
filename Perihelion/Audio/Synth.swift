import AVFoundation
import OSLog
import Synchronization

private let log = Logger(subsystem: "com.nevzorov.Perihelion", category: "Synth")

/// A tiny FM synth. Every sound is generated, nothing is sampled.
///
/// The render block runs on the audio thread, so the game never touches voice
/// state directly: it pushes commands into a single-producer/single-consumer ring
/// and the render block drains it at the top of each buffer. No locks and no
/// allocation on the audio thread.
@MainActor
final class Synth {
    enum Voice: Int32 {
        case bell = 0    // a body at closest approach
        case chime = 1   // a mote collected
        case whoosh = 2  // launch
        case thud = 3    // crash
    }

    var isMuted = false {
        didSet { applyVolume() }
    }

    /// Master level when not muted; the title screen plays quietly.
    var volume: Float = 1 {
        didSet { applyVolume() }
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = isMuted ? 0 : volume
    }

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var recording: RecordingSink?
    private let commands = CommandRing()
    private let bank = VoiceBank()
    private var isConfigured = false
    private var isRunning = false
    private var lastAttempt = -Double.infinity
    private var routeObserver: NSObjectProtocol?

    func start() {
        guard !isRunning else { return }
        lastAttempt = CACurrentMediaTime()
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("audio session unavailable: \(error.localizedDescription)")
        }
        if !isConfigured { configure() }
        do {
            try engine.start()
            isRunning = true
            log.notice("engine running")
        } catch {
            log.error("engine failed to start: \(error.localizedDescription)")
        }
    }

    private func configure() {
        // The output node can report 0 Hz before the route settles; the mixer
        // resamples, so any sane rate works for the source.
        let candidates = [engine.outputNode.outputFormat(forBus: 0).sampleRate, AVAudioSession.sharedInstance().sampleRate, 48_000]
        let sampleRate = candidates.first { $0 > 0 } ?? 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let commands = commands, bank = bank
        let rate = Float(sampleRate)
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            while let command = commands.pop() { bank.start(command) }
            bank.render(left: left, right: right, frames: Int(frameCount), sampleRate: rate)
            return noErr
        }
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 38
        engine.attach(source)
        engine.attach(reverb)
        engine.connect(source, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        // Headphones in or out, a call, a Bluetooth hop: the engine stops. Bring it back.
        routeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isRunning = false
                self?.start()
            }
        }
        isConfigured = true
    }

    /// Writes everything the synth plays to a 16-bit WAV, tapping before the main
    /// mixer so it records even while the game is muted. For editing footage:
    /// simulator screen recordings carry no sound.
    func startRecording(to url: URL) {
        guard isRunning, recording == nil else { return }
        let format = reverb.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            try? FileManager.default.removeItem(at: url)
            let file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            let sink = RecordingSink(file: file)
            recording = sink
            reverb.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                sink.write(buffer)
            }
            log.notice("recording audio to \(url.path)")
        } catch {
            log.error("audio recording failed: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard let sink = recording else { return }
        reverb.removeTap(onBus: 0)
        recording = nil
        sink.close()
        log.notice("audio recording closed")
    }

    /// `pan` is -1 (left) … 1 (right); `delay` in seconds.
    func play(_ voice: Voice, midi: Int, velocity: Float, pan: Float = 0, delay: Float = 0) {
        if !isRunning && CACurrentMediaTime() - lastAttempt > 3 { start() }
        guard isRunning else { return }
        _ = commands.push(SynthCommand(voice: voice.rawValue, frequency: Music.frequency(midi: midi),
                                       velocity: min(max(velocity, 0), 1), pan: min(max(pan, -1), 1), delay: delay))
    }
}

struct SynthCommand {
    var voice: Int32
    var frequency: Float
    var velocity: Float
    var pan: Float
    var delay: Float
}

/// Lock-free SPSC ring: the main thread only moves `head`, the audio thread only `tail`.
private final class CommandRing: @unchecked Sendable {
    private let capacity = 128
    private let storage: UnsafeMutablePointer<SynthCommand>
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)

    init() {
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: SynthCommand(voice: 0, frequency: 0, velocity: 0, pan: 0, delay: 0), count: capacity)
    }

    deinit {
        storage.deallocate()
    }

    func push(_ command: SynthCommand) -> Bool {
        let h = head.load(ordering: .relaxed)
        let next = (h + 1) % capacity
        if next == tail.load(ordering: .relaxed) { return false } // full: drop the note
        storage[h] = command
        head.store(next, ordering: .relaxed)
        return true
    }

    func pop() -> SynthCommand? {
        let t = tail.load(ordering: .relaxed)
        if t == head.load(ordering: .relaxed) { return nil }
        let command = storage[t]
        tail.store((t + 1) % capacity, ordering: .relaxed)
        return command
    }
}

/// Voice state lives in a fixed block of memory owned by the audio thread.
private final class VoiceBank: @unchecked Sendable {
    private struct State {
        var voice: Int32 = -1  // -1 = free
        var frequency: Float = 0
        var velocity: Float = 0
        var gainLeft: Float = 0
        var gainRight: Float = 0
        var delay: Float = 0
        var age: Float = 0
        var carrier: Float = 0
        var modulator: Float = 0
        var partial: Float = 0
        var low: Float = 0
        var band: Float = 0
    }

    private let count = 32
    private let states: UnsafeMutablePointer<State>
    private var noise: UInt32 = 0x9E37_79B9

    init() {
        states = .allocate(capacity: count)
        states.initialize(repeating: State(), count: count)
    }

    deinit {
        states.deallocate()
    }

    func start(_ command: SynthCommand) {
        // take a free voice, or steal the oldest
        var slot = 0
        var oldest: Float = -1
        for i in 0..<count {
            if states[i].voice < 0 { slot = i; oldest = .infinity; break }
            if states[i].age > oldest { oldest = states[i].age; slot = i }
        }
        let angle = (command.pan + 1) * .pi / 4 // equal-power pan
        states[slot] = State(voice: command.voice, frequency: command.frequency, velocity: command.velocity,
                             gainLeft: cos(angle), gainRight: sin(angle), delay: command.delay)
    }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int, sampleRate: Float) {
        let dt = 1 / sampleRate
        let twoPi = Float.pi * 2
        for n in 0..<frames {
            var l: Float = 0, r: Float = 0
            for i in 0..<count where states[i].voice >= 0 {
                var v = states[i]
                if v.delay > 0 {
                    v.delay -= dt
                    states[i] = v
                    continue
                }
                let t = v.age
                var sample: Float = 0
                var life: Float = 0
                switch v.voice {
                case 0: // bell: 2:1 FM with a decaying index, plus a faint inharmonic partial
                    let env = min(t / 0.004, 1) * exp(-t / 2.2)
                    let index = 2.4 * exp(-t / 0.3) * (0.5 + v.velocity)
                    sample = sin(twoPi * v.carrier + index * sin(twoPi * v.modulator)) * env
                    sample += sin(twoPi * v.partial) * 0.22 * exp(-t / 0.6) * env
                    v.carrier += v.frequency * dt
                    v.modulator += v.frequency * 2 * dt
                    v.partial += v.frequency * 2.76 * dt
                    life = 9
                case 1: // chime: glassy 3.5:1 FM that settles into a sine
                    let env = min(t / 0.002, 1) * exp(-t / 1.1)
                    let index = 1.6 * exp(-t / 0.08)
                    sample = sin(twoPi * v.carrier + index * sin(twoPi * v.modulator)) * env
                    sample += sin(twoPi * v.partial) * 0.3 * exp(-t / 0.4)
                    v.carrier += v.frequency * dt
                    v.modulator += v.frequency * 3.5 * dt
                    v.partial += v.frequency * 2 * dt
                    life = 5
                case 2: // whoosh: noise through a rising state-variable band-pass
                    noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5
                    let white = Float(noise) / Float(UInt32.max) * 2 - 1
                    let cutoff = 2 * sin(Float.pi * min(250 + 2400 * t / 0.45, 8000) / sampleRate)
                    v.low += cutoff * v.band
                    let high = white - v.low - 0.9 * v.band
                    v.band += cutoff * high
                    sample = v.band * sin(Float.pi * min(t / 0.45, 1)) * 0.9
                    life = 0.45
                default: // thud: a falling sine with a noisy knock
                    noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5
                    let white = Float(noise) / Float(UInt32.max) * 2 - 1
                    let pitch = 38 + 120 * exp(-t / 0.07)
                    v.carrier += pitch * dt
                    v.low += 0.08 * (white - v.low)
                    sample = sin(twoPi * v.carrier) * exp(-t / 0.4) + v.low * 3 * exp(-t / 0.06)
                    life = 1.4
                }
                if v.carrier > 1 { v.carrier -= v.carrier.rounded(.down) }
                if v.modulator > 1 { v.modulator -= v.modulator.rounded(.down) }
                if v.partial > 1 { v.partial -= v.partial.rounded(.down) }
                sample *= v.velocity
                l += sample * v.gainLeft
                r += sample * v.gainRight
                v.age += dt
                if v.age > life { v.voice = -1 }
                states[i] = v
            }
            left[n] = tanh(l * 0.3)
            right[n] = tanh(r * 0.3)
        }
    }
}

/// Owns the recording file and the single queue allowed to touch it.
///
/// `AVAudioFile` and `AVAudioPCMBuffer` are not `Sendable`, and the tap hands a
/// buffer over from the audio thread. The transfer is safe because the tap gives
/// up the buffer when it returns and every write happens on one serial queue,
/// which is not something the compiler can check, so it is spelled out here
/// rather than spread across the call site.
private final class RecordingSink: @unchecked Sendable {
    private let file: AVAudioFile
    private let queue = DispatchQueue(label: "perihelion.synth.recording")

    init(file: AVAudioFile) { self.file = file }

    func write(_ buffer: AVAudioPCMBuffer) {
        nonisolated(unsafe) let buffer = buffer
        queue.async { [file] in try? file.write(from: buffer) }
    }

    func close() {
        queue.sync { [file] in file.close() }
    }
}
