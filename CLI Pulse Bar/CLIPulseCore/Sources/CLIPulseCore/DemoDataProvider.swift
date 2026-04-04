import Foundation

internal struct DemoData {
    let dashboard: DashboardSummary
    let providers: [ProviderUsage]
    let sessions: [SessionRecord]
    let devices: [DeviceRecord]
    let alerts: [AlertRecord]
}

internal enum DemoDataProvider {
    static func generate() -> DemoData {
        let formatter = ISO8601DateFormatter()
        let now = Date()

        func timestamp(_ offset: TimeInterval = 0) -> String {
            formatter.string(from: now.addingTimeInterval(offset))
        }

        func trend(base: Int) -> [UsagePoint] {
            (0..<12).map { index in
                UsagePoint(
                    timestamp: timestamp(Double(-11 + index) * 3600),
                    value: base + Int.random(in: -2000...2000)
                )
            }
        }

        let providers = [
            ProviderUsage(provider: "Codex", today_usage: 85900, week_usage: 462000,
                          estimated_cost_today: 1.03, estimated_cost_week: 5.54,
                          cost_status_today: "Estimated", cost_status_week: "Estimated",
                          quota: 500000, remaining: 38000, status_text: "92% used",
                          trend: trend(base: 85000), recent_sessions: ["Dashboard metrics pass"], recent_errors: []),
            ProviderUsage(provider: "Gemini", today_usage: 43400, week_usage: 214000,
                          estimated_cost_today: 0.35, estimated_cost_week: 1.71,
                          cost_status_today: "Estimated", cost_status_week: "Estimated",
                          quota: 300000, remaining: 86000, status_text: "71% used",
                          trend: trend(base: 43000), recent_sessions: ["Helper heartbeat monitor"], recent_errors: []),
            ProviderUsage(provider: "Claude", today_usage: 24800, week_usage: 132000,
                          estimated_cost_today: 0.37, estimated_cost_week: 1.98,
                          cost_status_today: "Estimated", cost_status_week: "Estimated",
                          quota: 250000, remaining: 118000, status_text: "53% used",
                          trend: trend(base: 24000), recent_sessions: ["Provider adapter review"], recent_errors: []),
        ]

        let sessions = [
            SessionRecord(id: "s1", name: "Dashboard metrics pass", provider: "Codex",
                          project: "cli-pulse-ios", device_name: "MacBook Pro",
                          started_at: timestamp(-7200), last_active_at: timestamp(),
                          status: "running", total_usage: 24500, estimated_cost: 0.29,
                          cost_status: "Estimated", requests: 142, error_count: 0,
                          collection_confidence: "high"),
            SessionRecord(id: "s2", name: "Helper heartbeat monitor", provider: "Gemini",
                          project: "cli-pulse-helper", device_name: "lab-server-01",
                          started_at: timestamp(-3600), last_active_at: timestamp(),
                          status: "syncing", total_usage: 12800, estimated_cost: 0.10,
                          cost_status: "Estimated", requests: 87, error_count: 0,
                          collection_confidence: "medium"),
            SessionRecord(id: "s3", name: "Session error triage", provider: "Codex",
                          project: "backend-api", device_name: "build-box",
                          started_at: timestamp(-7200), last_active_at: timestamp(-3600),
                          status: "failed", total_usage: 8400, estimated_cost: 0.10,
                          cost_status: "Estimated", requests: 56, error_count: 3,
                          collection_confidence: "high"),
            SessionRecord(id: "s4", name: "Provider adapter review", provider: "Claude",
                          project: "provider-layer", device_name: "MacBook Pro",
                          started_at: timestamp(-3600), last_active_at: timestamp(),
                          status: "running", total_usage: 6200, estimated_cost: 0.09,
                          cost_status: "Estimated", requests: 38, error_count: 0,
                          collection_confidence: "low"),
        ]

        let devices = [
            DeviceRecord(id: "d1", name: "MacBook Pro", type: "laptop", system: "macOS 15.4",
                         status: "online", last_sync_at: timestamp(), helper_version: "0.2.0",
                         current_session_count: 2, cpu_usage: 42, memory_usage: 68),
            DeviceRecord(id: "d2", name: "lab-server-01", type: "server", system: "Ubuntu 24.04",
                         status: "online", last_sync_at: timestamp(), helper_version: "0.2.0",
                         current_session_count: 1, cpu_usage: 23, memory_usage: 45),
            DeviceRecord(id: "d3", name: "build-box", type: "server", system: "macOS 14.7",
                         status: "offline", last_sync_at: timestamp(-3600), helper_version: "0.1.9",
                         current_session_count: 0, cpu_usage: nil, memory_usage: nil),
        ]

        let alerts = [
            AlertRecord(id: "a1", type: "Quota Critical", severity: "Critical",
                        title: "Codex quota critically low", message: "Only 7.6% remaining (38,000 of 500,000 tokens)",
                        created_at: timestamp(), is_read: false, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: "Codex", related_device_name: nil,
                        source_kind: "provider", source_id: "Codex",
                        grouping_key: "quota-critical:Codex", suppression_key: "quota-critical:Codex"),
            AlertRecord(id: "a2", type: "Session Failed", severity: "Warning",
                        title: "Session failed: error triage", message: "Session 'Session error triage' encountered 3 errors on build-box",
                        created_at: timestamp(-3600), is_read: false, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: "p3", related_project_name: "backend-api",
                        related_session_id: "s3", related_session_name: "Session error triage",
                        related_provider: "Codex", related_device_name: "build-box",
                        source_kind: "session", source_id: "s3",
                        grouping_key: "session-failed:s3"),
            AlertRecord(id: "a3", type: "Helper Offline", severity: "Warning",
                        title: "Device offline: build-box", message: "build-box has not synced for over 60 minutes",
                        created_at: timestamp(-3600), is_read: true, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: nil, related_device_name: "build-box",
                        source_kind: "device", source_id: "d3",
                        grouping_key: "device-offline:build-box"),
            AlertRecord(id: "a4", type: "Cost Spike", severity: "Warning",
                        title: "Cost spike: Codex", message: "Codex estimated cost today reached $1.03, exceeding threshold $0.80",
                        created_at: timestamp(-7200), is_read: true, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: "Codex", related_device_name: nil,
                        source_kind: "provider", source_id: "Codex",
                        grouping_key: "cost-spike:Codex"),
            AlertRecord(id: "a5", type: "Error Rate Spike", severity: "Info",
                        title: "Error rate spike: Codex", message: "Codex error rate spiked: 3 errors across 4 sessions",
                        created_at: timestamp(-7200), is_read: true, is_resolved: false,
                        acknowledged_at: nil, snoozed_until: nil,
                        related_project_id: nil, related_project_name: nil,
                        related_session_id: nil, related_session_name: nil,
                        related_provider: "Codex", related_device_name: nil,
                        source_kind: "provider", source_id: "Codex",
                        grouping_key: "error-rate:Codex"),
        ]

        let breakdowns = providers.map { provider in
            ProviderBreakdown(provider: provider.provider, usage: provider.today_usage,
                              estimated_cost: provider.estimated_cost_today,
                              cost_status: "Estimated", remaining: provider.remaining)
        }

        let dashboard = DashboardSummary(
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
            trend: (0..<24).map { index in
                UsagePoint(
                    timestamp: timestamp(Double(-23 + index) * 3600),
                    value: 4000 + Int.random(in: 0...3000)
                )
            },
            recent_activity: [
                ActivityItem(id: "act1", title: "Session started", subtitle: "Dashboard metrics pass on MacBook Pro", timestamp: timestamp()),
                ActivityItem(id: "act2", title: "Alert fired", subtitle: "Codex quota critically low", timestamp: timestamp()),
                ActivityItem(id: "act3", title: "Session failed", subtitle: "Session error triage on build-box", timestamp: timestamp(-3600)),
            ],
            risk_signals: ["Codex quota below 10%", "build-box offline"],
            alert_summary: AlertSummaryDTO(critical: 1, warning: 3, info: 1)
        )

        return DemoData(
            dashboard: dashboard,
            providers: providers,
            sessions: sessions,
            devices: devices,
            alerts: alerts
        )
    }
}

extension AppState {
    public func enterDemoMode() {
        isDemoMode = true
        isAuthenticated = true
        isPaired = true
        userName = "Demo User"
        userEmail = "demo@clipulse.app"
        serverOnline = true
        lastRefresh = Date()

        applyDemoData(DemoDataProvider.generate())
        buildProviderDetails()
        updateCostSummary()
        publishWidgetData()
    }

    func applyDemoData(_ demoData: DemoData) {
        dashboard = demoData.dashboard
        providers = demoData.providers
        sessions = demoData.sessions
        devices = demoData.devices
        alerts = demoData.alerts
    }
}
