import CoreHaptics
import OSLog

/// The taptic engine as a second instrument: every close pass is felt as well as heard.
final class Haptics {
    private var engine: CHHapticEngine?
    private var needsRestart = false

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.stoppedHandler = { [weak self] _ in self?.needsRestart = true }
            engine.resetHandler = { [weak self] in self?.needsRestart = true }
            try engine.start()
            self.engine = engine
        } catch {
            Logger(subsystem: "com.nevzorov.Perihelion", category: "Haptics").error("unavailable: \(error.localizedDescription)")
        }
    }

    func tick() {
        play([transient(0.25, 0.9)])
    }

    func launch(power: Float) {
        play([transient(0.35 + 0.4 * power, 0.5)])
    }

    /// A body at closest approach: heavier and closer is deeper and stronger.
    func pass(strength: Float, sharpness: Float) {
        play([transient(0.25 + 0.75 * strength, sharpness),
              continuous(0.3 * strength, sharpness * 0.5, at: 0.02, duration: 0.12 + 0.2 * Double(strength))])
    }

    func collect() {
        play([transient(0.7, 1.0), transient(0.35, 1.0, at: 0.07)])
    }

    func crash() {
        play([transient(1.0, 0.15), continuous(0.6, 0.05, at: 0, duration: 0.3)])
    }

    func success() {
        play([transient(0.5, 0.8), transient(0.6, 0.8, at: 0.12), transient(0.8, 0.9, at: 0.24),
              continuous(0.35, 0.3, at: 0.3, duration: 0.5)])
    }

    private func transient(_ intensity: Float, _ sharpness: Float, at time: Double = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(intensity, 1)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: min(sharpness, 1)),
        ], relativeTime: time)
    }

    private func continuous(_ intensity: Float, _ sharpness: Float, at time: Double, duration: Double) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: min(intensity, 1)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: min(sharpness, 1)),
        ], relativeTime: time, duration: duration)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine else { return }
        do {
            if needsRestart {
                try engine.start()
                needsRestart = false
            }
            try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: CHHapticTimeImmediate)
        } catch {
            needsRestart = true
        }
    }
}
