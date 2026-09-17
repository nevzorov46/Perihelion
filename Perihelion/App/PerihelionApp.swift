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
    /// This build plays a first slice of the campaign.
    static let playlist = ["first-light", "slingshot"]

    let session: GameSession
    let renderer: Renderer?

    init() {
        session = GameSession(playlist: LevelDef.campaign.filter { Self.playlist.contains($0.id) })
        renderer = Renderer(session: session)
    }
}

struct GameScreen: View {
    let host: GameHost

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
            HUDView(hud: host.session.hud,
                    onNext: { host.session.nextLevel() },
                    onRestart: { host.session.restartLevel() },
                    onToggleSound: { host.session.toggleMute() })
        }
        .onAppear { host.session.start() }
    }
}
