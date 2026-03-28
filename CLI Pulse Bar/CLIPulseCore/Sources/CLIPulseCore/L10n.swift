import Foundation

/// Type-safe localization helper for CLIPulseCore.
///
/// Usage:
///     Text(L10n.tab.overview)
///     Text(L10n.dashboard.updated(timeAgo))
///
public enum L10n {
    private static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        return Bundle(for: BundleToken.self)
        #endif
    }()

    private static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    // MARK: - Tabs

    public enum tab {
        public static var overview: String { tr("tab.overview") }
        public static var providers: String { tr("tab.providers") }
        public static var sessions: String { tr("tab.sessions") }
        public static var alerts: String { tr("tab.alerts") }
        public static var settings: String { tr("tab.settings") }
    }

    // MARK: - Dashboard

    public enum dashboard {
        public static var title: String { tr("dashboard.title") }
        public static func updated(_ time: String) -> String { tr("dashboard.updated", time) }
        public static var serverOnline: String { tr("dashboard.server_online") }
        public static var serverOffline: String { tr("dashboard.server_offline") }
        public static var noData: String { tr("dashboard.no_data") }
        public static var connectHelper: String { tr("dashboard.connect_helper") }
        public static var usageToday: String { tr("dashboard.usage_today") }
        public static var costToday: String { tr("dashboard.cost_today") }
        public static var estCost: String { tr("dashboard.est_cost") }
        public static var requests: String { tr("dashboard.requests") }
        public static var activeSessions: String { tr("dashboard.active_sessions") }
        public static var onlineDevices: String { tr("dashboard.online_devices") }
        public static var unresolvedAlerts: String { tr("dashboard.unresolved_alerts") }
        public static var costSummary: String { tr("dashboard.cost_summary") }
        public static var today: String { tr("dashboard.today") }
        public static var thirtyDayEst: String { tr("dashboard.30day_est") }
        public static var providerUsage: String { tr("dashboard.provider_usage") }
        public static var topProjects: String { tr("dashboard.top_projects") }
        public static var noProjects: String { tr("dashboard.no_projects") }
        public static var riskSignals: String { tr("dashboard.risk_signals") }
        public static var activity: String { tr("dashboard.activity") }
        public static var quickStats: String { tr("dashboard.quick_stats") }
        public static var monitor: String { tr("dashboard.monitor") }
        public static var manage: String { tr("dashboard.manage") }
        public static var noUnresolvedAlerts: String { tr("dashboard.no_unresolved_alerts") }
    }

    // MARK: - Providers

    public enum providers {
        public static var title: String { tr("providers.title") }
        public static var showAll: String { tr("providers.show_all") }
        public static var hideDisabled: String { tr("providers.hide_disabled") }
        public static var tracked: String { tr("providers.tracked") }
        public static var noProviders: String { tr("providers.no_providers") }
        public static var noData: String { tr("providers.no_data") }
        public static var emptyHint: String { tr("providers.empty_hint") }
        public static var allHidden: String { tr("providers.all_hidden") }
        public static var showAllHint: String { tr("providers.show_all_hint") }
        public static var thisWeek: String { tr("providers.this_week") }
        public static var quota: String { tr("providers.quota") }
        public static var status: String { tr("providers.status") }
    }

    // MARK: - Sessions

    public enum sessions {
        public static var title: String { tr("sessions.title") }
        public static var select: String { tr("sessions.select") }
        public static var selectHint: String { tr("sessions.select_hint") }
        public static var noSessions: String { tr("sessions.no_sessions") }
        public static var emptyHint: String { tr("sessions.empty_hint") }
        public static var running: String { tr("sessions.running") }
        public static var details: String { tr("sessions.details") }
        public static func countRunning(_ count: Int) -> String { tr("sessions.count_running", count) }
    }

    // MARK: - Alerts

    public enum alerts {
        public static var title: String { tr("alerts.title") }
        public static var allClear: String { tr("alerts.all_clear") }
        public static var noAlerts: String { tr("alerts.no_alerts") }
        public static var noUnresolved: String { tr("alerts.no_unresolved") }
        public static var noMatching: String { tr("alerts.no_matching") }
        public static var open: String { tr("alerts.open") }
        public static var resolved: String { tr("alerts.resolved") }
        public static var all: String { tr("alerts.all") }
        public static var filter: String { tr("alerts.filter") }
        public static var ack: String { tr("alerts.ack") }
        public static var acknowledge: String { tr("alerts.acknowledge") }
        public static var resolve: String { tr("alerts.resolve") }
        public static var snooze: String { tr("alerts.snooze") }
        public static func snoozeMinutes(_ minutes: Int) -> String { tr("alerts.snooze_minutes", minutes) }
        public static var created: String { tr("alerts.created") }
        public static var related: String { tr("alerts.related") }
        public static var actions: String { tr("alerts.actions") }
        public static var severityCritical: String { tr("alerts.severity_critical") }
        public static var severityWarning: String { tr("alerts.severity_warning") }
        public static func unresolvedCount(_ count: Int) -> String { tr("alerts.unresolved_count", count) }
    }

    // MARK: - Settings

    public enum settings {
        public static var title: String { tr("settings.title") }
        public static var account: String { tr("settings.account") }
        public static var general: String { tr("settings.general") }
        public static var server: String { tr("settings.server") }
        public static var serverName: String { tr("settings.server_name") }
        public static var status: String { tr("settings.status") }
        public static var connected: String { tr("settings.connected") }
        public static var disconnected: String { tr("settings.disconnected") }
        public static var paired: String { tr("settings.paired") }
        public static var notPaired: String { tr("settings.not_paired") }
        public static var connection: String { tr("settings.connection") }
        public static var refreshCadence: String { tr("settings.refresh_cadence") }
        public static var refreshInterval: String { tr("settings.refresh_interval") }
        public static var subscription: String { tr("settings.subscription") }
        public static var currentPlan: String { tr("settings.current_plan") }
        public static var manageSubscription: String { tr("settings.manage_subscription") }
        public static var upgradePro: String { tr("settings.upgrade_pro") }
        public static var providers: String { tr("settings.providers") }
        public static var devices: String { tr("settings.devices") }
        public static var dataRetention: String { tr("settings.data_retention") }
        public static var days: String { tr("settings.days") }
        public static var notifications: String { tr("settings.notifications") }
        public static var desktopNotifications: String { tr("settings.desktop_notifications") }
        public static var desktopNotificationsHint: String { tr("settings.desktop_notifications_hint") }
        public static var sessionQuotaNotifications: String { tr("settings.session_quota_notifications") }
        public static var sessionQuotaHint: String { tr("settings.session_quota_hint") }
        public static var alertNotifications: String { tr("settings.alert_notifications") }
        public static var sessionQuotaAlerts: String { tr("settings.session_quota_alerts") }
        public static var checkProviderStatus: String { tr("settings.check_provider_status") }
        public static var costTracking: String { tr("settings.cost_tracking") }
        public static var display: String { tr("settings.display") }
        public static var showCostEstimates: String { tr("settings.show_cost_estimates") }
        public static var compactMode: String { tr("settings.compact_mode") }
        public static var menuBarMode: String { tr("settings.menu_bar_mode") }
        public static var reorderProviders: String { tr("settings.reorder_providers") }
        public static var reorderHint: String { tr("settings.reorder_hint") }
        public static var manageProviders: String { tr("settings.manage_providers") }
        public static var advanced: String { tr("settings.advanced") }
        public static var hidePersonalInfo: String { tr("settings.hide_personal_info") }
        public static var forceRefresh: String { tr("settings.force_refresh") }
        public static var about: String { tr("settings.about") }
        public static var version: String { tr("settings.version") }
        public static var build: String { tr("settings.build") }
        public static var privacyPolicy: String { tr("settings.privacy_policy") }
        public static var termsOfUse: String { tr("settings.terms_of_use") }
        public static var github: String { tr("settings.github") }
        public static var signOut: String { tr("settings.sign_out") }
        public static var signIn: String { tr("settings.sign_in") }
        public static var signInEmail: String { tr("settings.sign_in_email") }
        public static var signInHint: String { tr("settings.sign_in_hint") }
        public static var email: String { tr("settings.email") }
        public static var name: String { tr("settings.name") }
    }

    // MARK: - Auth

    public enum auth {
        public static var title: String { tr("auth.title") }
        public static var subtitle: String { tr("auth.subtitle") }
        public static var or: String { tr("auth.or") }
        public static var tryDemo: String { tr("auth.try_demo") }
        public static var welcome: String { tr("auth.welcome") }
        public static var watchHint: String { tr("auth.watch_hint") }
    }

    // MARK: - Subscription

    public enum subscription {
        public static var title: String { tr("subscription.title") }
        public static var proTitle: String { tr("subscription.pro_title") }
        public static var unlock: String { tr("subscription.unlock") }
        public static var monthly: String { tr("subscription.monthly") }
        public static var yearlySave: String { tr("subscription.yearly_save") }
        public static var popular: String { tr("subscription.popular") }
        public static var notAvailable: String { tr("subscription.not_available") }
        public static var restore: String { tr("subscription.restore") }
        public static var pro: String { tr("subscription.pro") }
        public static var team: String { tr("subscription.team") }
        public static var everythingInPro: String { tr("subscription.everything_in_pro") }
        public static var unlimitedDevices: String { tr("subscription.unlimited_devices") }
        public static var dataRetention365: String { tr("subscription.data_retention_365") }
        public static var teamDashboards: String { tr("subscription.team_dashboards") }
        public static var sharedAlerts: String { tr("subscription.shared_alerts") }
        public static var adminControls: String { tr("subscription.admin_controls") }
        public static var unlimitedProviders: String { tr("subscription.unlimited_providers") }
        public static var upTo5Devices: String { tr("subscription.up_to_5_devices") }
        public static var dataRetention90: String { tr("subscription.data_retention_90") }
        public static var priorityAlerts: String { tr("subscription.priority_alerts") }
        public static var costAnalytics: String { tr("subscription.cost_analytics") }
        public static var perYear: String { tr("subscription.per_year") }
        public static var perMonth: String { tr("subscription.per_month") }
        public static var upgradePro: String { tr("subscription.upgrade_pro") }
        public static var switchPro: String { tr("subscription.switch_pro") }
        public static var switchTeam: String { tr("subscription.switch_team") }
    }

    // MARK: - About

    public enum about {
        public static var title: String { tr("about.title") }
        public static var description: String { tr("about.description") }
        public static var copyright: String { tr("about.copyright") }
        public static var reportIssue: String { tr("about.report_issue") }
    }

    // MARK: - Widgets

    public enum widget {
        public static var usageTitle: String { tr("widget.usage_title") }
        public static var usageDescription: String { tr("widget.usage_description") }
        public static var overviewTitle: String { tr("widget.overview_title") }
        public static var overviewDescription: String { tr("widget.overview_description") }
        public static var appName: String { tr("widget.app_name") }
        public static var noData: String { tr("widget.no_data") }
        public static var noProviderData: String { tr("widget.no_provider_data") }
        public static var used: String { tr("widget.used") }
    }

    // MARK: - Time

    public enum time {
        public static var justNow: String { tr("time.just_now") }
        public static var ago: String { tr("time.ago") }
    }

    // MARK: - Common

    public enum common {
        public static var online: String { tr("common.online") }
        public static var offline: String { tr("common.offline") }
        public static var refreshAll: String { tr("common.refresh_all") }
        public static var cancel: String { tr("common.cancel") }
        public static var done: String { tr("common.done") }
        public static var save: String { tr("common.save") }
        public static var delete: String { tr("common.delete") }
        public static var enabled: String { tr("common.enabled") }
    }
}

#if !SWIFT_PACKAGE
private final class BundleToken {}
#endif
