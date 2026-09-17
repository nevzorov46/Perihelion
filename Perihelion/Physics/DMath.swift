/// Sine and cosine built only from + − × ÷, so they give the same bits everywhere.
///
/// The simulation is chaotic: a last-bit difference in a moon's position turns into
/// a different trajectory a few seconds later. libm's `sin`/`cos` are not required
/// to be correctly rounded and may change between OS releases - and levels are
/// baked on a Mac but played on a phone. IEEE-754 basic arithmetic and `sqrt` are
/// exact, so a Taylor series made of them is reproducible. Everything the physics
/// touches goes through here; rendering uses libm freely.
enum DMath {
    static let pi = 3.141592653589793
    static let tau = 6.283185307179586
    static let halfPi = 1.5707963267948966
    private static let quarterPi = 0.7853981633974483

    static func sin(_ value: Double) -> Double {
        var x = value - tau * ((value + pi) / tau).rounded(.down) // [-π, π)
        var sign = 1.0
        if x < 0 { x = -x; sign = -1 }
        if x > halfPi { x = pi - x }                                 // [0, π/2]
        return x > quarterPi ? sign * cosSeries(halfPi - x) : sign * sinSeries(x)
    }

    static func cos(_ value: Double) -> Double {
        var x = value - tau * ((value + pi) / tau).rounded(.down)
        if x < 0 { x = -x }                                          // cos is even
        var sign = 1.0
        if x > halfPi { x = pi - x; sign = -1 }
        return x > quarterPi ? sign * sinSeries(halfPi - x) : sign * cosSeries(x)
    }

    // |x| ≤ π/4 here, so the first omitted term is below 1e-16.
    private static func sinSeries(_ x: Double) -> Double {
        let x2 = x * x
        var s = 1 - x2 / 272
        s = 1 - x2 / 210 * s
        s = 1 - x2 / 156 * s
        s = 1 - x2 / 110 * s
        s = 1 - x2 / 72 * s
        s = 1 - x2 / 42 * s
        s = 1 - x2 / 20 * s
        s = 1 - x2 / 6 * s
        return x * s
    }

    private static func cosSeries(_ x: Double) -> Double {
        let x2 = x * x
        var c = 1 - x2 / 240
        c = 1 - x2 / 182 * c
        c = 1 - x2 / 132 * c
        c = 1 - x2 / 90 * c
        c = 1 - x2 / 56 * c
        c = 1 - x2 / 30 * c
        c = 1 - x2 / 12 * c
        c = 1 - x2 / 2 * c
        return c
    }
}
