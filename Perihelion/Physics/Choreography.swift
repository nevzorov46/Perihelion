/// The figure-eight solution of the three-body problem.
///
/// Three equal masses chasing each other around a single figure-eight, forever.
/// Found numerically by Moore (1993), proven to exist by Chenciner & Montgomery
/// (2000). Initial conditions from Simó, in units where G = m = 1.
///
/// One period is integrated once and kept as a table, so the stars ride the real
/// solution rather than a drawn lemniscate.
enum Choreography {
    static let period = 6.32591398
    static let sampleCount = 4096

    struct Table {
        let xs: [[Double]]
        let ys: [[Double]]
        /// How far body 0 lands from its start after one period - the table's error.
        let closure: Double
    }

    static let table: Table = build()

    /// Position of body `k` at dimensionless time `u`, linearly interpolated.
    static func position(body k: Int, at u: Double) -> SIMD2<Double> {
        var f = u.truncatingRemainder(dividingBy: period) / period
        if f < 0 { f += 1 }
        let s = f * Double(sampleCount)
        let i0 = min(Int(s.rounded(.down)), sampleCount - 1)
        let a = s - Double(i0)
        let i1 = (i0 + 1) % sampleCount
        let xs = table.xs[k], ys = table.ys[k]
        return SIMD2(xs[i0] + (xs[i1] - xs[i0]) * a, ys[i0] + (ys[i1] - ys[i0]) * a)
    }

    private static func build() -> Table {
        var x = [0.97000436, -0.97000436, 0], y = [-0.24308753, 0.24308753, 0]
        var vx = [0.466203685, 0.466203685, -0.93240737]
        var vy = [0.43236573, 0.43236573, -0.86473146]
        var ax = [0.0, 0, 0], ay = [0.0, 0, 0]

        func accelerate() {
            ax = [0, 0, 0]; ay = [0, 0, 0]
            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    let dx = x[j] - x[i], dy = y[j] - y[i]
                    let r2 = dx * dx + dy * dy
                    let inv = 1 / (r2 * r2.squareRoot())
                    ax[i] += dx * inv; ay[i] += dy * inv
                    ax[j] -= dx * inv; ay[j] -= dy * inv
                }
            }
        }

        let substeps = 16
        let h = period / Double(sampleCount * substeps)
        var xs = [[Double]](repeating: [Double](repeating: 0, count: sampleCount), count: 3)
        var ys = xs
        accelerate()
        for s in 0..<sampleCount {
            for k in 0..<3 { xs[k][s] = x[k]; ys[k][s] = y[k] }
            for _ in 0..<substeps {
                for k in 0..<3 {
                    vx[k] += ax[k] * h / 2; vy[k] += ay[k] * h / 2
                    x[k] += vx[k] * h; y[k] += vy[k] * h
                }
                accelerate()
                for k in 0..<3 { vx[k] += ax[k] * h / 2; vy[k] += ay[k] * h / 2 }
            }
        }
        let dx = x[0] - xs[0][0], dy = y[0] - ys[0][0]
        return Table(xs: xs, ys: ys, closure: (dx * dx + dy * dy).squareRoot())
    }
}
