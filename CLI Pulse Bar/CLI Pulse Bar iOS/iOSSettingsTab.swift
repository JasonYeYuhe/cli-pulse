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
                    Section(L10n.settings.account) {
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
                    Section(L10n.settings.subscription) {
                        HStack {
                            Text(L10n.settings.currentPlan)
                            Spacer()
                            SubscriptionBadge(tier: state.subscriptionManager.currentTier)
                        }

                        HStack {
                            Text(L10n.settings.providers)
                            Spacer()
                            Text(state.subscriptionManager.maxProviders < 0 ? "Unlimited" : "\(state.subscriptionManager.maxProviders)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(L10n.settings.devices)
                            Spacer()
                            Text(state.subscriptionManager.maxDevices < 0 ? "Unlimited" : "\(state.subscriptionManager.maxDevices)")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(L10n.settings.dataRetention)
                            Spacer()
                            Text("\(state.subscriptionManager.dataRetentionDays) \(L10n.settings.days)")
                                .foregroundStyle(.secondary)
                        }

                        NavigationLink {
                            SubscriptionView(manager: state.subscriptionManager)
                        } label: {
                            HStack {
                                if state.subscriptionManager.isProOrAbove {
                                    Label(L10n.settings.manageSubscription, systemImage: "gear")
                                } else {
                                    Label(L10n.settings.upgradePro, systemImage: "star.fill")
                                        .foregroundStyle(PulseTheme.accent)
                                }
                            }
                        }
                    }

                    // General
                    Section(L10n.settings.general) {
                        HStack {
                            Text(L10n.settings.server)
                            Spacer()
                            Text(L10n.settings.serverName)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(L10n.settings.status)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(state.serverOnline ? .green : .red)
                                    .frame(width: 8, height: 8)
                                Text(state.serverOnline ? L10n.settings.connected : L10n.settings.disconnected)
                                    .font(.caption)
                                    .foregroundStyle(state.serverOnline ? .green : .red)
                            }
                        }

                        Picker(L10n.settings.refreshInterval, selection: Binding(
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
                    Section(L10n.settings.display) {
                        Toggle(L10n.settings.showCostEstimates, isOn: $state.showCost)
                        Toggle(L10n.settings.compactMode, isOn: $state.compactMode)

                        Picker(L10n.settings.menuBarMode, selection: Binding(
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
                                Text(L10n.settings.reorderProviders)
                                Spacer()
                                let enabled = state.providerConfigs.filter(\.isEnabled).count
                                Text("\(enabled)/\(state.providerConfigs.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(L10n.settings.providers)
                    }

                    // Notifications
                    Section(L10n.settings.notifications) {
                        Toggle(L10n.settings.alertNotifications, isOn: $state.notificationsEnabled)
                        Toggle(L10n.settings.sessionQuotaAlerts, isOn: $state.sessionQuotaNotifications)
                        Toggle(L10n.settings.checkProviderStatus, isOn: $state.checkProviderStatus)
                    }

                    // Advanced
                    Section(L10n.settings.advanced) {
                        Toggle(L10n.settings.hidePersonalInfo, isOn: $state.hidePersonalInfo)

                        Button {
                            Task { await state.refreshAll() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text(L10n.settings.forceRefresh)
                            }
                        }
                        .disabled(state.isLoading)
                    }

                    // About
                    Section(L10n.settings.about) {
                        HStack {
                            Text(L10n.settings.version)
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(L10n.settings.build)
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                                .foregroundStyle(.secondary)
                        }
                        Link(destination: URL(string: "https://github.com/jasonyeyuhe/cli-pulse")!) {
                            HStack {
                                Text(L10n.settings.github)
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                        }
                        Link(destination: URL(string: "https://github.com/jasonyeyuhe/cli-pulse/blob/main/PRIVACY.md")!) {
                            HStack {
                                Text(L10n.settings.privacyPolicy)
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                        }
                        Link(destination: URL(string: "https://github.com/jasonyeyuhe/cli-pulse/blob/main/TERMS.md")!) {
                            HStack {
                                Text(L10n.settings.termsOfUse)
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
                                Text(L10n.settings.signOut)
                            }
                        }
                    }
                } else {
                    Section {
                        Text(L10n.settings.signInHint)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.settings.title)
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
                Text(L10n.settings.reorderHint)
            }
        }
        .navigationTitle(L10n.settings.manageProviders)
        .environment(\.editMode, .constant(.active))
    }
}
