import SwiftUI
import CLIPulseCore

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("cli_pulse_menubar_height") private var storedHeight: Double = 580

    /// Adaptive max height: 85% of the screen where the status item lives, capped at 900pt.
    private static var maxMenuBarHeight: CGFloat {
        let screenHeight = NSApp.windows
            .first(where: { $0.className.contains("StatusBarWindow") || $0.className.contains("NSStatusBar") })?
            .screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 800
        return min(screenHeight * 0.85, 900)
    }

    private var effectiveHeight: CGFloat {
        min(max(CGFloat(storedHeight), 400), Self.maxMenuBarHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !state.isAuthenticated {
                notConnectedView
            } else if state.isPaired || state.isLocalMode {
                connectedView
            } else {
                notConnectedView
            }
        }
        .frame(width: 380, height: effectiveHeight)
    }

    // MARK: - Not Connected

    @AppStorage("cli_pulse_onboarding_completed") private var onboardingCompleted = false

    private var notConnectedView: some View {
        VStack(spacing: 0) {
            if !state.isAuthenticated && !onboardingCompleted {
                OnboardingWizardView()
                    .environmentObject(state)
            } else {
                tabBar
                SettingsTab()
                    .environmentObject(state)
            }
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

            // Tier limit warning banner
            if let warning = state.tierLimitWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 9))
                    Text(warning)
                        .font(.system(size: 9))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        state.tierLimitWarning = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.08))
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

            // Resize handle
            resizeHandle
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

            Text("CLI Pulse v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
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

    // MARK: - Resize Handle

    /// Draggable bar at the bottom edge; vertical drag changes the stored height.
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: .separatorColor).opacity(0.35))
                    .frame(width: 36, height: 3)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newHeight = CGFloat(storedHeight) + value.translation.height
                        let clamped = min(max(newHeight, 400), Self.maxMenuBarHeight)
                        storedHeight = Double(clamped)
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
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
