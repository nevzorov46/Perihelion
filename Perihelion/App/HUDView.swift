import SwiftUI

/// Typography and colour for each art direction.
private struct HUDTheme {
    let style: VisualStyle

    var ink: Color {
        style == .atlas ? Color(red: 0.93, green: 0.83, blue: 0.6) : .white
    }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        switch style {
        case .observatory: return .system(size: size, weight: weight)
        case .light: return .system(size: size, weight: weight == .semibold ? .light : .ultraLight)
        case .atlas: return .system(size: size, weight: weight == .semibold ? .medium : .regular, design: .serif)
        }
    }

    func mono(_ size: CGFloat) -> Font {
        style == .atlas ? .system(size: size, design: .serif).italic() : .system(size: size, weight: .medium, design: .monospaced)
    }

    func caption(level: Int) -> String {
        style == .atlas ? "HARMONIA · TABVLA \(Self.roman(level))" : "PERIHELION"
    }

    func number(_ level: Int) -> String {
        style == .atlas ? "" : String(format: "%02d", level)
    }

    private static func roman(_ n: Int) -> String {
        let table: [(Int, String)] = [(10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, out = ""
        for (value, glyph) in table { while n >= value { out += glyph; n -= value } }
        return out
    }
}

struct HUDView: View {
    let hud: HUDModel
    let onBack: () -> Void
    let onNext: () -> Void
    let onRestart: () -> Void
    let onToggleSound: () -> Void

    private var theme: HUDTheme { HUDTheme(style: hud.style) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.spring(duration: 0.45), value: hud.cleared)
        .animation(.easeOut(duration: 0.25), value: hud.toast)
        .animation(.easeOut(duration: 0.5), value: hud.hintVisible)
        .animation(.easeOut(duration: 0.3), value: hud.collected)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            IconButton(systemName: "chevron.left", theme: theme, action: onBack)
            VStack(alignment: .leading, spacing: 6) {
                Text(theme.caption(level: hud.levelNumber))
                    .font(theme.font(11, .semibold))
                    .tracking(3.2)
                    .foregroundStyle(theme.ink.opacity(0.45))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !theme.number(hud.levelNumber).isEmpty {
                        Text(theme.number(hud.levelNumber))
                            .font(theme.mono(13))
                            .foregroundStyle(theme.ink.opacity(0.4))
                    }
                    Text(hud.levelName)
                        .font(theme.font(hud.style == .atlas ? 27 : 24, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .italic(hud.style == .atlas)
                        .foregroundStyle(theme.ink)
                }
                MotePips(total: hud.moteCount, collected: hud.collected, theme: theme)
                    .padding(.top, 2)
            }
            .allowsHitTesting(false)
            Spacer()
            HStack(spacing: 8) {
                IconButton(systemName: hud.muted ? "speaker.slash" : "speaker.wave.2", theme: theme, action: onToggleSound)
                IconButton(systemName: "arrow.counterclockwise", theme: theme, action: onRestart)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let toast = hud.toast, !hud.cleared {
                Text(toast)
                    .font(theme.font(15, .semibold))
                    .foregroundStyle(theme.ink.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(theme.ink.opacity(0.08)))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
            }
            if hud.cleared {
                ClearedCard(motes: hud.moteCount, shots: hud.shots, isLast: hud.isLastLevel, theme: theme, onNext: onNext)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if hud.hintVisible {
                    Text(hud.hint)
                        .font(theme.font(15))
                        .foregroundStyle(theme.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                Text(hud.shots == 1 ? "1 shot" : "\(hud.shots) shots")
                    .font(theme.mono(12))
                    .foregroundStyle(theme.ink.opacity(0.35))
                    .opacity(hud.shots > 0 ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Latin names engraved beside fixed bodies (atlas style).
struct BodyLabelsView: View {
    let hud: HUDModel

    var body: some View {
        ZStack {
            ForEach(hud.labels) { label in
                Text(label.text)
                    .font(.system(size: 9, weight: .regular, design: .serif))
                    .tracking(2.4)
                    .foregroundStyle(Color(red: 0.93, green: 0.83, blue: 0.6).opacity(0.75))
                    .fixedSize()
                    .position(label.point)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.3), value: hud.labels)
    }
}

/// One pip per mote, drawn like the motes on the field - a ring around a spark -
/// so the counter reads as "these, collected" without a word.
private struct MotePips: View {
    let total: Int
    let collected: Int
    let theme: HUDTheme

    private var gold: Color {
        theme.style == .atlas ? theme.ink : Color(red: 1, green: 0.8, blue: 0.5)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                let lit = i < collected
                ZStack {
                    Circle()
                        .strokeBorder(lit ? gold : theme.ink.opacity(0.22), lineWidth: 1)
                    Image(systemName: "sparkle")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(lit ? gold : theme.ink.opacity(0.22))
                }
                .frame(width: 15, height: 15)
                .shadow(color: lit ? gold.opacity(0.8) : .clear, radius: 4)
                .scaleEffect(lit ? 1.1 : 1)
            }
        }
    }
}

private struct IconButton: View {
    let systemName: String
    let theme: HUDTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: theme.style == .light ? .light : .medium))
                .foregroundStyle(theme.ink.opacity(0.75))
                .frame(width: 40, height: 40)
                .background {
                    if theme.style == .atlas {
                        Circle().strokeBorder(theme.ink.opacity(0.35), lineWidth: 0.8)
                    } else {
                        Circle().fill(.white.opacity(0.08))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// A slim bar, not a card: the finished trajectory is the picture, so nothing covers it.
private struct ClearedCard: View {
    let motes: Int
    let shots: Int
    let isLast: Bool
    let theme: HUDTheme
    let onNext: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(theme.style == .atlas ? "Harmonia" : "Cleared")
                    .font(theme.font(22, .semibold))
                    .italic(theme.style == .atlas)
                    .foregroundStyle(theme.ink)
                Text("\(motes) of \(motes)  ·  \(shots == 1 ? "1 shot" : "\(shots) shots")")
                    .font(theme.mono(12))
                    .foregroundStyle(theme.ink.opacity(0.55))
            }
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            Button(action: onNext) {
                HStack(spacing: 6) {
                    Text(isLast ? "Again" : "Next sky")
                    Image(systemName: isLast ? "arrow.counterclockwise" : "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .font(theme.font(16, .semibold))
                .foregroundStyle(theme.style == .atlas ? Color(red: 0.05, green: 0.08, blue: 0.18) : .black)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Capsule().fill(theme.ink))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}
