import Foundation
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
internal final class DataRefreshManager {
    struct Context {
        let isAuthenticated: Bool
        let isDemoMode: Bool
        let isPaired: Bool
        let isLoading: Bool
        let notificationsEnabled: Bool
        let providerConfigs: [ProviderConfig]
        let maxDevices: Int
        let maxProviders: Int
        let currentTierName: String
    }

    struct RefreshPayload {
        let dashboard: DashboardSummary
        let providers: [ProviderUsage]
        let sessions: [SessionRecord]
        let devices: [DeviceRecord]
        let alerts: [AlertRecord]
        let locallySupplementedProviders: Set<String>
        let tierLimitWarning: String?
        let lastRefresh: Date
        let isLocalMode: Bool
    }

    struct Callbacks {
        let isAuthenticated: () -> Bool
        let setLoading: (Bool) -> Void
        let setLastError: (String?) -> Void
        let setServerOnline: (Bool) -> Void
        let applyPayload: (RefreshPayload) -> Void
        let sendNotification: (AlertRecord) -> Void
        let afterRefresh: () -> Void
        let handleTokenExpired: (String) -> Void
    }

    private let api: APIClient
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var previousAlertIDs: Set<String> = []

    #if os(macOS)
    private var helperSyncObserver: NSObjectProtocol?
    #endif

    init(api: APIClient) {
        self.api = api
    }

    func refreshAll(context: Context, callbacks: Callbacks) async {
        guard context.isAuthenticated, !context.isDemoMode else { return }

        #if os(macOS)
        if !context.isPaired {
            await refreshLocal(context: context, callbacks: callbacks)
            return
        }
        #else
        guard context.isPaired else { return }
        #endif

        guard !context.isLoading else { return }
        callbacks.setLoading(true)
        callbacks.setLastError(nil)

        do {
            callbacks.setServerOnline(try await api.health())
        } catch {
            callbacks.setServerOnline(false)
            callbacks.setLastError("Server offline")
            callbacks.setLoading(false)
            return
        }

        guard !Task.isCancelled else {
            callbacks.setLoading(false)
            return
        }

        do {
            async let dashboard = api.dashboard()
            async let providers = api.providers()
            async let sessions = api.sessions()
            async let devices = api.devices()
            async let alerts = api.alerts()

            let (dashboardData, providerData, sessionData, deviceData, alertData) = try await (
                dashboard, providers, sessions, devices, alerts
            )

            #if os(macOS)
            let localResults = await runCollectors(providerConfigs: context.providerConfigs)
            let (resolvedProviders, supplementedProviders) = Self.mergeCloudWithLocal(
                cloud: providerData,
                local: localResults
            )

            #if DEBUG
            Self.dumpMergeDiagnostic(cloud: providerData, local: localResults, merged: resolvedProviders)
            #endif
            #else
            let resolvedProviders = providerData
            let supplementedProviders: Set<String> = []
            #endif

            guard callbacks.isAuthenticated() else {
                callbacks.setLoading(false)
                return
            }

            let warning = Self.tierLimitWarning(
                deviceCount: deviceData.count,
                enabledProviderCount: context.providerConfigs.filter(\.isEnabled).count,
                maxDevices: context.maxDevices,
                maxProviders: context.maxProviders,
                currentTierName: context.currentTierName
            )

            let newAlerts = alertData.filter { alert in
                !alert.is_resolved && !previousAlertIDs.contains(alert.id)
            }
            if context.notificationsEnabled {
                for alert in newAlerts {
                    callbacks.sendNotification(alert)
                }
            }
            previousAlertIDs = Set(alertData.map(\.id))

            callbacks.applyPayload(
                RefreshPayload(
                    dashboard: dashboardData,
                    providers: resolvedProviders,
                    sessions: sessionData,
                    devices: deviceData,
                    alerts: alertData,
                    locallySupplementedProviders: supplementedProviders,
                    tierLimitWarning: warning,
                    lastRefresh: Date(),
                    isLocalMode: false
                )
            )
            callbacks.afterRefresh()
        } catch let error as APIError where error == .tokenExpired {
            callbacks.handleTokenExpired(error.localizedDescription)
        } catch {
            callbacks.setLastError(error.localizedDescription)
        }

        callbacks.setLoading(false)
    }

    func startRefreshLoop(interval: Int, onRefreshRequested: @escaping @MainActor () async -> Void) {
        stopRefreshLoop()

        let effectiveInterval = max(TimeInterval(interval), 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleRefresh(using: onRefreshRequested)
            }
        }

        #if os(macOS)
        observeHelperSync(onRefreshRequested: onRefreshRequested)
        #endif
    }

    func stopRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        #if os(macOS)
        if let helperSyncObserver {
            DistributedNotificationCenter.default().removeObserver(helperSyncObserver)
            self.helperSyncObserver = nil
        }
        #endif
    }

    func cancelInFlightRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func updateRefreshInterval(_ seconds: Int, isAuthenticated: Bool, onRefreshRequested: @escaping @MainActor () async -> Void) {
        guard isAuthenticated else { return }
        startRefreshLoop(interval: seconds, onRefreshRequested: onRefreshRequested)
    }

    #if os(macOS)
    private func refreshLocal(context: Context, callbacks: Callbacks) async {
        guard !context.isLoading else { return }
        callbacks.setLoading(true)
        callbacks.setLastError(nil)
        callbacks.setServerOnline(true)

        let collectorResults = await runCollectors(providerConfigs: context.providerConfigs)
        let scanResult = await Task.detached { LocalScanner.shared.scan() }.value

        guard callbacks.isAuthenticated() else {
            callbacks.setLoading(false)
            return
        }

        var mergedProviders: [String: ProviderUsage] = [:]
        for provider in scanResult.providers {
            mergedProviders[provider.provider] = provider
        }
        for result in collectorResults {
            mergedProviders[result.usage.provider] = result.usage
        }

        let providers = mergedProviders.values.sorted { $0.today_usage > $1.today_usage }
        let devices = [DeviceRecord(
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
        let alerts: [AlertRecord] = []

        let dashboard = DashboardSummary(
            total_usage_today: providers.reduce(0) { $0 + $1.today_usage },
            total_estimated_cost_today: providers.reduce(0) { $0 + $1.estimated_cost_today },
            cost_status: "Estimated",
            total_requests_today: scanResult.sessions.reduce(0) { $0 + $1.requests },
            active_sessions: scanResult.activeSessionCount,
            online_devices: 1,
            unresolved_alerts: 0,
            provider_breakdown: providers.map {
                ProviderBreakdown(provider: $0.provider, usage: $0.today_usage,
                                  estimated_cost: $0.estimated_cost_today,
                                  cost_status: $0.cost_status_today, remaining: $0.remaining)
            },
            top_projects: [],
            trend: [],
            recent_activity: [],
            risk_signals: scanResult.isEmpty && collectorResults.isEmpty
                ? ["No AI tools detected. Start a coding session to see data."] : [],
            alert_summary: AlertSummaryDTO(critical: 0, warning: 0, info: 0)
        )

        previousAlertIDs = []
        callbacks.applyPayload(
            RefreshPayload(
                dashboard: dashboard,
                providers: providers,
                sessions: scanResult.sessions,
                devices: devices,
                alerts: alerts,
                locallySupplementedProviders: [],
                tierLimitWarning: nil,
                lastRefresh: Date(),
                isLocalMode: true
            )
        )
        callbacks.afterRefresh()
        callbacks.setLoading(false)
    }

    func runCollectors(providerConfigs: [ProviderConfig]) async -> [CollectorResult] {
        let enabledConfigs = providerConfigs.filter(\.isEnabled)
        var results: [CollectorResult] = []

        await withTaskGroup(of: CollectorResult?.self) { group in
            for config in enabledConfigs {
                guard let collector = CollectorRegistry.collector(for: config.kind, config: config) else { continue }
                group.addTask {
                    do {
                        return try await collector.collect(config: config)
                    } catch {
                        let message = "[Collector] \(config.kind.rawValue) failed: \(error.localizedDescription)"
                        if !Self.shouldSilenceCollectorError(kind: config.kind, error: error) {
                            print(message)
                        }

                        let logPath = NSTemporaryDirectory() + "clipulse_collector_errors.log"
                        let entry = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
                        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(entry.data(using: .utf8) ?? Data())
                            fileHandle.closeFile()
                        } else {
                            try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
                        }
                        return nil
                    }
                }
            }

            for await result in group {
                if let result {
                    results.append(result)
                }
            }
        }

        return results
    }

    nonisolated static func mergeCloudWithLocal(cloud: [ProviderUsage], local: [CollectorResult]) -> ([ProviderUsage], Set<String>) {
        var merged: [String: ProviderUsage] = [:]
        for provider in cloud {
            merged[provider.provider] = provider
        }

        var supplemented: Set<String> = []

        for result in local {
            guard result.dataKind == .quota || result.dataKind == .credits else { continue }

            let name = result.usage.provider
            if let existing = merged[name] {
                let cloudHasQuota = existing.quota != nil && (existing.quota ?? 0) > 0
                let cloudHasTiers = !existing.tiers.isEmpty
                let cloudIsEmpty = !cloudHasQuota && !cloudHasTiers
                let localWins = !result.usage.tiers.isEmpty
                    && result.usage.tiers.count >= existing.tiers.count

                if cloudIsEmpty || localWins {
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
            } else {
                merged[name] = result.usage
                supplemented.insert(name)
            }
        }

        return (merged.values.sorted { $0.today_usage > $1.today_usage }, supplemented)
    }

    nonisolated static func dumpMergeDiagnostic(cloud: [ProviderUsage], local: [CollectorResult], merged: [ProviderUsage]) {
        func snapshot(_ provider: ProviderUsage) -> [String: Any] {
            [
                "provider": provider.provider,
                "quota": provider.quota as Any,
                "remaining": provider.remaining as Any,
                "tiers_count": provider.tiers.count,
                "tiers": provider.tiers.map {
                    [
                        "name": $0.name,
                        "quota": $0.quota,
                        "remaining": $0.remaining,
                        "reset_time": $0.reset_time as Any,
                    ]
                },
                "plan_type": provider.plan_type as Any,
                "reset_time": provider.reset_time as Any,
                "today_usage": provider.today_usage,
            ]
        }

        let diagnostic: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "cloud": cloud.map(snapshot),
            "local_collectors": local.map {
                [
                    "provider": $0.usage.provider,
                    "data_kind": String(describing: $0.dataKind),
                    "usage": snapshot($0.usage),
                ]
            },
            "merged": merged.map(snapshot),
        ]

        if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            try? string.write(
                toFile: NSTemporaryDirectory() + "clipulse_merge_diagnostic.json",
                atomically: true,
                encoding: .utf8
            )
        }
    }

    nonisolated private static func shouldSilenceCollectorError(kind: ProviderKind, error: Error) -> Bool {
        guard kind == .ollama else { return false }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           [NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
            return true
        }

        return nsError.localizedDescription == "Could not connect to the server."
    }

    private func observeHelperSync(onRefreshRequested: @escaping @MainActor () async -> Void) {
        helperSyncObserver = DistributedNotificationCenter.default().addObserver(
            forName: HelperIPC.didSyncNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleRefresh(using: onRefreshRequested)
            }
        }
    }
    #endif

    private func scheduleRefresh(using onRefreshRequested: @escaping @MainActor () async -> Void) {
        refreshTask = Task { @MainActor in
            await onRefreshRequested()
        }
    }

    private static func tierLimitWarning(
        deviceCount: Int,
        enabledProviderCount: Int,
        maxDevices: Int,
        maxProviders: Int,
        currentTierName: String
    ) -> String? {
        var warnings: [String] = []
        if maxDevices >= 0, deviceCount > maxDevices {
            warnings.append("Devices: \(deviceCount)/\(maxDevices)")
        }
        if maxProviders >= 0, enabledProviderCount > maxProviders {
            warnings.append("Providers: \(enabledProviderCount)/\(maxProviders)")
        }
        guard !warnings.isEmpty else { return nil }
        return "Over \(currentTierName) plan limits — \(warnings.joined(separator: ", ")). Upgrade or reduce usage."
    }
}

extension AppState {
    public func refreshAll() async {
        await dataRefreshManager.refreshAll(context: refreshContext(), callbacks: refreshCallbacks())
    }

    public func acknowledgeAlert(_ alert: AlertRecord) async {
        if isDemoMode {
            if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
                alerts[idx] = demoUpdateAlert(
                    alerts[idx],
                    isRead: true,
                    acknowledgedAt: ISO8601DateFormatter().string(from: Date())
                )
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

    public func startRefreshLoop() {
        dataRefreshManager.startRefreshLoop(interval: refreshInterval, onRefreshRequested: refreshRequest())
    }

    public func stopRefreshLoop() {
        dataRefreshManager.stopRefreshLoop()
    }

    public func updateRefreshInterval(_ seconds: Int) {
        refreshInterval = seconds
        dataRefreshManager.updateRefreshInterval(
            seconds,
            isAuthenticated: isAuthenticated,
            onRefreshRequested: refreshRequest()
        )
    }

    public func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func updateCostSummary() {
        let todayByProvider = providers.map { ($0.provider, $0.estimated_cost_today) }
        let todayTotal = todayByProvider.reduce(0) { $0 + $1.1 }
        let thirtyDayByProvider = providers.map { ($0.provider, $0.estimated_cost_week * 4.3) }
        let thirtyDayTotal = thirtyDayByProvider.reduce(0) { $0 + $1.1 }
        costSummary = CostSummary(
            todayTotal: todayTotal,
            todayByProvider: todayByProvider,
            thirtyDayTotal: thirtyDayTotal,
            thirtyDayByProvider: thirtyDayByProvider
        )
    }

    func publishWidgetData() {
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

        let widgetProviders = providers.prefix(10).map { provider in
            WidgetProviderData(
                name: provider.provider,
                usage: provider.today_usage,
                quota: provider.quota,
                costToday: provider.estimated_cost_today,
                iconName: provider.providerKind?.iconName ?? "cpu"
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

    func sendNotification(for alert: AlertRecord) {
        let content = UNMutableNotificationContent()
        content.title = "CLI Pulse: \(alert.severity)"
        content.body = alert.title
        content.sound = alert.alertSeverity == .critical ? .defaultCritical : .default

        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func applyRefreshPayload(_ payload: DataRefreshManager.RefreshPayload) {
        dashboard = payload.dashboard
        providers = payload.providers
        sessions = payload.sessions
        devices = payload.devices
        alerts = payload.alerts
        locallySupplementedProviders = payload.locallySupplementedProviders
        tierLimitWarning = payload.tierLimitWarning
        lastRefresh = payload.lastRefresh
        isLocalMode = payload.isLocalMode
    }

    func completeRefresh() {
        buildProviderDetails()
        updateCostSummary()
        publishWidgetData()
    }

    func refreshContext() -> DataRefreshManager.Context {
        DataRefreshManager.Context(
            isAuthenticated: isAuthenticated,
            isDemoMode: isDemoMode,
            isPaired: isPaired,
            isLoading: isLoading,
            notificationsEnabled: notificationsEnabled,
            providerConfigs: providerConfigs,
            maxDevices: subscriptionManager.maxDevices,
            maxProviders: subscriptionManager.maxProviders,
            currentTierName: subscriptionManager.currentTier.rawValue
        )
    }

    func refreshCallbacks() -> DataRefreshManager.Callbacks {
        DataRefreshManager.Callbacks(
            isAuthenticated: { [weak self] in self?.isAuthenticated ?? false },
            setLoading: { [weak self] in self?.isLoading = $0 },
            setLastError: { [weak self] in self?.lastError = $0 },
            setServerOnline: { [weak self] in self?.serverOnline = $0 },
            applyPayload: { [weak self] in self?.applyRefreshPayload($0) },
            sendNotification: { [weak self] in self?.sendNotification(for: $0) },
            afterRefresh: { [weak self] in self?.completeRefresh() },
            handleTokenExpired: { [weak self] message in
                self?.signOut()
                self?.lastError = message
            }
        )
    }

    func refreshRequest() -> @MainActor () async -> Void {
        { [weak self] in
            guard let self else { return }
            await self.refreshAll()
        }
    }

    func demoUpdateAlert(
        _ alert: AlertRecord,
        isRead: Bool? = nil,
        isResolved: Bool? = nil,
        acknowledgedAt: String? = nil,
        snoozedUntil: String? = nil
    ) -> AlertRecord {
        AlertRecord(
            id: alert.id,
            type: alert.type,
            severity: alert.severity,
            title: alert.title,
            message: alert.message,
            created_at: alert.created_at,
            is_read: isRead ?? alert.is_read,
            is_resolved: isResolved ?? alert.is_resolved,
            acknowledged_at: acknowledgedAt ?? alert.acknowledged_at,
            snoozed_until: snoozedUntil ?? alert.snoozed_until,
            related_project_id: alert.related_project_id,
            related_project_name: alert.related_project_name,
            related_session_id: alert.related_session_id,
            related_session_name: alert.related_session_name,
            related_provider: alert.related_provider,
            related_device_name: alert.related_device_name,
            source_kind: alert.source_kind,
            source_id: alert.source_id,
            grouping_key: alert.grouping_key,
            suppression_key: alert.suppression_key
        )
    }
}
