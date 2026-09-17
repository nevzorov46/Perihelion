import Foundation

/// Art directions. The game ships in `.observatory`; the other two stay
/// reachable with `-style light|atlas` for development. Raw values match `PHStyle`.
enum VisualStyle: Int32, CaseIterable {
    case observatory = 0
    case light = 1
    case atlas = 2

    static var launchArgument: VisualStyle? {
        switch UserDefaults.standard.string(forKey: "style") {
        case "observatory": return .observatory
        case "light": return .light
        case "atlas": return .atlas
        default: return nil
        }
    }
}
