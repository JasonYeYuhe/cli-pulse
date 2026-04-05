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
    @State private var helperEnabled = HelperLogin.isEnabled
    @State private var settingsSection: SettingsSection = .general

    enum SettingsSection: String, CaseIterable {
        case general = "General"
        case display = "Display"
        case providers = "Providers"
        case advanced = "Advanced"

        var label: String {
            switch self {
            case .general: return L10n.settings.general
            case .display: return L10n.settings.display
            case .providers: return "Providers"
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
                case .providers:
                    providerSettingsSection
                case .advanced:
                    advancedSection
                }
            }

            Divider()

            // Team management (Pro/Team subscription)
            TeamView()
                .environmentObject(state)

            Divider()
            dangerZone
        }
    }

    // MARK: - Pairing

    @State private var showSetupGuide = false
    @State private var editingProviderKind: ProviderKind?

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L10n.settings.connection, icon: "link")

            // Current mode indicator
            if state.isPaired {
                modeIndicator(icon: "cloud.fill", text: L10n.onboarding.syncedMode, color: PulseTheme.accent)
            } else if state.isLocalMode {
                modeIndicator(icon: "desktopcomputer", text: L10n.onboarding.localModeDesc, color: .green)
                Text(L10n.onboarding.notSyncedHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                modeIndicator(icon: "questionmark.circle", text: "Not Connected", color: .orange)
            }

            if !state.isPaired {
                // How It Works card
                howItWorksCard

                Divider()

                // Setup guide
                if let info = state.pairingInfo {
                    setupStepsView(info: info)
                } else {
                    Button {
                        Task { await state.generatePairingCode() }
                    } label: {
                        HStack {
                            if state.isLoading { ProgressView().controlSize(.small) }
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 10))
                            Text(L10n.onboarding.setUpSync)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PulseTheme.accent)
                    .disabled(state.isLoading)
                }
            }

            if let error = state.pairingError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
    }

    private func modeIndicator(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.onboarding.howItWorks)
                .font(.system(size: 11, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                howItWorksRow(icon: "desktopcomputer", title: L10n.onboarding.localModeTitle, desc: L10n.onboarding.localModeDesc)
                howItWorksRow(icon: "cloud", title: L10n.onboarding.cloudModeTitle, desc: L10n.onboarding.cloudModeDesc)
            }
        }
        .padding(10)
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func howItWorksRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(PulseTheme.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                Text(desc)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @State private var pairingInProgress = false
    @State private var nativePairingError: String?

    private func setupStepsView(info: PairingInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.onboarding.setupStepsTitle)
                .font(.system(size: 12, weight: .bold))

            // Native helper: one-click setup
            VStack(alignment: .leading, spacing: 8) {
                Text("The background helper syncs your usage data to the cloud so you can see it on iOS, Watch, and Android.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Button {
                    Task { await pairAndStartNativeHelper(code: info.code) }
                } label: {
                    HStack {
                        if pairingInProgress { ProgressView().controlSize(.small) }
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("Set Up Background Helper")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulseTheme.accent)
                .disabled(pairingInProgress || state.isLoading)

                if let error = nativePairingError {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // Manual fallback for users who prefer terminal
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(info.install_command)
                            .font(.system(size: 8.5, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(3)
                        Spacer(minLength: 4)
                        copyButton(text: info.install_command)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Text("python3 /tmp/cli_pulse_helper.py daemon")
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 4)
                        copyButton(text: "python3 /tmp/cli_pulse_helper.py daemon")
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } label: {
                Text("Manual setup (Terminal)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Pairing code display
            HStack {
                Text("Your code:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(info.code)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(PulseTheme.accent)
                Spacer()
                copyButton(text: info.code)
            }
            .padding(8)
            .background(PulseTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Button {
                Task { await state.checkPairingStatus() }
            } label: {
                HStack {
                    if state.isLoading { ProgressView().controlSize(.small) }
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10))
                    Text(L10n.onboarding.checkSync)
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(PulseTheme.accent)
            .disabled(state.isLoading)
        }
        .padding(10)
        .background(PulseTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(PulseTheme.accent.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func setupStep<Content: View>(number: Int, title: String, desc: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(PulseTheme.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(desc)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
    }

    /// Register the native helper via Supabase RPC, save config, and enable Login Item.
    private func pairAndStartNativeHelper(code: String) async {
        pairingInProgress = true
        nativePairingError = nil
        do {
            let client = HelperAPIClient()
            let deviceName = Host.current().localizedName ?? "Mac"
            let config = try await client.registerHelper(
                pairingCode: code,
                deviceName: deviceName,
                system: "\(ProcessInfo.processInfo.operatingSystemVersionString)"
            )
            HelperConfig.save(config)
            HelperLogin.register()
            helperEnabled = HelperLogin.isEnabled
            // Check pairing status to update UI
            await state.checkPairingStatus()
        } catch {
            nativePairingError = error.localizedDescription
        }
        pairingInProgress = false
    }

    private func copyButton(text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(PulseTheme.accent)
        .help("Copy to clipboard")
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

    // MARK: - Provider Settings

    private var providerSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Provider Configuration", icon: "cpu")

            Text("Configure data source, credentials, and display for each provider.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            ForEach(state.providerConfigs) { config in
                providerSettingsRow(config: config)
            }
        }
        .sheet(item: $editingProviderKind) { kind in
            ProviderConfigEditor(kind: kind, state: state, onDismiss: { editingProviderKind = nil })
                .frame(width: 340, height: 380)
        }
    }

    private func providerSettingsRow(config: ProviderConfig) -> some View {
        HStack(spacing: 6) {
            Image(systemName: config.kind.iconName)
                .font(.system(size: 10))
                .foregroundStyle(PulseTheme.providerColor(config.kind.rawValue))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(config.kind.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("Source: \(config.sourceMode.rawValue)")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                    if config.hasCredentials {
                        Text("Key set")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if let label = config.accountLabel, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Button {
                editingProviderKind = config.kind
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 10))
                    .foregroundStyle(PulseTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(PulseTheme.cardBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
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

            SectionHeader(title: "Background Helper", icon: "arrow.triangle.2.circlepath")

            Toggle(isOn: $helperEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Enable background sync")
                        .font(.system(size: 11))
                    Text("Syncs usage data to cloud for iOS/Watch/Android")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: helperEnabled) { _ in
                HelperLogin.toggle()
            }

            if let status = HelperIPC.readStatus() {
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.state == .running ? Color.green : (status.state == .error ? Color.red : Color.gray))
                        .frame(width: 6, height: 6)
                    if let lastSync = status.lastSync {
                        let ago = Int(Date().timeIntervalSince(lastSync))
                        Text(ago < 60 ? "Synced just now" : "Synced \(ago / 60)m ago")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    } else if let error = status.error {
                        Text(error)
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    } else {
                        Text(status.state == .running ? "Running" : "Not running")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            FolderAccessView()

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
