import simd

/// The stars and dust around the field, as objects rather than wallpaper.
///
/// Each one carries a depth: 0 sits at infinity and ignores the camera, 1 travels
/// with the field. That is what gives the sky parallax when the camera pans, and
/// a slow drift of its own so space never looks frozen.
struct Starfield {
    struct Speck {
        var position: SIMD2<Float>
        var drift: SIMD2<Float>
        /// 0 = infinitely far (locked to the view), 1 = in the field's plane.
        var depth: Float
        var radius: Float
        var brightness: Float
        var color: SIMD3<Float>
        var twinkleRate: Float
        var twinklePhase: Float
        var spikes: Bool
    }

    /// Stars live over a region wider than any camera can see, and wrap inside it.
    static let bounds = (x: Float(-700), y: Float(-600), width: Float(3000), height: Float(2200))

    let stars: [Speck]
    let dust: [Speck]

    init(seed: UInt32, stars starCount: Int = 340, dust dustCount: Int = 90) {
        var random = SeededRandom(seed: seed)
        func next() -> Float { Float(random.next()) }

        func speck(depthRange: ClosedRange<Float>, radius: ClosedRange<Float>, isDust: Bool) -> Speck {
            let depth = depthRange.lowerBound + next() * (depthRange.upperBound - depthRange.lowerBound)
            // faint by default, with a few standouts: brightness falls off as a cube
            let roll = next()
            let brightness = isDust ? 0.05 + 0.1 * roll : 0.1 + 1.5 * roll * roll * roll
            let temperature = next()
            let cool = SIMD3<Float>(0.62, 0.74, 1.0), warm = SIMD3<Float>(1.0, 0.86, 0.68)
            // a couple of points per second on screen: enough to feel adrift, not enough to distract
            let drift = SIMD2<Float>(-6 - 10 * depth, 2 + 4 * depth) * (0.6 + 0.8 * next()) * 0.35
            return Speck(
                position: SIMD2(Self.bounds.x + next() * Self.bounds.width, Self.bounds.y + next() * Self.bounds.height),
                drift: drift,
                depth: depth,
                radius: radius.lowerBound + next() * (radius.upperBound - radius.lowerBound),
                brightness: brightness,
                color: simd_mix(cool, warm, SIMD3(repeating: temperature * temperature)),
                twinkleRate: next() < 0.45 ? 0.6 + 2.4 * next() : 0,
                twinklePhase: next() * 6.28,
                spikes: !isDust && roll > 0.985)
        }

        stars = (0..<starCount).map { _ in speck(depthRange: 0.05...0.75, radius: 1.1...3.6, isDust: false) }
        dust = (0..<dustCount).map { _ in speck(depthRange: 0.5...0.95, radius: 5...16, isDust: true) }
    }

    /// Where a speck appears now: drifted, wrapped, and shifted by its depth
    /// against the camera's travel.
    static func place(_ speck: Speck, time: Float, cameraTravel: SIMD2<Float>) -> SIMD2<Float> {
        var p = speck.position + speck.drift * time
        p.x = bounds.x + (p.x - bounds.x).truncatingRemainder(dividingBy: bounds.width)
        p.y = bounds.y + (p.y - bounds.y).truncatingRemainder(dividingBy: bounds.height)
        if p.x < bounds.x { p.x += bounds.width }
        if p.y < bounds.y { p.y += bounds.height }
        return p + cameraTravel * (1 - speck.depth)
    }
}
