import Foundation
import SwiftUI
import UserNotifications
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
public final class AppState: ObservableObject {
    // MARK: - Auth State
    @Published public var isAuthenticated = false
    @Published public var isPaired = false
    @Published public var userName: String = ""
    @Published public var userEmail: String = ""

    // MARK: - Data
    @Published public var dashboard: DashboardSummary?
    @Published public var providers: [ProviderUsage] = []
    @Published public var sessions: [SessionRecord] = []
    @Published public var devices: [DeviceRecord] = []
    @Published public var alerts: [AlertRecord] = []

    // MARK: - Subscription
    @Published public var subscriptionManager = SubscriptionManager.shared

    // Forward SubscriptionManager changes to trigger UI updates
    private var subscriptionCancellable: AnyCancellable?

    // MARK: - UI State
    @Published public var selectedTab: Tab = .overview
    @Published public var isLoading = false
    @Published public var lastError: String?
    @Published public var tierLimitWarning: String?
    @Published public var lastRefresh: Date?
    @Published public var serverOnline = false
    @Published public var isLocalMode = false  // true when showing local scan data (no cloud)

    // MARK: - Provider Management
    @Published public var providerConfigs: [ProviderConfig] = ProviderConfig.defaults()
    @Published public var providerDetails: [ProviderDetail] = []
    @Published public var costSummary: CostSummary = CostSummary()

    /// Providers that had cloud data supplemented with local collector data in the last refresh.
    public var locallySupplementedProviders: Set<String> = []

    // MARK: - Refresh Task Tracking
    private var refreshTask: Task<Void, Never>?
    private static let refreshTokenKeychainKey = "cli_pulse_refresh_token"

    // MARK: - Settings — General
    private static let tokenKeychainKey = "cli_pulse_token"

    public var storedToken: String {
        get { KeychainHelper.load(key: Self.tokenKeychainKey) ?? "" }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(key: Self.tokenKeychainKey)
            } else {
                KeychainHelper.save(key: Self.tokenKeychainKey, value: newValue)
            }
            // Also clear legacy UserDefaults value if present
            UserDefaults.standard.removeObject(forKey: "cli_pulse_token")
        }
    }
    @AppStorage("cli_pulse_refresh_interval") public var refreshInterval: Int = 120
    @AppStorage("cli_pulse_show_cost") public var showCost = true
    @AppStorage("cli_pulse_notifications") public var notificationsEnabled = true
    @AppStorage("cli_pulse_compact_mode") public var compactMode = false
    @AppStorage("cli_pulse_check_provider_status") public var checkProviderStatus = true
    @AppStorage("cli_pulse_session_quota_notifications") public var sessionQuotaNotifications = true
    @AppStorage("cli_pulse_hide_personal_info") public var hidePersonalInfo = false
    @AppStorage("cli_pulse_appearance") public var appearanceModeRaw = 0 // 0=system, 1=light, 2=dark

    public var appearanceMode: ColorScheme? {
        switch appearanceModeRaw {
        case 1: return .light
        case 2: return .dark
        default: return nil // system
        }
    }

    // MARK: - Settings — Display
    @AppStorage("cli_pulse_menubar_display_mode") public var menuBarDisplayModeRaw = MenuBarDisplayMode.icon.rawValue
    @AppStorage("cli_pulse_menubar_content_mode") public var menuBarContentModeRaw = MenuBarContentMode.usageAsUsed.rawValue
    @AppStorage("cli_pulse_merge_icons") public var mergeMenuBarIcons = true

    public var menuBarDisplayMode: MenuBarDisplayMode {
        get { MenuBarDisplayMode(rawValue: menuBarDisplayModeRaw) ?? .icon }
        set { menuBarDisplayModeRaw = newValue.rawValue }
    }

    public var menuBarContentMode: MenuBarContentMode {
        get { MenuBarContentMode(rawValue: menuBarContentModeRaw) ?? .usageAsUsed }
        set { menuBarContentModeRaw = newValue.rawValue }
    }

    public enum Tab: String, CaseIterable {
        case overview = "Overview"
        case providers = "Providers"
        case sessions = "Sessions"
        case alerts = "Alerts"
        case settings = "Settings"

        public var icon: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.33percent"
            case .providers: return "cpu"
            case .sessions: return "terminal"
            case .alerts: return "bell.badge"
            case .settings: return "gear"
            }
        }

        public var label: String {
            switch self {
            case .overview: return L10n.tab.overview
            case .providers: return L10n.tab.providers
            case .sessions: return L10n.tab.sessions
            case .alerts: return L10n.tab.alerts
            case .settings: return L10n.tab.settings
            }
        }
    }

    public let api: APIClient
    private var refreshTimer: Timer?
    private var previousAlertIDs: Set<String> = []

    // MARK: - Menu Bar Label
    public var menuBarLabel: String {
        guard isAuthenticated, isPaired else { return "" }
        let unresolvedCount = alerts.filter { !$0.is_resolved }.count
        if unresolvedCount > 0 {
            return "\(unresolvedCount)"
        }
        switch menuBarDisplayMode {
        case .percent:
            if let top = mostUsedProvider, top.usagePercent > 0 {
                let remaining = Int((1.0 - top.usagePercent) * 100)
                return "\(remaining)%"
            }
            return ""
        case .mostUsed:
            return mostUsedProvider?.provider ?? ""
        case .pace:
            if let top = mostUsedProvider, top.usagePercent > 0 {
                return String(format: "%.0f%%", top.usagePercent * 100)
            }
            return ""
        case .icon:
            return ""
        }
    }

    public var menuBarIcon: String {
        guard isAuthenticated, isPaired else { return "waveform.path.ecg" }
        let unresolvedCount = alerts.filter { !$0.is_resolved }.count
        if unresolvedCount > 0 { return "exclamationmark.triangle.fill" }
        if !serverOnline { return "wifi.slash" }
        if menuBarDisplayMode == .mostUsed, let top = mostUsedProvider,
           let kind = top.providerKind {
            return kind.iconName
        }
        return "waveform.path.ecg"
    }

    public var mostUsedProvider: ProviderUsage? {
        providers
            .filter { p in enabledProviderNames.contains(p.provider) }
            .max(by: { $0.usagePercent < $1.usagePercent })
    }

    public var enabledProviderNames: Set<String> {
        Set(providerConfigs.filter(\.isEnabled).map(\.kind.rawValue))
    }

    // MARK: - Provider Config Management

    public func toggleProvider(_ kind: ProviderKind) {
        if let idx = providerConfigs.firstIndex(where: { $0.kind == kind }) {
            let wasEnabled = providerConfigs[idx].isEnabled
            // Enforce tier limit when enabling
            if !wasEnabled {
                let maxProviders = subscriptionManager.maxProviders
                if maxProviders >= 0 {
                    let currentEnabled = providerConfigs.filter(\.isEnabled).count
                    if currentEnabled >= maxProviders {
                        tierLimitWarning = "Your \(subscriptionManager.currentTier.rawValue) plan allows up to \(maxProviders) providers. Upgrade to enable more."
                        return
                    }
                }
            }
            providerConfigs[idx].isEnabled.toggle()
            saveProviderConfigs()
        }
    }

    public func moveProvider(from source: IndexSet, to destination: Int) {
        providerConfigs.move(fromOffsets: source, toOffset: destination)
        for i in providerConfigs.indices {
            providerConfigs[i].sortOrder = i
        }
        saveProviderConfigs()
    }

    public func saveProviderConfigs() {
        // Save non-sensitive fields to UserDefaults (apiKey/manualCookieHeader excluded via CodingKeys)
        if let data = try? JSONEncoder().encode(providerConfigs) {
            UserDefaults.standard.set(data, forKey: "cli_pulse_provider_configs")
        }
        // Save secrets to Keychain
        for config in providerConfigs {
            config.saveSecrets()
        }
    }

    private static let secretsMigratedKey = "cli_pulse_provider_secrets_migrated"

    private func loadProviderConfigs() {
        guard let data = UserDefaults.standard.data(forKey: "cli_pulse_provider_configs") else { return }

        // Migrate legacy secrets from UserDefaults JSON → Keychain (one-time)
        if !UserDefaults.standard.bool(forKey: Self.secretsMigratedKey) {
            migrateLegacySecrets(from: data)
            UserDefaults.standard.set(true, forKey: Self.secretsMigratedKey)
        }

        if let configs = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providerConfigs = configs
            // Add any new providers not in saved config
            let existingKinds = Set(configs.map(\.kind))
            let newProviders = ProviderKind.allCases.filter { !existingKinds.contains($0) }
            for kind in newProviders {
                providerConfigs.append(ProviderConfig(kind: kind, isEnabled: true, sortOrder: providerConfigs.count))
            }
        }
        // Hydrate secrets from Keychain (includes any just-migrated values)
        for i in providerConfigs.indices {
            providerConfigs[i].loadSecrets()
        }
    }

    /// One-time migration: extract apiKey/manualCookieHeader from legacy
    /// UserDefaults JSON and move them to Keychain.
    private func migrateLegacySecrets(from data: Data) {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for entry in array {
            guard let kindRaw = entry["kind"] as? String,
                  let kind = ProviderKind(rawValue: kindRaw) else { continue }
            if let apiKey = entry["apiKey"] as? String, !apiKey.isEmpty {
                KeychainHelper.save(key: "cli_pulse_provider_\(kind.rawValue)_apiKey", value: apiKey)
            }
            if let cookie = entry["manualCookieHeader"] as? String, !cookie.isEmpty {
                KeychainHelper.save(key: "cli_pulse_provider_\(kind.rawValue)_cookie", value: cookie)
            }
        }
        // Re-save configs without secrets to strip them from UserDefaults
        // (The next saveProviderConfigs() call will also do this, but be explicit)
        if let configs = try? JSONDecoder().decode([ProviderConfig].self, from: data),
           let cleanData = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(cleanData, forKey: "cli_pulse_provider_configs")
        }
    }

    public func buildProviderDetails() {
        providerDetails = providerConfigs.sorted(by: { $0.sortOrder < $1.sortOrder }).compactMap { config in
            if let usage = providers.first(where: { $0.provider == config.kind.rawValue }) {
                // Build tiers from API tier data (CodexBar-style)
                var tiers: [UsageTier] = []
                if !usage.tiers.isEmpty {
                    // Use per-tier data from helper sync (skip zero-quota tiers)
                    tiers = usage.tiers.compactMap { t in
                        guard t.quota > 0 else { return nil }
                        return UsageTier(
                            name: t.name,
                            usage: t.quota - t.remaining,
                            quota: t.quota,
                            remaining: t.remaining,
                            resetTime: t.reset_time
                        )
                    }
                } else if let quota = usage.quota, quota > 0 {
                    // Fallback: single tier from top-level quota
                    tiers.append(UsageTier(
                        name: "Default",
                        usage: usage.today_usage,
                        quota: quota,
                        remaining: usage.remaining,
                        resetTime: usage.reset_time
                    ))
                }
                let effectiveSource: SourceType
                if config.sourceMode != .auto {
                    effectiveSource = config.sourceMode
                } else if isLocalMode {
                    effectiveSource = .local
                } else if locallySupplementedProviders.contains(usage.provider) {
                    effectiveSource = .merged
                } else {
                    effectiveSource = .api
                }
                return ProviderDetail(
                    provider: usage,
                    config: config,
                    tiers: tiers,
                    operationalStatus: .operational,
                    accountEmail: config.accountLabel,
                    planType: usage.plan_type,
                    sourceType: effectiveSource
                )
            }
            return nil
        }
    }

    public init() {
        self.api = APIClient()
        subscriptionManager.apiClient = api
        loadProviderConfigs()
        // Forward SubscriptionManager objectWillChange so UI updates on tier changes
        subscriptionCancellable = subscriptionManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Persist rotated tokens to Keychain when auto-refresh happens
        Task {
            await api.setTokenRefreshHandler { [weak self] newAccess, newRefresh in
                guard let self else { return }
                Task { @MainActor in
                    self.storedToken = newAccess
                    if !newRefresh.isEmpty {
                        KeychainHelper.save(key: Self.refreshTokenKeychainKey, value: newRefresh)
                    }
                }
            }
        }
        // Migrate legacy token from UserDefaults to Keychain
        if let legacyToken = UserDefaults.standard.string(forKey: "cli_pulse_token"), !legacyToken.isEmpty {
            KeychainHelper.save(key: Self.tokenKeychainKey, value: legacyToken)
            UserDefaults.standard.removeObject(forKey: "cli_pulse_token")
        }
        Task {
            if isDemoMode {
                enterDemoMode()
            } else {
                if !storedToken.isEmpty {
                    await api.updateToken(storedToken)
                    // Restore refresh token
                    if let savedRefresh = KeychainHelper.load(key: Self.refreshTokenKeychainKey) {
                        await api.updateRefreshToken(savedRefresh)
                    }
                    await restoreSession()
                }
            }
        }
    }

    // MARK: - Auth

    /// OTP step 1: send verification code to email
    @Published public var otpSent = false
    @Published public var otpEmail = ""

    public func sendOTP(email: String) async {
        isLoading = true
        lastError = nil
        do {
            try await api.sendOTP(email: email)
            otpEmail = email
            otpSent = true
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    /// OTP step 2: verify code and sign in
    public func verifyOTP(code: String) async {
        isLoading = true
        lastError = nil
        do {
            let response = try await api.verifyOTP(email: otpEmail, code: code)
            storeAuthTokens(response)
            userName = response.user.name
            userEmail = response.user.email
            isPaired = response.paired
            isAuthenticated = true
            otpSent = false
            otpEmail = ""
            startRefreshLoop()
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    /// Password-based sign in (for demo / review account)
    public func signInWithPassword(email: String, password: String) async {
        isLoading = true
        lastError = nil
        do {
            let response = try await api.signInWithPassword(email: email, password: password)
            storeAuthTokens(response)
            userName = response.user.name
            userEmail = response.user.email
            isPaired = response.paired
            isAuthenticated = true
            startRefreshLoop()
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    /// Reset OTP flow (go back to email entry)
    public func resetOTP() {
        otpSent = false
        otpEmail = ""
        lastError = nil
    }

    public func signInWithApple(identityToken: String, nonce: String? = nil, fullName: String?, email: String?) async {
        isLoading = true
        lastError = nil
        do {
            let response = try await api.signInWithApple(identityToken: identityToken, nonce: nonce, fullName: fullName, email: email)
            storeAuthTokens(response)
            userName = response.user.name
            userEmail = response.user.email
            isPaired = response.paired
            isAuthenticated = true
            startRefreshLoop()
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    /// Store access + refresh tokens from an auth response
    private func storeAuthTokens(_ response: AuthResponse) {
        storedToken = response.access_token
        if let refresh = response.refresh_token, !refresh.isEmpty {
            KeychainHelper.save(key: Self.refreshTokenKeychainKey, value: refresh)
        }
    }

    // MARK: - Pairing

    @Published public var pairingInfo: PairingInfo?
    @Published public var pairingError: String?

    public func generatePairingCode() async {
        isLoading = true
        pairingError = nil
        do {
            pairingInfo = try await api.pairingCode()
        } catch {
            pairingError = error.localizedDescription
        }
        isLoading = false
    }

    public func checkPairingStatus() async {
        isLoading = true
        pairingError = nil
        do {
            // The helper calls register_helper RPC which sets paired=true.
            // We just need to re-check our profile.
            let response = try await api.me()
            isPaired = response.paired
            if isPaired {
                pairingInfo = nil
                startRefreshLoop()
                await refreshAll()
            } else {
                pairingError = "Helper hasn't connected yet. Run the command above, then try again."
            }
        } catch {
            pairingError = error.localizedDescription
        }
        isLoading = false
    }

    @AppStorage("cli_pulse_demo_mode") public var isDemoMode = false

    public func enterDemoMode() {
        isDemoMode = true
        isAuthenticated = true
        isPaired = true
        userName = "Demo User"
        userEmail = "demo@clipulse.app"
        serverOnline = true
        lastRefresh = Date()

        let now = ISO8601DateFormatter().string(from: Date())
        let hourAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        let twoHoursAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200))

        func trend(_ base: Int) -> [UsagePoint] {
            (0..<12).map { i in
                UsagePoint(timestamp: ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(-11 + i) * 3600)), value: base + Int.random(in: -2000...2000))
            }
        }

        providers = [
            ProviderUsage(provider: "Codex", today_usage: 85900, week_usage: 462000,
                          estimated_cost_today: 1.03, estimated_cost_week: 5.54,
                          cost_status_today: "Estimated", cost_status_week: "Estimated",
                          quota: 500000, remaining: 38000, status_text: "92% used",
                          trend: trend(85000), recent_sessions: ["Dashboard metrics pass"], recent_errors: []),
            ProviderUsage(provider: "Gemini", today_usage: 43400, week_usage: 214000,
                          estimated_cost_today: 0.35, estimated_cost_week: 1.71,
                          cost_status_today: "Estimated", cost_status_week: "Estimated",
                          quota: 300000, remaining: 86000, status_text: "71% used",
                          trend: trend(43000), recent_sessions: ["Helper heartbeat monitor"], recent_errors: []),
            ProviderUsage(provider: "Claude", today_usage: 24800, week_usage: 132000,
                          estimated_cost_today: 0.37, estimated_cost_week: 1.98,
                          cost_status_today: "Estimated", cost_status_week: "Estimated",
                          quota: 250000, remaining: 118000, status_text: "53% used",
                          trend: trend(24000), recent_sessions: ["Provider adapter review"], recent_errors: []),
        ]

        sessions = [
            SessionRecord(id: "s1", name: "Dashboard metrics pass", provider: "Codex",
                          project: "cli-pulse-ios", device_name: "MacBook Pro",
                          started_at: twoHoursAgo, last_active_at: now,
                          status: "running", total_usage: 24500, estimated_cost: 0.29,
                          cost_status: "Estimated", requests: 142, error_count: 0,
                          collection_confidence: "high"),
            SessionRecord(id: "s2", name: "Helper heartbeat monitor", provider: "Gemini",
                          project: "cli-pulse-helper", device_name: "lab-server-01",
                          started_at: hourAgo, last_active_at: now,
                          status: "syncing", total_usage: 12800, estimated_cost: 0.10,
                          cost_status: "Estimated", requests: 87, error_count: 0,
                          collection_confidence: "medium"),
            SessionRecord(id: "s3", name: "Session error triage", provider: "Codex",
                          project: "backend-api", device_name: "build-box",
                          started_at: twoHoursAgo, last_active_at: hourAgo,
                          status: "failed", total_usage: 8400, estimated_cost: 0.10,
                          cost_status: "Estimated", requests: 56, error_count: 3,
                          collection_confidence: "high"),
            SessionRecord(id: "s4", name: "Provider adapter review", provider: "Claude",
                          project: "provider-layer", device_name: "MacBook Pro",
                          started_at: hourAgo, last_active_at: now,
                          status: "running", total_usage: 6200, estimated_cost: 0.09,
                          cost_status: "Estimated", requests: 38, error_count: 0,
                          collection_confidence: "low"),
        ]

        devices = [
            DeviceRecord(id: "d1", name: "MacBook Pro", type: "laptop", system: "macOS 15.4",
                         status: "online", last_sync_at: now, helper_version: "0.2.0",
                         current_session_count: 2, cpu_usage: 42, memory_usage: 68),
            DeviceRecord(id: "d2", name: "lab-server-01", type: "server", system: "Ubuntu 24.04",
                         status: "online", last_sync_at: now, helper_version: "0.2.0",
                         current_session_count: 1, cpu_usage: 23, memory_usage: 45),
            DeviceRecord(id: "d3", name: "build-box", type: "server", system: "macOS 14.7",
                         status: "offline", last_sync_at: hourAgo, helper_version: "0.1.9",
                         current_session_count: 0, cpu_usage: nil, memory_usage: nil),
        ]

        alerts = [
            AlertRecord(id: "a1", type: "Quota Critical", severity: "Critical",
                        title: "Codex quota critically low", message: "Only 7.6% remaining (38,000 of 500,000 tokens)",
                        created_at: now, is_read: false, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: "Codex", related_device_name: nil,
                        source_kind: "provider", source_id: "Codex",
                        grouping_key: "quota-critical:Codex", suppression_key: "quota-critical:Codex"),
            AlertRecord(id: "a2", type: "Session Failed", severity: "Warning",
                        title: "Session failed: error triage", message: "Session 'Session error triage' encountered 3 errors on build-box",
                        created_at: hourAgo, is_read: false, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: "p3", related_project_name: "backend-api",
                        related_session_id: "s3", related_session_name: "Session error triage",
                        related_provider: "Codex", related_device_name: "build-box",
                        source_kind: "session", source_id: "s3",
                        grouping_key: "session-failed:s3"),
            AlertRecord(id: "a3", type: "Helper Offline", severity: "Warning",
                        title: "Device offline: build-box", message: "build-box has not synced for over 60 minutes",
                        created_at: hourAgo, is_read: true, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: nil, related_device_name: "build-box",
                        source_kind: "device", source_id: "d3",
                        grouping_key: "device-offline:build-box"),
            AlertRecord(id: "a4", type: "Cost Spike", severity: "Warning",
                        title: "Cost spike: Codex", message: "Codex estimated cost today reached $1.03, exceeding threshold $0.80",
                        created_at: twoHoursAgo, is_read: true, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: "Codex", related_device_name: nil,
                        source_kind: "provider", source_id: "Codex",
                        grouping_key: "cost-spike:Codex"),
            AlertRecord(id: "a5", type: "Error Rate Spike", severity: "Info",
                        title: "Error rate spike: Codex", message: "Codex error rate spiked: 3 errors across 4 sessions",
                        created_at: twoHoursAgo, is_read: true, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: "Codex", related_device_name: nil,
                        source_kind: "provider", source_id: "Codex",
                        grouping_key: "error-rate:Codex"),
        ]

        let breakdowns = providers.map { p in
            ProviderBreakdown(provider: p.provider, usage: p.today_usage,
                              estimated_cost: p.estimated_cost_today,
                              cost_status: "Estimated", remaining: p.remaining)
        }

        dashboard = DashboardSummary(
            total_usage_today: providers.reduce(0) { $0 + $1.today_usage },
            total_estimated_cost_today: providers.reduce(0) { $0 + $1.estimated_cost_today },
            cost_status: "Estimated",
            total_requests_today: sessions.reduce(0) { $0 + $1.requests },
            active_sessions: sessions.filter { $0.status == "running" || $0.status == "syncing" }.count,
            online_devices: devices.filter { $0.status == "online" }.count,
            unresolved_alerts: alerts.filter { !$0.is_resolved }.count,
            provider_breakdown: breakdowns,
            top_projects: [
                TopProject(id: "p1", name: "cli-pulse-ios", usage: 24500, estimated_cost: 0.29, cost_status: "Estimated"),
                TopProject(id: "p2", name: "cli-pulse-helper", usage: 12800, estimated_cost: 0.10, cost_status: "Estimated"),
                TopProject(id: "p3", name: "backend-api", usage: 8400, estimated_cost: 0.10, cost_status: "Estimated"),
            ],
            trend: (0..<24).map { i in
                UsagePoint(timestamp: ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(-23 + i) * 3600)),
                           value: 4000 + Int.random(in: 0...3000))
            },
            recent_activity: [
                ActivityItem(id: "act1", title: "Session started", subtitle: "Dashboard metrics pass on MacBook Pro", timestamp: now),
                ActivityItem(id: "act2", title: "Alert fired", subtitle: "Codex quota critically low", timestamp: now),
                ActivityItem(id: "act3", title: "Session failed", subtitle: "Session error triage on build-box", timestamp: hourAgo),
            ],
            risk_signals: ["Codex quota below 10%", "build-box offline"],
            alert_summary: AlertSummaryDTO(critical: 1, warning: 3, info: 1)
        )

        buildProviderDetails()
        updateCostSummary()
        publishWidgetData()
    }

    public func signOut() {
        stopRefreshLoop()
        // Cancel any in-flight refresh to prevent stale data overwriting cleared state
        refreshTask?.cancel()
        refreshTask = nil
        // Revoke server-side token
        Task { await api.signOutServer() }
        storedToken = ""
        KeychainHelper.delete(key: Self.refreshTokenKeychainKey)
        isDemoMode = false
        isAuthenticated = false
        isPaired = false
        isLocalMode = false
        userName = ""
        userEmail = ""
        dashboard = nil
        providers = []
        sessions = []
        devices = []
        alerts = []
        selectedTab = .overview
    }

    public func deleteAccount() async {
        isLoading = true
        lastError = nil
        do {
            try await api.deleteAccount()
            isLoading = false
            signOut()
        } catch {
            lastError = error.localizedDescription
            isLoading = false
        }
    }

    public func restoreSession() async {
        if isDemoMode {
            enterDemoMode()
            return
        }
        isLoading = true
        do {
            let response = try await api.me()
            userName = response.user.name
            userEmail = response.user.email
            isPaired = response.paired
            isAuthenticated = true
            serverOnline = true
            isLoading = false
            await subscriptionManager.updateCurrentEntitlements()
            startRefreshLoop()
            await refreshAll()
        } catch {
            storedToken = ""
            isAuthenticated = false
            isLoading = false
        }
    }

    // MARK: - Data Refresh

    public func refreshAll() async {
        guard isAuthenticated, !isDemoMode else { return }

        // If not paired to cloud, use local scanning on macOS
        #if os(macOS)
        if !isPaired {
            await refreshLocal()
            return
        }
        #else
        guard isPaired else { return }
        #endif

        // Skip if a refresh is already in progress
        guard !isLoading else { return }
        isLoading = true
        lastError = nil

        do {
            let healthy = try await api.health()
            serverOnline = healthy
        } catch {
            serverOnline = false
            lastError = "Server offline"
            isLoading = false
            return
        }

        // Check cancellation before heavy work
        guard !Task.isCancelled else { isLoading = false; return }

        do {
            async let d = api.dashboard()
            async let p = api.providers()
            async let s = api.sessions()
            async let dev = api.devices()
            async let a = api.alerts()

            let (dash, provs, sess, devs, alts) = try await (d, p, s, dev, a)

            // Guard against sign-out during in-flight requests
            guard isAuthenticated else { isLoading = false; return }
            dashboard = dash
            sessions = sess
            devices = devs

            // On macOS, run local collectors to supplement cloud data where
            // the backend doesn't return quota/tier information for a provider.
            #if os(macOS)
            let localResults = await runCollectors()
            let (merged, supplemented) = Self.mergeCloudWithLocal(cloud: provs, local: localResults)
            providers = merged
            locallySupplementedProviders = supplemented

            // Runtime diagnostic: dump before/after merge state for verification
            Self.dumpMergeDiagnostic(cloud: provs, local: localResults, merged: merged)
            #else
            providers = provs
            locallySupplementedProviders = []
            #endif

            // Check tier limits and surface warnings
            let maxDevices = subscriptionManager.maxDevices
            let maxProviders = subscriptionManager.maxProviders
            var warnings: [String] = []
            if maxDevices >= 0, devs.count > maxDevices {
                warnings.append("Devices: \(devs.count)/\(maxDevices)")
            }
            if maxProviders >= 0 {
                let enabledCount = providerConfigs.filter(\.isEnabled).count
                if enabledCount > maxProviders {
                    warnings.append("Providers: \(enabledCount)/\(maxProviders)")
                }
            }
            tierLimitWarning = warnings.isEmpty ? nil : "Over \(subscriptionManager.currentTier.rawValue) plan limits — \(warnings.joined(separator: ", ")). Upgrade or reduce usage."

            // Check for new alerts before updating
            let newAlerts = alts.filter { alert in
                !alert.is_resolved && !previousAlertIDs.contains(alert.id)
            }
            if notificationsEnabled {
                for alert in newAlerts {
                    sendNotification(for: alert)
                }
            }
            previousAlertIDs = Set(alts.map(\.id))
            alerts = alts

            lastRefresh = Date()
            buildProviderDetails()
            updateCostSummary()
            publishWidgetData()
        } catch let error as APIError where error == .tokenExpired {
            signOut()
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Cloud + Local Merge

    #if os(macOS)
    /// Merge cloud provider data with local collector results.
    ///
    /// **Freshness rule**: local collectors run as part of each `refreshAll()`
    /// cycle, so their quota/tier data is always fresher than cloud data
    /// (which depends on the last helper daemon sync to Supabase). When a
    /// local collector returns quota/tier data, it wins for those fields.
    /// Cloud continues to supply trend, cost, session, and error fields.
    ///
    /// - If local returned quota or tier data, use local quota/tier fields.
    /// - If cloud has no quota AND no tiers, use local data.
    /// - If local has no data for a provider, keep cloud data as-is.
    /// - statusOnly results are never merged into cloud data.
    /// - Providers not in cloud are added from local.
    ///
    /// Returns (merged providers, set of provider names that were locally supplemented).
    nonisolated static func mergeCloudWithLocal(cloud: [ProviderUsage], local: [CollectorResult]) -> ([ProviderUsage], Set<String>) {
        var merged: [String: ProviderUsage] = [:]
        for p in cloud { merged[p.provider] = p }
        var supplemented: Set<String> = []

        for result in local {
            // Skip statusOnly (e.g. Ollama model listing) — not useful to overlay on cloud data
            guard result.dataKind == .quota || result.dataKind == .credits else { continue }

            let name = result.usage.provider
            if let existing = merged[name] {
                let cloudHasQuota = existing.quota != nil && (existing.quota ?? 0) > 0
                let cloudHasTiers = !existing.tiers.isEmpty
                let cloudIsEmpty = !cloudHasQuota && !cloudHasTiers
                // Freshness tiebreaker: when local has tiers and at least
                // as many as cloud, prefer local because it was just fetched
                // (seconds ago) vs cloud data from the last helper sync
                // (potentially hours stale). Cloud only wins when it has
                // strictly more tiers than local.
                let localWins = !result.usage.tiers.isEmpty
                    && result.usage.tiers.count >= existing.tiers.count

                if cloudIsEmpty || localWins {
                    // Cloud is incomplete OR local has equal/richer tier data — use local quota/tiers (fresher)
                    merged[name] = ProviderUsage(
                        provider: existing.provider,
                        today_usage: existing.today_usage > 0 ? existing.today_usage : result.usage.today_usage,
                        week_usage: existing.week_usage > 0 ? existing.week_usage : result.usage.week_usage,
                        estimated_cost_today: existing.estimated_cost_today,
                        estimated_cost_week: existing.estimated_cost_week,
                        cost_status_today: existing.cost_status_today,
                        cost_status_week: existing.cost_status_week,
                        quota: result.usage.quota,
                        remaining: result.usage.remaining,
                        plan_type: result.usage.plan_type ?? existing.plan_type,
                        reset_time: result.usage.reset_time ?? existing.reset_time,
                        tiers: result.usage.tiers,
                        status_text: result.usage.status_text,
                        trend: existing.trend,
                        recent_sessions: existing.recent_sessions,
                        recent_errors: existing.recent_errors,
                        metadata: existing.metadata ?? result.usage.metadata
                    )
                    supplemented.insert(name)
                }
                // Local had no quota/tier data — keep cloud as-is
            } else {
                // Provider not in cloud results — add local-only data
                merged[name] = result.usage
                supplemented.insert(name)
            }
        }

        return (merged.values.sorted { $0.today_usage > $1.today_usage }, supplemented)
    }

    /// Dump merge diagnostic to /tmp for runtime verification.
    nonisolated static func dumpMergeDiagnostic(cloud: [ProviderUsage], local: [CollectorResult], merged: [ProviderUsage]) {
        func snapshot(_ p: ProviderUsage) -> [String: Any] {
            [
                "provider": p.provider,
                "quota": p.quota as Any,
                "remaining": p.remaining as Any,
                "tiers_count": p.tiers.count,
                "tiers": p.tiers.map { ["name": $0.name, "quota": $0.quota, "remaining": $0.remaining, "reset_time": $0.reset_time as Any] },
                "plan_type": p.plan_type as Any,
                "reset_time": p.reset_time as Any,
                "today_usage": p.today_usage,
            ]
        }
        let diag: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "cloud": cloud.map(snapshot),
            "local_collectors": local.map { [
                "provider": $0.usage.provider,
                "data_kind": String(describing: $0.dataKind),
                "usage": snapshot($0.usage),
            ] },
            "merged": merged.map(snapshot),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: diag, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            try? str.write(toFile: NSTemporaryDirectory() + "clipulse_merge_diagnostic.json", atomically: true, encoding: .utf8)
        }
    }
    #endif

    // MARK: - Local Mode (macOS only, no cloud needed)
    //
    // Two-phase local refresh:
    //   1. Run provider-native collectors for providers with credentials configured.
    //      These return real quota/credits/tier data.
    //   2. Run LocalScanner for process detection (sessions + estimated usage).
    //      Scanner results fill in providers that don't have a collector.
    // Collector results take precedence; scanner results are used as fallback.

    #if os(macOS)
    private func refreshLocal() async {
        guard !isLoading else { return }
        isLoading = true
        isLocalMode = true
        serverOnline = true
        lastError = nil

        // Phase 1: Run provider-native collectors concurrently
        let collectorResults = await runCollectors()

        // Phase 2: Run process detection via LocalScanner
        let scanResult = await Task.detached { LocalScanner.shared.scan() }.value

        // Guard against sign-out during async work
        guard isAuthenticated else { isLoading = false; return }

        // Merge: collector results override scanner results for the same provider.
        // Scanner sessions are always preserved (collectors don't produce sessions).
        sessions = scanResult.sessions

        var mergedProviders: [String: ProviderUsage] = [:]
        // Start with scanner results as baseline
        for p in scanResult.providers {
            mergedProviders[p.provider] = p
        }
        // Overlay collector results (real quota data takes precedence)
        for result in collectorResults {
            mergedProviders[result.usage.provider] = result.usage
        }
        providers = mergedProviders.values.sorted { $0.today_usage > $1.today_usage }

        devices = [DeviceRecord(
            id: "local",
            name: ProcessInfo.processInfo.hostName,
            type: "macOS",
            system: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            status: "online",
            last_sync_at: ISO8601DateFormatter().string(from: Date()),
            helper_version: "local",
            current_session_count: scanResult.activeSessionCount,
            cpu_usage: nil,
            memory_usage: nil
        )]
        alerts = []

        let totalUsage = providers.reduce(0) { $0 + $1.today_usage }
        let totalCost = providers.reduce(0) { $0 + $1.estimated_cost_today }

        let breakdown = providers.map {
            ProviderBreakdown(provider: $0.provider, usage: $0.today_usage,
                              estimated_cost: $0.estimated_cost_today,
                              cost_status: $0.cost_status_today, remaining: $0.remaining)
        }
        dashboard = DashboardSummary(
            total_usage_today: totalUsage,
            total_estimated_cost_today: totalCost,
            cost_status: "Estimated",
            total_requests_today: scanResult.sessions.reduce(0) { $0 + $1.requests },
            active_sessions: scanResult.activeSessionCount,
            online_devices: 1,
            unresolved_alerts: 0,
            provider_breakdown: breakdown,
            top_projects: [],
            trend: [],
            recent_activity: [],
            risk_signals: scanResult.isEmpty && collectorResults.isEmpty
                ? ["No AI tools detected. Start a coding session to see data."] : [],
            alert_summary: AlertSummaryDTO(critical: 0, warning: 0, info: 0)
        )

        lastRefresh = Date()
        buildProviderDetails()
        updateCostSummary()
        isLoading = false
    }

    /// Run all available collectors concurrently. Non-fatal: errors are logged, not thrown.
    private func runCollectors() async -> [CollectorResult] {
        let configs = providerConfigs.filter(\.isEnabled)
        var results: [CollectorResult] = []

        await withTaskGroup(of: CollectorResult?.self) { group in
            for config in configs {
                if let collector = CollectorRegistry.collector(for: config.kind, config: config) {
                    group.addTask {
                        do {
                            return try await collector.collect(config: config)
                        } catch {
                            // Non-fatal: collector failure doesn't block other providers
                            let msg = "[Collector] \(config.kind.rawValue) failed: \(error.localizedDescription)"
                            if !Self.shouldSilenceCollectorError(kind: config.kind, error: error) {
                                print(msg)
                            }
                            // Append to diagnostic log
                            let logPath = NSTemporaryDirectory() + "clipulse_collector_errors.log"
                            let entry = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
                            if let fh = FileHandle(forWritingAtPath: logPath) {
                                fh.seekToEndOfFile()
                                fh.write(entry.data(using: .utf8) ?? Data())
                                fh.closeFile()
                            } else {
                                try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
                            }
                            return nil
                        }
                    }
                }
            }
            for await result in group {
                if let r = result { results.append(r) }
            }
        }
        return results
    }

    nonisolated private static func shouldSilenceCollectorError(kind: ProviderKind, error: Error) -> Bool {
        // Local Ollama is optional. When the daemon is not running, connection-refused
        // noise in the Xcode console is not actionable for most users.
        guard kind == .ollama else { return false }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           [NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost]
            .contains(nsError.code) {
            return true
        }

        return nsError.localizedDescription == "Could not connect to the server."
    }
    #endif

    private func updateCostSummary() {
        let todayByProvider = providers.map { ($0.provider, $0.estimated_cost_today) }
        let todayTotal = todayByProvider.reduce(0) { $0 + $1.1 }
        let thirtyDayByProvider = providers.map { ($0.provider, $0.estimated_cost_week * 4.3) } // approximate
        let thirtyDayTotal = thirtyDayByProvider.reduce(0) { $0 + $1.1 }
        costSummary = CostSummary(
            todayTotal: todayTotal,
            todayByProvider: todayByProvider,
            thirtyDayTotal: thirtyDayTotal,
            thirtyDayByProvider: thirtyDayByProvider
        )
    }

    // MARK: - Widget Data

    private func publishWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.yyh.CLI-Pulse") else { return }

        struct WidgetProviderData: Codable {
            let name: String
            let usage: Int
            let quota: Int?
            let costToday: Double
            let iconName: String
        }

        struct WidgetData: Codable {
            let totalUsageToday: Int
            let totalCostToday: Double
            let activeSessions: Int
            let unresolvedAlerts: Int
            let providers: [WidgetProviderData]
            let lastUpdated: Date
        }

        let widgetProviders = providers.prefix(10).map { p in
            WidgetProviderData(
                name: p.provider,
                usage: p.today_usage,
                quota: p.quota,
                costToday: p.estimated_cost_today,
                iconName: p.providerKind?.iconName ?? "cpu"
            )
        }

        let data = WidgetData(
            totalUsageToday: dashboard?.total_usage_today ?? 0,
            totalCostToday: dashboard?.total_estimated_cost_today ?? 0,
            activeSessions: dashboard?.active_sessions ?? 0,
            unresolvedAlerts: alerts.filter { !$0.is_resolved }.count,
            providers: Array(widgetProviders),
            lastUpdated: Date()
        )

        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: "widgetData")
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - Alert Actions

    private func demoUpdateAlert(_ a: AlertRecord, isRead: Bool? = nil, isResolved: Bool? = nil, acknowledgedAt: String? = nil, snoozedUntil: String? = nil) -> AlertRecord {
        AlertRecord(id: a.id, type: a.type, severity: a.severity, title: a.title, message: a.message, created_at: a.created_at, is_read: isRead ?? a.is_read, is_resolved: isResolved ?? a.is_resolved, acknowledged_at: acknowledgedAt ?? a.acknowledged_at, snoozed_until: snoozedUntil ?? a.snoozed_until, related_project_id: a.related_project_id, related_project_name: a.related_project_name, related_session_id: a.related_session_id, related_session_name: a.related_session_name, related_provider: a.related_provider, related_device_name: a.related_device_name, source_kind: a.source_kind, source_id: a.source_id, grouping_key: a.grouping_key, suppression_key: a.suppression_key)
    }

    public func acknowledgeAlert(_ alert: AlertRecord) async {
        if isDemoMode {
            if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
                alerts[idx] = demoUpdateAlert(alerts[idx], isRead: true, acknowledgedAt: ISO8601DateFormatter().string(from: Date()))
            }
            return
        }
        do {
            _ = try await api.acknowledgeAlert(id: alert.id)
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func resolveAlert(_ alert: AlertRecord) async {
        if isDemoMode {
            if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
                alerts[idx] = demoUpdateAlert(alerts[idx], isRead: true, isResolved: true)
            }
            return
        }
        do {
            _ = try await api.resolveAlert(id: alert.id)
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func snoozeAlert(_ alert: AlertRecord, minutes: Int) async {
        if isDemoMode {
            if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
                let until = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(minutes) * 60))
                alerts[idx] = demoUpdateAlert(alerts[idx], isRead: true, snoozedUntil: until)
            }
            return
        }
        do {
            _ = try await api.snoozeAlert(id: alert.id, minutes: minutes)
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Refresh Timer

    public func startRefreshLoop() {
        stopRefreshLoop()
        let interval = max(TimeInterval(refreshInterval), 60) // Minimum 60s to save battery
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshTask = Task {
                    await self.refreshAll()
                }
            }
        }
    }

    public func stopRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    public func updateRefreshInterval(_ seconds: Int) {
        refreshInterval = seconds
        if isAuthenticated {
            startRefreshLoop()
        }
    }

    // MARK: - Notifications

    private func sendNotification(for alert: AlertRecord) {
        let content = UNMutableNotificationContent()
        content.title = "CLI Pulse: \(alert.severity)"
        content.body = alert.title
        content.sound = alert.alertSeverity == .critical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
