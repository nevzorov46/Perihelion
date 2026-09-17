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
    let playlist: [LevelDef]

    private(set) var levelIndex = 0
    private(set) var level: Level
    private(set) var transform = FieldTransform.zero
    private(set) var clock: Double = 0
    /// Where the bodies are drawn: the flight's time, or winding back to zero.
    private(set) var bodyTime: Double = 0

    private(set) var aim: Shot?
    private(set) var aimPower: Double = 0
    private(set) var prediction: [SIMD2<Float>] = []

    private(set) var flight: Flight?
    private(set) var cometVisible = false
    private(set) var trail: [TrailPoint] = []
    private(set) var ghost: [SIMD2<Float>] = []
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
    private var completedAt: Double?
    private var failureDelay = 0.6
    private var rewind: (start: Double, from: Double)?
    private var toastUntil: Double?

    /// `-demo YES` fires each level's proof shot by itself - for recordings and checks.
    private let isDemo = UserDefaults.standard.bool(forKey: "demo")
    private var demoStart: Double?

    init(playlist: [LevelDef]) {
        precondition(!playlist.isEmpty)
        self.playlist = playlist
        level = Level(playlist[0])
        load(0)
    }

    func start() {
        synth.start()
    }

    func layout(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        transform = FieldTransform(viewSize: size, topInset: safeTop + 92, bottomInset: safeBottom + 64)
    }

    // MARK: - Levels

    func load(_ index: Int) {
        levelIndex = index
        level = Level(playlist[index])
        shots = 0
        flight = nil
        cometVisible = false
        trail = []
        ghost = []
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
        demoStart = nil

        hud.levelNumber = index + 1
        hud.levelName = level.def.name
        hud.hint = level.def.hint
        hud.hintVisible = true
        hud.moteCount = level.motes.count
        hud.collected = 0
        hud.shots = 0
        hud.toast = nil
        hud.cleared = false
        hud.isLastLevel = index == playlist.count - 1
    }

    func nextLevel() {
        load((levelIndex + 1) % playlist.count)
    }

    func restartLevel() {
        load(levelIndex)
    }

    func toggleMute() {
        synth.isMuted.toggle()
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

    private func launch(_ shot: Shot) {
        if !trail.isEmpty { ghost = trail.map(\.position) }
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
        if !trail.isEmpty { ghost = trail.map(\.position) }
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

        if var current = flight {
            if current.isFlying {
                accumulator += dt
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
        pulses.removeAll { clock - $0.start > 1.4 }
        if isDemo { runDemo() }
    }

    private func handle(_ event: FlightEvent, in current: Flight) {
        switch event {
        case let .perihelion(body, _, pull, _):
            let b = level.bodies[body]
            let strength = Float(min(max(log10(pull / Sim.perihelionPull) / 1.6, 0.12), 1))
            synth.play(.bell, midi: Music.midi(root: level.def.root, degree: Music.bodyDegree(b, index: body)),
                       velocity: 0.35 + 0.65 * strength, pan: pan(current.bodyPositions[body]))
            haptics.pass(strength: strength, sharpness: b.kind == .planet || b.kind == .moon ? 0.55 : 0.2)
            pulses.append(Pulse(body: body, start: clock, strength: strength))

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
            nextLevel()
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
