// Measures the gravitational pull a player actually experiences, so the haptic
// thresholds can be set from the campaign rather than guessed. Run through
// tools/run.sh feel.

import Foundation

/// The pull as `GameSession.updateClimax` computes it: the strongest single body.
func pull(_ flight: Flight, _ level: Level) -> Double {
    var strongest = 0.0
    for i in level.bodies.indices {
        let d = flight.bodyPositions[i] - flight.position
        strongest = max(strongest, level.bodies[i].mu / (d.x * d.x + d.y * d.y + 1))
    }
    return strongest
}

/// The current mapping, kept here so the report shows what today's build feels like.
func currentLevel(_ pull: Double) -> Float {
    let x = Float(min(max((pull - 700) / (6000 - 700), 0), 1))
    return x * x
}

struct Run {
    let id: String
    let samples: [Double]

    var peak: Double { samples.max() ?? 0 }
    var median: Double { samples.isEmpty ? 0 : samples.sorted()[samples.count / 2] }
    /// Share of the flight the hum would be audible, and the share at full strength.
    var humShare: Double {
        samples.isEmpty ? 0 : Double(samples.filter { currentLevel($0) >= 0.03 }.count) / Double(samples.count)
    }
    var fullShare: Double {
        samples.isEmpty ? 0 : Double(samples.filter { currentLevel($0) >= 0.9 }.count) / Double(samples.count)
    }
}

var runs: [Run] = []
for def in LevelDef.campaign {
    guard let shot = def.shot else { continue }
    let level = Level(def)
    var flight = Flight(level: level, shot: shot)
    var samples: [Double] = []
    while flight.isFlying {
        flight.step()
        samples.append(pull(flight, level))
    }
    runs.append(Run(id: def.id, samples: samples))
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func right(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
}

func whole(_ value: Double) -> String { String(Int(value.rounded())) }

print("pull along each level's proof shot")
print("  " + pad("level", 15) + right("median", 12) + right("peak", 12) + right("hum", 9) + right("full", 9))
for run in runs {
    print("  " + pad(run.id, 15)
          + right(whole(run.median), 12)
          + right(whole(run.peak), 12)
          + right(whole(run.humShare * 100) + "%", 9)
          + right(whole(run.fullShare * 100) + "%", 9))
}

let peaks = runs.map(\.peak).sorted()
let medians = runs.map(\.median).sorted()
print("")
print("across the campaign")
print("  peak pull:   lowest " + whole(peaks.first ?? 0) + ", median " + whole(peaks[peaks.count / 2]) + ", highest " + whole(peaks.last ?? 0))
print("  median pull: lowest " + whole(medians.first ?? 0) + ", median " + whole(medians[medians.count / 2]) + ", highest " + whole(medians.last ?? 0))
print("")
print("  today's mapping starts the hum at pull 1617 and saturates at 6000")
let silent = runs.filter { $0.humShare < 0.01 }.map(\.id)
let pinned = runs.filter { $0.fullShare > 0.5 }.map(\.id)
if !silent.isEmpty { print("  never hums:     " + silent.joined(separator: ", ")) }
if !pinned.isEmpty { print("  pinned at full: " + pinned.joined(separator: ", ")) }
