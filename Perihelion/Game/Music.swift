import Foundation

/// Which note each thing sings. Everything sits on a major pentatonic scale, so any
/// order of events - any trajectory - stays consonant.
///
/// The idea is Kepler's (Harmonices Mundi, 1619): heavier bodies sing lower, and
/// the motes you collect climb the scale, so a clean run ends on a rising phrase.
enum Music {
    private static let pentatonic = [0, 2, 4, 7, 9]

    static func midi(root: Int, degree: Int) -> Int {
        let octave = Int((Double(degree) / 5).rounded(.down))
        return root + 12 * octave + pentatonic[degree - octave * 5]
    }

    static func frequency(midi: Int) -> Float {
        Float(440 * pow(2, Double(midi - 69) / 12))
    }

    static func bodyDegree(_ body: Body, index: Int) -> Int {
        let heft = Int((log2(body.mu / 1e7)).rounded())
        switch body.kind {
        case .hole: return -8
        case .star: return -3 - heft + index % 3
        case .planet: return 1 - heft + index % 2
        case .moon: return 4
        }
    }

    static func moteDegree(order: Int) -> Int {
        5 + order
    }

    static let resolution = [5, 7, 9, 10]
}
