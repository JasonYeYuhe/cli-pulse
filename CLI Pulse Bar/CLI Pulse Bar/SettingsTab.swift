import SwiftUI
import ServiceManagement
import CLIPulseCore

struct SettingsTab: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var email = ""
    @State private var otpCode = ""
    @State private var serverInput = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var settingsSection: SettingsSection = .general

    enum SettingsSection: String, CaseIterable {
        case general = "General"
        case display = "Display"
        case advanced = "Advanced"

        var label: String {
            switch self {
            case .general: return L10n.settings.general
            case .display: return L10n.settings.display
            case .advanced: return L10n.settings.advanced
            }
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.settings.title)
                    .font(.system(size: 14, weight: .bold))

                if state.isAuthenticated {
                    authenticatedSection
                } else {
                    loginSection
                }
            }
            .padding(12)
        }
        .onAppear {
            serverInput = ""
        }
    }

    // MARK: - Login

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L10n.settings.server, icon: "server.rack")

            SectionHeader(title: L10n.settings.signIn, icon: "person.circle")

            if state.otpSent {
                Text(L10n.auth.codeSentTo(state.otpEmail))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField(L10n.auth.codePlaceholder, text: $otpCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))

                Button {
                    Task { await state.verifyOTP(code: otpCode) }
                } label: {
                    HStack {
                        if state.isLoading { ProgressView().controlSize(.small) }
                        Text(L10n.auth.verifyCode)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isLoading)

                Button { otpCode = ""; state.resetOTP() } label: {
                    Text(L10n.auth.backToEmail).font(.system(size: 10))
                }
            } else {
                TextField(L10n.settings.email, text: $email)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                Button {
                    Task { await state.sendOTP(email: email) }
                } label: {
                    HStack {
                        if state.isLoading { ProgressView().controlSize(.small) }
                        Text(L10n.auth.sendCode)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(email.isEmpty || !email.contains("@") || state.isLoading)
            }

            if let error = state.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Authenticated

    private var authenticatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountCard

            if !state.isPaired {
                Divider()
                pairingSection
            } else {
                Divider()

                subscriptionSection

                Divider()

                // Section picker
                Picker("", selection: $settingsSection) {
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        Text(section.label)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                switch settingsSection {
                case .general:
                    generalSection
                case .display:
                    displaySection
                case .advanced:
                    advancedSection
                }
            }

            Divider()
            dangerZone
        }
    }

    // MARK: - Pairing

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L10n.settings.connection, icon: "link")

            Text("Connect a CLI helper to start monitoring your AI usage.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let info = state.pairingInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your pairing code:")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(info.code)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(PulseTheme.accent)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(info.code, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PulseTheme.accent)
                    }
                    .padding(8)
                    .background(PulseTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Run on your machine:")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(info.install_command)
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(info.install_command, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PulseTheme.accent)
                    }
                    .padding(8)
                    .background(PulseTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        Task { await state.checkPairingStatus() }
                    } label: {
                        HStack {
                            if state.isLoading { ProgressView().controlSize(.small) }
                            Text("I've paired — check status")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.accent)
                    .disabled(state.isLoading)
                }
            } else {
                Button {
                    Task { await state.generatePairingCode() }
                } label: {
                    HStack {
                        if state.isLoading { ProgressView().controlSize(.small) }
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 10))
                        Text("Generate Pairing Code")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(state.isLoading)
            }

            if let error = state.pairingError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
    }

    private var accountCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(PulseTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.userName)
                    .font(.system(size: 12, weight: .semibold))
                if !state.hidePersonalInfo {
                    Text(state.userEmail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                StatusBadge(
                    text: state.isPaired ? L10n.settings.paired : L10n.settings.notPaired,
                    color: state.isPaired ? .green : .orange
                )
            }
        }
        .padding(8)
        .background(PulseTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Subscription

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.settings.subscription, icon: "creditcard")

            HStack {
                Text(L10n.settings.currentPlan)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                SubscriptionBadge(tier: state.subscriptionManager.currentTier)
            }

            HStack {
                Text(L10n.settings.providers)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.subscriptionManager.maxProviders < 0 ? "Unlimited" : "\(state.subscriptionManager.maxProviders)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text(L10n.settings.devices)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.subscriptionManager.maxDevices < 0 ? "Unlimited" : "\(state.subscriptionManager.maxDevices)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text(L10n.settings.dataRetention)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(state.subscriptionManager.dataRetentionDays) \(L10n.settings.days)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if state.subscriptionManager.isProOrAbove {
                Button {
                    openWindow(id: "subscription")
                } label: {
                    Label(L10n.settings.manageSubscription, systemImage: "gear")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(PulseTheme.accent)
            } else {
                Button {
                    openWindow(id: "subscription")
                } label: {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text(L10n.settings.upgradePro)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L10n.settings.connection, icon: "server.rack")

            HStack {
                Text(L10n.settings.server)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.settings.serverName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text(L10n.settings.status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(state.serverOnline ? .green : .red)
                    .frame(width: 6, height: 6)
                Text(state.serverOnline ? L10n.settings.connected : L10n.settings.disconnected)
                    .font(.system(size: 10))
                    .foregroundStyle(state.serverOnline ? .green : .red)
            }

            HStack {
                Text(L10n.settings.refreshCadence)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { state.refreshInterval },
                    set: { state.updateRefreshInterval($0) }
                )) {
                    Text("1m").tag(60)
                    Text("2m").tag(120)
                    Text("5m").tag(300)
                    Text("10m").tag(600)
                    Text("30m").tag(1800)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 220)
            }

            Divider()

            SectionHeader(title: L10n.settings.notifications, icon: "bell")

            Toggle(isOn: $state.notificationsEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.settings.desktopNotifications)
                        .font(.system(size: 11))
                    Text(L10n.settings.desktopNotificationsHint)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $state.sessionQuotaNotifications) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.settings.sessionQuotaNotifications)
                        .font(.system(size: 11))
                    Text(L10n.settings.sessionQuotaHint)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            SectionHeader(title: L10n.settings.costTracking, icon: "dollarsign.circle")

            Toggle(isOn: $state.showCost) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show cost summary")
                        .font(.system(size: 11))
                    Text("Display today + 30 day spend estimates")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $state.checkProviderStatus) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.settings.checkProviderStatus)
                        .font(.system(size: 11))
                    Text("Auto-poll provider status pages")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Menu Bar", icon: "menubar.rectangle")

            HStack {
                Text("Display mode")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { state.menuBarDisplayMode },
                    set: { state.menuBarDisplayMode = $0 }
                )) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 120)
            }

            Text(state.menuBarDisplayMode.description)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            Toggle(isOn: $state.mergeMenuBarIcons) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Merge menu bar icons")
                        .font(.system(size: 11))
                    Text("Single icon with provider switcher")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            SectionHeader(title: "Menu Content", icon: "list.bullet")

            HStack {
                Text("Content mode")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { state.menuBarContentMode },
                    set: { state.menuBarContentMode = $0 }
                )) {
                    ForEach(MenuBarContentMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 140)
            }

            Divider()

            SectionHeader(title: "Appearance", icon: "paintbrush")

            Toggle(isOn: $state.compactMode) {
                Text(L10n.settings.compactMode)
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            SectionHeader(title: "Overview Providers", icon: "square.grid.2x2")

            Text("Select which providers to show in the Overview tab. Drag to reorder.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            List {
                ForEach(state.providerConfigs) { config in
                    Button {
                        state.toggleProvider(config.kind)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 8))
                                .foregroundStyle(.quaternary)
                            Image(systemName: config.kind.iconName)
                                .font(.system(size: 8))
                                .foregroundStyle(PulseTheme.providerColor(config.kind.rawValue))
                            Text(config.kind.rawValue)
                                .font(.system(size: 9))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: config.isEnabled ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 9))
                                .foregroundStyle(config.isEnabled ? Color.green : Color.gray)
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(config.isEnabled ? PulseTheme.providerColor(config.kind.rawValue).opacity(0.06) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                .onMove { from, to in
                    state.moveProvider(from: from, to: to)
                }
            }
            .listStyle(.plain)
            .frame(height: min(CGFloat(state.providerConfigs.count) * 24, 240))
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Startup", icon: "power")

            Toggle(isOn: $launchAtLogin) {
                Text("Launch at login")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: launchAtLogin) { _ in
                LaunchAtLogin.toggle()
            }

            Divider()

            SectionHeader(title: "Privacy", icon: "lock.shield")

            Toggle(isOn: $state.hidePersonalInfo) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.settings.hidePersonalInfo)
                        .font(.system(size: 11))
                    Text("Hide email addresses in the UI")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            SectionHeader(title: "Debug", icon: "ladybug")

            HStack {
                Text("Token")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.storedToken.isEmpty ? "none" : "••••••••")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            HStack {
                Text("Providers loaded")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(state.providers.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text("Last refresh")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastRefresh = state.lastRefresh {
                    Text(lastRefresh, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Never")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                openWindow(id: "about")
            } label: {
                Label(L10n.about.title, systemImage: "info.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(PulseTheme.accent)

            Link(destination: URL(string: "https://jasonyeyuhe.github.io/cli-pulse/privacy.html")!) {
                Label(L10n.settings.privacyPolicy, systemImage: "hand.raised")
                    .font(.system(size: 11))
            }
            .foregroundStyle(PulseTheme.accent)

            Link(destination: URL(string: "https://jasonyeyuhe.github.io/cli-pulse/terms.html")!) {
                Label(L10n.settings.termsOfUse, systemImage: "doc.text")
                    .font(.system(size: 11))
            }
            .foregroundStyle(PulseTheme.accent)

            Button {
                state.signOut()
            } label: {
                Label(L10n.settings.signOut, systemImage: "arrow.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit CLI Pulse Bar", systemImage: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }

}
