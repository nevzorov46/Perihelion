import Foundation
import simd

/// Turns the session's state into this frame's GPU geometry: ribbons and one
/// instanced batch of sprites, in draw order. Arrays keep their capacity between
/// frames, so steady-state frames allocate nothing.
///
/// Each visual style decides here how the same physics is drawn; the simulation
/// and the shaders' building blocks are shared.
final class SceneBuilder {
    private(set) var sprites: [PHSprite] = []
    private(set) var ribbon: [PHRibbonVertex] = []
    private(set) var strips: [Range<Int>] = []
    private(set) var grid = PHGridUniforms()
    private(set) var lens = PHLensUniforms()
    private var positions: [SIMD2<Double>] = []
    private var style = VisualStyle.observatory
    private var time: Float = 0

    func build(_ session: GameSession) {
        sprites.removeAll(keepingCapacity: true)
        ribbon.removeAll(keepingCapacity: true)
        strips.removeAll(keepingCapacity: true)
        style = session.style
        time = Float(session.clock)

        let level = session.level
        if positions.count != level.bodies.count {
            positions = Array(repeating: .zero, count: level.bodies.count)
        }
        level.positions(at: session.bodyTime, into: &positions)

        buildGrid(level)
        buildLens(session)
        if style == .atlas { chartFrame() }
        orbitGuides(level)
        trails(session)
        aim(session)
        bodies(session)
        motes(session)
        comet(session)
        particles(session)
    }

    // MARK: - Field

    private func buildGrid(_ level: Level) {
        grid = PHGridUniforms()
        let count = min(level.bodies.count, Int(PH_MAX_MASSES))
        withUnsafeMutableBytes(of: &grid.masses) { raw in
            let masses = raw.bindMemory(to: SIMD4<Float>.self)
            for i in 0..<count {
                let b = level.bodies[i]
                masses[i] = SIMD4(Float(positions[i].x), Float(positions[i].y), Float(b.mu), Float(b.radius))
            }
        }
        grid.count = Int32(count)
        switch style {
        case .observatory: grid.color = SIMD4(SIMD3(0.2, 0.42, 0.6) * 0.035, 0)
        case .light: grid.color = .zero
        case .atlas: grid.color = SIMD4(Ink.gold * 0.05, 0.05)
        }
    }

    /// Einstein radius grows with √μ; only the telescope look bends the sky.
    private func buildLens(_ session: GameSession) {
        lens = PHLensUniforms()
        lens.zoom = 1
        lens.aspect = 1
        let t = session.transform
        guard t.viewSize.width > 0 else { return }
        // the sky is far away: it drifts a fifth as much as the field
        let camera = session.camera
        let travel = camera.focus - SIMD2(Sim.width / 2, Sim.height / 2)
        lens.parallax = SIMD2(Float(t.fitScale * travel.y / Double(t.viewSize.width)),
                              Float(-t.fitScale * travel.x / Double(t.viewSize.height))) * 0.2
        lens.zoom = Float(1 + (camera.zoom - 1) * 0.2)
        lens.aspect = Float(t.viewSize.width / t.viewSize.height)
        guard style == .observatory else { return }
        let bodies = session.level.bodies
        let count = min(bodies.count, Int(PH_MAX_MASSES))
        withUnsafeMutableBytes(of: &lens.lenses) { raw in
            let lenses = raw.bindMemory(to: SIMD4<Float>.self)
            for i in 0..<count {
                let screen = t.toScreen(positions[i])
                let einstein = 0.011 * bodies[i].mu.squareRoot() * t.scale / Double(t.viewSize.height)
                lenses[i] = SIMD4(Float(screen.x / t.viewSize.width), Float(screen.y / t.viewSize.height),
                                  Float(einstein * einstein), 0)
            }
        }
        lens.count = Int32(count)
    }

    /// A cartographer's border: a double rule around the field, a hairline outside it.
    private func chartFrame() {
        let w = Float(Sim.width), h = Float(Sim.height)
        let rules: [(inset: Float, profile: PHRibbonProfile, width: Float)] = [(-16, PHRibbonDoubleRule, 9), (-34, PHRibbonHairline, 2.4)]
        for rule in rules {
            let i = rule.inset
            let corners = [SIMD2<Float>(i, i), SIMD2(w - i, i), SIMD2(w - i, h - i), SIMD2(i, h - i), SIMD2(i, i)]
            for k in 0..<4 {
                appendRibbon(count: 2, width: rule.width, profile: rule.profile) { j in
                    (corners[k + j], SIMD4(Ink.gold, 0.55))
                }
            }
        }
        let corners = [SIMD2<Double>(-25, -25), SIMD2(Sim.width + 25, -25), SIMD2(Sim.width + 25, Sim.height + 25), SIMD2(-25, Sim.height + 25)]
        for corner in corners {
            add(corner, 14, PHSpriteGlyph, SIMD4(Ink.gold, 0.8), SIMD4(.pi / 4, 0, 0, 0))
        }
    }

    private func orbitGuides(_ level: Level) {
        for (i, body) in level.bodies.enumerated() {
            guard case let .orbit(parent, center, radius, _, _) = body.path else { continue }
            let c = parent >= 0 ? positions[parent] : center
            let r = Float(radius)
            switch style {
            case .observatory:
                let dots = Int(2 * .pi * radius / 16)
                let color = Palette.bodyColor(body) * 0.3
                for k in 0..<dots {
                    let a = Double(k) / Double(dots) * 2 * .pi + Double(time) * 0.02 * Double(i + 1)
                    add(SIMD2(c.x + radius * cos(a), c.y + radius * sin(a)), 1.4, PHSpriteDisc, SIMD4(color, 0))
                }
            case .light:
                add(c, r + 6, PHSpriteRing, SIMD4(SIMD3(repeating: 0.1), 0), SIMD4(r / (r + 6), 0.004, 0, 0))
            case .atlas:
                add(c, r + 8, PHSpriteChartRing, SIMD4(Ink.gold, 0.4), SIMD4(r / (r + 8), 0, 0, 90))
            }
        }
    }

    // MARK: - Trails

    private func trails(_ session: GameSession) {
        switch style {
        case .observatory:
            // the last three attempts, the newest brightest: something to correct against
            for (age, ghost) in session.ghosts.suffix(3).reversed().enumerated() {
                appendRibbon(count: ghost.count, width: 2.6, profile: PHRibbonGlow) { i in
                    (ghost[i], SIMD4(SIMD3(0.55, 0.7, 1.0), [0.42, 0.22, 0.12][age]))
                }
            }
        case .light:
            // light painting keeps every recent attempt: the picture builds up
            for (g, ghost) in session.ghosts.enumerated() {
                let age = Float(session.ghosts.count - g)
                appendRibbon(count: ghost.count, width: 2, profile: PHRibbonFilament) { i in
                    (ghost[i], SIMD4(Self.iridescent(Float(i) * 0.004 + Float(g) * 0.13), 0.16 / age))
                }
            }
        case .atlas:
            if let ghost = session.ghosts.last {
                appendRibbon(count: ghost.count, width: 2.4, profile: PHRibbonHairline, dash: 16) { i in
                    (ghost[i], SIMD4(Ink.gold, 0.45))
                }
            }
        }

        let trail = session.trail
        guard trail.count > 1 else { return }
        let opacity = session.trailOpacity
        let n = trail.count
        // once cleared, a wave of light runs the whole path from launch to finish
        var wave: Float = -1
        if let completedAt = session.completedAt {
            wave = Float(session.clock - completedAt - 0.25) / 1.5
        }
        func heat(_ i: Int) -> Float {
            let head = 2.6 * max(0, 1 - Float(n - 1 - i) / 70)
            guard wave > -0.2 && wave < 1.2 else { return 1 + head }
            let x = (Float(i) / Float(n) - wave) / 0.07
            return 1 + head + 3.5 * exp(-x * x)
        }

        switch style {
        case .observatory:
            // the dust tail: warm, left behind along the orbit
            appendRibbon(count: n, width: 20, profile: PHRibbonGlow) { i in
                (trail[i].position, SIMD4(SIMD3(1.0, 0.72, 0.42), 0.16 * heat(i) * opacity))
            }
            appendRibbon(count: n, width: 3.4, profile: PHRibbonFilament) { i in
                let fast = simd_clamp((trail[i].speed - 150) / 900, 0, 1)
                let color = simd_mix(SIMD3<Float>(1.0, 0.85, 0.65), SIMD3(0.7, 0.92, 1.0), SIMD3(repeating: fast))
                return (trail[i].position, SIMD4(color, 1.1 * heat(i) * opacity))
            }
        case .light:
            // slow is wide, fast is thin - like a hand moving a light
            let width: (Int) -> Float = { i in simd_clamp(520 / max(trail[i].speed, 1), 0.55, 2.4) }
            appendRibbon(count: n, width: 26, widthScale: width, profile: PHRibbonGlow) { i in
                (trail[i].position, SIMD4(Self.iridescent(Float(i) * 0.004), 0.2 * heat(i) * opacity))
            }
            appendRibbon(count: n, width: 4.2, widthScale: width, profile: PHRibbonFilament) { i in
                (trail[i].position, SIMD4(Self.iridescent(Float(i) * 0.004) * 0.6 + 0.4, 1.4 * heat(i) * opacity))
            }
            for strand in 0..<2 {
                let phase = Float(strand) * .pi
                appendRibbon(count: n, width: 1.5, offset: { along in 7 * sin(along / 34 + phase) }, profile: PHRibbonFilament) { i in
                    (trail[i].position, SIMD4(Self.iridescent(Float(i) * 0.004 + 0.33 + Float(strand) * 0.2), 0.8 * opacity))
                }
            }
        case .atlas:
            appendRibbon(count: n, width: 8, profile: PHRibbonDoubleRule) { i in
                (trail[i].position, SIMD4(Ink.gold, 0.95 * opacity))
            }
        }
    }

    // MARK: - Aim

    private func aim(_ session: GameSession) {
        let launch = session.level.launch
        let power = Float(session.aimPower)
        let aiming = session.aim != nil

        switch style {
        case .observatory:
            if aiming {
                add(launch, 34, PHSpriteRing, SIMD4(SIMD3(0.7, 0.85, 1.0) * (0.5 + power), 0), SIMD4(0.55 + 0.35 * power, 0.05, 0, 0))
            } else {
                add(launch, 30, PHSpriteRing, SIMD4(SIMD3(0.5, 0.6, 0.9) * (0.35 + 0.1 * sin(time * 2)), 0), SIMD4(0.75, 0.04, 0, 0))
            }
            let n = session.prediction.count
            for (i, p) in session.prediction.enumerated() {
                let fade = 1 - Float(i) / Float(max(n, 1))
                add(SIMD2<Double>(p), 7, PHSpriteGlow, SIMD4(Palette.comet * (0.9 * fade * fade + 0.05), 0))
            }
        case .light:
            let level: Float = aiming ? 0.4 + power : 0.25 + 0.08 * sin(time * 2)
            add(launch, 30, PHSpriteRing, SIMD4(SIMD3(repeating: level), 0), SIMD4(aiming ? 0.5 + 0.4 * power : 0.7, 0.03, 0, 0))
            let prediction = session.prediction
            let n = prediction.count
            appendRibbon(count: n, width: 2, profile: PHRibbonFilament) { i in
                let fade = 1 - Float(i) / Float(n)
                return (prediction[i], SIMD4(SIMD3(repeating: 1), 0.7 * fade * fade))
            }
        case .atlas:
            let radius: Float = aiming ? 26 + 14 * power : 26
            add(launch, radius + 10, PHSpriteChartRing, SIMD4(Ink.gold, 0.8), SIMD4(radius / (radius + 10), 24, 0.1, 0))
            let n = session.prediction.count
            for (i, p) in session.prediction.enumerated() {
                let fade = 1 - Float(i) / Float(max(n, 1))
                add(SIMD2<Double>(p), 2.2, PHSpriteDisc, SIMD4(Ink.ivory * fade, fade))
            }
        }
    }

    // MARK: - Bodies

    private func bodies(_ session: GameSession) {
        let level = session.level
        let lightSource = level.bodies.indices.first { level.bodies[$0].kind == .star || level.bodies[$0].kind == .hole }
        for (i, body) in level.bodies.enumerated() {
            let p = positions[i]
            let r = Float(body.radius)
            let color = Palette.bodyColor(body)
            var light = SIMD2<Float>(-0.5, 0.75)
            if let lightSource, lightSource != i {
                let d = positions[lightSource] - p
                light = simd_normalize(SIMD2(Float(d.y), Float(d.x))) // world → screen axes (x right, y up)
            }

            switch (style, body.kind) {
            case (.observatory, .star):
                let flicker = 1 + 0.04 * sin(time * 3.1 + Float(i) * 1.7)
                let flare = Float(session.slowness)
                add(p, r * 9 * (1 + 0.3 * flare), PHSpriteGlow, SIMD4(color * 1.2 * flicker * (1 + 0.55 * flare), 0))
                add(p, r * 17 * (1 + 0.5 * flare), PHSpriteSpikes, SIMD4(color * 0.9 * (1 + 0.85 * flare), 0))
                add(p, r, PHSpriteStar, SIMD4(color * 1.35, 1), SIMD4(Float(i) * 13.7, 0, 0, 0))
            case (.observatory, .planet), (.observatory, .moon):
                add(p, r * 5.5, PHSpriteGlow, SIMD4(color * 0.3, 0))
                add(p, r * 2.4, PHSpriteRing, SIMD4(color * 0.5, 0), SIMD4(0.62, 0.05, 0, 0))
                add(p, r, PHSpritePlanet, SIMD4(color, 1), SIMD4(light.x, light.y, 7 + Float(i) * 3, Float(i) * 5.3))
            case (.observatory, .hole):
                add(p, r * 9, PHSpriteGlow, SIMD4(Palette.accretion * 0.22, 0))
                add(p, r * 3, PHSpriteHole, SIMD4(Palette.accretion * 1.6, 1))

            case (.light, .star):
                add(p, r * 6, PHSpriteGlow, SIMD4(color * 0.5, 0))
                add(p, r * 1.6, PHSpriteRing, SIMD4(color * 2.2, 0), SIMD4(0.72, 0.035, 0, 0))
                add(p, r * 0.4, PHSpriteDisc, SIMD4(SIMD3(repeating: 3), 0))
            case (.light, .planet), (.light, .moon):
                add(p, r * 3, PHSpriteGlow, SIMD4(color * 0.12, 0))
                add(p, r * 1.4, PHSpriteRing, SIMD4(color * 1.3, 0), SIMD4(0.7, 0.05, 0, 0))
            case (.light, .hole):
                add(p, r * 1.6, PHSpriteRing, SIMD4(SIMD3(1.0, 0.8, 0.6) * 2, 0), SIMD4(0.66, 0.03, 0, 0))
                add(p, r, PHSpriteDisc, SIMD4(.zero, 1))

            case (.atlas, .star):
                add(p, r * 4.6, PHSpriteChartRing, SIMD4(Ink.gold, 0.6), SIMD4(0.92, 72, 0.025, 0))
                add(p, r * 3.3, PHSpriteEngravedSun, SIMD4(Ink.gold, 1), SIMD4(1 / 3.3, time * 0.04 + Float(i), 0, 0))
            case (.atlas, .planet), (.atlas, .moon):
                add(p, r * 1.15, PHSpriteEngravedPlanet, SIMD4(Ink.gold, 1), SIMD4(light.x, light.y, 1 / 1.15, 0))
            case (.atlas, .hole):
                add(p, r * 3.2, PHSpriteChartRing, SIMD4(Ink.gold, 0.7), SIMD4(0.75, 36, 0.05, 0))
                add(p, r * 1.8, PHSpriteChartRing, SIMD4(Ink.gold, 0.6), SIMD4(0.9, 0, 0, 40))
                add(p, r * 1.05, PHSpriteDisc, SIMD4(SIMD3(0.002, 0.004, 0.012), 1))
            }

            for pulse in session.pulses where pulse.body == i {
                let age = Float(session.clock - pulse.start)
                let fade = max(0, 1 - age / 1.4)
                let quad = r * 7
                let radius = (r * 1.25 + age * r * 4.5) / quad
                switch style {
                case .observatory:
                    add(p, quad, PHSpriteRing, SIMD4(color * 1.6 * pulse.strength * fade * fade, 0), SIMD4(radius, 0.025, 0, 0))
                case .light:
                    add(p, quad, PHSpriteRing, SIMD4(Self.iridescent(age * 0.5 + Float(i) * 0.3) * 2 * pulse.strength * fade, 0),
                        SIMD4(radius, 0.02, 0, 0))
                case .atlas:
                    add(p, quad, PHSpriteChartRing, SIMD4(Ink.ivory, fade * pulse.strength), SIMD4(radius, 0, 0, 60))
                }
            }
        }
    }

    // MARK: - Motes

    private func motes(_ session: GameSession) {
        for (i, m) in session.level.motes.enumerated() {
            let breathe = 0.8 + 0.2 * sin(time * 2.3 + Float(i) * 1.9)
            if let at = session.collectedAt[i] {
                let age = Float(session.clock - at)
                let fade = max(0, 1 - age / 0.9)
                switch style {
                case .observatory:
                    if fade > 0 { add(m, 70, PHSpriteRing, SIMD4(Palette.mote * 2.2 * fade, 0), SIMD4(0.15 + age * 0.9, 0.03, 0, 0)) }
                    add(m, 12, PHSpriteGlow, SIMD4(Palette.mote * 0.25, 0))
                case .light:
                    if fade > 0 { add(m, 80, PHSpriteRing, SIMD4(Self.iridescent(Float(i) * 0.2) * 2.5 * fade, 0), SIMD4(0.1 + age, 0.02, 0, 0)) }
                    add(m, 10, PHSpriteGlow, SIMD4(Self.iridescent(Float(i) * 0.2) * 0.4, 0))
                case .atlas:
                    if fade > 0 { add(m, 60, PHSpriteChartRing, SIMD4(Ink.ivory, fade), SIMD4(0.2 + age * 0.85, 16, 0.04, 0)) }
                    add(m, 10, PHSpriteGlyph, SIMD4(Ink.ivory, 0.55))
                }
            } else {
                switch style {
                case .observatory:
                    // a ring and no spikes: spikes mean "star", the ring means "take me"
                    add(m, 44, PHSpriteGlow, SIMD4(Palette.mote * 0.5 * breathe, 0))
                    add(m, 34, PHSpriteRing, SIMD4(Palette.mote * 0.9 * breathe, 0), SIMD4(0.74 + 0.04 * sin(time * 2.3 + Float(i) * 1.9), 0.035, 0, 0))
                    add(m, 26, PHSpriteSparkle, SIMD4(Palette.mote * 2.4 * breathe, 0), SIMD4(time * 0.25 + Float(i), 0, 0, 0))
                case .light:
                    add(m, 16, PHSpriteGlow, SIMD4(SIMD3(repeating: 0.5 * breathe), 0))
                    add(m, 2.6, PHSpriteDisc, SIMD4(SIMD3(repeating: 3), 0))
                case .atlas:
                    add(m, 16, PHSpriteGlyph, SIMD4(Ink.gold, 1), SIMD4(time * 0.15 + Float(i), 0, 0, 0))
                }
            }
        }
    }

    // MARK: - Comet

    private func comet(_ session: GameSession) {
        let position: SIMD2<Double>
        if let flight = session.flight {
            guard session.cometVisible else { return }
            position = flight.position
        } else if !session.isRewinding {
            position = session.level.launch
        } else {
            return
        }
        let resting = session.flight == nil
        let breathe: Float = resting ? 0.8 + 0.2 * sin(time * 2) : 1

        switch style {
        case .observatory:
            if !resting { ionTail(session, from: position) }
            add(position, 46, PHSpriteGlow, SIMD4(SIMD3(0.7, 0.9, 1.0) * 1.3 * breathe, 0))
            add(position, 4.5, PHSpriteDisc, SIMD4(SIMD3(repeating: 6 * breathe), 0))
        case .light:
            add(position, 28, PHSpriteGlow, SIMD4(SIMD3(repeating: 1.2 * breathe), 0))
            add(position, 3.5, PHSpriteDisc, SIMD4(SIMD3(repeating: 8 * breathe), 0))
        case .atlas:
            add(position, 14, PHSpriteGlyph, SIMD4(Ink.ivory, 1), SIMD4(0.3, 0, 0, 0))
        }
    }

    /// The ion tail points straight away from the star, whatever the comet's heading.
    private func ionTail(_ session: GameSession, from head: SIMD2<Double>) {
        let bodies = session.level.bodies
        let stars = bodies.indices.filter { bodies[$0].kind == .star || bodies[$0].kind == .hole }
        guard let star = stars.min(by: { simd_distance(positions[$0], head) < simd_distance(positions[$1], head) }) else { return }
        let away = head - positions[star]
        let distance = max(simd_length(away), 1)
        let direction = SIMD2<Float>(away / distance)
        let length = Float(min(max(bodies[star].mu * 1.4e-3 / distance, 30), 240))
        let base = SIMD2<Float>(head)
        let n = 16
        appendRibbon(count: n, width: 16, widthScale: { i in 0.25 + Float(i) / Float(n) }, profile: PHRibbonGlow) { i in
            let t = Float(i) / Float(n - 1)
            return (base + direction * length * t, SIMD4(SIMD3(0.35, 0.6, 1.0), 1.4 * (1 - t) * (1 - t)))
        }
    }

    private func particles(_ session: GameSession) {
        for (k, particle) in session.particles.enumerated() {
            let fade = 1 - particle.age / particle.life
            switch style {
            case .observatory:
                sprite(particle.position, particle.size, PHSpriteGlow, SIMD4(particle.color * 1.8 * fade * fade, 0))
            case .light:
                sprite(particle.position, particle.size, PHSpriteGlow, SIMD4(Self.iridescent(Float(k) * 0.07) * 1.8 * fade * fade, 0))
            case .atlas:
                sprite(particle.position, particle.size * 0.35, PHSpriteDisc, SIMD4(Ink.gold * fade, fade))
            }
        }
    }

    // MARK: - Helpers

    private enum Ink {
        static let gold = SIMD3<Float>(0.86, 0.56, 0.2)
        static let ivory = SIMD3<Float>(0.90, 0.84, 0.68)
    }

    /// A soft spectral cycle (cosine palette), for light painting.
    private static func iridescent(_ t: Float) -> SIMD3<Float> {
        let phase = SIMD3<Float>(0, 0.33, 0.67)
        let angle = (SIMD3(repeating: t) + phase) * (2 * .pi)
        let spectrum = SIMD3<Float>(repeating: 0.5) + 0.5 * SIMD3(cos(angle.x), cos(angle.y), cos(angle.z))
        return simd_mix(SIMD3(repeating: 0.75), spectrum, SIMD3(repeating: 0.8))
    }

    private func add(_ p: SIMD2<Double>, _ radius: Float, _ kind: PHSpriteKind, _ color: SIMD4<Float>,
                     _ params: SIMD4<Float> = .zero) {
        sprite(SIMD2<Float>(p), radius, kind, color, params)
    }

    private func sprite(_ p: SIMD2<Float>, _ radius: Float, _ kind: PHSpriteKind, _ color: SIMD4<Float>,
                        _ params: SIMD4<Float> = .zero) {
        sprites.append(PHSprite(position: p, radius: radius, kind: Int32(kind.rawValue), color: color, params: params))
    }

    /// A triangle strip along a polyline. `width` is in world units; `widthScale`
    /// varies it per point, `offset` shifts the strip sideways by arc length.
    private func appendRibbon(count: Int, width: Float, widthScale: ((Int) -> Float)? = nil,
                              offset: ((Float) -> Float)? = nil, profile: PHRibbonProfile, dash: Float = 0,
                              _ point: (Int) -> (SIMD2<Float>, SIMD4<Float>)) {
        guard count > 1 else { return }
        let start = ribbon.count
        let params = SIMD4<Float>(Float(profile.rawValue), dash, 0, 0)
        var previous = point(0).0
        var along: Float = 0
        for i in 0..<count {
            let (p, color) = point(i)
            let next = i + 1 < count ? point(i + 1).0 : p
            along += simd_distance(p, previous)
            var tangent = next - previous
            let length = simd_length(tangent)
            tangent = length > 1e-4 ? tangent / length : SIMD2(1, 0)
            let normal = SIMD2(-tangent.y, tangent.x)
            let center = p + normal * (offset?(along) ?? 0)
            let half = width * (widthScale?(i) ?? 1) / 2
            ribbon.append(PHRibbonVertex(position: center + normal * half, across: -1, along: along, color: color, params: params))
            ribbon.append(PHRibbonVertex(position: center - normal * half, across: 1, along: along, color: color, params: params))
            previous = p
        }
        strips.append(start..<ribbon.count)
    }
}
