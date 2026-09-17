import SwiftUI

struct HUDView: View {
    let hud: HUDModel
    let onNext: () -> Void
    let onRestart: () -> Void
    let onToggleSound: () -> Void

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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PERIHELION")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(.white.opacity(0.4))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%02d", hud.levelNumber))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(hud.levelName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                MotePips(total: hud.moteCount, collected: hud.collected)
                    .padding(.top, 2)
            }
            .allowsHitTesting(false)
            Spacer()
            HStack(spacing: 10) {
                IconButton(systemName: hud.muted ? "speaker.slash" : "speaker.wave.2", action: onToggleSound)
                IconButton(systemName: "arrow.counterclockwise", action: onRestart)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let toast = hud.toast, !hud.cleared {
                Text(toast)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .allowsHitTesting(false)
            }
            if hud.cleared {
                ClearedCard(motes: hud.moteCount, shots: hud.shots, isLast: hud.isLastLevel, onNext: onNext)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if hud.hintVisible {
                    Text(hud.hint)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                Text(hud.shots == 1 ? "1 shot" : "\(hud.shots) shots")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .opacity(hud.shots > 0 ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct MotePips: View {
    let total: Int
    let collected: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(i < collected ? Color(red: 1, green: 0.8, blue: 0.5) : .white.opacity(0.18))
                    .scaleEffect(i < collected ? 1.15 : 1)
            }
        }
    }
}

private struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct ClearedCard: View {
    let motes: Int
    let shots: Int
    let isLast: Bool
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Cleared")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
            Text("\(motes) of \(motes)  ·  \(shots == 1 ? "1 shot" : "\(shots) shots")")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Button(action: onNext) {
                Text(isLast ? "Play again" : "Next sky")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            Text("or drag to fly this sky again")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .environment(\.colorScheme, .dark)
    }
}
