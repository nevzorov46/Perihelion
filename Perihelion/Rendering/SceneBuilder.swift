import Foundation
import simd

/// Turns the session's state into this frame's GPU geometry: trail ribbons and
/// one instanced batch of sprites, in draw order. Arrays keep their capacity
/// between frames, so steady-state frames allocate nothing.
final class SceneBuilder {
    private(set) var sprites: [PHSprite] = []
    private(set) var ribbon: [PHRibbonVertex] = []
    private(set) var strips: [Range<Int>] = []
    private(set) var grid = PHGridUniforms()
    private var positions: [SIMD2<Double>] = []

    func build(_ session: GameSession) {
        sprites.removeAll(keepingCapacity: true)
        ribbon.removeAll(keepingCapacity: true)
        strips.removeAll(keepingCapacity: true)

        let level = session.level
        let time = Float(session.clock)
        if positions.count != level.bodies.count {
            positions = Array(repeating: .zero, count: level.bodies.count)
        }
        level.positions(at: session.bodyTime, into: &positions)

        buildGrid(level)
        orbitGuides(level, time: time)
        trails(session)
        aim(session, time: time)
        bodies(session, time: time)
        motes(session, time: time)
        comet(session, time: time)
        particles(session)
    }

    // MARK: - Pieces

    private func buildGrid(_ level: Level) {
        grid = PHGridUniforms()
        let count = min(level.bodies.count, Int(PH_MAX_GRID_MASSES))
        withUnsafeMutableBytes(of: &grid.masses) { raw in
            let masses = raw.bindMemory(to: SIMD4<Float>.self)
            for i in 0..<count {
                let b = level.bodies[i]
                masses[i] = SIMD4(Float(positions[i].x), Float(positions[i].y), Float(b.mu), Float(b.radius))
            }
        }
        grid.count = Int32(count)
        grid.intensity = 0.055
    }

    private func orbitGuides(_ level: Level, time: Float) {
        for (i, body) in level.bodies.enumerated() {
            guard case let .orbit(parent, center, radius, _, _) = body.path else { continue }
            let c = parent >= 0 ? positions[parent] : center
            let dots = Int(2 * .pi * radius / 16)
            let color = Palette.bodyColor(body) * 0.35
            for k in 0..<dots {
                let a = Double(k) / Double(dots) * 2 * .pi + Double(time) * 0.02 * Double(i + 1)
                let p = SIMD2(c.x + radius * cos(a), c.y + radius * sin(a))
                add(p, 1.4, PHSpriteDisc, SIMD4(color, 0))
            }
        }
    }

    private func trails(_ session: GameSession) {
        if session.ghost.count > 1 {
            appendRibbon(count: session.ghost.count, width: 2.2) { i in
                (session.ghost[i], SIMD4(Palette.ghost, 0.2))
            }
        }
        let trail = session.trail
        guard trail.count > 1 else { return }
        let opacity = session.trailOpacity
        let n = trail.count
        func color(_ i: Int, _ gain: Float) -> SIMD4<Float> {
            let fast = simd_clamp((trail[i].speed - 150) / 900, 0, 1)
            let fromHead = Float(n - 1 - i)
            let heat = 1 + 2.6 * max(0, 1 - fromHead / 70)
            return SIMD4(simd_mix(Palette.trailSlow, Palette.trailFast, SIMD3(repeating: fast)), gain * heat * opacity)
        }
        appendRibbon(count: n, width: 16) { i in (trail[i].position, color(i, 0.3)) }
        appendRibbon(count: n, width: 3.4) { i in (trail[i].position, color(i, 1.5)) }
    }

    private func aim(_ session: GameSession, time: Float) {
        let launch = session.level.launch
        guard session.aim != nil else {
            // launch pad, breathing
            add(launch, 30, PHSpriteRing, SIMD4(Palette.trailSlow * (0.35 + 0.1 * sin(time * 2)), 0), SIMD4(0.75, 0.04, 0, 0))
            return
        }
        let power = Float(session.aimPower)
        add(launch, 34, PHSpriteRing, SIMD4(simd_mix(Palette.trailSlow, Palette.trailFast, SIMD3(repeating: power)) * (0.5 + power), 0),
            SIMD4(0.55 + 0.35 * power, 0.05, 0, 0))
        let n = session.prediction.count
        for (i, p) in session.prediction.enumerated() {
            let fade = 1 - Float(i) / Float(max(n, 1))
            add(SIMD2<Double>(p), 7, PHSpriteGlow, SIMD4(Palette.comet * (0.9 * fade * fade + 0.05), 0))
        }
    }

    private func bodies(_ session: GameSession, time: Float) {
        let level = session.level
        let star = level.bodies.indices.first { level.bodies[$0].kind == .star || level.bodies[$0].kind == .hole }
        for (i, body) in level.bodies.enumerated() {
            let p = positions[i]
            let r = Float(body.radius)
            let color = Palette.bodyColor(body)
            switch body.kind {
            case .star:
                let flicker = 1 + 0.04 * sin(time * 3.1 + Float(i) * 1.7)
                add(p, r * 8, PHSpriteGlow, SIMD4(color * 1.25 * flicker, 0))
                add(p, r, PHSpriteStar, SIMD4(color * 1.35, 1), SIMD4(Float(i) * 13.7, 0, 0, 0))
            case .planet, .moon:
                // light comes from the brightest body, turned into screen axes (x right, y up)
                var light = SIMD2<Float>(-0.5, 0.75)
                if let star {
                    let d = positions[star] - p
                    light = simd_normalize(SIMD2(Float(d.y), Float(d.x)))
                }
                add(p, r * 3.2, PHSpriteGlow, SIMD4(color * 0.16, 0))
                add(p, r, PHSpritePlanet, SIMD4(color, 1), SIMD4(light.x, light.y, 7 + Float(i) * 3, Float(i) * 5.3))
            case .hole:
                add(p, r * 9, PHSpriteGlow, SIMD4(Palette.accretion * 0.22, 0))
                add(p, r * 3, PHSpriteHole, SIMD4(Palette.accretion * 1.6, 1))
            }
            for pulse in session.pulses where pulse.body == i {
                let age = Float(session.clock - pulse.start)
                let quad = r * 7
                let fade = max(0, 1 - age / 1.4)
                add(p, quad, PHSpriteRing, SIMD4(color * 1.6 * pulse.strength * fade * fade, 0),
                    SIMD4((r * 1.25 + age * r * 4.5) / quad, 0.025, 0, 0))
            }
        }
    }

    private func motes(_ session: GameSession, time: Float) {
        for (i, m) in session.level.motes.enumerated() {
            if let at = session.collectedAt[i] {
                let age = Float(session.clock - at)
                if age < 0.9 {
                    let fade = 1 - age / 0.9
                    add(m, 70, PHSpriteRing, SIMD4(Palette.mote * 2.2 * fade, 0), SIMD4(0.15 + age * 0.9, 0.03, 0, 0))
                }
                add(m, 12, PHSpriteGlow, SIMD4(Palette.mote * 0.25, 0))
            } else {
                let breathe = 0.8 + 0.2 * sin(time * 2.3 + Float(i) * 1.9)
                add(m, 34, PHSpriteGlow, SIMD4(Palette.mote * 0.45 * breathe, 0))
                add(m, 22, PHSpriteSparkle, SIMD4(Palette.mote * 2.4 * breathe, 0), SIMD4(time * 0.25 + Float(i), 0, 0, 0))
            }
        }
    }

    private func comet(_ session: GameSession, time: Float) {
        if let flight = session.flight {
            guard session.cometVisible else { return }
            add(flight.position, 40, PHSpriteGlow, SIMD4(Palette.comet * 1.3, 0))
            add(flight.position, 4.5, PHSpriteDisc, SIMD4(SIMD3(repeating: 6), 0))
        } else if !session.isRewinding {
            let breathe = 0.8 + 0.2 * sin(time * 2)
            add(session.level.launch, 30, PHSpriteGlow, SIMD4(Palette.comet * breathe, 0))
            add(session.level.launch, 4, PHSpriteDisc, SIMD4(SIMD3(repeating: 4.5), 0))
        }
    }

    private func particles(_ session: GameSession) {
        for particle in session.particles {
            let fade = 1 - particle.age / particle.life
            sprites.append(PHSprite(position: particle.position, radius: particle.size, kind: Int32(PHSpriteGlow.rawValue),
                                    color: SIMD4(particle.color * 1.8 * fade * fade, 0), params: .zero))
        }
    }

    // MARK: - Helpers

    private func add(_ p: SIMD2<Double>, _ radius: Float, _ kind: PHSpriteKind, _ color: SIMD4<Float>,
                     _ params: SIMD4<Float> = .zero) {
        sprites.append(PHSprite(position: SIMD2<Float>(p), radius: radius, kind: Int32(kind.rawValue),
                                color: color, params: params))
    }

    /// A triangle strip along a polyline, `width` in world units.
    private func appendRibbon(count: Int, width: Float, _ point: (Int) -> (SIMD2<Float>, SIMD4<Float>)) {
        let start = ribbon.count
        var previous = point(0).0
        for i in 0..<count {
            let (p, color) = point(i)
            let next = i + 1 < count ? point(i + 1).0 : p
            var tangent = next - previous
            let length = simd_length(tangent)
            tangent = length > 1e-4 ? tangent / length : SIMD2(1, 0)
            let normal = SIMD2(-tangent.y, tangent.x) * (width / 2)
            ribbon.append(PHRibbonVertex(position: p + normal, across: -1, pad: 0, color: color))
            ribbon.append(PHRibbonVertex(position: p - normal, across: 1, pad: 0, color: color))
            previous = p
        }
        strips.append(start..<ribbon.count)
    }
}
