// Checks the physics against itself. Run through tools/run.sh verify.

import Foundation

var failures = 0
func check(_ ok: Bool, _ message: String) {
    print((ok ? "  ok    " : "  FAIL  ") + message)
    if !ok { failures += 1 }
}

print("math")
var trigError = 0.0
for i in 0..<400_000 {
    let x = Double(i - 200_000) * 0.000731
    trigError = max(trigError, abs(DMath.sin(x) - Foundation.sin(x)), abs(DMath.cos(x) - Foundation.cos(x)))
}
check(trigError < 1e-13, "DMath sin/cos within \(trigError) of libm")
check(Choreography.table.closure < 1e-6, "figure-eight closes after one period to \(Choreography.table.closure)")

print("integrator")
do {
    // circular orbit around a fixed star: energy must not drift
    let mu = 3e7, r = 200.0
    let def = LevelDef(id: "orbit", name: "", hint: "", root: 0, preview: 0,
                       bodies: [.fixed(.star, x: 800, y: 500, mu: mu)], launch: SIMD2(800, 500 - r),
                       motes: [], shot: nil, window: 0)
    var flight = Flight(level: Level(def), shot: Shot(angle: 0, speed: (mu / r).squareRoot()))
    func energy(_ f: Flight) -> Double {
        let dx = f.position.x - 800, dy = f.position.y - 500
        return 0.5 * (f.velocity.x * f.velocity.x + f.velocity.y * f.velocity.y) - mu / (dx * dx + dy * dy + Sim.softening2).squareRoot()
    }
    let e0 = energy(flight)
    var drift = 0.0
    while flight.isFlying { flight.step(); drift = max(drift, abs(energy(flight) - e0) / abs(e0)) }
    check(flight.state == .timedOut, "circular orbit survives \(Sim.maxTime) s")
    check(drift < 1e-6, "energy drift \(drift)")
}

print("campaign")
var fingerprint: UInt64 = 1_469_598_103_934_665_603
for def in LevelDef.campaign {
    let level = Level(def)
    guard let shot = def.shot else { check(false, "\(def.id) has no proof shot"); continue }
    let start = Date()
    let flight = Flight.run(level, shot)
    let window = Design.measureWindow(level, shot)
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    check(flight.isComplete, "\(def.id): proof shot collects \(flight.collectedCount)/\(level.motes.count), window \(window) (\(ms) ms)")
    for value in [flight.position.x, flight.position.y, flight.velocity.x, flight.velocity.y] {
        fingerprint = (fingerprint ^ value.bitPattern) &* 1_099_511_628_211
    }
}
print("  fingerprint \(String(fingerprint, radix: 16)) - must match on every machine")

print(failures == 0 ? "all good" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
