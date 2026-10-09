// Measures the gravitational pull a player actually experiences, so the haptic
// thresholds can be set from the campaign rather than guessed. Run through
// tools/run.sh feel.

import Foundation

/// The pull as today's `GameSession.updateClimax` computes it: absolute acceleration.
func absolutePull(_ flight: Flight, _ level: Level) -> Double {
    var strongest = 0.0
    for i in level.bodies.indices {
        let d = flight.bodyPositions[i] - flight.position
        strongest = max(strongest, level.bodies[i].mu / (d.x * d.x + d.y * d.y + 1))
    }
    return strongest
}

/// The proposed measure: how close to a surface the comet is, where 1 is touching.
///
/// `mu / d²` divided by the same body's pull at its own surface leaves `(R / d)²`,
/// so the mass cancels and the number means the same thing on a moon and on a
/// black hole. That is what makes it usable on every level without tuning.
func closeness(_ flight: Flight, _ level: Level) -> Double {
    var closest = 0.0
    for i in level.bodies.indices {
        let d = flight.bodyPositions[i] - flight.position
        let surface = level.bodies[i].radius + Sim.cometRadius
        let ratio = surface * surface / max(d.x * d.x + d.y * d.y, 1e-9)
        closest = max(closest, min(ratio, 1))
    }
    return closest
}

/// Today's mapping, kept so the report shows what the current build feels like.
func currentLevel(_ pull: Double) -> Float {
    let x = Float(min(max((pull - 700) / (6000 - 700), 0), 1))
    return x * x
}

/// The proposed curve. Closeness alone is too quiet to feel on the gentle levels,
/// where the comet never comes within seven radii of anything; raising it to a
/// fractional power lifts a distant pass into the range the Taptic Engine can
/// actually render while leaving a graze at full strength.
func proposedLevel(_ closeness: Double) -> Double {
    min(max(pow(closeness, 0.45), 0), 1)
}

struct Run {
    let id: String
    let absolute: [Double]
    let close: [Double]

    func share(_ samples: [Double], above threshold: Double) -> Double {
        samples.isEmpty ? 0 : Double(samples.filter { $0 >= threshold }.count) / Double(samples.count)
    }

    var peakClose: Double { close.max() ?? 0 }
    var humShareToday: Double {
        absolute.isEmpty ? 0 : Double(absolute.filter { currentLevel($0) >= 0.03 }.count) / Double(absolute.count)
    }
        var humShareProposed: Double { share(close.map(proposedLevel), above: 0.05) }
    var strongShareProposed: Double { share(close.map(proposedLevel), above: 0.5) }
    var peakProposed: Double { close.map(proposedLevel).max() ?? 0 }
}

var runs: [Run] = []
for def in LevelDef.campaign {
    guard let shot = def.shot else { continue }
    let level = Level(def)
    var flight = Flight(level: level, shot: shot)
    var absolute: [Double] = []
    var close: [Double] = []
    while flight.isFlying {
        flight.step()
        absolute.append(absolutePull(flight, level))
        close.append(closeness(flight, level))
    }
    runs.append(Run(id: def.id, absolute: absolute, close: close))
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func right(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
}

func whole(_ value: Double) -> String { String(Int(value.rounded())) }

// Each level's own proof shot sets the reference: the hum is "how close to the
// closest this level ever gets", so a gentle tutorial and a black hole both use
// the full range of the Taptic Engine.
func curve(_ relative: Double, _ power: Double) -> Double {
    min(max(pow(min(max(relative, 0), 1), power), 0), 1)
}

let threshold = 0.08
print("duty cycle of the hum, per curve power (share of flight above \(threshold))")
print("  " + pad("level", 15) + right("today", 9) + right("p=1.0", 9) + right("p=1.5", 9)
      + right("p=2.0", 9) + right("p=3.0", 9))
for run in runs {
    let peak = max(run.peakClose, 1e-9)
    var cells = ""
    for power in [1.0, 1.5, 2.0, 3.0] {
        let levels = run.close.map { curve($0 / peak, power) }
        let share = Double(levels.filter { $0 >= threshold }.count) / Double(max(levels.count, 1))
        cells += right(whole(share * 100) + "%", 9)
    }
    print("  " + pad(run.id, 15) + right(whole(run.humShareToday * 100) + "%", 9) + cells)
}

print("")
print("share of flight at strong hum (>= 0.5)")
print("  " + pad("level", 15) + right("p=1.0", 9) + right("p=1.5", 9) + right("p=2.0", 9) + right("p=3.0", 9))
for run in runs {
    let peak = max(run.peakClose, 1e-9)
    var cells = ""
    for power in [1.0, 1.5, 2.0, 3.0] {
        let levels = run.close.map { curve($0 / peak, power) }
        let share = Double(levels.filter { $0 >= 0.5 }.count) / Double(max(levels.count, 1))
        cells += right(whole(share * 100) + "%", 9)
    }
    print("  " + pad(run.id, 15) + cells)
}
