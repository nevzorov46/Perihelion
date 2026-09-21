import Foundation
import Observation

/// Which skies are cleared, and in how few shots. Kept in UserDefaults.
@Observable
final class Progress {
    private(set) var best: [String: Int]

    init() {
        best = UserDefaults.standard.dictionary(forKey: "best") as? [String: Int] ?? [:]
    }

    func bestShots(_ id: String) -> Int? {
        best[id]
    }

    func record(_ id: String, shots: Int) {
        guard best[id].map({ shots < $0 }) ?? true else { return }
        best[id] = shots
        UserDefaults.standard.set(best, forKey: "best")
    }

    /// Where "Play" picks up: the first sky not yet cleared.
    func nextIndex(in levels: [LevelDef]) -> Int {
        levels.firstIndex { best[$0.id] == nil } ?? 0
    }
}
