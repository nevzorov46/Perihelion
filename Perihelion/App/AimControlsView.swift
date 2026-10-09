import SwiftUI

/// Aiming for a player who cannot see the field.
///
/// The game is played by dragging back from the comet: the drag carries the
/// angle and the power, and both are invisible to VoiceOver. This strip gives
/// them each a control that the rotor can adjust and that speaks its value, plus
/// a way to hear where everything is. It appears only while VoiceOver is
/// running, so it costs the rest of the game nothing.
///
/// It is drawn rather than hidden behind clear views, because a low-vision
/// player uses both: they hear the value and see where their finger is.
struct AimControlsView: View {
    let session: GameSession

    @State private var bearing: Double = 0
    @State private var strength: Double = 0.5

    private static let bearingStep: Double = 15
    private static let strengthStep: Double = 0.1

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                control(
                    title: "DIRECTION",
                    reading: Self.spokenBearing(bearing),
                    label: "Aim direction",
                    value: Self.spokenBearing(bearing),
                    hint: "Swipe up or down to turn the shot"
                ) { direction in
                    bearing = (bearing + (direction == .increment ? Self.bearingStep : -Self.bearingStep))
                        .normalisedDegrees
                    apply()
                }

                control(
                    title: "POWER",
                    reading: "\(Int((strength * 100).rounded()))%",
                    label: "Power",
                    value: "\(Int((strength * 100).rounded())) percent",
                    hint: "Swipe up or down to throw harder or softer"
                ) { direction in
                    strength = min(max(strength + (direction == .increment ? Self.strengthStep : -Self.strengthStep), 0), 1)
                    apply()
                }
            }

            HStack(spacing: 10) {
                action("SKY") {
                    UIAccessibility.announce(session.skyDescription())
                }
                .accessibilityLabel("Describe the sky")
                .accessibilityHint("Reads out where the bodies and the motes are")

                action("LAUNCH") {
                    session.setAim(bearing: bearing, strength: strength)
                    session.fireCurrentAim()
                    UIAccessibility.announce("Launched at \(Self.spokenBearing(bearing))")
                }
                .accessibilityLabel("Launch")
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.66))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
        }
        .padding(.horizontal, 16)
        .onAppear {
            apply()
            UIAccessibility.announce(session.skyDescription())
        }
    }

    /// Keeps the preview arc, the sound and the spoken value on the same numbers.
    private func apply() {
        session.setAim(bearing: bearing, strength: strength)
        session.previewAimSound()
    }

    /// "two o'clock, 60 degrees": the clock face to aim by, the degrees to be exact.
    static func spokenBearing(_ degrees: Double) -> String {
        var hour = Int((degrees / 30).rounded()) % 12
        if hour == 0 { hour = 12 }
        return "\(hour) o'clock, \(Int(degrees.rounded())) degrees"
    }

    private func control(title: String, reading: String, label: String, value: String, hint: String,
                         adjust: @escaping (AccessibilityAdjustmentDirection) -> Void) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.45))
            Text(reading)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.07))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityHint(hint)
        .accessibilityAdjustableAction(adjust)
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.1))
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressFade())
    }
}
