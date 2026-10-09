import SwiftUI

/// Sound, vibration and a way to start the campaign over.
///
/// The vibration row says what the engine is actually doing. On a device with
/// system haptics switched off, or in a simulator, a plain switch would lie: it
/// would sit there saying "on" while nothing happens. Saying so costs one line
/// and saves the player wondering whether the game is broken.
struct SettingsView: View {
    let session: GameSession
    let onBack: () -> Void

    @State private var soundOn: Bool
    @State private var hapticsOn: Bool
    @State private var confirmingReset = false
    @State private var appeared = false

    init(session: GameSession, onBack: @escaping () -> Void) {
        self.session = session
        self.onBack = onBack
        _soundOn = State(initialValue: session.isSoundOn)
        _hapticsOn = State(initialValue: session.haptics.isOn)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("SETTINGS")
                .font(.system(size: 22, weight: .thin))
                .tracking(8)
                .padding(.leading, 8)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 8)
                .padding(.top, 30)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            VStack(spacing: 22) {
                row("SOUND", note: nil) {
                    Toggle("", isOn: $soundOn)
                        .labelsHidden()
                        .tint(Color(red: 0.55, green: 0.72, blue: 1))
                        .onChange(of: soundOn) { _, on in
                            if on == session.isSoundOn { return }
                            session.toggleMute()
                        }
                        .accessibilityLabel("Sound")
                }

                row("VIBRATION", note: hapticsNote) {
                    Toggle("", isOn: $hapticsOn)
                        .labelsHidden()
                        .tint(Color(red: 0.55, green: 0.72, blue: 1))
                        .onChange(of: hapticsOn) { _, on in
                            session.haptics.isOn = on
                            if on { session.haptics.test() }
                        }
                        .accessibilityLabel("Vibration")
                        .accessibilityHint("Gravity is felt as well as seen")
                }

                if hapticsOn {
                    Button {
                        session.haptics.test()
                    } label: {
                        Text("TEST")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .overlay {
                                Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressFade())
                    .accessibilityHint("Plays one tap, so you can tell whether this device vibrates")
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 26)
            // The attract loop is alive behind this screen, so the controls need a
            // ground of their own; thin type over a black hole is unreadable.
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.black.opacity(0.62))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                    }
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 22)

            Spacer()

            VStack(spacing: 18) {
                Button {
                    if confirmingReset {
                        session.progress.reset()
                        confirmingReset = false
                    } else {
                        confirmingReset = true
                    }
                } label: {
                    Text(confirmingReset ? "TAP AGAIN TO ERASE" : "RESET PROGRESS")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(confirmingReset
                                         ? Color(red: 1, green: 0.55, blue: 0.45)
                                         : .white.opacity(0.4))
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressFade())
                .accessibilityHint(confirmingReset
                                   ? "Erases every cleared sky"
                                   : "Ask to erase every cleared sky")

                Button(action: onBack) {
                    Text("BACK")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressFade())
            }
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
        .onChange(of: hapticsOn) { _, _ in confirmingReset = false }
    }

    /// Only shown when it tells the player something they cannot see for themselves.
    private var hapticsNote: String? {
        switch session.haptics.status {
        case .ready, .off: nil
        case .unavailable: "This device has no taptic engine, or system haptics are off in Settings."
        case .failed(let reason): "The haptic engine would not start: \(reason)"
        }
    }

    private func row(_ title: String, note: String?,
                     @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                control()
            }
            if let note {
                Text(note)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.5).opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
