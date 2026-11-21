import SwiftUI

@main
struct IronFrontApp: App {
    @StateObject private var session = GameSession()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Group {
                if let g = session.game { CommandView(session:session,game:g) }
                else { Lobby(session:session) }
            }
            .tint(Palette.amber).preferredColorScheme(.dark).statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onChange(of:phase) { value in if value != .active { session.background() } }
        }
    }
}
