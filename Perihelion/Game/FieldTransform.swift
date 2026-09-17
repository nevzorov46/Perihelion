import CoreGraphics
import simd

/// Maps the landscape world (1600 × 1000) onto a portrait screen.
///
/// The world is rotated a quarter turn, so the launch side (world left) sits at
/// the bottom of the phone. It is a true rotation, not a mirror: the physics is
/// untouched and orbits keep their handedness.
///
///     screen.x = cx + s·(world.y − 500)
///     screen.y = cy − s·(world.x − 800)
struct FieldTransform {
    let viewSize: CGSize
    /// Points per world unit.
    let scale: Double
    /// Screen position of the world's centre, in points.
    let center: CGPoint

    static let zero = FieldTransform(viewSize: .zero, scale: 1, center: .zero)

    init(viewSize: CGSize, scale: Double, center: CGPoint) {
        self.viewSize = viewSize
        self.scale = scale
        self.center = center
    }

    init(viewSize: CGSize, topInset: CGFloat, bottomInset: CGFloat) {
        let availableHeight = max(viewSize.height - topInset - bottomInset, 1)
        let scale = min(Double(viewSize.width) / Sim.height, Double(availableHeight) / Sim.width)
        self.init(viewSize: viewSize, scale: scale,
                  center: CGPoint(x: viewSize.width / 2, y: topInset + availableHeight / 2))
    }

    func toScreen(_ w: SIMD2<Double>) -> CGPoint {
        CGPoint(x: Double(center.x) + scale * (w.y - Sim.height / 2),
                y: Double(center.y) - scale * (w.x - Sim.width / 2))
    }

    func toWorld(_ p: CGPoint) -> SIMD2<Double> {
        SIMD2(Sim.width / 2 - Double(p.y - center.y) / scale,
              Sim.height / 2 + Double(p.x - center.x) / scale)
    }

    /// A screen-space vector expressed in world axes (rotation only, length kept).
    func worldDirection(_ v: CGVector) -> SIMD2<Double> {
        SIMD2(-Double(v.dy), Double(v.dx))
    }

    var clipMatrix: simd_float4x4 {
        let vw = Double(max(viewSize.width, 1)), vh = Double(max(viewSize.height, 1))
        let s = scale, cx = Double(center.x), cy = Double(center.y)
        return simd_float4x4(columns: (
            SIMD4<Float>(0, Float(2 * s / vh), 0, 0),                       // world x → clip y
            SIMD4<Float>(Float(2 * s / vw), 0, 0, 0),                       // world y → clip x
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(Float(2 / vw * (cx - Sim.height / 2 * s) - 1),
                         Float(1 - 2 / vh * (cy + Sim.width / 2 * s)), 0, 1)
        ))
    }
}
