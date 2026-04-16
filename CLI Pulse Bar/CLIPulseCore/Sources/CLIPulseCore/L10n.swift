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
        public static var appearance: String { tr("settings.appearance") }
        public static var appearanceSystem: String { tr("settings.appearance_system") }
        public static var appearanceLight: String { tr("settings.appearance_light") }
        public static var appearanceDark: String { tr("settings.appearance_dark") }
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
        public static var sendCode: String { tr("auth.send_code") }
        public static var verifyCode: String { tr("auth.verify_code") }
        public static var enterCode: String { tr("auth.enter_code") }
        public static var codeSent: String { tr("auth.code_sent") }
        public static func codeSentTo(_ email: String) -> String { tr("auth.code_sent_to", email) }
        public static var resendCode: String { tr("auth.resend_code") }
        public static var backToEmail: String { tr("auth.back_to_email") }
        public static var codePlaceholder: String { tr("auth.code_placeholder") }
        public static var passwordOptional: String { tr("auth.password_optional") }
        public static var passwordPlaceholder: String { tr("auth.password_placeholder") }
        public static var signInGoogle: String { tr("auth.sign_in_google") }
        public static var signInGithub: String { tr("auth.sign_in_github") }
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
        public static var free: String { tr("subscription.free") }
        public static var pro: String { tr("subscription.pro") }
        public static var team: String { tr("subscription.team") }
        public static var freeDescription: String { tr("subscription.free_description") }
        public static var proDescription: String { tr("subscription.pro_description") }
        public static var teamDescription: String { tr("subscription.team_description") }
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

    // MARK: - Account

    public enum account {
        public static var deleteAccount: String { tr("account.delete_account") }
        public static var deleteConfirmTitle: String { tr("account.delete_confirm_title") }
        public static var deleteConfirmMessage: String { tr("account.delete_confirm_message") }
        public static var unlimited: String { tr("account.unlimited") }
    }

    // MARK: - Session Details

    public enum detail {
        public static var provider: String { tr("detail.provider") }
        public static var project: String { tr("detail.project") }
        public static var device: String { tr("detail.device") }
        public static var started: String { tr("detail.started") }
        public static var usage: String { tr("detail.usage") }
        public static var cost: String { tr("detail.cost") }
        public static var requests: String { tr("detail.requests") }
        public static var errors: String { tr("detail.errors") }
        public static var remaining: String { tr("detail.remaining") }
        public static func remainingValue(_ value: String) -> String { tr("detail.remaining_value", value) }
        public static func usageToday(_ value: String) -> String { tr("detail.usage_today", value) }
    }

    // MARK: - Quota Status

    public enum quota {
        public static var low: String { tr("quota.low") }
        public static var moderate: String { tr("quota.moderate") }
        public static var ok: String { tr("quota.ok") }
    }

    // MARK: - Login Placeholders

    public enum login {
        public static var emailPlaceholder: String { tr("login.email_placeholder") }
        public static var namePlaceholder: String { tr("login.name_placeholder") }
    }

    // MARK: - Display Mode

    public enum display {
        public static var icon: String { tr("display.icon") }
        public static var percent: String { tr("display.percent") }
        public static var pace: String { tr("display.pace") }
        public static var mostUsed: String { tr("display.most_used") }
    }

    // MARK: - Status

    public enum status {
        public static var running: String { tr("status.running") }
        public static var idle: String { tr("status.idle") }
        public static var failed: String { tr("status.failed") }
        public static var syncing: String { tr("status.syncing") }
        public static var online: String { tr("status.online") }
        public static var offline: String { tr("status.offline") }
        public static var degraded: String { tr("status.degraded") }
        public static var operational: String { tr("status.operational") }
        public static var down: String { tr("status.down") }
        public static var disabled: String { tr("status.disabled") }

        /// Map a server status string to its localized display text.
        public static func localized(_ raw: String) -> String {
            switch raw {
            case "Running", "running": return running
            case "Idle", "idle": return idle
            case "Failed", "failed": return failed
            case "Syncing", "syncing": return syncing
            case "Online", "online": return online
            case "Offline", "offline": return offline
            case "Degraded", "degraded": return degraded
            case "Operational", "operational": return operational
            case "Down", "down": return down
            case "Disabled", "disabled": return disabled
            default: return raw
            }
        }
    }

    // MARK: - Badges

    public enum badge {
        public static var free: String { tr("badge.free") }
        public static var pro: String { tr("badge.pro") }
        public static var team: String { tr("badge.team") }
        public static var exact: String { tr("badge.exact") }
        public static var estimated: String { tr("badge.estimated") }
        public static var unavailable: String { tr("badge.unavailable") }
        public static var high: String { tr("badge.high") }
        public static var medium: String { tr("badge.medium") }
        public static var low: String { tr("badge.low") }
        public static var cloud: String { tr("badge.cloud") }
        public static var local: String { tr("badge.local") }
        public static var aggregator: String { tr("badge.aggregator") }
        public static var ide: String { tr("badge.ide") }
    }

    // MARK: - Onboarding / Sync Setup

    public enum onboarding {
        public static var howItWorks: String { tr("onboarding.how_it_works") }
        public static var cloudSyncTitle: String { tr("onboarding.cloud_sync_title") }
        public static var cloudSyncDesc: String { tr("onboarding.cloud_sync_desc") }
        public static var notBluetooth: String { tr("onboarding.not_bluetooth") }
        public static var setupStepsTitle: String { tr("onboarding.setup_steps_title") }
        public static var step1Mac: String { tr("onboarding.step1_mac") }
        public static var step2Helper: String { tr("onboarding.step2_helper") }
        public static var step3Phone: String { tr("onboarding.step3_phone") }
        public static var localModeTitle: String { tr("onboarding.local_mode_title") }
        public static var localModeDesc: String { tr("onboarding.local_mode_desc") }
        public static var cloudModeTitle: String { tr("onboarding.cloud_mode_title") }
        public static var cloudModeDesc: String { tr("onboarding.cloud_mode_desc") }
        public static var iosWaiting: String { tr("onboarding.ios_waiting") }
        public static var iosWaitingDesc: String { tr("onboarding.ios_waiting_desc") }
        public static var checkSync: String { tr("onboarding.check_sync") }
        public static var setUpSync: String { tr("onboarding.set_up_sync") }
        public static var syncedMode: String { tr("onboarding.synced_mode") }
        public static var notSyncedHint: String { tr("onboarding.not_synced_hint") }
    }

    // MARK: - Common

    // MARK: - Team

    public enum team {
        public static var title: String { tr("team.title") }
        public static var requiresProHint: String { tr("team.requires_pro_hint") }
        public static var noTeams: String { tr("team.no_teams") }
        public static var members: String { tr("team.members") }
        public static var pendingInvites: String { tr("team.pending_invites") }
        public static var pending: String { tr("team.pending") }
        public static var invite: String { tr("team.invite") }
        public static var makeAdmin: String { tr("team.make_admin") }
        public static var makeMember: String { tr("team.make_member") }
        public static var remove: String { tr("team.remove") }
        public static var createTeam: String { tr("team.create_team") }
        public static var teamName: String { tr("team.team_name") }
        public static var create: String { tr("team.create") }
        public static var inviteMember: String { tr("team.invite_member") }
        public static var emailAddress: String { tr("team.email_address") }
        public static var sendInvite: String { tr("team.send_invite") }
    }

    // MARK: - Integrations

    public enum integrations {
        public static var title: String { tr("integrations.title") }
        public static var webhookNotifications: String { tr("integrations.webhook_notifications") }
        public static var webhookHint: String { tr("integrations.webhook_hint") }
        public static var webhookURLPlaceholder: String { tr("integrations.webhook_url_placeholder") }
        public static var testWebhook: String { tr("integrations.test_webhook") }
        public static var eventFilter: String { tr("integrations.event_filter") }
        public static var eventFilterHint: String { tr("integrations.event_filter_hint") }
        public static var filterSeverities: String { tr("integrations.filter_severities") }
        public static var filterTypes: String { tr("integrations.filter_types") }
        public static var filterProviders: String { tr("integrations.filter_providers") }
        public static var filterAll: String { tr("integrations.filter_all") }
    }

    // MARK: - Forecast

    public enum forecast {
        public static var title: String { tr("forecast.title") }
        public static var monthEnd: String { tr("forecast.month_end") }
        public static var soFar: String { tr("forecast.so_far") }
        public static var confidence: String { tr("forecast.confidence") }
        public static var estimate: String { tr("forecast.estimate") }
        public static var insufficientData: String { tr("forecast.insufficient_data") }
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
        public static var today: String { tr("common.today") }
        public static var noData: String { tr("common.no_data") }
        public static var navigation: String { tr("common.navigation") }
        public static var data: String { tr("common.data") }
        public static var refresh: String { tr("common.refresh") }
    }
}

#if !SWIFT_PACKAGE
private final class BundleToken {}
#endif
