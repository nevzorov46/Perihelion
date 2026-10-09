import Observation
import UIKit

/// The system switches the game honours, in one place and kept live.
///
/// SwiftUI has environment values for these, but the parts that need them most
/// are the simulation and the Metal renderer, which are not views. Reading them
/// here once, and watching for changes, keeps one answer for the whole app.
@MainActor
@Observable
final class AccessibilitySettings {
    static let shared = AccessibilitySettings()

    /// Camera shake and screen-space distortion are the two things in this game
    /// that move the whole picture without the player asking. Both go away.
    private(set) var reduceMotion = UIAccessibility.isReduceMotionEnabled
    /// Motes and bodies are told apart by hue first; with this on they get rings.
    private(set) var differentiateWithoutColour = UIAccessibility.shouldDifferentiateWithoutColor
    /// Aiming by dragging is no use to someone who cannot see where the drag
    /// started, so with VoiceOver running the field offers explicit controls.
    /// `-aimControls YES` shows the VoiceOver aiming strip without VoiceOver, for
    /// checking its layout and for screenshots.
    private let forcesAimControls = UserDefaults.standard.bool(forKey: "aimControls")
    private(set) var voiceOverRunning = UIAccessibility.isVoiceOverRunning

    private var observers: [NSObjectProtocol] = []

    private init() {
        observe(UIAccessibility.reduceMotionStatusDidChangeNotification) { [weak self] in
            self?.reduceMotion = UIAccessibility.isReduceMotionEnabled
        }
        observe(UIAccessibility.differentiateWithoutColorDidChangeNotification) { [weak self] in
            self?.differentiateWithoutColour = UIAccessibility.shouldDifferentiateWithoutColor
        }
        observe(UIAccessibility.voiceOverStatusDidChangeNotification) { [weak self] in
            guard let self else { return }
            voiceOverRunning = UIAccessibility.isVoiceOverRunning || forcesAimControls
        }
        voiceOverRunning = voiceOverRunning || forcesAimControls
    }

    private func observe(_ name: Notification.Name, _ update: @escaping @MainActor () -> Void) {
        observers.append(NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in update() }
        })
    }
}

extension UIAccessibility {
    /// Speaks `message` once VoiceOver has finished whatever it is saying.
    @MainActor
    static func announce(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        var announcement = AttributedString(message)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }
}
