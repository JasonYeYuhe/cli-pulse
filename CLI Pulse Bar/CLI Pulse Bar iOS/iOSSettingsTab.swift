import SwiftUI
import CLIPulseCore

struct iOSSettingsTab: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            Form {
                if state.isAuthenticated {
                    // Account
                    Section("Account") {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundStyle(PulseTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.userName)
                                    .font(.headline)
                                if !state.hidePersonalInfo {
                                    Text(state.userEmail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            StatusBadge(
                                text: state.isPaired ? "Paired" : "Not Paired",
                                color: state.isPaired ? .green : .orange
                            )
                        }
                        .padding(.vertical, 4)
                    }

                    // Subscription
                    Section("Subscription") {
                        HStack {
                            Text("Current Plan")
                            Spacer()
                            SubscriptionBadge(tier: state.subscriptionManager.currentTier)
                        }

                        HStack {
                            Text("Providers")
                            Spacer()
                            Text(state.subscriptionManager.maxProviders < 0 ? "Unlimited" : "\(state.subscriptionManager.maxProviders)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Devices")
                            Spacer()
                            Text(state.subscriptionManager.maxDevices < 0 ? "Unlimited" : "\(state.subscriptionManager.maxDevices)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Data Retention")
                            Spacer()
                            Text("\(state.subscriptionManager.dataRetentionDays) days")
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink {
                            SubscriptionView(manager: state.subscriptionManager)
                        } label: {
                            HStack {
                                if state.subscriptionManager.isProOrAbove {
                                    Label("Manage Subscription", systemImage: "gear")
                                } else {
                                    Label("Upgrade to Pro", systemImage: "star.fill")
                                        .foregroundStyle(PulseTheme.accent)
                                }
                            }
                        }
                    }

                    // General
                    Section("General") {
                        HStack {
                            Text("Server")
                            Spacer()
                            Text("Supabase (Tokyo)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Status")
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(state.serverOnline ? .green : .red)
                                    .frame(width: 8, height: 8)
                                Text(state.serverOnline ? "Connected" : "Disconnected")
                                    .font(.caption)
                                    .foregroundStyle(state.serverOnline ? .green : .red)
                            }
                        }

                        Picker("Refresh Interval", selection: Binding(
                            get: { state.refreshInterval },
                            set: { state.updateRefreshInterval($0) }
                        )) {
                            Text("30s").tag(30)
                            Text("1m").tag(60)
                            Text("2m").tag(120)
                            Text("5m").tag(300)
                            Text("10m").tag(600)
                            Text("30m").tag(1800)
                        }
                    }

                    // Display
                    Section("Display") {
                        Toggle("Show cost estimates", isOn: $state.showCost)
                        Toggle("Compact mode", isOn: $state.compactMode)

                        Picker("Menu Bar Mode", selection: Binding(
                            get: { state.menuBarDisplayMode },
                            set: { state.menuBarDisplayMode = $0 }
                        )) {
                            ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }

                    // Provider Management - inline grid
                    Section {
                        let columns: [GridItem] = isIPad
                            ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                            : [GridItem(.flexible()), GridItem(.flexible())]

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(state.providerConfigs) { config in
                                providerToggleCell(config)
                            }
                        }
                        .padding(.vertical, 4)

                        NavigationLink {
                            ProviderManagementView()
                                .environmentObject(state)
                        } label: {
                            HStack {
                                Text("Reorder Providers")
                                Spacer()
                                let enabled = state.providerConfigs.filter(\.isEnabled).count
                                Text("\(enabled)/\(state.providerConfigs.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Providers")
                    }

                    // Notifications
                    Section("Notifications") {
                        Toggle("Alert notifications", isOn: $state.notificationsEnabled)
                        Toggle("Session quota alerts", isOn: $state.sessionQuotaNotifications)
                        Toggle("Check provider status", isOn: $state.checkProviderStatus)
                    }

                    // Advanced
                    Section("Advanced") {
                        Toggle("Hide personal information", isOn: $state.hidePersonalInfo)

                        Button {
                            Task { await state.refreshAll() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Force Refresh All Data")
                            }
                        }
                        .disabled(state.isLoading)
                    }

                    // About
                    Section("About") {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Build")
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                                .foregroundStyle(.secondary)
                        }
                        Link(destination: URL(string: "https://github.com/jasonyeyuhe/cli-pulse")!) {
                            HStack {
                                Text("GitHub Repository")
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                        }
                        Link(destination: URL(string: "https://github.com/jasonyeyuhe/cli-pulse/blob/main/PRIVACY.md")!) {
                            HStack {
                                Text("Privacy Policy")
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                        }
                        Link(destination: URL(string: "https://github.com/jasonyeyuhe/cli-pulse/blob/main/TERMS.md")!) {
                            HStack {
                                Text("Terms of Use")
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                        }
                    }

                    // Sign Out
                    Section {
                        Button(role: .destructive) {
                            state.signOut()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.right.square")
                                Text("Sign Out")
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Sign in to get started")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func providerToggleCell(_ config: ProviderConfig) -> some View {
        VStack(spacing: 6) {
            Image(systemName: config.kind.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(config.isEnabled
                    ? PulseTheme.providerColor(config.kind.rawValue)
                    : .gray
                )
                .frame(width: 36, height: 36)
                .background(
                    (config.isEnabled
                        ? PulseTheme.providerColor(config.kind.rawValue)
                        : Color.gray
                    ).opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(config.kind.rawValue)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(config.isEnabled ? .primary : .secondary)

            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { _ in state.toggleProvider(config.kind) }
            ))
            .labelsHidden()
            .scaleEffect(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Provider Management View

struct ProviderManagementView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List {
            Section {
                ForEach(state.providerConfigs) { config in
                    HStack(spacing: 12) {
                        Image(systemName: config.kind.iconName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PulseTheme.providerColor(config.kind.rawValue))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(config.kind.rawValue)
                                .font(.body)
                            if let usage = state.providers.first(where: { $0.provider == config.kind.rawValue }) {
                                Text("\(CostFormatter.formatUsage(usage.today_usage)) today")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No data")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { config.isEnabled },
                            set: { _ in state.toggleProvider(config.kind) }
                        ))
                        .labelsHidden()
                    }
                }
                .onMove { from, to in
                    state.moveProvider(from: from, to: to)
                }
            } header: {
                Text("Drag to reorder, toggle to enable/disable")
            }
        }
        .navigationTitle("Manage Providers")
        .environment(\.editMode, .constant(.active))
    }
}
