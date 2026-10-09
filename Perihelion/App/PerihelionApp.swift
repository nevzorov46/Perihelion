import SwiftUI
import UIKit

@main
struct PerihelionApp: App {
    // Created once for the app's lifetime; SwiftUI may re-create views freely.
    private let host = GameHost()

    var body: some Scene {
        WindowGroup {
            GameScreen(host: host)
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

@MainActor
final class GameHost {
    let session: GameSession
    let renderer: Renderer?

    init() {
        // the whole campaign; `-level <id>` opens one baked sky on its own, for checks and footage
        let only = UserDefaults.standard.string(forKey: "level")
        let playlist = LevelDef.campaign.filter { only == nil || $0.id == only }
        session = GameSession(playlist: playlist.isEmpty ? LevelDef.campaign : playlist)
        renderer = Renderer(session: session)
    }
}

struct GameScreen: View {
    let host: GameHost
    private let a11y = AccessibilitySettings.shared
    /// `-clean YES` hides every overlay: footage of the sky alone, for editing.
    private let isClean = UserDefaults.standard.bool(forKey: "clean")
    /// Footage and test runs (`-demo`, `-level`, `-clean`) go straight into a sky.
    private static let skipsMenu = ["demo", "level", "clean"].contains { UserDefaults.standard.object(forKey: $0) != nil }
    @State private var screen: Screen = GameScreen.skipsMenu ? .playing : .title

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let renderer = host.renderer {
                FieldView(renderer: renderer, session: host.session)
                    .ignoresSafeArea()
            } else {
                Text("This device can’t run Metal.")
                    .foregroundStyle(.secondary)
            }
            switch screen {
            case .title:
                TitleView(onPlay: { play(host.session.progress.nextIndex(in: host.session.playlist)) },
                          onSkies: { show(.skies) },
                          onSettings: { show(.settings) })
                    .transition(.opacity)
            case .skies:
                SkiesView(levels: host.session.playlist, progress: host.session.progress,
                          onPick: { play($0) }, onBack: { show(.title) })
                    .transition(.opacity)
            case .settings:
                SettingsView(session: host.session, onBack: { show(.title) })
                    .transition(.opacity)
            case .playing:
                if !isClean {
                    BodyLabelsView(hud: host.session.hud)
                        .ignoresSafeArea()
                    HUDView(hud: host.session.hud,
                            onBack: { backToTitle() },
                            onNext: { host.session.nextLevel() },
                            onRestart: { host.session.restartLevel() },
                            onToggleSound: { host.session.toggleMute() })
                        .transition(.opacity)
                    // Dragging back from the comet carries the angle and the power,
                    // and says neither out loud. With VoiceOver running they become
                    // two controls the rotor can turn.
                    if a11y.voiceOverRunning {
                        VStack {
                            Spacer()
                            AimControlsView(session: host.session)
                                .padding(.bottom, 92)
                        }
                    }
                }
            }
        }
        .onAppear {
            host.session.start()
            if screen != .playing { host.session.enterAttract() }
        }
        .onChange(of: host.session.hud.toast) { _, toast in
            if let toast { UIAccessibility.announce(toast) }
        }
        .onChange(of: host.session.hud.collected) { previous, collected in
            guard collected > previous else { return }
            UIAccessibility.announce("\(collected) of \(host.session.hud.moteCount)")
        }
    }

    private func show(_ next: Screen) {
        withAnimation(.easeInOut(duration: 0.35)) { screen = next }
    }

    private func play(_ index: Int) {
        host.session.play(index)
        show(.playing)
    }

    private func backToTitle() {
        host.session.enterAttract()
        show(.title)
    }
}
