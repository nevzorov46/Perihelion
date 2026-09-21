import SwiftUI

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
    /// `-clean YES` hides every overlay: footage of the sky alone, for editing.
    private let isClean = UserDefaults.standard.bool(forKey: "clean")

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
            if !isClean {
                BodyLabelsView(hud: host.session.hud)
                    .ignoresSafeArea()
                HUDView(hud: host.session.hud,
                        onNext: { host.session.nextLevel() },
                        onRestart: { host.session.restartLevel() },
                        onToggleSound: { host.session.toggleMute() },
                        onCameraDistance: { host.session.cycleCameraDistance() },
                        onCameraFollow: { host.session.toggleCameraFollow() })
            }
        }
        .onAppear { host.session.start() }
    }
}
