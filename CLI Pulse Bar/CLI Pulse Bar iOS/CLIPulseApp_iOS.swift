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
            CommandMenu("Navigation") {
                Button("Dashboard") { appState.selectedTab = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Providers") { appState.selectedTab = .providers }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Sessions") { appState.selectedTab = .sessions }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Alerts") { appState.selectedTab = .alerts }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Settings") { appState.selectedTab = .settings }
                    .keyboardShortcut("5", modifiers: .command)
            }
            CommandMenu("Data") {
                Button("Refresh") {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
