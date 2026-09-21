import SwiftUI

enum Screen {
    case title, skies, playing
}

/// Over the live attract loop: the name, one line, two ways in.
struct TitleView: View {
    let onPlay: () -> Void
    let onSkies: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Text("PERIHELION")
                    .font(.system(size: 38, weight: .thin))
                    .tracking(11)
                    .foregroundStyle(.white)
                    .shadow(color: Color(red: 0.6, green: 0.75, blue: 1).opacity(0.6), radius: 18)
                Text("a gravity game that plays music")
                    .font(.system(size: 14, weight: .light))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            Spacer()
            VStack(spacing: 12) {
                Button(action: onPlay) {
                    Text("Play")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                Button(action: onSkies) {
                    Text("Skies")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Text("real gravity · every pass is a note")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .opacity(appeared ? 1 : 0)
        }
        .background(alignment: .bottom) {
            // a little darkness under the buttons, so the sky stays the picture
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.2)) { appeared = true }
        }
    }
}

/// Every sky as a small star chart, cleared ones marked with the best shot count.
struct SkiesView: View {
    let levels: [LevelDef]
    let progress: Progress
    let onPick: (Int) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("SKIES")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(levels.enumerated()), id: \.element.id) { index, def in
                        Button { onPick(index) } label: {
                            SkyCard(number: index + 1, def: def, best: progress.bestShots(def.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(Color.black.opacity(0.72).ignoresSafeArea())
    }
}

private struct SkyCard: View {
    let number: Int
    let def: LevelDef
    let best: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkyDiagram(def: def)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.02, green: 0.025, blue: 0.06)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Text(def.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(best.map { $0 == 1 ? "cleared · 1 shot" : "cleared · \($0) shots" } ?? "\(def.motes.count) motes")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(best == nil ? .white.opacity(0.35) : Color(red: 1, green: 0.8, blue: 0.5))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(best == nil ? 0.08 : 0.2), lineWidth: 1))
    }
}

/// The sky drawn like the game frames it: world rotated a quarter turn, launch at
/// the bottom. Bodies sit where they start; orbits, the figure-eight and the motes
/// are traced faintly.
struct SkyDiagram: View {
    let def: LevelDef

    var body: some View {
        Canvas { context, size in
            let level = Level(def)
            var positions = [SIMD2<Double>](repeating: .zero, count: level.bodies.count)
            level.positions(at: 0, into: &positions)
            let scale = min(size.width / Sim.height, size.height / Sim.width) * 0.92
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ w: SIMD2<Double>) -> CGPoint {
                CGPoint(x: center.x + scale * (w.y - Sim.height / 2), y: center.y - scale * (w.x - Sim.width / 2))
            }

            // orbits, and the figure-eight once
            var drewEight = false
            for (i, body) in level.bodies.enumerated() {
                if case let .orbit(parent, c, radius, _, _) = body.path {
                    let hub = point(parent >= 0 ? positions[parent] : c)
                    let r = radius * scale
                    context.stroke(Path(ellipseIn: CGRect(x: hub.x - r, y: hub.y - r, width: 2 * r, height: 2 * r)),
                                   with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
                }
                if case let .choreography(_, _, _, tau, _, _, _) = body.path, !drewEight {
                    drewEight = true
                    var eight = Path()
                    var probe = [SIMD2<Double>](repeating: .zero, count: level.bodies.count)
                    for step in 0...120 {
                        level.positions(at: Double(step) / 120 * Choreography.period * tau, into: &probe)
                        let p = point(probe[i])
                        if step == 0 { eight.move(to: p) } else { eight.addLine(to: p) }
                    }
                    context.stroke(eight, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
                }
            }

            // motes
            for m in level.motes {
                let p = point(m)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)),
                             with: .color(Color(red: 1, green: 0.78, blue: 0.45).opacity(0.85)))
            }

            // bodies, with a little glow on anything that shines
            for (i, body) in level.bodies.enumerated() {
                let p = point(positions[i])
                let r = max(body.radius * scale, 2)
                let rgb = Palette.bodyColor(body)
                let color = Color(red: Double(pow(rgb.x, 1 / 2.2)), green: Double(pow(rgb.y, 1 / 2.2)), blue: Double(pow(rgb.z, 1 / 2.2)))
                if body.kind == .star || body.kind == .hole {
                    let halo = r * 4
                    context.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: 2 * halo, height: 2 * halo)),
                                 with: .radialGradient(Gradient(colors: [color.opacity(0.45), .clear]),
                                                       center: p, startRadius: 0, endRadius: halo))
                }
                let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                context.fill(disc, with: .color(body.kind == .hole ? .black : color))
                if body.kind == .hole {
                    context.stroke(disc, with: .color(Color(red: 1, green: 0.65, blue: 0.3)), lineWidth: 1)
                }
            }

            // launch
            let launch = point(level.launch)
            context.stroke(Path(ellipseIn: CGRect(x: launch.x - 3.5, y: launch.y - 3.5, width: 7, height: 7)),
                           with: .color(.white.opacity(0.7)), lineWidth: 0.8)
        }
    }
}
