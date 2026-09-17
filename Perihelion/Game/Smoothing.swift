import simd

/// Critically damped spring smoothing (the classic `SmoothDamp`).
///
/// Exponential smoothing - `x += (target − x) · k` - jumps to full speed the
/// instant the target moves, which the eye reads as a flick. A spring carries its
/// own velocity, so it accelerates and settles smoothly and never overshoots.
/// The closed form below is stable at any frame time.
enum Smoothing {
    static func damp(_ value: inout Double, _ velocity: inout Double, target: Double, time: Double, dt: Double) {
        guard time > 0, dt > 0 else { value = target; velocity = 0; return }
        let omega = 2 / time
        let x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        value = target + (change + temp) * decay
    }

    static func damp(_ value: inout SIMD2<Double>, _ velocity: inout SIMD2<Double>, target: SIMD2<Double>, time: Double, dt: Double) {
        var x = value.x, y = value.y, vx = velocity.x, vy = velocity.y
        damp(&x, &vx, target: target.x, time: time, dt: dt)
        damp(&y, &vy, target: target.y, time: time, dt: dt)
        value = SIMD2(x, y)
        velocity = SIMD2(vx, vy)
    }
}
