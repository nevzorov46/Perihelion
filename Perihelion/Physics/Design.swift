/// Puzzles that are solvable by construction.
///
/// Instead of placing motes and hoping a path exists, fire a shot, keep it if its
/// path is interesting, and drop the motes onto that path. The shot that made the
/// level is its proof of solvability.
///
/// Then measure how hard it is to *find*: re-fire the shot with the error a hand
/// makes (half a degree of aim, a percent of power) and count how many of those
/// still collect everything. That fraction is the difficulty.
enum Design {
    static let windowAngleStep = 0.008  // rad
    static let windowSpeedStep = 0.012  // relative

    struct Brief {
        var motes: Int
        var tries = 400
        var aim = 0.0
        var spread: Double
        var minSpeed = 260.0
        var maxSpeed = 680.0
        var minTime = 2.0
        var maxTime = 9.0
        var minLength = 900.0
        var maxLength: Double?
        var firstGap = 170.0
        var minTurn: Double
        var maxTurn: Double
        var minWindow: Double
        var maxWindow = 1.0
    }

    struct Result {
        let shot: Shot
        let motes: [SIMD2<Double>]
        /// Total turning of the path, radians.
        let turn: Double
        let length: Double
        let window: Double
    }

    /// Fraction of a 5×5 grid of near-miss shots (centre excluded) that still win.
    static func measureWindow(_ level: Level, _ shot: Shot) -> Double {
        var wins = 0, total = 0
        for i in -2...2 {
            for j in -2...2 where !(i == 0 && j == 0) {
                total += 1
                let nudged = Shot(angle: shot.angle + Double(i) * windowAngleStep,
                                  speed: shot.speed * (1 + Double(j) * windowSpeedStep))
                if Flight.run(level, nudged).isComplete { wins += 1 }
            }
        }
        return Double(wins) / Double(total)
    }

    static func design(_ level: Level, brief: Brief, random: inout SeededRandom) -> Result? {
        for _ in 0..<brief.tries {
            let shot = Shot(angle: brief.aim + (random.next() * 2 - 1) * brief.spread,
                            speed: brief.minSpeed + (brief.maxSpeed - brief.minSpeed) * random.next())
            if let result = attempt(level, shot, brief: brief, random: &random) { return result }
        }
        return nil
    }

    static func attempt(_ level: Level, _ shot: Shot, brief: Brief, random: inout SeededRandom) -> Result? {
        let pad = 50.0
        var path: [SIMD2<Double>] = []
        path.reserveCapacity(Int(brief.maxTime / Sim.dt) + 2)
        var flight = Flight(level: level, shot: shot)
        path.append(flight.position)
        while flight.isFlying && flight.time < brief.maxTime {
            flight.step()
            path.append(flight.position)
        }

        var end = path.count - 1
        if case .crashed = flight.state { end = max(0, end - Int((0.15 / Sim.dt).rounded())) }
        for i in 1..<max(end + 1, 1) {
            let p = path[i]
            if p.x < pad || p.x > Sim.width - pad || p.y < pad || p.y > Sim.height - pad { end = i - 1; break }
        }
        guard Double(end) * Sim.dt >= brief.minTime else { return nil }

        // arc length, optionally capped
        var arc = [Double](repeating: 0, count: end + 1)
        var i = 1
        while i <= end {
            let dx = path[i].x - path[i - 1].x, dy = path[i].y - path[i - 1].y
            arc[i] = arc[i - 1] + (dx * dx + dy * dy).squareRoot()
            if let cap = brief.maxLength, arc[i] >= cap { end = i; break }
            i += 1
        }
        let length = arc[end]
        guard length >= brief.minLength else { return nil }

        // total turning: Σ|sin Δθ| over short chords (sqrt only, no atan2)
        var turn = 0.0
        let k = 12
        var c = k
        while c + k <= end {
            let ax = path[c].x - path[c - k].x, ay = path[c].y - path[c - k].y
            let bx = path[c + k].x - path[c].x, by = path[c + k].y - path[c].y
            let la = (ax * ax + ay * ay).squareRoot(), lb = (bx * bx + by * by).squareRoot()
            if la > 1e-9 && lb > 1e-9 { turn += abs(ax * by - ay * bx) / (la * lb) }
            c += k
        }
        guard turn >= brief.minTurn && turn <= brief.maxTurn else { return nil }

        // motes spread along the arc, the inner ones jittered
        let count = brief.motes
        let start = max(brief.firstGap, length * 0.14)
        let span = length - start
        var motes: [SIMD2<Double>] = []
        for j in 0..<count {
            var s = count == 1 ? length : start + span * Double(j) / Double(count - 1)
            if j > 0 && j < count - 1 { s += (random.next() * 2 - 1) * 0.16 * span / Double(count) }
            var lo = 0, hi = end
            while lo < hi {
                let mid = (lo + hi) / 2
                if arc[mid] < s { lo = mid + 1 } else { hi = mid }
            }
            motes.append(SIMD2((path[lo].x * 10).rounded() / 10, (path[lo].y * 10).rounded() / 10))
        }

        // readable layouts: clear of the launch, of each other, of fixed bodies
        let launch = level.launch
        for j in motes.indices {
            let m = motes[j]
            if squaredDistance(m, launch) < 130 * 130 { return nil }
            for q in 0..<j where squaredDistance(motes[q], m) < 95 * 95 { return nil }
            for body in level.bodies {
                guard case let .fixed(p) = body.path else { continue }
                let clear = body.radius + 34
                if squaredDistance(p, m) < clear * clear { return nil }
            }
        }

        let designed = level.withMotes(motes)
        guard Flight.run(designed, shot).isComplete else { return nil } // rounding moved a mote off the path
        let window = measureWindow(designed, shot)
        guard window >= brief.minWindow && window <= brief.maxWindow else { return nil }
        return Result(shot: shot, motes: motes, turn: turn, length: length, window: window)
    }

    private static func squaredDistance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
