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
        // `-level <id>` opens any baked sky on its own, for checks and screenshots.
        let only = UserDefaults.standard.string(forKey: "level")
        let ids = only.map { [$0] } ?? Self.playlist
        let playlist = LevelDef.campaign.filter { ids.contains($0.id) }
        session = GameSession(playlist: playlist.isEmpty ? LevelDef.campaign : playlist)
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
            BodyLabelsView(hud: host.session.hud)
                .ignoresSafeArea()
            HUDView(hud: host.session.hud,
                    onNext: { host.session.nextLevel() },
                    onRestart: { host.session.restartLevel() },
                    onToggleSound: { host.session.toggleMute() },
                    onCameraDistance: { host.session.cycleCameraDistance() },
                    onCameraFollow: { host.session.toggleCameraFollow() })
        }
        .onAppear { host.session.start() }
    }
}
