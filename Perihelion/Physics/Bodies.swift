/// Bodies on rails.
///
/// This is the restricted N-body problem: the comet feels every body, the bodies
/// don't feel the comet (its mass is negligible), so they can follow exact analytic
/// paths - Kepler circles, a binary around its barycentre, the figure-eight
/// choreography. Periods are derived from the masses, never picked by hand:
/// ω = √(μ / r³).
enum BodyKind {
    case star, planet, moon, hole
}

/// How a level describes its sky. Indices in `around` refer to the expanded list.
enum BodySpec {
    case fixed(BodyKind, x: Double, y: Double, mu: Double)
    case orbiting(BodyKind, around: Int, radius: Double, phase: Double, direction: Double, mu: Double)
    case binary(x: Double, y: Double, separation: Double, mu1: Double, mu2: Double, phase: Double, direction: Double)
    case threeBody(x: Double, y: Double, scale: Double, period: Double, rotation: Double, phase: Double)
}

enum BodyPath {
    case fixed(SIMD2<Double>)
    /// `parent` is an index into the body list, or -1 to orbit `center`.
    case orbit(parent: Int, center: SIMD2<Double>, radius: Double, phase: Double, omega: Double)
    case choreography(body: Int, center: SIMD2<Double>, scale: Double, tau: Double, phase: Double, cosR: Double, sinR: Double)
}

struct Body {
    let kind: BodyKind
    /// Gravitational parameter G·M, in world units³/s².
    let mu: Double
    let radius: Double
    /// Visual only: hue in degrees.
    let hue: Double
    let path: BodyPath
}

extension BodySpec {
    static func expand(_ specs: [BodySpec]) -> [Body] {
        var bodies: [Body] = []
        var planetCount = 0

        func make(_ kind: BodyKind, _ mu: Double, _ path: BodyPath) -> Body {
            let hue: Double
            switch kind {
            case .star: hue = mu < 1.4e7 ? 24 : mu < 3.2e7 ? 44 : 212 // orange dwarf, yellow-white, blue giant
            case .planet: hue = [172, 262, 338, 32, 200, 118][planetCount % 6]
            case .moon: hue = 220
            case .hole: hue = 28
            }
            return Body(kind: kind, mu: mu, radius: radius(kind, mu), hue: hue, path: path)
        }

        for spec in specs {
            switch spec {
            case let .fixed(kind, x, y, mu):
                bodies.append(make(kind, mu, .fixed(SIMD2(x, y))))
                if kind == .planet { planetCount += 1 }

            case let .orbiting(kind, around, r, phase, direction, mu):
                let omega = direction * (bodies[around].mu / (r * r * r)).squareRoot()
                bodies.append(make(kind, mu, .orbit(parent: around, center: .zero, radius: r, phase: phase, omega: omega)))
                if kind == .planet { planetCount += 1 }

            case let .binary(x, y, d, m1, m2, phase, direction):
                let total = m1 + m2
                let omega = direction * (total / (d * d * d)).squareRoot()
                let center = SIMD2(x, y)
                bodies.append(make(.star, m1, .orbit(parent: -1, center: center, radius: d * m2 / total, phase: phase, omega: omega)))
                bodies.append(make(.star, m2, .orbit(parent: -1, center: center, radius: d * m1 / total, phase: phase + DMath.pi, omega: omega)))

            case let .threeBody(x, y, scale, period, rotation, phase):
                // Scaling lengths by L and time by τ keeps Newton's law intact if G·m = L³/τ².
                let tau = period / Choreography.period
                let mu = scale * scale * scale / (tau * tau)
                for k in 0..<3 {
                    bodies.append(make(.star, mu, .choreography(
                        body: k, center: SIMD2(x, y), scale: scale, tau: tau, phase: phase,
                        cosR: DMath.cos(rotation), sinR: DMath.sin(rotation))))
                }
            }
        }
        return bodies
    }

    /// round(a + b·∛(μ/10⁶)) without `cbrt`, which isn't correctly rounded.
    private static func radius(_ kind: BodyKind, _ mu: Double) -> Double {
        let (a, b): (Double, Double)
        switch kind {
        case .star: (a, b) = (8, 6.2)
        case .planet: (a, b) = (5, 5.4)
        case .moon: (a, b) = (4, 3.6)
        case .hole: (a, b) = (9, 2.2)
        }
        let m = mu / 1e6
        var r = a.rounded(.down)
        while true {
            let c = (r + 0.5 - a) / b
            if c * c * c >= m { return r }
            r += 1
        }
    }
}
