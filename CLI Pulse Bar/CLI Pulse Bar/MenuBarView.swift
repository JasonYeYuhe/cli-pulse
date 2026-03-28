import SwiftUI
import CLIPulseCore

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if !state.isAuthenticated || !state.isPaired {
                notConnectedView
            } else {
                connectedView
            }
        }
        .frame(width: 380, height: 520)
    }

    // MARK: - Not Connected

    private var notConnectedView: some View {
        VStack(spacing: 0) {
            tabBar
            SettingsTab()
                .environmentObject(state)
        }
    }

    // MARK: - Connected

    private var connectedView: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = state.lastError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(error)
                        .font(.system(size: 9))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        state.lastError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.08))
            }

            tabBar

            // Tab Content
            Group {
                switch state.selectedTab {
                case .overview:
                    OverviewTab()
                case .providers:
                    ProvidersTab()
                case .sessions:
                    SessionsTab()
                case .alerts:
                    AlertsTab()
                case .settings:
                    SettingsTab()
                }
            }
            .environmentObject(state)
            .frame(maxHeight: .infinity)

            // Footer
            footer
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppState.Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .separatorColor).opacity(0.1))
    }

    private func tabButton(_ tab: AppState.Tab) -> some View {
        Button {
            state.selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12))

                    // Alert badge
                    if tab == .alerts {
                        let count = state.alerts.filter { !$0.is_resolved }.count
                        if count > 0 {
                            Text("\(min(count, 99))")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .background(Capsule().fill(.red))
                                .offset(x: 8, y: -6)
                        }
                    }
                }
                Text(tab.label)
                    .font(.system(size: 8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundStyle(state.selectedTab == tab ? PulseTheme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if state.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }

            // Provider switcher (compact icons)
            if state.mergeMenuBarIcons {
                providerSwitcher
            }

            Spacer()

            Text("CLI Pulse v0.1.0")
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)

            Spacer()

            Button {
                Task { await state.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(state.isLoading)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .separatorColor).opacity(0.1))
    }

    private var providerSwitcher: some View {
        let enabled = Array(state.providerConfigs.filter(\.isEnabled))
        let visible = Array(enabled.prefix(5))
        return HStack(spacing: 2) {
            ForEach(visible) { config in
                let hasData = state.providers.contains { $0.provider == config.kind.rawValue }
                Image(systemName: config.kind.iconName)
                    .font(.system(size: 7))
                    .foregroundStyle(hasData ? PulseTheme.providerColor(config.kind.rawValue) : Color.gray.opacity(0.3))
            }
            if enabled.count > 5 {
                Text("+\(enabled.count - 5)")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
