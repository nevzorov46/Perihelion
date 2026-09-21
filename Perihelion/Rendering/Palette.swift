import simd

/// Linear-light colours. Emissive things go above 1.0 on purpose: that is what
/// the bloom picks up.
enum Palette {
    static let mote = SIMD3<Float>(1.0, 0.70, 0.36)
    static let trailSlow = SIMD3<Float>(0.58, 0.36, 1.0)
    static let trailFast = SIMD3<Float>(0.30, 0.92, 1.0)
    static let comet = SIMD3<Float>(0.75, 0.85, 1.0)
    static let ghost = SIMD3<Float>(0.55, 0.55, 0.9)
    static let accretion = SIMD3<Float>(1.0, 0.58, 0.26)

    static let nebulae: [SIMD3<Float>] = [
        SIMD3(0.45, 0.30, 1.0),
        SIMD3(0.20, 0.55, 1.0),
        SIMD3(0.85, 0.30, 0.70),
        SIMD3(0.20, 0.80, 0.75),
    ]

    /// HSL in sRGB, converted to linear.
    static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> SIMD3<Float> {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        let m = lightness - c / 2
        func linear(_ v: Double) -> Float { Float(pow(v + m, 2.2)) }
        return SIMD3(linear(r), linear(g), linear(b))
    }

    static func srgb(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Float> {
        SIMD3(Float(pow(r, 2.2)), Float(pow(g, 2.2)), Float(pow(b, 2.2)))
    }

    static func bodyColor(_ body: Body) -> SIMD3<Float> {
        switch body.kind {
        case .star:
            // real stars are pale (Charity's blackbody table): O/B #9bb0ff, G #fff4ea, K #ffd2a1
            switch body.hue {
            case ..<30: return srgb(1.0, 0.82, 0.63)
            case ..<100: return srgb(1.0, 0.96, 0.92)
            default: return srgb(0.61, 0.69, 1.0)
            }
        case .planet: return hsl(body.hue, 0.5, 0.52)
        case .moon: return hsl(body.hue, 0.08, 0.62)
        case .hole: return accretion
        }
    }
}
