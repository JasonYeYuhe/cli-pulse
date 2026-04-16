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
    private var subscriptionCancellable: AnyCancellable?

    // MARK: - UI State
    @Published public var selectedTab: Tab = .overview
    @Published public var isLoading = false
    @Published public var lastError: String?
    @Published public var tierLimitWarning: String?
    @Published public var lastRefresh: Date?
    @Published public var serverOnline = false
    @Published public var isLocalMode = false

    // MARK: - Provider Management
    @Published public var providerConfigs: [ProviderConfig] = ProviderConfig.defaults()
    @Published public var providerDetails: [ProviderDetail] = []
    @Published public var costSummary: CostSummary = CostSummary()
    public var locallySupplementedProviders: Set<String> = []

    // MARK: - Cost Usage Scan (precise token data from local JSONL logs, macOS only)
    @Published public var costUsageScanResult: CostUsageScanResult?

    // MARK: - Cost Forecast
    @Published public var costForecast: CostForecast?

    // MARK: - Auth Flow
    @Published public var otpSent = false
    @Published public var otpEmail = ""
    @Published public var pairingInfo: PairingInfo?
    @Published public var pairingError: String?
    @AppStorage("cli_pulse_demo_mode") public var isDemoMode = false

    // MARK: - Webhook Integration
    @AppStorage("cli_pulse_webhook_enabled") public var webhookEnabled = false
    @AppStorage("cli_pulse_webhook_url") public var webhookURL = ""

    // MARK: - Settings - General
    nonisolated static let tokenKeychainKey = "cli_pulse_token"

    public var storedToken: String {
        get { KeychainHelper.load(key: Self.tokenKeychainKey) ?? "" }
        set { Self.persistAuthTokens(access: newValue, refresh: storedRefreshToken) }
    }

    @AppStorage("cli_pulse_refresh_interval") public var refreshInterval: Int = 120
    @AppStorage("cli_pulse_show_cost") public var showCost = true
    @AppStorage("cli_pulse_notifications") public var notificationsEnabled = true
    @AppStorage("cli_pulse_compact_mode") public var compactMode = false
    @AppStorage("cli_pulse_check_provider_status") public var checkProviderStatus = true
    @AppStorage("cli_pulse_session_quota_notifications") public var sessionQuotaNotifications = true
    @AppStorage("cli_pulse_hide_personal_info") public var hidePersonalInfo = false
    @AppStorage("cli_pulse_appearance") public var appearanceModeRaw = 0

    public var appearanceMode: ColorScheme? {
        switch appearanceModeRaw {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    // MARK: - Settings - Display
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
    let authManager: AuthManager
    let dataRefreshManager: DataRefreshManager

    private static let secretsMigratedKey = "cli_pulse_provider_secrets_migrated"

    public init() {
        self.api = APIClient()
        self.authManager = AuthManager(api: api, persistTokens: Self.persistAuthTokens)
        self.dataRefreshManager = DataRefreshManager(api: api)
        subscriptionManager.apiClient = api
        loadProviderConfigs()

        subscriptionCancellable = subscriptionManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        if let legacyToken = UserDefaults.standard.string(forKey: "cli_pulse_token"), !legacyToken.isEmpty {
            Self.persistAuthTokens(access: legacyToken, refresh: KeychainHelper.load(key: AuthManager.refreshTokenKeychainKey))
        }
        UserDefaults.standard.removeObject(forKey: "cli_pulse_token")

        Task {
            await api.setTokenRefreshHandler { newAccess, newRefresh in
                Self.persistAuthTokens(access: newAccess, refresh: newRefresh)
            }
            await restoreSession()
        }
    }

    // MARK: - Menu Bar

    public var menuBarLabel: String {
        guard isAuthenticated, isPaired else { return "" }
        let unresolvedCount = alerts.filter { !$0.is_resolved }.count
        if unresolvedCount > 0 {
            return "\(unresolvedCount)"
        }
        switch menuBarDisplayMode {
        case .percent:
            if let top = mostUsedProvider, top.usagePercent > 0 {
                return "\(Int((1.0 - top.usagePercent) * 100))%"
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
        if menuBarDisplayMode == .mostUsed, let top = mostUsedProvider, let kind = top.providerKind {
            return kind.iconName
        }
        return "waveform.path.ecg"
    }

    public var mostUsedProvider: ProviderUsage? {
        providers
            .filter { enabledProviderNames.contains($0.provider) }
            .max(by: { $0.usagePercent < $1.usagePercent })
    }

    public var enabledProviderNames: Set<String> {
        Set(providerConfigs.filter(\.isEnabled).map(\.kind.rawValue))
    }

    // MARK: - Provider Config Management

    public func toggleProvider(_ kind: ProviderKind) {
        if let idx = providerConfigs.firstIndex(where: { $0.kind == kind }) {
            let wasEnabled = providerConfigs[idx].isEnabled
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
        for index in providerConfigs.indices {
            providerConfigs[index].sortOrder = index
        }
        saveProviderConfigs()
    }

    public func saveProviderConfigs() {
        if let data = try? JSONEncoder().encode(providerConfigs) {
            UserDefaults.standard.set(data, forKey: "cli_pulse_provider_configs")
            UserDefaults(suiteName: HelperIPC.suiteName)?.set(data, forKey: HelperIPC.providerConfigsKey)
        }
        for config in providerConfigs {
            config.saveSecrets()
        }
    }

    public func buildProviderDetails() {
        providerDetails = providerConfigs.sorted(by: { $0.sortOrder < $1.sortOrder }).compactMap { config in
            guard let usage = providers.first(where: { $0.provider == config.kind.rawValue }) else { return nil }

            let tiers: [UsageTier]
            if !usage.tiers.isEmpty {
                tiers = usage.tiers.compactMap { tier in
                    guard tier.quota > 0 else { return nil }
                    return UsageTier(
                        name: tier.name,
                        usage: tier.quota - tier.remaining,
                        quota: tier.quota,
                        remaining: tier.remaining,
                        resetTime: tier.reset_time
                    )
                }
            } else if let quota = usage.quota, quota > 0 {
                tiers = [
                    UsageTier(
                        name: "Default",
                        usage: usage.today_usage,
                        quota: quota,
                        remaining: usage.remaining,
                        resetTime: usage.reset_time
                    )
                ]
            } else {
                tiers = []
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
    }

    private func loadProviderConfigs() {
        guard let data = UserDefaults.standard.data(forKey: "cli_pulse_provider_configs") else { return }

        if !UserDefaults.standard.bool(forKey: Self.secretsMigratedKey) {
            migrateLegacySecrets(from: data)
            UserDefaults.standard.set(true, forKey: Self.secretsMigratedKey)
        }

        if let configs = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providerConfigs = configs
            let existingKinds = Set(configs.map(\.kind))
            for kind in ProviderKind.allCases where !existingKinds.contains(kind) {
                providerConfigs.append(ProviderConfig(kind: kind, isEnabled: true, sortOrder: providerConfigs.count))
            }
        }

        for index in providerConfigs.indices {
            providerConfigs[index].loadSecrets()
        }
    }

    private func migrateLegacySecrets(from data: Data) {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for entry in array {
            guard let kindRaw = entry["kind"] as? String, let kind = ProviderKind(rawValue: kindRaw) else { continue }
            if let apiKey = entry["apiKey"] as? String, !apiKey.isEmpty {
                KeychainHelper.save(key: "cli_pulse_provider_\(kind.rawValue)_apiKey", value: apiKey)
            }
            if let cookie = entry["manualCookieHeader"] as? String, !cookie.isEmpty {
                KeychainHelper.save(key: "cli_pulse_provider_\(kind.rawValue)_cookie", value: cookie)
            }
        }

        if let configs = try? JSONDecoder().decode([ProviderConfig].self, from: data),
           let cleanData = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(cleanData, forKey: "cli_pulse_provider_configs")
        }
    }
}
