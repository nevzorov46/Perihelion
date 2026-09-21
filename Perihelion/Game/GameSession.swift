import CoreGraphics
import Foundation
import QuartzCore
import simd

struct TrailPoint {
    var position: SIMD2<Float>
    var speed: Float
}

struct Particle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var age: Float
    var life: Float
    var color: SIMD3<Float>
    var size: Float
}

struct Pulse {
    let body: Int
    let start: Double
    let strength: Float
}

/// A ring of distortion expanding from a close pass (drawn in the composite pass).
struct Shockwave {
    let center: SIMD2<Double>
    let start: Double
    let strength: Float
    static let life = 0.9
}

/// One play session: aiming, flying, rewinding, clearing.
///
/// Lives on the main thread and is advanced by the renderer's frame callback
/// (MTKView drives `draw(in:)` from the main run loop), so no locking. SwiftUI
/// never observes this object - only `HUDModel`, which changes a few times per
/// shot. Publishing per-frame state into SwiftUI would rebuild views 120 times a
/// second for text that changes once.
final class GameSession {
    let hud = HUDModel()
    let synth = Synth()
    let haptics = Haptics()
    let tail = CometTail()
    let playlist: [LevelDef]

    private(set) var levelIndex = 0
    private(set) var level: Level
    private(set) var transform = FieldTransform.zero
    private(set) var camera = Camera()
    private(set) var clock: Double = 0
    /// 0 in open space, rising toward 1 as the comet dives close to a mass.
    /// Time slows with it, and the picture flares.
    private(set) var slowness: Double = 0
    private(set) var completedAt: Double?
    private(set) var shockwaves: [Shockwave] = []
    /// A brief exposure kick at the tightest passes, decaying to 0.
    private(set) var flash: Double = 0
    /// Remaining freeze of simulated time after a hard pass (hit-stop).
    private var hitStop: Double = 0
    private var recordingEndsAt: Double?
    /// Where the bodies are drawn: the flight's time, or winding back to zero.
    private(set) var bodyTime: Double = 0

    private(set) var aim: Shot?
    private(set) var aimPower: Double = 0
    private(set) var prediction: [SIMD2<Float>] = []

    private(set) var flight: Flight?
    private(set) var cometVisible = false
    private(set) var trail: [TrailPoint] = []
    /// Previous attempts, oldest first.
    private(set) var ghosts: [[SIMD2<Float>]] = []
    /// Chosen at launch with `-style`; the game ships in `.observatory`.
    let style = VisualStyle.launchArgument ?? .observatory
    private(set) var trailOpacity: Float = 1
    private(set) var collectedAt: [Double?] = []
    private(set) var pulses: [Pulse] = []
    private(set) var particles: [Particle] = []
    var isRewinding: Bool { rewind != nil }

    private struct Drag {
        let start: CGPoint
        var samples: [(time: CFTimeInterval, point: CGPoint)]
    }

    private static let deadZone: CGFloat = 12
    private var drag: Drag?
    private var lastPowerTick = 0
    private var accumulator = 0.0
    private var shots = 0
    private var endedAt: Double?
    private var failureDelay = 0.6
    private var layoutInsets = (size: CGSize.zero, top: CGFloat(0), bottom: CGFloat(0))
    private var shakeEnergy = 0.0
    private var shakePhase = 0.0
    private var tailPositions: [SIMD2<Double>] = []
    // camera springs
    private var focusVelocity = SIMD2<Double>.zero
    private var zoomVelocity = 0.0
    private var lead = SIMD2<Double>.zero
    private var leadVelocity = SIMD2<Double>.zero
    private var easedSlowness = 0.0
    private var easedSlownessVelocity = 0.0
    private var rewind: (start: Double, from: Double)?
    private var toastUntil: Double?

    /// `-demo YES` fires each level's proof shot by itself - for recordings and checks.
    private let isDemo = UserDefaults.standard.bool(forKey: "demo")
    /// The title screen's live background: the game plays its own showcase skies.
    private(set) var isAttract = false
    private var attractCursor = 0
    private static let showcase = ["three-body", "binary", "event-horizon", "orrery", "slingshot"]
    /// The player's own mute, restored when leaving the title screen.
    private var userMuted = false
    let progress = Progress()
    /// How close the camera pulls in during flight, and whether it tracks the comet.
    /// Still being tuned: `-zoom 1.3 -follow NO` tries other settings for one launch.
    private let flightZoom = UserDefaults.standard.string(forKey: "zoom").flatMap(Double.init) ?? 1.15
    private let followsComet = UserDefaults.standard.string(forKey: "follow").map { ["YES", "1", "true"].contains($0) } ?? true
    private var demoStart: Double?

    init(playlist: [LevelDef]) {
        precondition(!playlist.isEmpty)
        self.playlist = playlist
        level = Level(playlist[0])
        hud.style = style
        load(0)
    }

    func start() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "mute") {
            synth.isMuted = true
            userMuted = true
            hud.muted = true
        }
        synth.start()
        // `-recordAudio YES [-recordSeconds 120]`: the soundtrack of a footage run,
        // written to Documents/perihelion.wav and closed cleanly when time is up
        if defaults.bool(forKey: "recordAudio"),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            synth.startRecording(to: documents.appendingPathComponent("perihelion.wav"))
            recordingEndsAt = defaults.string(forKey: "recordSeconds").flatMap(Double.init) ?? 120
        }
    }

    func layout(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        layoutInsets = (size, safeTop + 92, safeBottom + 64)
        transform = FieldTransform(viewSize: size, topInset: layoutInsets.top, bottomInset: layoutInsets.bottom, camera: camera)
        updateLabels()
    }

    private func updateLabels() {
        guard style == .atlas, transform.viewSize.width > 0 else {
            if !hud.labels.isEmpty { hud.labels = [] }
            return
        }
        var labels: [BodyLabel] = []
        var suns = 0
        let starCount = level.bodies.filter { $0.kind == .star }.count
        for (i, body) in level.bodies.enumerated() {
            guard case let .fixed(p) = body.path else { continue }
            let name: String
            switch body.kind {
            case .star:
                suns += 1
                name = starCount > 1 ? "SOL \(suns == 1 ? "I" : suns == 2 ? "II" : "III")" : "SOL"
            case .planet: name = "PLANETA"
            case .moon: name = "LVNA"
            case .hole: name = "VORAGO"
            }
            let screen = transform.toScreen(p)
            let reach = CGFloat(body.radius * (body.kind == .star ? 3.6 : 1.6) * transform.scale)
            labels.append(BodyLabel(id: i, text: name, point: CGPoint(x: screen.x, y: screen.y + reach + 10)))
        }
        let launch = transform.toScreen(level.launch)
        labels.append(BodyLabel(id: -1, text: "COMETA", point: CGPoint(x: launch.x, y: launch.y + 30)))
        hud.labels = labels
    }

    // MARK: - Levels

    func load(_ index: Int) {
        levelIndex = index
        level = Level(playlist[index])
        shots = 0
        flight = nil
        cometVisible = false
        trail = []
        ghosts = []
        trailOpacity = 1
        prediction = []
        aim = nil
        drag = nil
        collectedAt = Array(repeating: nil, count: level.motes.count)
        pulses = []
        particles = []
        endedAt = nil
        completedAt = nil
        rewind = nil
        bodyTime = 0
        slowness = 0
        tail.reset()
        shockwaves = []
        flash = 0
        hitStop = 0
        easedSlowness = 0
        easedSlownessVelocity = 0
        camera = Camera()
        focusVelocity = .zero
        zoomVelocity = 0
        lead = .zero
        leadVelocity = .zero
        demoStart = nil

        // the sky's place in the whole campaign, not in whatever subset is being played
        hud.levelNumber = (LevelDef.campaign.firstIndex { $0.id == level.def.id } ?? index) + 1
        hud.levelName = level.def.name
        hud.hint = level.def.hint
        hud.hintVisible = true
        hud.moteCount = level.motes.count
        hud.collected = 0
        hud.shots = 0
        hud.toast = nil
        hud.cleared = false
        hud.isLastLevel = index == playlist.count - 1
        updateLabels()
    }

    func nextLevel() {
        load((levelIndex + 1) % playlist.count)
    }

    /// Title screen: loop the showcase skies, quietly, without haptics.
    func enterAttract() {
        isAttract = true
        haptics.isEnabled = false
        synth.volume = 0.35
        loadShowcase()
    }

    /// Leave the title screen and play sky `index`.
    func play(_ index: Int) {
        isAttract = false
        haptics.isEnabled = true
        synth.volume = 1
        synth.isMuted = userMuted
        hud.muted = userMuted
        load(min(max(index, 0), playlist.count - 1))
    }

    private func loadShowcase() {
        let ids = Self.showcase
        for step in 0..<ids.count {
            let id = ids[(attractCursor + step) % ids.count]
            if let index = playlist.firstIndex(where: { $0.id == id }) {
                attractCursor = (attractCursor + step + 1) % ids.count
                load(index)
                return
            }
        }
        load(0)
    }

    func restartLevel() {
        load(levelIndex)
    }

    func toggleMute() {
        synth.isMuted.toggle()
        userMuted = synth.isMuted
        hud.muted = synth.isMuted
    }

    // MARK: - Touch

    func touchBegan(at point: CGPoint) {
        if flight != nil { beginRewind() } // abort a flight, or leave a cleared one
        drag = Drag(start: point, samples: [(CACurrentMediaTime(), point)])
        lastPowerTick = 0
    }

    func touchMoved(to point: CGPoint) {
        guard var current = drag else { return }
        current.samples.append((CACurrentMediaTime(), point))
        if current.samples.count > 24 { current.samples.removeFirst() }
        drag = current
        updateAim(pull: pull(from: current.start, to: point))
    }

    func touchEnded(at point: CGPoint) {
        guard let current = drag else { return }
        drag = nil
        // A finger drifts as it lifts. Aim where it rested a moment before release.
        let now = CACurrentMediaTime()
        let resting = current.samples.last(where: { now - $0.time >= 0.05 })?.point ?? point
        let restingPull = pull(from: current.start, to: resting)
        updateAim(pull: hypot(restingPull.dx, restingPull.dy) >= Self.deadZone ? restingPull : pull(from: current.start, to: point))
        if let aim { launch(aim) }
        aim = nil
        prediction = []
    }

    func touchCancelled() {
        drag = nil
        aim = nil
        prediction = []
    }

    private func pull(from start: CGPoint, to point: CGPoint) -> CGVector {
        CGVector(dx: start.x - point.x, dy: start.y - point.y)
    }

    private var fullPull: CGFloat {
        min(max(transform.viewSize.width * 0.45, 140), 240)
    }

    private func updateAim(pull: CGVector) {
        let length = hypot(pull.dx, pull.dy)
        guard length >= Self.deadZone else {
            aim = nil
            prediction = []
            return
        }
        let direction = transform.worldDirection(pull)
        let power = min(Double((length - Self.deadZone) / fullPull), 1)
        let shot = Shot(angle: atan2(direction.y, direction.x),
                        speed: Sim.minSpeed + (Sim.maxSpeed - Sim.minSpeed) * power)
        setAim(shot, power: power)
        let tick = Int(power * 10)
        if tick != lastPowerTick {
            lastPowerTick = tick
            haptics.tick()
        }
    }

    private func setAim(_ shot: Shot, power: Double) {
        aim = shot
        aimPower = power
        var preview = Flight(level: level, shot: shot)
        var points: [SIMD2<Float>] = []
        let steps = Int(level.def.preview / Sim.dt)
        var i = 0
        while i < steps && preview.isFlying {
            preview.step()
            if i % 10 == 0 { points.append(SIMD2<Float>(preview.position)) }
            i += 1
        }
        prediction = points
    }

    // MARK: - Flight

    private func keepGhost() {
        guard trail.count > 1 else { return }
        ghosts.append(trail.map(\.position))
        if ghosts.count > 6 { ghosts.removeFirst() }
    }

    private func launch(_ shot: Shot) {
        if rewind == nil { keepGhost() }
        rewind = nil
        trail = [TrailPoint(position: SIMD2<Float>(level.launch), speed: Float(shot.speed))]
        trailOpacity = 1
        collectedAt = Array(repeating: nil, count: level.motes.count)
        flight = Flight(level: level, shot: shot, recordsEvents: true)
        cometVisible = true
        accumulator = 0
        endedAt = nil
        completedAt = nil
        bodyTime = 0
        shots += 1

        hud.shots = shots
        hud.hintVisible = false
        hud.collected = 0
        hud.cleared = false
        hud.toast = nil

        let power = Float((shot.speed - Sim.minSpeed) / (Sim.maxSpeed - Sim.minSpeed))
        synth.play(.whoosh, midi: 60, velocity: 0.3 + 0.5 * power)
        haptics.launch(power: power)
    }

    private func beginRewind() {
        keepGhost()
        rewind = (clock, bodyTime)
        flight = nil
        cometVisible = false
        endedAt = nil
        completedAt = nil
        collectedAt = Array(repeating: nil, count: level.motes.count)
        hud.cleared = false
        hud.collected = 0
    }

    func advance(dt: Double) {
        clock += dt
        if let end = recordingEndsAt, clock >= end {
            synth.stopRecording()
            recordingEndsAt = nil
        }
        updateSlowness(dt: dt)

        if var current = flight {
            if current.isFlying {
                // a hard pass freezes simulated time for a beat; the world keeps glowing
                if hitStop > 0 {
                    hitStop -= dt
                } else {
                    accumulator += dt * timeScale
                }
                var budget = 96
                while accumulator >= Sim.dt && current.isFlying && budget > 0 {
                    current.step()
                    accumulator -= Sim.dt
                    budget -= 1
                    if current.steps % 3 == 0 || !current.isFlying {
                        let v = current.velocity
                        trail.append(TrailPoint(position: SIMD2<Float>(current.position),
                                                speed: Float((v.x * v.x + v.y * v.y).squareRoot())))
                    }
                }
                if budget == 0 { accumulator = 0 } // fell behind: drop time rather than spiral
                let events = current.events
                current.events.removeAll(keepingCapacity: true)
                bodyTime = current.time
                flight = current
                for event in events { handle(event, in: current) }
                if !current.isFlying && endedAt == nil { endedAt = clock }
            }
            if let completedAt, !hud.cleared, clock - completedAt > 1.6 {
                hud.cleared = true
            }
            if let endedAt, completedAt == nil, clock - endedAt > failureDelay {
                beginRewind()
            }
        }

        if let rewind {
            let p = min((clock - rewind.start) / 0.55, 1)
            let eased = p * p * (3 - 2 * p)
            bodyTime = rewind.from * (1 - eased)
            trailOpacity = Float(1 - eased)
            if p >= 1 {
                self.rewind = nil
                trail = []
                trailOpacity = 1
                bodyTime = 0
            }
        }

        if let toastUntil, clock > toastUntil {
            hud.toast = nil
            self.toastUntil = nil
        }
        updateParticles(Float(dt))
        updateTail(dt: dt)
        updateClimax(dt: dt)
        pulses.removeAll { clock - $0.start > 1.4 }
        updateCamera(dt: dt)
        if isDemo || isAttract { runDemo() }
    }

    private func handle(_ event: FlightEvent, in current: Flight) {
        switch event {
        case let .perihelion(body, _, pull, _):
            let b = level.bodies[body]
            let strength = Float(min(max(log10(pull / Sim.perihelionPull) / 1.6, 0.12), 1))
            synth.play(.bell, midi: Music.midi(root: level.def.root, degree: Music.bodyDegree(b, index: body)),
                       velocity: 0.35 + 0.65 * strength, pan: pan(current.bodyPositions[body]))
            haptics.releaseGravity()
            haptics.pass(strength: strength, sharpness: b.kind == .planet || b.kind == .moon ? 0.55 : 0.2)
            pulses.append(Pulse(body: body, start: clock, strength: strength))
            if strength > 0.3 {
                // the climax: space rings out from the body, the frame flares, time catches its breath
                shockwaves.append(Shockwave(center: current.bodyPositions[body], start: clock, strength: strength))
                if shockwaves.count > Int(PH_MAX_WAVES) { shockwaves.removeFirst() }
                flash = max(flash, Double(strength))
                if strength > 0.45 { hitStop = 0.04 + 0.09 * Double(strength) }
            }

        case let .collect(mote, order):
            collectedAt[mote] = clock
            let p = level.motes[mote]
            synth.play(.chime, midi: Music.midi(root: level.def.root, degree: Music.moteDegree(order: order)),
                       velocity: 0.75, pan: pan(p))
            haptics.collect()
            burst(at: p, color: Palette.mote, count: 26, speed: 110, life: 0.9, size: 7)
            hud.collected = order + 1

        case .complete:
            completedAt = clock
            if !isAttract { progress.record(level.def.id, shots: shots) }
            for (i, degree) in Music.resolution.enumerated() {
                synth.play(.chime, midi: Music.midi(root: level.def.root, degree: degree), velocity: 0.5,
                           pan: Float(i) * 0.3 - 0.45, delay: 0.3 + Float(i) * 0.12)
            }
            haptics.success()

        case let .crash(body, position):
            cometVisible = false
            let b = level.bodies[body]
            burst(at: position, color: Palette.bodyColor(b) * 1.5 + 0.3, count: 48, speed: 190, life: 1.2, size: 6)
            if completedAt == nil {
                synth.play(.thud, midi: 36, velocity: 1)
                haptics.crash()
                shakeEnergy = 1
                failureDelay = 1.0
                showToast(Self.crashMessage(b.kind))
            }

        case .escape:
            cometVisible = false
            if completedAt == nil {
                failureDelay = 0.45
                showToast("Lost to the dark")
            }

        case .timeout:
            if completedAt == nil {
                failureDelay = 0.3
                showToast("Out of time")
            }
        }
    }

    private static func crashMessage(_ kind: BodyKind) -> String {
        switch kind {
        case .star: return "Burned up in the star"
        case .planet: return "Crashed into the planet"
        case .moon: return "Hit the moon"
        case .hole: return "Swallowed by the dark"
        }
    }

    private func showToast(_ text: String) {
        hud.toast = text
        toastUntil = clock + 1.8
    }

    private func pan(_ p: SIMD2<Double>) -> Float {
        guard transform.viewSize.width > 0 else { return 0 }
        return Float(transform.toScreen(p).x / transform.viewSize.width) * 2 - 1
    }

    // MARK: - Camera and time

    private func updateSlowness(dt: Double) {
        var target = 0.0
        if let current = flight, current.isFlying, completedAt == nil {
            var pull = 0.0
            for i in level.bodies.indices {
                let d = current.bodyPositions[i] - current.position
                pull = max(pull, level.bodies[i].mu / (d.x * d.x + d.y * d.y + 1))
            }
            let x = min(max((pull - 900) / (5200 - 900), 0), 1)
            target = x * x * (3 - 2 * x)
        }
        slowness += (target - slowness) * (1 - exp(-dt * 7))
    }

    /// Whole field while aiming; close behind the comet in flight; back out to
    /// reveal the full path once the sky is cleared.
    ///
    /// Everything the camera follows is itself smoothed - the comet's heading and
    /// the slow-motion amount - so a hairpin turn around a star doesn't whip the
    /// view around with it.
    private func updateCamera(dt: Double) {
        let center = SIMD2(Sim.width / 2, Sim.height / 2)
        Smoothing.damp(&easedSlowness, &easedSlownessVelocity, target: slowness, time: 1.0, dt: dt)

        var zoomTarget = 1.0
        var focusTarget = center
        if isAttract {
            // the title screen: the whole sky, held still, above the controls
            finishCamera(zoomTarget: 1, focusTarget: center, dt: dt)
            return
        }
        if let current = flight, current.isFlying, completedAt == nil, rewind == nil {
            zoomTarget = flightZoom + 0.07 * easedSlowness
            guard followsComet else {
                // holding still means holding the whole field, so nothing flies off-screen
                finishCamera(zoomTarget: min(zoomTarget, 1), focusTarget: center, dt: dt)
                return
            }
            Smoothing.damp(&lead, &leadVelocity, target: current.velocity * 0.18, time: 0.5, dt: dt)
            var look = lead
            let reach = (look.x * look.x + look.y * look.y).squareRoot()
            if reach > 160 { look *= 160 / reach }
            focusTarget = center + (current.position + look - center) * 0.6
        } else {
            lead = .zero
            leadVelocity = .zero
        }

        let half = transform.visibleHalfExtent(zoom: zoomTarget)
        // the camera may look past the field's edge - the sky continues there, and
        // a hard stop at the border would freeze the pan whenever the field nearly fits
        func clamp(_ v: Double, half: Double, extent: Double) -> Double {
            let low = half - 200, high = extent - half + 200
            return low > high ? extent / 2 : min(max(v, low), high)
        }
        focusTarget.x = clamp(focusTarget.x, half: half.along, extent: Sim.width)
        focusTarget.y = clamp(focusTarget.y, half: half.across, extent: Sim.height)
        finishCamera(zoomTarget: zoomTarget, focusTarget: focusTarget, dt: dt)
    }

    private func finishCamera(zoomTarget: Double, focusTarget: SIMD2<Double>, dt: Double) {
        Smoothing.damp(&camera.zoom, &zoomVelocity, target: zoomTarget, time: 0.95, dt: dt)
        Smoothing.damp(&camera.focus, &focusVelocity, target: focusTarget, time: 0.8, dt: dt)

        // a decaying wobble, not white noise: it reads as an impact rather than a glitch
        shakeEnergy *= exp(-dt * 6)
        if shakeEnergy > 0.01 {
            shakePhase += dt * 34
            let amplitude = 7 * shakeEnergy
            camera.shake = CGVector(dx: amplitude * sin(shakePhase), dy: amplitude * sin(shakePhase * 0.73 + 1.7))
        } else {
            camera.shake = .zero
        }
        // on the title screen the sky sits in the upper part, clear of the buttons
        let bottom = layoutInsets.bottom + (isAttract ? 250 : 0)
        transform = FieldTransform(viewSize: layoutInsets.size, topInset: layoutInsets.top,
                                   bottomInset: bottom, camera: camera)
    }

    /// How fast simulated time runs against the clock: slower near a mass.
    var timeScale: Double { 1 - 0.62 * slowness }

    private func updateClimax(dt: Double) {
        flash *= exp(-dt * 5)
        shockwaves.removeAll { clock - $0.start > Shockwave.life }
        // the pull, felt: a hum that swells as the comet dives in and snaps off at the closest point
        var level: Float = 0
        if let current = flight, current.isFlying, cometVisible, completedAt == nil {
            var pull = 0.0
            for i in self.level.bodies.indices {
                let d = current.bodyPositions[i] - current.position
                pull = max(pull, self.level.bodies[i].mu / (d.x * d.x + d.y * d.y + 1))
            }
            let x = Float(min(max((pull - 700) / (6000 - 700), 0), 1))
            level = x * x
        }
        haptics.gravity(level)
    }

    private func updateTail(dt: Double) {
        let emitting = flight.map { $0.isFlying && cometVisible } ?? false
        if let current = flight {
            tailPositions = current.bodyPositions
        } else {
            if tailPositions.count != level.bodies.count {
                tailPositions = Array(repeating: .zero, count: level.bodies.count)
            }
            level.positions(at: bodyTime, into: &tailPositions)
        }
        tail.update(dt: Float(dt * timeScale),
                    comet: emitting ? flight.map { ($0.position, $0.velocity) } : nil,
                    bodies: level.bodies, positions: tailPositions,
                    ageRate: rewind == nil ? 1 : 4)
    }

    // MARK: - Particles

    private func burst(at p: SIMD2<Double>, color: SIMD3<Float>, count: Int, speed: Float, life: Float, size: Float) {
        for _ in 0..<count {
            let angle = Float.random(in: 0..<(2 * .pi))
            let v = speed * Float.random(in: 0.25...1)
            particles.append(Particle(position: SIMD2<Float>(p), velocity: SIMD2(cos(angle), sin(angle)) * v,
                                      age: 0, life: life * Float.random(in: 0.5...1), color: color,
                                      size: size * Float.random(in: 0.6...1.3)))
        }
        if particles.count > 600 { particles.removeFirst(particles.count - 600) }
    }

    private func updateParticles(_ dt: Float) {
        var i = 0
        while i < particles.count {
            particles[i].age += dt
            if particles[i].age >= particles[i].life {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
                continue
            }
            particles[i].position += particles[i].velocity * dt
            particles[i].velocity *= exp(-2.2 * dt)
            i += 1
        }
    }

    // MARK: - Demo

    private func runDemo() {
        guard let shot = level.def.shot else { return }
        if hud.cleared, let completedAt, clock - completedAt > 4 {
            if isAttract { loadShowcase() } else { nextLevel() }
            return
        }
        guard flight == nil, rewind == nil else { return }
        let start = demoStart ?? clock
        demoStart = start
        let t = clock - start
        guard t > 1 else { return }
        let p = min((t - 1) / 1.1, 1)
        let eased = p * p * (3 - 2 * p)
        let power = (shot.speed - Sim.minSpeed) / (Sim.maxSpeed - Sim.minSpeed) * eased
        setAim(Shot(angle: shot.angle, speed: Sim.minSpeed + (Sim.maxSpeed - Sim.minSpeed) * power), power: power)
        if t > 2.6 {
            launch(shot)
            aim = nil
            prediction = []
            demoStart = nil
        }
    }
}
