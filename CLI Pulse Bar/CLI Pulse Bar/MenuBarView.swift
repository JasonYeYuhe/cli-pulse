import SwiftUI
import CLIPulseCore

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    /// Adaptive max height: 85% of the screen where the status item lives, capped at 900pt.
    fileprivate static var maxMenuBarHeight: CGFloat {
        // Prefer the screen hosting the status item; fall back to main screen
        let screenHeight = NSApp.windows
            .first(where: { $0.className.contains("StatusBarWindow") || $0.className.contains("NSStatusBar") })?
            .screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 800
        return min(screenHeight * 0.85, 900)
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
        .frame(width: 380)
        .frame(minHeight: 520, maxHeight: .infinity)
        .background(WindowResizableHelper())
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

// MARK: - Window Resizable Helper

/// NSViewRepresentable that finds the hosting MenuBarExtra window and enables resizing.
/// The window's maxSize is the real constraint; SwiftUI content expands to fill whatever
/// height the window has, so there's no blank gap when the user drags to resize.
private struct WindowResizableHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.applyWindowConstraints(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            Self.applyWindowConstraints(window)
        }
    }

    /// Configure the window for vertical-only resize. Called on every SwiftUI update
    /// so the maxHeight stays fresh if the user moves to a different display.
    private static func applyWindowConstraints(_ window: NSWindow) {
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        let maxH = MenuBarView.maxMenuBarHeight
        // Width locked to 380 (no horizontal resize); height 520..maxH
        window.minSize = NSSize(width: 380, height: 520)
        window.maxSize = NSSize(width: 380, height: maxH)
    }
}
