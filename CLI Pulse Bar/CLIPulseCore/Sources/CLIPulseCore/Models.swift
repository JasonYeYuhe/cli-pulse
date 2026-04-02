import Foundation

// MARK: - Enums

public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex = "Codex"
    case gemini = "Gemini"
    case claude = "Claude"
    case cursor = "Cursor"
    case openCode = "OpenCode"
    case droid = "Droid"
    case antigravity = "Antigravity"
    case copilot = "Copilot"
    case zai = "z.ai"
    case minimax = "MiniMax"
    case augment = "Augment"
    case jetbrainsAI = "JetBrains AI"
    case kimiK2 = "Kimi K2"
    case amp = "Amp"
    case synthetic = "Synthetic"
    case warp = "Warp"
    case kilo = "Kilo"
    case ollama = "Ollama"
    case openRouter = "OpenRouter"
    case alibaba = "Alibaba"
    case kimi = "Kimi"
    case kiro = "Kiro"
    case vertexAI = "Vertex AI"
    case perplexity = "Perplexity"
    case volcanoEngine = "Volcano Engine"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .codex: return "terminal"
        case .gemini: return "sparkles"
        case .claude: return "brain.head.profile"
        case .cursor: return "cursorarrow.rays"
        case .openCode: return "chevron.left.forwardslash.chevron.right"
        case .droid: return "cpu"
        case .antigravity: return "arrow.up.circle"
        case .copilot: return "airplane"
        case .zai: return "z.circle"
        case .minimax: return "chart.bar"
        case .augment: return "plus.magnifyingglass"
        case .jetbrainsAI: return "hammer"
        case .kimiK2: return "k.circle"
        case .amp: return "bolt"
        case .synthetic: return "wand.and.stars"
        case .warp: return "arrow.right.circle"
        case .kilo: return "scalemass"
        case .ollama: return "desktopcomputer"
        case .openRouter: return "arrow.triangle.branch"
        case .alibaba: return "cloud"
        case .kimi: return "k.circle.fill"
        case .kiro: return "arrow.triangle.turn.up.right.diamond"
        case .vertexAI: return "v.circle"
        case .perplexity: return "magnifyingglass.circle"
        case .volcanoEngine: return "flame"
        }
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case running = "Running"
    case idle = "Idle"
    case failed = "Failed"
    case syncing = "Syncing"
}

public enum DeviceStatus: String, Codable, Sendable {
    case online = "Online"
    case degraded = "Degraded"
    case offline = "Offline"
}

public enum AlertType: String, Codable, Sendable {
    case quotaLow = "Quota Low"
    case usageSpike = "Usage Spike"
    case helperOffline = "Helper Offline"
    case syncFailed = "Sync Failed"
    case authExpired = "Auth Expired"
    case sessionFailed = "Session Failed"
    case sessionTooLong = "Session Too Long"
    case projectBudgetExceeded = "Project Budget Exceeded"
    case costSpike = "Cost Spike"
    case errorRateSpike = "Error Rate Spike"
    case quotaCritical = "Quota Critical"
}

public enum CollectionConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

public enum ProviderCategory: String, Codable, Sendable {
    case cloud
    case local
    case aggregator
    case ide
}

public enum AlertSeverity: String, Codable, Sendable {
    case critical = "Critical"
    case warning = "Warning"
    case info = "Info"
}

public enum CostStatus: String, Codable, Sendable {
    case exact = "Exact"
    case estimated = "Estimated"
    case unavailable = "Unavailable"
}

public enum ProviderStatus: String, Codable, Sendable {
    case operational = "Operational"
    case degraded = "Degraded"
    case down = "Down"
}

public enum SourceType: String, Codable, CaseIterable, Sendable {
    case auto
    case web
    case cli
    case oauth
    case api
    case local
    case merged  // cloud + local collector supplemented
}

// MARK: - Auth

public struct AuthRequest: Codable, Sendable {
    public let email: String
    public let name: String

    public init(email: String, name: String) {
        self.email = email
        self.name = name
    }
}

public struct AuthResponse: Codable, Sendable {
    public let access_token: String
    public let refresh_token: String?
    public let user: UserDTO
    public let paired: Bool

    public init(access_token: String, refresh_token: String? = nil, user: UserDTO, paired: Bool) {
        self.access_token = access_token
        self.refresh_token = refresh_token
        self.user = user
        self.paired = paired
    }
}

public struct UserDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let email: String

    public init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}

// MARK: - Dashboard

public struct DashboardSummary: Codable, Sendable {
    public let total_usage_today: Int
    public let total_estimated_cost_today: Double
    public let cost_status: String
    public let total_requests_today: Int
    public let active_sessions: Int
    public let online_devices: Int
    public let unresolved_alerts: Int
    public let provider_breakdown: [ProviderBreakdown]
    public let top_projects: [TopProject]
    public let trend: [UsagePoint]
    public let recent_activity: [ActivityItem]
    public let risk_signals: [String]
    public let alert_summary: AlertSummaryDTO

    public init(
        total_usage_today: Int, total_estimated_cost_today: Double,
        cost_status: String, total_requests_today: Int,
        active_sessions: Int, online_devices: Int, unresolved_alerts: Int,
        provider_breakdown: [ProviderBreakdown], top_projects: [TopProject],
        trend: [UsagePoint], recent_activity: [ActivityItem],
        risk_signals: [String], alert_summary: AlertSummaryDTO
    ) {
        self.total_usage_today = total_usage_today
        self.total_estimated_cost_today = total_estimated_cost_today
        self.cost_status = cost_status
        self.total_requests_today = total_requests_today
        self.active_sessions = active_sessions
        self.online_devices = online_devices
        self.unresolved_alerts = unresolved_alerts
        self.provider_breakdown = provider_breakdown
        self.top_projects = top_projects
        self.trend = trend
        self.recent_activity = recent_activity
        self.risk_signals = risk_signals
        self.alert_summary = alert_summary
    }
}

public struct ProviderBreakdown: Codable, Identifiable, Sendable {
    public let provider: String
    public let usage: Int
    public let estimated_cost: Double
    public let cost_status: String
    public let remaining: Int?

    public var id: String { provider }

    public var providerKind: ProviderKind? {
        ProviderKind(rawValue: provider)
    }

    public init(provider: String, usage: Int, estimated_cost: Double, cost_status: String, remaining: Int?) {
        self.provider = provider
        self.usage = usage
        self.estimated_cost = estimated_cost
        self.cost_status = cost_status
        self.remaining = remaining
    }
}

public struct TopProject: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let usage: Int
    public let estimated_cost: Double
    public let cost_status: String

    public init(id: String, name: String, usage: Int, estimated_cost: Double, cost_status: String) {
        self.id = id
        self.name = name
        self.usage = usage
        self.estimated_cost = estimated_cost
        self.cost_status = cost_status
    }
}

public struct UsagePoint: Codable, Identifiable, Sendable {
    public let timestamp: String
    public let value: Int

    public var id: String { timestamp }

    public init(timestamp: String, value: Int) {
        self.timestamp = timestamp
        self.value = value
    }
}

public struct ActivityItem: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let timestamp: String

    public init(id: String, title: String, subtitle: String, timestamp: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
    }
}

public struct AlertSummaryDTO: Codable, Sendable {
    public let critical: Int
    public let warning: Int
    public let info: Int

    public init(critical: Int, warning: Int, info: Int) {
        self.critical = critical
        self.warning = warning
        self.info = info
    }
}

// MARK: - Provider

public struct ProviderMetadata: Codable, Sendable {
    public let display_name: String
    public let category: String
    public let supports_exact_cost: Bool
    public let supports_quota: Bool
    public let default_quota: Int?

    public var providerCategory: ProviderCategory? {
        ProviderCategory(rawValue: category)
    }

    public init(display_name: String, category: String, supports_exact_cost: Bool = false, supports_quota: Bool = true, default_quota: Int? = nil) {
        self.display_name = display_name
        self.category = category
        self.supports_exact_cost = supports_exact_cost
        self.supports_quota = supports_quota
        self.default_quota = default_quota
    }
}

public struct ProviderUsage: Codable, Identifiable, Sendable {
    public let provider: String
    public let today_usage: Int
    public let week_usage: Int
    public let estimated_cost_today: Double
    public let estimated_cost_week: Double
    public let cost_status_today: String
    public let cost_status_week: String
    public let quota: Int?
    public let remaining: Int?
    public let plan_type: String?
    public let reset_time: String?
    public let tiers: [TierDTO]
    public let status_text: String
    public let trend: [UsagePoint]
    public let recent_sessions: [String]
    public let recent_errors: [String]
    public let metadata: ProviderMetadata?

    public var id: String { provider }

    public var providerKind: ProviderKind? {
        ProviderKind(rawValue: provider)
    }

    public var usagePercent: Double {
        guard let quota = quota, quota > 0 else { return 0 }
        let used = quota - (remaining ?? 0)
        return min(1.0, Double(used) / Double(quota))
    }

    public init(
        provider: String, today_usage: Int, week_usage: Int,
        estimated_cost_today: Double, estimated_cost_week: Double,
        cost_status_today: String, cost_status_week: String,
        quota: Int?, remaining: Int?,
        plan_type: String? = nil, reset_time: String? = nil,
        tiers: [TierDTO] = [],
        status_text: String,
        trend: [UsagePoint], recent_sessions: [String], recent_errors: [String],
        metadata: ProviderMetadata? = nil
    ) {
        self.provider = provider
        self.today_usage = today_usage
        self.week_usage = week_usage
        self.estimated_cost_today = estimated_cost_today
        self.estimated_cost_week = estimated_cost_week
        self.cost_status_today = cost_status_today
        self.cost_status_week = cost_status_week
        self.quota = quota
        self.remaining = remaining
        self.plan_type = plan_type
        self.reset_time = reset_time
        self.tiers = tiers
        self.status_text = status_text
        self.trend = trend
        self.recent_sessions = recent_sessions
        self.recent_errors = recent_errors
        self.metadata = metadata
    }
}

public struct TierDTO: Codable, Sendable {
    public let name: String
    public let quota: Int
    public let remaining: Int
    public let reset_time: String?

    public init(name: String, quota: Int, remaining: Int, reset_time: String? = nil) {
        self.name = name
        self.quota = quota
        self.remaining = remaining
        self.reset_time = reset_time
    }
}

// MARK: - Session

public struct SessionRecord: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let provider: String
    public let project: String
    public let device_name: String
    public let started_at: String
    public let last_active_at: String
    public let status: String
    public let total_usage: Int
    public let estimated_cost: Double
    public let cost_status: String
    public let requests: Int
    public let error_count: Int
    public let collection_confidence: String?

    public var providerKind: ProviderKind? {
        ProviderKind(rawValue: provider)
    }

    public var sessionStatus: SessionStatus? {
        SessionStatus(rawValue: status)
    }

    public var confidence: CollectionConfidence? {
        guard let collection_confidence else { return nil }
        return CollectionConfidence(rawValue: collection_confidence)
    }

    public var startedDate: Date? {
        ISO8601DateFormatter().date(from: started_at)
    }

    public var lastActiveDate: Date? {
        ISO8601DateFormatter().date(from: last_active_at)
    }

    public init(
        id: String, name: String, provider: String, project: String,
        device_name: String, started_at: String, last_active_at: String,
        status: String, total_usage: Int, estimated_cost: Double,
        cost_status: String, requests: Int, error_count: Int,
        collection_confidence: String? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.project = project
        self.device_name = device_name
        self.started_at = started_at
        self.last_active_at = last_active_at
        self.status = status
        self.total_usage = total_usage
        self.estimated_cost = estimated_cost
        self.cost_status = cost_status
        self.requests = requests
        self.error_count = error_count
        self.collection_confidence = collection_confidence
    }
}

// MARK: - Device

public struct DeviceRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let system: String
    public let status: String
    public let last_sync_at: String?
    public let helper_version: String
    public let current_session_count: Int
    public let cpu_usage: Int?
    public let memory_usage: Int?

    public var deviceStatus: DeviceStatus? {
        DeviceStatus(rawValue: status)
    }

    public init(
        id: String, name: String, type: String, system: String,
        status: String, last_sync_at: String?, helper_version: String,
        current_session_count: Int, cpu_usage: Int?, memory_usage: Int?
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.system = system
        self.status = status
        self.last_sync_at = last_sync_at
        self.helper_version = helper_version
        self.current_session_count = current_session_count
        self.cpu_usage = cpu_usage
        self.memory_usage = memory_usage
    }
}

// MARK: - Alert

public struct AlertRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let severity: String
    public let title: String
    public let message: String
    public let created_at: String
    public let is_read: Bool
    public let is_resolved: Bool
    public let acknowledged_at: String?
    public let snoozed_until: String?
    public let related_project_id: String?
    public let related_project_name: String?
    public let related_session_id: String?
    public let related_session_name: String?
    public let related_provider: String?
    public let related_device_name: String?
    public let source_kind: String?
    public let source_id: String?
    public let grouping_key: String?
    public let suppression_key: String?

    public var alertSeverity: AlertSeverity? {
        AlertSeverity(rawValue: severity)
    }

    public var alertType: AlertType? {
        AlertType(rawValue: type)
    }

    public var createdDate: Date? {
        ISO8601DateFormatter().date(from: created_at)
    }

    public init(
        id: String, type: String, severity: String, title: String,
        message: String, created_at: String, is_read: Bool, is_resolved: Bool,
        acknowledged_at: String?, snoozed_until: String?,
        related_project_id: String?, related_project_name: String?,
        related_session_id: String?, related_session_name: String?,
        related_provider: String?, related_device_name: String?,
        source_kind: String? = nil, source_id: String? = nil,
        grouping_key: String? = nil, suppression_key: String? = nil
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.title = title
        self.message = message
        self.created_at = created_at
        self.is_read = is_read
        self.is_resolved = is_resolved
        self.acknowledged_at = acknowledged_at
        self.snoozed_until = snoozed_until
        self.related_project_id = related_project_id
        self.related_project_name = related_project_name
        self.related_session_id = related_session_id
        self.related_session_name = related_session_name
        self.related_provider = related_provider
        self.related_device_name = related_device_name
        self.source_kind = source_kind
        self.source_id = source_id
        self.grouping_key = grouping_key
        self.suppression_key = suppression_key
    }
}

// MARK: - Pairing

public struct PairingInfo: Codable, Sendable {
    public let code: String
    public let install_command: String

    public init(code: String, install_command: String) {
        self.code = code
        self.install_command = install_command
    }
}

// MARK: - Helper

public struct SuccessResponse: Codable, Sendable {
    public let ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

// MARK: - Settings

public struct SettingsSnapshot: Codable, Sendable {
    public let notifications_enabled: Bool
    public let push_policy: String
    public let digest_enabled: Bool
    public let digest_interval_hours: Int
    public let usage_spike_threshold: Int
    public let project_budget_threshold_usd: Double
    public let session_too_long_threshold_minutes: Int
    public let offline_grace_period_minutes: Int
    public let repeated_failure_threshold: Int
    public let alert_cooldown_minutes: Int
    public let data_retention_days: Int

    public init(
        notifications_enabled: Bool, push_policy: String,
        digest_enabled: Bool, digest_interval_hours: Int,
        usage_spike_threshold: Int, project_budget_threshold_usd: Double,
        session_too_long_threshold_minutes: Int, offline_grace_period_minutes: Int,
        repeated_failure_threshold: Int, alert_cooldown_minutes: Int,
        data_retention_days: Int
    ) {
        self.notifications_enabled = notifications_enabled
        self.push_policy = push_policy
        self.digest_enabled = digest_enabled
        self.digest_interval_hours = digest_interval_hours
        self.usage_spike_threshold = usage_spike_threshold
        self.project_budget_threshold_usd = project_budget_threshold_usd
        self.session_too_long_threshold_minutes = session_too_long_threshold_minutes
        self.offline_grace_period_minutes = offline_grace_period_minutes
        self.repeated_failure_threshold = repeated_failure_threshold
        self.alert_cooldown_minutes = alert_cooldown_minutes
        self.data_retention_days = data_retention_days
    }
}
