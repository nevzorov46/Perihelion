/// The simulation. Foundation-free and UI-free: the app and the command-line tools
/// compile this same file.
///
/// Integrator: kick-drift-kick leapfrog at a fixed 480 Hz. It is symplectic, so a
/// bound orbit keeps its energy instead of slowly spiralling in or out, and the
/// fixed step makes every shot exactly reproducible.
enum Sim {
    static let width = 1600.0
    static let height = 1000.0
    static let dt = 1.0 / 480
    static let maxTime = 16.0
    static let margin = 320.0
    static let minSpeed = 90.0
    static let maxSpeed = 780.0
    static let moteRadius = 22.0
    static let cometRadius = 4.0
    static let softening2 = 16.0
    /// An approach counts as a note when the body's pull exceeds this (units/s²).
    static let perihelionPull = 320.0
}

struct Shot {
    var angle: Double
    var speed: Double
}

struct LevelDef {
    let id: String
    let name: String
    let hint: String
    /// MIDI note the level's music is built on.
    let root: Int
    /// Seconds of trajectory the aiming preview reveals.
    let preview: Double
    let bodies: [BodySpec]
    let launch: SIMD2<Double>
    let motes: [SIMD2<Double>]
    /// A launch that collects every mote: the level's proof of solvability.
    let shot: Shot?
    /// Share of near-miss shots that still win (see Design.measureWindow).
    let window: Double
}

final class Level {
    let def: LevelDef
    let bodies: [Body]
    let motes: [SIMD2<Double>]
    var launch: SIMD2<Double> { def.launch }

    init(_ def: LevelDef, motes: [SIMD2<Double>]? = nil) {
        self.def = def
        self.bodies = BodySpec.expand(def.bodies)
        self.motes = motes ?? def.motes
    }

    func withMotes(_ motes: [SIMD2<Double>]) -> Level {
        Level(def, motes: motes)
    }

    func positions(at t: Double, into out: inout [SIMD2<Double>]) {
        for i in bodies.indices {
            switch bodies[i].path {
            case let .fixed(p):
                out[i] = p
            case let .orbit(parent, center, radius, phase, omega):
                let c = parent >= 0 ? out[parent] : center
                let a = phase + omega * t
                out[i] = SIMD2(c.x + radius * DMath.cos(a), c.y + radius * DMath.sin(a))
            case let .choreography(k, center, scale, tau, phase, cosR, sinR):
                let p = Choreography.position(body: k, at: t / tau + phase)
                let x = p.x * scale, y = p.y * scale
                out[i] = SIMD2(center.x + x * cosR - y * sinR, center.y + x * sinR + y * cosR)
            }
        }
    }
}

enum FlightState: Equatable {
    case flying
    case crashed(body: Int)
    case escaped
    case timedOut
}

enum FlightEvent {
    case crash(body: Int, position: SIMD2<Double>)
    case collect(mote: Int, order: Int)
    case complete
    /// Closest approach to a body - detected one step after it happens.
    case perihelion(body: Int, distance: Double, pull: Double, speed: Double)
    case escape
    case timeout
}

struct Flight {
    let level: Level
    let recordsEvents: Bool
    private(set) var position: SIMD2<Double>
    private(set) var velocity: SIMD2<Double>
    private(set) var steps = 0
    private(set) var state = FlightState.flying
    private(set) var collected: [Bool]
    private(set) var collectedCount = 0
    private(set) var completeTime: Double?
    var events: [FlightEvent] = []

    private(set) var bodyPositions: [SIMD2<Double>]
    private var acceleration = SIMD2<Double>.zero
    private var distance2: [Double]
    private var previous: [Double]
    private var previous2: [Double]

    var time: Double { Double(steps) * Sim.dt }
    var isFlying: Bool { state == .flying }
    var isComplete: Bool { completeTime != nil }

    init(level: Level, shot: Shot, recordsEvents: Bool = false) {
        self.level = level
        self.recordsEvents = recordsEvents
        position = level.launch
        velocity = SIMD2(shot.speed * DMath.cos(shot.angle), shot.speed * DMath.sin(shot.angle))
        collected = [Bool](repeating: false, count: level.motes.count)
        let n = level.bodies.count
        bodyPositions = [SIMD2<Double>](repeating: .zero, count: n)
        distance2 = [Double](repeating: 0, count: n)
        previous = distance2
        previous2 = distance2
        level.positions(at: 0, into: &bodyPositions)
        _ = gravity()
        previous = distance2
        previous2 = distance2
    }

    /// Sums the pull of every body; returns the index of a body we're inside, if any.
    private mutating func gravity() -> Int? {
        var ax = 0.0, ay = 0.0
        var hit: Int?
        let bodies = level.bodies
        for i in bodies.indices {
            let dx = bodyPositions[i].x - position.x
            let dy = bodyPositions[i].y - position.y
            let r2 = dx * dx + dy * dy
            distance2[i] = r2
            let reach = bodies[i].radius + Sim.cometRadius
            if r2 < reach * reach { hit = i }
            let s = r2 + Sim.softening2
            let k = bodies[i].mu / (s * s.squareRoot())
            ax += dx * k
            ay += dy * k
        }
        acceleration = SIMD2(ax, ay)
        return hit
    }

    mutating func step() {
        guard state == .flying else { return }
        let h = Sim.dt, hh = Sim.dt * 0.5
        velocity.x += acceleration.x * hh
        velocity.y += acceleration.y * hh
        position.x += velocity.x * h
        position.y += velocity.y * h
        steps += 1
        level.positions(at: time, into: &bodyPositions)
        let hit = gravity()
        velocity.x += acceleration.x * hh
        velocity.y += acceleration.y * hh

        if let hit {
            state = .crashed(body: hit)
            if recordsEvents { events.append(.crash(body: hit, position: position)) }
            return
        }

        let motes = level.motes
        for j in motes.indices where !collected[j] {
            let dx = motes[j].x - position.x, dy = motes[j].y - position.y
            if dx * dx + dy * dy < Sim.moteRadius * Sim.moteRadius {
                collected[j] = true
                collectedCount += 1
                if recordsEvents { events.append(.collect(mote: j, order: collectedCount - 1)) }
                if collectedCount == motes.count {
                    completeTime = time
                    if recordsEvents { events.append(.complete) }
                }
            }
        }

        if recordsEvents {
            for i in level.bodies.indices {
                let now = distance2[i], a = previous[i], b = previous2[i]
                if a < b && a <= now {
                    let pull = level.bodies[i].mu / a
                    if pull > Sim.perihelionPull {
                        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
                        events.append(.perihelion(body: i, distance: a.squareRoot(), pull: pull, speed: speed))
                    }
                }
                previous2[i] = a
                previous[i] = now
            }
        }

        if position.x < -Sim.margin || position.x > Sim.width + Sim.margin
            || position.y < -Sim.margin || position.y > Sim.height + Sim.margin {
            state = .escaped
            if recordsEvents { events.append(.escape) }
        } else if time >= Sim.maxTime {
            state = .timedOut
            if recordsEvents { events.append(.timeout) }
        }
    }

    /// Runs a shot until it ends or collects everything.
    static func run(_ level: Level, _ shot: Shot) -> Flight {
        var flight = Flight(level: level, shot: shot)
        while flight.isFlying && !flight.isComplete { flight.step() }
        return flight
    }
}
