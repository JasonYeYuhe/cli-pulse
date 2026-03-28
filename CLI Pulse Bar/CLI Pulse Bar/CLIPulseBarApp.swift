import SwiftUI
import ServiceManagement
import CLIPulseCore

@main
struct CLIPulseBarApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.hierarchical)
                let label = appState.menuBarLabel
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.tab.overview) { appState.selectedTab = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button(L10n.tab.providers) { appState.selectedTab = .providers }
                    .keyboardShortcut("2", modifiers: .command)
                Button(L10n.tab.sessions) { appState.selectedTab = .sessions }
                    .keyboardShortcut("3", modifiers: .command)
                Button(L10n.tab.alerts) { appState.selectedTab = .alerts }
                    .keyboardShortcut("4", modifiers: .command)
                Button(L10n.tab.settings) { appState.selectedTab = .settings }
                    .keyboardShortcut("5", modifiers: .command)
                Divider()
                Button(L10n.common.refreshAll) {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Window(L10n.about.title, id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - About Window

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            VStack(spacing: 4) {
                Text(L10n.about.title)
                    .font(.system(size: 20, weight: .bold))
                Text("\(L10n.settings.version) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(L10n.settings.build) \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text(L10n.about.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Divider()
                .padding(.horizontal, 20)

            VStack(spacing: 6) {
                Link(L10n.settings.github, destination: URL(string: "https://github.com/jasonyeyuhe/cli-pulse")!)
                    .font(.system(size: 11))
                Link(L10n.about.reportIssue, destination: URL(string: "https://github.com/jasonyeyuhe/cli-pulse/issues")!)
                    .font(.system(size: 11))
            }

            Text(L10n.about.copyright)
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .padding(30)
        .frame(width: 340)
    }
}

// MARK: - Launch at Login Helper

enum LaunchAtLogin {
    @available(macOS 13.0, *)
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @available(macOS 13.0, *)
    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("LaunchAtLogin error: \(error)")
        }
    }
}
