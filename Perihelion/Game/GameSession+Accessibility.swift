import Foundation

/// Aiming without seeing the field.
///
/// The game is played by dragging back from the comet, which tells a sighted
/// player the angle and the power at a glance and tells a VoiceOver player
/// nothing at all. These give the same two numbers names, so they can be set
/// with the rotor and read back, and describe the sky so there is something to
/// aim at.
///
/// The field transform rotates the world: world +x is up the screen and world +y
/// is to the right. A shot's world angle is therefore already a bearing measured
/// clockwise from straight up, which is why it can be spoken as a clock face
/// without any further conversion.
extension GameSession {
    /// Where the shot points, in degrees clockwise from straight up.
    var aimBearing: Double {
        guard let aim else { return 0 }
        return (aim.angle * 180 / .pi).normalisedDegrees
    }

    /// How hard it is thrown, 0 … 1.
    var aimStrength: Double { aim == nil ? 0.5 : aimPower }

    /// Sets both at once: the rotor changes one at a time, but a `Shot` needs both.
    func setAim(bearing: Double, strength: Double) {
        let clamped = min(max(strength, 0), 1)
        let radians = bearing.normalisedDegrees * .pi / 180
        setAim(Shot(angle: radians, speed: Sim.minSpeed + (Sim.maxSpeed - Sim.minSpeed) * clamped),
               power: clamped)
    }

    /// Fires whatever is currently aimed, as lifting a finger would.
    func fireCurrentAim() {
        if flight != nil { restartLevel() }
        if aim == nil { setAim(bearing: 0, strength: 0.5) }
        guard let shot = aim else { return }
        launchShot(shot)
        aim = nil
        prediction = []
    }

    /// Spoken as "two o'clock, mid field": the clock face is easier to hold in
    /// the head than degrees, and the distance only has to be good enough to aim.
    func spokenDirection(to point: SIMD2<Double>, from origin: SIMD2<Double>) -> String {
        let up = point.x - origin.x
        let right = point.y - origin.y
        let bearing = (atan2(right, up) * 180 / .pi).normalisedDegrees
        var hour = Int((bearing / 30).rounded()) % 12
        if hour == 0 { hour = 12 }
        let distance = (up * up + right * right).squareRoot() / Sim.width
        let range = switch distance {
        case ..<0.18: "close"
        case ..<0.45: "mid field"
        default: "far"
        }
        return "\(hour) o'clock, \(range)"
    }

    /// The whole sky in one sentence per thing, read from the launch point.
    func skyDescription() -> String {
        var parts = ["\(level.def.name). \(level.motes.count) motes to collect."]
        var positions = [SIMD2<Double>](repeating: .zero, count: level.bodies.count)
        level.positions(at: 0, into: &positions)
        for (i, body) in level.bodies.enumerated() {
            let name = switch body.kind {
            case .star: "star"
            case .planet: "planet"
            case .moon: "moon"
            case .hole: "black hole"
            }
            parts.append("A \(name) at \(spokenDirection(to: positions[i], from: level.launch)).")
        }
        for (i, mote) in level.motes.enumerated() where collectedAt.indices.contains(i) && collectedAt[i] == nil {
            parts.append("Mote at \(spokenDirection(to: mote, from: level.launch)).")
        }
        return parts.joined(separator: " ")
    }

    /// What the aim sounds like, so the rotor has feedback of its own: pitch rises
    /// with the bearing and the note gets louder with the power.
    func previewAimSound() {
        // pitch climbs with the bearing, loudness with the power, so the rotor
        // has feedback that does not need the screen
        let step = Int((aimBearing / 360 * 10).rounded()) % 10
        synth.play(.chime, midi: Music.midi(root: 60, degree: step),
                   velocity: 0.25 + 0.5 * Float(aimStrength))
    }
}

extension Double {
    /// 0 … 360, so a bearing never reads as minus thirty degrees.
    var normalisedDegrees: Double {
        let wrapped = truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}
