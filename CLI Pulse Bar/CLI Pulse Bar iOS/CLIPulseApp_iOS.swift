import SwiftUI
import CLIPulseCore

@main
struct CLIPulseApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            iOSMainView()
                .environmentObject(appState)
                .onAppear {
                    #if targetEnvironment(macCatalyst)
                    // Not using Catalyst, but future-proof
                    #endif
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu(L10n.common.navigation) {
                Button(L10n.dashboard.title) { appState.selectedTab = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button(L10n.tab.providers) { appState.selectedTab = .providers }
                    .keyboardShortcut("2", modifiers: .command)
                Button(L10n.tab.sessions) { appState.selectedTab = .sessions }
                    .keyboardShortcut("3", modifiers: .command)
                Button(L10n.tab.alerts) { appState.selectedTab = .alerts }
                    .keyboardShortcut("4", modifiers: .command)
                Button(L10n.tab.settings) { appState.selectedTab = .settings }
                    .keyboardShortcut("5", modifiers: .command)
            }
            CommandMenu(L10n.common.data) {
                Button(L10n.common.refresh) {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
