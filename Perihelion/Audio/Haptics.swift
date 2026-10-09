import CoreHaptics
import OSLog

/// The taptic engine as a second instrument: every close pass is felt as well as heard.
@MainActor
final class Haptics {
    /// Off on the title screen: the attract loop shouldn't buzz in your hand.
    var isEnabled = true {
        didSet { if !isEnabled { releaseGravity(); humLatched = false } }
    }

    private var engine: CHHapticEngine?
    private var needsRestart = false
    private var hum: CHHapticAdvancedPatternPlayer?
    private var humLevel: Float = 0
    /// After the snap at perihelion the hum stays down until the pull fades, so it
    /// doesn't swell straight back up on the way out.
    private var humLatched = false

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.stoppedHandler = { [weak self] _ in self?.needsRestart = true }
            engine.resetHandler = { [weak self] in self?.needsRestart = true }
            try engine.start()
            self.engine = engine
        } catch {
            Logger(subsystem: "com.nevzorov.Perihelion", category: "Haptics").error("unavailable: \(error.localizedDescription)")
        }
    }

    func tick() {
        play([transient(0.25, 0.9)])
    }

    func launch(power: Float) {
        play([transient(0.35 + 0.4 * power, 0.5)])
    }

    /// A body at closest approach: heavier and closer is deeper and stronger.
    func pass(strength: Float, sharpness: Float) {
        play([transient(0.25 + 0.75 * strength, sharpness),
              continuous(0.3 * strength, sharpness * 0.5, at: 0.02, duration: 0.12 + 0.2 * Double(strength))])
    }

    /// A continuous rumble that follows the gravitational pull, 0 … 1. Parameters
    /// are only sent when the level moves noticeably, to stay off the haptic server.
    func gravity(_ level: Float) {
        guard isEnabled, let engine else { return }
        if humLatched {
            if level < 0.05 { humLatched = false }
            return
        }
        if level < 0.03 {
            if hum != nil { stopHum() }
            return
        }
        do {
            if hum == nil {
                if needsRestart { try engine.start(); needsRestart = false }
                let pattern = try CHHapticPattern(events: [continuous(1, 0.12, at: 0, duration: 30)], parameters: [])
                let player = try engine.makeAdvancedPlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                hum = player
                humLevel = -1
            }
            if abs(level - humLevel) > 0.04 {
                humLevel = level
                try hum?.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                                  value: 0.15 + 0.85 * level, relativeTime: 0)],
                                        atTime: CHHapticTimeImmediate)
            }
        } catch {
            needsRestart = true
            hum = nil
        }
    }

    /// Cut the hum at the closest point, so the pass lands as one sharp tap.
    func releaseGravity() {
        guard hum != nil else { return }
        stopHum()
        humLatched = true
    }

    private func stopHum() {
        try? hum?.stop(atTime: CHHapticTimeImmediate)
        hum = nil
        humLevel = 0
    }

    func collect() {
        play([transient(0.7, 1.0), transient(0.35, 1.0, at: 0.07)])
    }

    func crash() {
        play([transient(1.0, 0.15), continuous(0.6, 0.05, at: 0, duration: 0.3)])
    }

    func success() {
        play([transient(0.5, 0.8), transient(0.6, 0.8, at: 0.12), transient(0.8, 0.9, at: 0.24),
              continuous(0.35, 0.3, at: 0.3, duration: 0.5)])
    }

    private func transient(_ intensity: Float, _ sharpness: Float, at time: Double = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(intensity, 1)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: min(sharpness, 1)),
        ], relativeTime: time)
    }

    private func continuous(_ intensity: Float, _ sharpness: Float, at time: Double, duration: Double) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(intensity, 1)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: min(sharpness, 1)),
        ], relativeTime: time, duration: duration)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard isEnabled, let engine else { return }
        do {
            if needsRestart {
                try engine.start()
                needsRestart = false
            }
            try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: CHHapticTimeImmediate)
        } catch {
            needsRestart = true
        }
    }
}
