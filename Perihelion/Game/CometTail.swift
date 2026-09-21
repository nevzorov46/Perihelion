import Foundation
import simd

/// The dust tail as one continuous sheet, the way comet scientists draw it.
///
/// Every 1/40 s the nucleus releases a *column* of grains - one grain for each of
/// nine radiation-pressure ratios β, all starting at the nucleus with its
/// velocity. Each grain then falls around the star under gravity weakened by the
/// light pushing on it, g·(1 − β). Big grains (small β) stay on the comet's orbit,
/// fine ones are blown outward.
///
/// Stitch neighbouring grains together and the tail becomes a mesh: rows are
/// syndynes (one β, every age), columns are synchrones (one release time, every
/// β). That is the classical Finson-Probstein picture, and it is why the tail
/// reads as a smooth fan instead of a spray of dots. Columns released in bursts
/// come out brighter - the striae of Comet McNaught.
///
/// Ices sublimate faster near the star, so each column remembers how active the
/// comet was when it left: the tail flares at perihelion. Purely visual - none of
/// this feeds back into the physics.
final class CometTail {
    /// `-tailModel legacy` brings back the first pass (every star equally bright,
    /// activity ∝ 1/r²) for side-by-side comparison.
    static let isLegacyModel = UserDefaults.standard.string(forKey: "tailModel") == "legacy"

    /// Radiation pressure over gravity, one per row, from the orbit outward.
    /// β is quoted for a Sun-like star; brighter stars push harder (see `luminosity`).
    static let betas: [Float] = [0.02, 0.06, 0.12, 0.2, 0.3, 0.42, 0.56, 0.72, 0.9]
    static let interval: Float = 1.0 / 40
    static let life: Float = 2.6
    private static let capacity = Int(life / interval) + 4
    static var rows: Int { betas.count }

    /// How hard the comet is outgassing now, 0 … 4.
    private(set) var activity: Float = 0
    /// Columns alive, newest first.
    private(set) var columnCount = 0

    private var newest = -1
    private var positions: [SIMD2<Float>]
    private var velocities: [SIMD2<Float>]
    private var ages: [Float]
    private var outgassing: [Float]
    private var striae: [Float]
    private var releaseTimer: Float = 0
    private var releases = 0
    private let striaKnots: [Float] = (0..<64).map { _ in .random(in: 0...1) }

    init() {
        let n = Self.capacity * Self.rows
        positions = Array(repeating: .zero, count: n)
        velocities = Array(repeating: .zero, count: n)
        ages = Array(repeating: 0, count: Self.capacity)
        outgassing = Array(repeating: 0, count: Self.capacity)
        striae = Array(repeating: 1, count: Self.capacity)
    }

    func reset() {
        columnCount = 0
        newest = -1
        activity = 0
        releaseTimer = 0
    }

    /// Column `i` counted from the newest (0).
    func column(_ i: Int) -> (age: Float, activity: Float, stria: Float, slot: Int) {
        let slot = (newest - i + Self.capacity) % Self.capacity
        return (ages[slot], outgassing[slot], striae[slot], slot)
    }

    func position(slot: Int, row: Int) -> SIMD2<Float> {
        positions[slot * Self.rows + row]
    }

    /// `comet` is nil when nothing is released (resting, crashed, rewinding);
    /// the sheet already out keeps flowing and fades. `ageRate` > 1 hurries it.
    func update(dt: Float, comet: (position: SIMD2<Double>, velocity: SIMD2<Double>)?,
                bodies: [Body], positions bodyPositions: [SIMD2<Double>], ageRate: Float = 1) {
        let light = bodies.map(Self.luminosity)

        var target: Float = 0
        if let comet {
            let p = SIMD2<Float>(comet.position)
            for i in bodies.indices where light[i] > 0 {
                let d = SIMD2<Float>(bodyPositions[i]) - p
                let flux = light[i] * 160_000 / max(simd_length_squared(d), 900) // 1 at 400 units from a Sun-like star
                // ice sublimation climbs faster than the light itself: about 1/r³ here
                target += Self.isLegacyModel ? flux : flux * flux.squareRoot()
            }
            // a comet in a lit system always outgasses a little; near the star it boils
            let floor: Float = Self.isLegacyModel ? 0.5 : 0.35
            target = light.contains { $0 > 0 } ? min(max(target, floor), 4) : 0
        }
        activity += (target - activity) * min(dt * 4, 1)

        // age, and retire columns past their life (the oldest sit at the end)
        for i in 0..<columnCount {
            let slot = (newest - i + Self.capacity) % Self.capacity
            ages[slot] += dt * ageRate
        }
        while columnCount > 0, column(columnCount - 1).age >= Self.life { columnCount -= 1 }

        // four sub-steps: the inner grains ride the comet's own hairpin at perihelion
        let steps = 4
        let h = dt / Float(steps)
        let bodyXY = bodyPositions.map { SIMD2<Float>($0) }
        let mu = bodies.map { Float($0.mu) }
        for _ in 0..<steps {
            for i in 0..<columnCount {
                let slot = (newest - i + Self.capacity) % Self.capacity
                for row in 0..<Self.rows {
                    let k = slot * Self.rows + row
                    let beta = Self.betas[row]
                    var a = SIMD2<Float>.zero
                    for b in bodies.indices {
                        let d = bodyXY[b] - positions[k]
                        let s = simd_length_squared(d) + 400
                        a += d * (mu[b] * (1 - beta * light[b]) / (s * s.squareRoot()))
                    }
                    velocities[k] += a * h
                    positions[k] += velocities[k] * h
                }
            }
        }

        guard let comet else { return }
        releaseTimer += dt
        while releaseTimer >= Self.interval {
            releaseTimer -= Self.interval
            release(at: SIMD2<Float>(comet.position), velocity: SIMD2<Float>(comet.velocity), activity: target)
        }
    }

    /// How hard a body's light pushes, relative to a Sun-like star.
    ///
    /// Main-sequence luminosity grows roughly as mass^3.5, and radiation pressure
    /// scales with luminosity while gravity scales with mass - so β is quoted for
    /// a reference star and multiplied by L/M against it. A blue giant blows its
    /// finest dust clean away (β·L/M > 1: net repulsion); an orange dwarf barely
    /// stirs it. The black hole's value is invented: its accretion disk shines.
    static func luminosity(_ body: Body) -> Float {
        switch body.kind {
        case .star:
            if isLegacyModel { return 1 }
            let m = Float(body.mu / 2.4e7)
            let lightOverMass = m * m * m / m.squareRoot() / m  // M^3.5 / M = M^2.5
            return min(max(lightOverMass, 0.1), 2.5)
        case .hole: return 0.5
        case .planet, .moon: return 0
        }
    }

    private func release(at p: SIMD2<Float>, velocity v: SIMD2<Float>, activity: Float) {
        newest = (newest + 1) % Self.capacity
        columnCount = min(columnCount + 1, Self.capacity)
        for row in 0..<Self.rows {
            positions[newest * Self.rows + row] = p
            velocities[newest * Self.rows + row] = v
        }
        ages[newest] = 0
        outgassing[newest] = activity
        // bursts of outgassing, smooth in time: brighter synchrones read as striae
        let x = Float(releases) * 0.3
        let i0 = Int(x) % striaKnots.count, i1 = (i0 + 1) % striaKnots.count
        let f = x - x.rounded(.down)
        let smooth = f * f * (3 - 2 * f)
        let burst = striaKnots[i0] + (striaKnots[i1] - striaKnots[i0]) * smooth
        striae[newest] = 0.3 + 1.5 * burst * burst
        releases += 1
    }
}
