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

    // MARK: - UI State
    @Published public var selectedTab: Tab = .overview
    @Published public var isLoading = false
    @Published public var lastError: String?
    @Published public var lastRefresh: Date?
    @Published public var serverOnline = false

    // MARK: - Provider Management
    @Published public var providerConfigs: [ProviderConfig] = ProviderConfig.defaults()
    @Published public var providerDetails: [ProviderDetail] = []
    @Published public var costSummary: CostSummary = CostSummary()

    // MARK: - Settings — General
    @AppStorage("cli_pulse_token") public var storedToken = ""
    @AppStorage("cli_pulse_refresh_interval") public var refreshInterval: Int = 30
    @AppStorage("cli_pulse_show_cost") public var showCost = true
    @AppStorage("cli_pulse_notifications") public var notificationsEnabled = true
    @AppStorage("cli_pulse_compact_mode") public var compactMode = false
    @AppStorage("cli_pulse_check_provider_status") public var checkProviderStatus = true
    @AppStorage("cli_pulse_session_quota_notifications") public var sessionQuotaNotifications = true
    @AppStorage("cli_pulse_hide_personal_info") public var hidePersonalInfo = false

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

    private func saveProviderConfigs() {
        if let data = try? JSONEncoder().encode(providerConfigs) {
            UserDefaults.standard.set(data, forKey: "cli_pulse_provider_configs")
        }
    }

    private func loadProviderConfigs() {
        if let data = UserDefaults.standard.data(forKey: "cli_pulse_provider_configs"),
           let configs = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providerConfigs = configs
            // Add any new providers not in saved config
            let existingKinds = Set(configs.map(\.kind))
            let newProviders = ProviderKind.allCases.filter { !existingKinds.contains($0) }
            for kind in newProviders {
                providerConfigs.append(ProviderConfig(kind: kind, isEnabled: true, sortOrder: providerConfigs.count))
            }
        }
    }

    public func buildProviderDetails() {
        providerDetails = providerConfigs.sorted(by: { $0.sortOrder < $1.sortOrder }).compactMap { config in
            if let usage = providers.first(where: { $0.provider == config.kind.rawValue }) {
                // Build tiers from usage data
                var tiers: [UsageTier] = []
                if let quota = usage.quota {
                    tiers.append(UsageTier(
                        name: "Default",
                        usage: usage.today_usage,
                        quota: quota,
                        remaining: usage.remaining,
                        resetTime: nil
                    ))
                }
                return ProviderDetail(
                    provider: usage,
                    config: config,
                    tiers: tiers,
                    operationalStatus: .operational,
                    sourceType: .auto
                )
            }
            return nil
        }
    }

    public init() {
        self.api = APIClient()
        loadProviderConfigs()
        Task {
            if isDemoMode {
                enterDemoMode()
            } else {
                if !storedToken.isEmpty {
                    await api.updateToken(storedToken)
                    await restoreSession()
                }
            }
        }
    }

    // MARK: - Auth

    public func signIn(email: String, name: String) async {
        isLoading = true
        lastError = nil
        do {
            let response = try await api.signIn(email: email, name: name)
            storedToken = response.access_token
            userName = response.user.name
            userEmail = response.user.email
            isPaired = response.paired
            isAuthenticated = true
            if isPaired {
                startRefreshLoop()
                await refreshAll()
            }
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    public func signInWithApple(identityToken: String, fullName: String?, email: String?) async {
        isLoading = true
        lastError = nil
        do {
            let response = try await api.signInWithApple(identityToken: identityToken, fullName: fullName, email: email)
            storedToken = response.access_token
            userName = response.user.name
            userEmail = response.user.email
            isPaired = response.paired
            isAuthenticated = true
            if isPaired {
                startRefreshLoop()
                await refreshAll()
            }
        } catch {
            lastError = error.localizedDescription
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
                          cost_status: "Estimated", requests: 142, error_count: 0),
            SessionRecord(id: "s2", name: "Helper heartbeat monitor", provider: "Gemini",
                          project: "cli-pulse-helper", device_name: "lab-server-01",
                          started_at: hourAgo, last_active_at: now,
                          status: "syncing", total_usage: 12800, estimated_cost: 0.10,
                          cost_status: "Estimated", requests: 87, error_count: 0),
            SessionRecord(id: "s3", name: "Session error triage", provider: "Codex",
                          project: "backend-api", device_name: "build-box",
                          started_at: twoHoursAgo, last_active_at: hourAgo,
                          status: "failed", total_usage: 8400, estimated_cost: 0.10,
                          cost_status: "Estimated", requests: 56, error_count: 3),
            SessionRecord(id: "s4", name: "Provider adapter review", provider: "Claude",
                          project: "provider-layer", device_name: "MacBook Pro",
                          started_at: hourAgo, last_active_at: now,
                          status: "running", total_usage: 6200, estimated_cost: 0.09,
                          cost_status: "Estimated", requests: 38, error_count: 0),
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
            AlertRecord(id: "a1", type: "quota_low", severity: "critical",
                        title: "Codex quota critically low", message: "Only 7.6% remaining (38,000 of 500,000 tokens)",
                        created_at: now, is_read: false, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: "Codex", related_device_name: nil),
            AlertRecord(id: "a2", type: "session_failed", severity: "warning",
                        title: "Session failed: error triage", message: "Session 'Session error triage' encountered 3 errors on build-box",
                        created_at: hourAgo, is_read: false, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: "backend-api",
                        related_session_id: "s3", related_session_name: "Session error triage",
                        related_provider: "Codex", related_device_name: "build-box"),
            AlertRecord(id: "a3", type: "helper_offline", severity: "warning",
                        title: "Device offline: build-box", message: "build-box has not synced for over 60 minutes",
                        created_at: hourAgo, is_read: true, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: nil, related_device_name: "build-box"),
            AlertRecord(id: "a4", type: "usage_spike", severity: "info",
                        title: "Usage spike detected", message: "Codex usage increased 40% compared to yesterday's average",
                        created_at: twoHoursAgo, is_read: true, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: "Codex", related_device_name: nil),
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
            alert_summary: AlertSummaryDTO(critical: 1, warning: 2, info: 1)
        )

        buildProviderDetails()
        updateCostSummary()
        publishWidgetData()
    }

    public func signOut() {
        stopRefreshLoop()
        storedToken = ""
        isDemoMode = false
        isAuthenticated = false
        isPaired = false
        userName = ""
        userEmail = ""
        dashboard = nil
        providers = []
        sessions = []
        devices = []
        alerts = []
        selectedTab = .overview
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
            if isPaired {
                startRefreshLoop()
                await refreshAll()
            }
        } catch {
            storedToken = ""
            isAuthenticated = false
        }
        isLoading = false
    }

    // MARK: - Data Refresh

    public func refreshAll() async {
        guard isAuthenticated, isPaired, !isDemoMode else { return }
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

        do {
            async let d = api.dashboard()
            async let p = api.providers()
            async let s = api.sessions()
            async let dev = api.devices()
            async let a = api.alerts()

            let (dash, provs, sess, devs, alts) = try await (d, p, s, dev, a)
            dashboard = dash
            providers = provs
            sessions = sess
            devices = devs

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
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

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

    public func acknowledgeAlert(_ alert: AlertRecord) async {
        if isDemoMode {
            if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
                let a = alerts[idx]
                alerts[idx] = AlertRecord(id: a.id, type: a.type, severity: a.severity, title: a.title, message: a.message, created_at: a.created_at, is_read: true, is_resolved: a.is_resolved, acknowledged_at: ISO8601DateFormatter().string(from: Date()), snoozed_until: a.snoozed_until, related_project_id: a.related_project_id, related_project_name: a.related_project_name, related_session_id: a.related_session_id, related_session_name: a.related_session_name, related_provider: a.related_provider, related_device_name: a.related_device_name)
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
                let a = alerts[idx]
                alerts[idx] = AlertRecord(id: a.id, type: a.type, severity: a.severity, title: a.title, message: a.message, created_at: a.created_at, is_read: true, is_resolved: true, acknowledged_at: a.acknowledged_at, snoozed_until: a.snoozed_until, related_project_id: a.related_project_id, related_project_name: a.related_project_name, related_session_id: a.related_session_id, related_session_name: a.related_session_name, related_provider: a.related_provider, related_device_name: a.related_device_name)
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
                let a = alerts[idx]
                let until = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(minutes) * 60))
                alerts[idx] = AlertRecord(id: a.id, type: a.type, severity: a.severity, title: a.title, message: a.message, created_at: a.created_at, is_read: true, is_resolved: a.is_resolved, acknowledged_at: a.acknowledged_at, snoozed_until: until, related_project_id: a.related_project_id, related_project_name: a.related_project_name, related_session_id: a.related_session_id, related_session_name: a.related_session_name, related_provider: a.related_provider, related_device_name: a.related_device_name)
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
        let interval = TimeInterval(refreshInterval)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshAll()
            }
        }
    }

    public func stopRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    public func updateRefreshInterval(_ seconds: Int) {
        refreshInterval = seconds
        if isAuthenticated, isPaired {
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
