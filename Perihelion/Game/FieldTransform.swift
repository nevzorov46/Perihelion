import CoreGraphics
import simd

/// Where the camera looks. Zoom 1 shows the whole field.
struct Camera {
    var zoom = 1.0
    var focus = SIMD2(Sim.width / 2, Sim.height / 2)
    /// Screen-space shake, in points.
    var shake = CGVector.zero
}

/// Maps the landscape world (1600 × 1000) onto a portrait screen through the camera.
///
/// The world is rotated a quarter turn, so the launch side (world left) sits at
/// the bottom of the phone. It is a true rotation, not a mirror: the physics is
/// untouched and orbits keep their handedness.
///
///     screen.x = cx + s·(world.y − focus.y)
///     screen.y = cy − s·(world.x − focus.x)
struct FieldTransform {
    let viewSize: CGSize
    /// Height available to the field between the HUD bars, in points.
    let availableHeight: CGFloat
    /// Points per world unit with the whole field in view.
    let fitScale: Double
    /// Points per world unit right now.
    let scale: Double
    /// Screen position of the camera's focus, in points.
    let center: CGPoint
    let focus: SIMD2<Double>

    static let zero = FieldTransform(viewSize: .zero, topInset: 0, bottomInset: 0)

    init(viewSize: CGSize, topInset: CGFloat, bottomInset: CGFloat, camera: Camera = Camera()) {
        self.viewSize = viewSize
        availableHeight = max(viewSize.height - topInset - bottomInset, 1)
        fitScale = max(min(Double(viewSize.width) / Sim.height, Double(availableHeight) / Sim.width), 1e-3)
        scale = fitScale * camera.zoom
        center = CGPoint(x: viewSize.width / 2 + camera.shake.dx,
                         y: topInset + availableHeight / 2 + camera.shake.dy)
        focus = camera.focus
    }

    func toScreen(_ w: SIMD2<Double>) -> CGPoint {
        CGPoint(x: Double(center.x) + scale * (w.y - focus.y),
                y: Double(center.y) - scale * (w.x - focus.x))
    }

    func toWorld(_ p: CGPoint) -> SIMD2<Double> {
        SIMD2(focus.x - Double(p.y - center.y) / scale,
              focus.y + Double(p.x - center.x) / scale)
    }

    /// A screen-space vector expressed in world axes (rotation only, length kept).
    func worldDirection(_ v: CGVector) -> SIMD2<Double> {
        SIMD2(-Double(v.dy), Double(v.dx))
    }

    /// Half the visible world, along world y (screen width) and world x (field height).
    func visibleHalfExtent(zoom: Double) -> (across: Double, along: Double) {
        let s = fitScale * zoom
        return (Double(viewSize.width) / (2 * s), Double(availableHeight) / (2 * s))
    }

    var clipMatrix: simd_float4x4 {
        let vw = Double(max(viewSize.width, 1)), vh = Double(max(viewSize.height, 1))
        let s = scale, cx = Double(center.x), cy = Double(center.y)
        return simd_float4x4(columns: (
            SIMD4<Float>(0, Float(2 * s / vh), 0, 0),                       // world x → clip y
            SIMD4<Float>(Float(2 * s / vw), 0, 0, 0),                       // world y → clip x
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(Float(2 / vw * (cx - s * focus.y) - 1),
                         Float(1 - 2 / vh * (cy + s * focus.x)), 0, 1)
        ))
    }
}
