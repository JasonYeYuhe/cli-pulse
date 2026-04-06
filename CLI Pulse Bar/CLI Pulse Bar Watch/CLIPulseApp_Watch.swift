import SwiftUI
import CLIPulseCore

@main
struct CLIPulseWatchApp: App {
    @StateObject private var appState = WatchAppState()
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchMainView()
                .environmentObject(appState)
                .environmentObject(sessionManager)
                .onAppear {
                    sessionManager.activate()
                    appState.applyFallbackData(from: sessionManager)
                }
        }
    }
}
