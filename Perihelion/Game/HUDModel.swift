import CoreGraphics
import Observation

/// What SwiftUI shows over the field. Written only when something changes -
/// a handful of times per shot, never per frame.
@Observable
final class HUDModel {
    var levelNumber = 1
    var levelName = ""
    var hint = ""
    var hintVisible = true
    var moteCount = 0
    var collected = 0
    var shots = 0
    var toast: String?
    var cleared = false
    var isLastLevel = false
    var muted = false
    var style = VisualStyle.observatory
    var cameraFollows = true
    /// Engraved names beside fixed bodies, atlas style only. Screen points.
    var labels: [BodyLabel] = []
}

struct BodyLabel: Identifiable, Equatable {
    let id: Int
    let text: String
    let point: CGPoint
}
