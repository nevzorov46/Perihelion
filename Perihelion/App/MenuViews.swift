import SwiftUI

enum Screen {
    case title, skies, settings, playing
}

/// Over the live attract loop: the name, one line, two ways in.
struct TitleView: View {
    let onPlay: () -> Void
    let onSkies: () -> Void
    let onSettings: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("PERIHELION")
                    .font(.system(size: 38, weight: .thin))
                    .tracking(11)
                    .padding(.leading, 11) // tracking pads the last letter; re-centre
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 8)
                    .shadow(color: Color(red: 0.6, green: 0.75, blue: 1).opacity(0.55), radius: 18)
                Text("a gravity game where orbits play notes")
                    .font(.system(size: 15, weight: .light))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.88))
                    // a dark halo keeps the thin type legible over any flare behind it
                    .shadow(color: .black, radius: 3)
                    .shadow(color: .black.opacity(0.8), radius: 10)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 26)
            .background {
                Ellipse()
                    .fill(.black.opacity(0.55))
                    .blur(radius: 28)
                    .allowsHitTesting(false)
            }
            .padding(.top, 34)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -10)
            Spacer()
            VStack(spacing: 26) {
                OrbitButton(title: "PLAY", action: onPlay)
                Button(action: onSkies) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.5))
                        Text("SKIES")
                            .font(.system(size: 13, weight: .medium))
                            .tracking(5)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressFade())
                Button(action: onSettings) {
                    Text("SETTINGS")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressFade())
            }
            .padding(.bottom, 26)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            // a little darkness under the controls, so the sky stays the picture
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).delay(0.2)) { appeared = true }
        }
    }
}

/// The play button as a tiny orbit: a comet circles a faint ring, trailing light.
/// Pressing it speeds the comet up and brightens the ring, like a pass at perihelion.
struct OrbitButton: View {
    let title: String
    let action: () -> Void
    @State private var pressed = false
    @State private var phase: Double = 0
    @State private var lastTick: Date?

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 10
                let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
                let glow = pressed ? 0.45 : 0.28

                // soft light inside the orbit
                context.fill(ring, with: .radialGradient(Gradient(colors: [.white.opacity(pressed ? 0.12 : 0.06), .clear]),
                                                         center: center, startRadius: 0, endRadius: radius))
                context.stroke(ring, with: .color(.white.opacity(glow * 0.6)), lineWidth: 0.8)

                // the comet's trail: a fading arc behind it
                let head = Angle(radians: phase)
                var trail = Path()
                trail.addArc(center: center, radius: radius, startAngle: head - .degrees(140), endAngle: head, clockwise: false)
                // the conic gradient runs a full turn from the tail's end; the trail spans 140° of it
                let span = 140.0 / 360.0
                context.stroke(trail, with: .conicGradient(
                    Gradient(stops: [.init(color: .clear, location: 0),
                                     .init(color: .white.opacity(0.95), location: span),
                                     .init(color: .clear, location: span + 0.001)]),
                    center: center, angle: head - .degrees(140)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

                // the comet itself, with a glow
                let p = CGPoint(x: center.x + radius * cos(phase), y: center.y + radius * sin(phase))
                let halo: CGFloat = pressed ? 16 : 12
                context.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: 2 * halo, height: 2 * halo)),
                             with: .radialGradient(Gradient(colors: [Color(red: 0.7, green: 0.95, blue: 1).opacity(0.9), .clear]),
                                                   center: p, startRadius: 0, endRadius: halo))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.white))
            }
            .onChange(of: now) { _, date in
                let dt = lastTick.map { date.timeIntervalSince($0) } ?? 0
                lastTick = date
                phase += min(dt, 0.05) * (pressed ? 7 : 1.6)
            }
        }
        .frame(width: 148, height: 148)
        .overlay {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .tracking(7)
                .foregroundStyle(.white)
                .padding(.leading, 7) // tracking adds space after the last letter; re-centre
                .shadow(color: .white.opacity(0.5), radius: pressed ? 10 : 4)
        }
        .scaleEffect(pressed ? 0.95 : 1)
        .animation(.spring(duration: 0.3), value: pressed)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { value in
                    pressed = false
                    if hypot(value.translation.width, value.translation.height) < 40 { action() }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(Text(title.capitalized))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// Dims a text button while it is held.
struct PressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.5 : 1)
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
