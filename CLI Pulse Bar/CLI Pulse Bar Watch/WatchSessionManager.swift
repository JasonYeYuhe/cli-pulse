import Foundation
import WatchConnectivity
import CLIPulseCore

/// Manages WatchConnectivity to receive data from the paired iPhone app.
/// Stores received dashboard data as a fallback when the API is unreachable.
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var lastReceivedDashboard: DashboardSummary?
    @Published var lastReceivedProviders: [ProviderUsage] = []
    @Published var lastReceivedSessions: [SessionRecord] = []
    @Published var lastReceivedAlerts: [AlertRecord] = []
    @Published var isPhoneReachable = false
    @Published var lastSyncDate: Date?

    // Auth tokens received from iPhone
    @Published var pendingAuthToken: String?
    @Published var pendingRefreshToken: String?
    @Published var pendingAuthEmail: String?
    @Published var pendingAuthName: String?

    private let dashboardKey = "cli_pulse_watch_dashboard"
    private let providersKey = "cli_pulse_watch_providers"
    private let sessionsKey = "cli_pulse_watch_sessions"
    private let alertsKey = "cli_pulse_watch_alerts"

    private override init() {
        super.init()
    }

    /// Activate the WCSession if supported.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Apply fallback data to the AppState when the server is unreachable.
    @MainActor
    func applyFallbackData(to state: AppState) {
        if state.dashboard == nil, let dash = lastReceivedDashboard {
            state.dashboard = dash
        }
        if state.providers.isEmpty, !lastReceivedProviders.isEmpty {
            state.providers = lastReceivedProviders
        }
        if state.sessions.isEmpty, !lastReceivedSessions.isEmpty {
            state.sessions = lastReceivedSessions
        }
        if state.alerts.isEmpty, !lastReceivedAlerts.isEmpty {
            state.alerts = lastReceivedAlerts
        }
    }

    // MARK: - Persistence

    private func persistData() {
        let encoder = JSONEncoder()
        if let dash = lastReceivedDashboard,
           let data = try? encoder.encode(dash) {
            UserDefaults.standard.set(data, forKey: dashboardKey)
        }
        if !lastReceivedProviders.isEmpty,
           let data = try? encoder.encode(lastReceivedProviders) {
            UserDefaults.standard.set(data, forKey: providersKey)
        }
        if !lastReceivedSessions.isEmpty,
           let data = try? encoder.encode(lastReceivedSessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
        if !lastReceivedAlerts.isEmpty,
           let data = try? encoder.encode(lastReceivedAlerts) {
            UserDefaults.standard.set(data, forKey: alertsKey)
        }
    }

    func loadPersistedData() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: dashboardKey),
           let dash = try? decoder.decode(DashboardSummary.self, from: data) {
            lastReceivedDashboard = dash
        }
        if let data = UserDefaults.standard.data(forKey: providersKey),
           let providers = try? decoder.decode([ProviderUsage].self, from: data) {
            lastReceivedProviders = providers
        }
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let sessions = try? decoder.decode([SessionRecord].self, from: data) {
            lastReceivedSessions = sessions
        }
        if let data = UserDefaults.standard.data(forKey: alertsKey),
           let alerts = try? decoder.decode([AlertRecord].self, from: data) {
            lastReceivedAlerts = alerts
        }
    }

    // MARK: - Process application context

    private func processContext(_ context: [String: Any]) {
        let decoder = JSONDecoder()

        // Decode on background thread, batch-update all published properties in a single main-thread dispatch
        let dash = (context["dashboard"] as? Data).flatMap { try? decoder.decode(DashboardSummary.self, from: $0) }
        let providers = (context["providers"] as? Data).flatMap { try? decoder.decode([ProviderUsage].self, from: $0) }
        let sessions = (context["sessions"] as? Data).flatMap { try? decoder.decode([SessionRecord].self, from: $0) }
        let alerts = (context["alerts"] as? Data).flatMap { try? decoder.decode([AlertRecord].self, from: $0) }

        DispatchQueue.main.async {
            if let dash { self.lastReceivedDashboard = dash }
            if let providers { self.lastReceivedProviders = providers }
            if let sessions { self.lastReceivedSessions = sessions }
            if let alerts { self.lastReceivedAlerts = alerts }
            self.lastSyncDate = Date()
            self.persistData()
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
        }
        // Load any previously persisted data on activation
        DispatchQueue.main.async {
            self.loadPersistedData()
        }
        // Process any existing application context
        if !session.receivedApplicationContext.isEmpty {
            processContext(session.receivedApplicationContext)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        processContext(applicationContext)
    }

    /// Receive queued user info from iPhone (auth tokens or logout signal).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["cli_pulse_logout"] as? Bool == true {
            DispatchQueue.main.async {
                self.pendingAuthToken = nil
                self.pendingRefreshToken = nil
                self.pendingAuthEmail = nil
                self.pendingAuthName = nil
                // Clear stored tokens
                UserDefaults.standard.removeObject(forKey: "cli_pulse_watch_auth_token")
                UserDefaults.standard.removeObject(forKey: "cli_pulse_watch_refresh_token")
                NotificationCenter.default.post(name: .watchDidReceiveLogout, object: nil)
            }
            return
        }

        if userInfo["cli_pulse_auth"] as? Bool == true {
            let token = userInfo["access_token"] as? String
            let refresh = userInfo["refresh_token"] as? String
            let email = userInfo["email"] as? String
            let name = userInfo["name"] as? String

            guard let token, !token.isEmpty else { return }

            // Persist for independent token lifecycle
            UserDefaults.standard.set(token, forKey: "cli_pulse_watch_auth_token")
            if let refresh { UserDefaults.standard.set(refresh, forKey: "cli_pulse_watch_refresh_token") }

            DispatchQueue.main.async {
                self.pendingAuthToken = token
                self.pendingRefreshToken = refresh
                self.pendingAuthEmail = email
                self.pendingAuthName = name
                NotificationCenter.default.post(name: .watchDidReceiveAuth, object: nil, userInfo: [
                    "access_token": token,
                    "refresh_token": refresh ?? "",
                    "email": email ?? "",
                    "name": name ?? "",
                ])
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchDidReceiveAuth = Notification.Name("watchDidReceiveAuth")
    static let watchDidReceiveLogout = Notification.Name("watchDidReceiveLogout")
}
