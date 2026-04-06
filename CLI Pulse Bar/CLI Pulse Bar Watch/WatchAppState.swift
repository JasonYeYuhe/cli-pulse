import Foundation
import SwiftUI
import CLIPulseCore

/// Lightweight app state for watchOS, exposing only the properties watch views need.
/// Full AppState has 40+ published properties; this has ~15, reducing memory and processing overhead.
@MainActor
public final class WatchAppState: ObservableObject {
    // MARK: - Auth
    @Published var isAuthenticated = false
    @Published var isPaired = false
    @Published var userName = ""
    @Published var userEmail = ""

    // MARK: - Data
    @Published var dashboard: DashboardSummary?
    @Published var providers: [ProviderUsage] = []
    @Published var sessions: [SessionRecord] = []
    @Published var alerts: [AlertRecord] = []

    // MARK: - UI
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastRefresh: Date?
    @Published var serverOnline = false

    // MARK: - Auth Flow
    @Published var otpSent = false
    @Published var otpEmail = ""

    // MARK: - Settings
    @AppStorage("cli_pulse_demo_mode") var isDemoMode = false
    @AppStorage("cli_pulse_show_cost") var showCost = true

    // MARK: - Internal
    private let api: APIClient
    private let authManager: AuthManager
    private var refreshTimer: Timer?

    init() {
        self.api = APIClient()
        self.authManager = AuthManager(api: api, persistTokens: { access, refresh in
            if !access.isEmpty {
                KeychainHelper.save(key: "cli_pulse_token", value: access)
            } else {
                KeychainHelper.delete(key: "cli_pulse_token")
            }
            if let refresh, !refresh.isEmpty {
                KeychainHelper.save(key: "cli_pulse_refresh_token", value: refresh)
            } else {
                KeychainHelper.delete(key: "cli_pulse_refresh_token")
            }
        })

        Task { await restoreSession() }

        // Listen for iPhone auth
        NotificationCenter.default.addObserver(forName: .watchDidReceiveAuth, object: nil, queue: .main) { [weak self] notif in
            guard let self, let info = notif.userInfo,
                  let token = info["access_token"] as? String, !token.isEmpty else { return }
            Task { @MainActor in
                self.applyWatchAuth(
                    token: token,
                    refreshToken: info["refresh_token"] as? String,
                    email: info["email"] as? String ?? "",
                    name: info["name"] as? String ?? ""
                )
            }
        }

        NotificationCenter.default.addObserver(forName: .watchDidReceiveLogout, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.signOut()
            }
        }
    }

    // MARK: - Auth Actions

    func sendOTP(email: String) async {
        isLoading = true
        lastError = nil
        do {
            otpEmail = try await authManager.sendOTP(email: email)
            otpSent = true
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    func verifyOTP(code: String) async {
        isLoading = true
        lastError = nil
        do {
            let authState = try await authManager.verifyOTP(email: otpEmail, code: code)
            userName = authState.userName
            userEmail = authState.userEmail
            isPaired = authState.isPaired
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

    func resetOTP() {
        let state = authManager.resetOTP()
        otpSent = state.otpSent
        otpEmail = state.otpEmail
        lastError = state.lastError
    }

    func applyWatchAuth(token: String, refreshToken: String?, email: String, name: String) {
        KeychainHelper.save(key: "cli_pulse_token", value: token)
        if let rt = refreshToken {
            KeychainHelper.save(key: "cli_pulse_refresh_token", value: rt)
        }
        userName = name
        userEmail = email
        isAuthenticated = true
        isPaired = true
        startRefreshLoop()
        Task { await refreshAll() }
    }

    func signOut() {
        stopRefreshLoop()
        let token = KeychainHelper.load(key: "cli_pulse_token") ?? ""
        Task { await authManager.signOut(currentAccessToken: token) }
        isAuthenticated = false
        isPaired = false
        userName = ""
        userEmail = ""
        dashboard = nil
        providers = []
        sessions = []
        alerts = []
    }

    // MARK: - Provider Helpers

    var enabledProviderNames: [String] {
        providers.map { $0.provider }
    }

    // MARK: - Alert Actions

    func acknowledgeAlert(_ alert: AlertRecord) async {
        do {
            _ = try await api.acknowledgeAlert(id: alert.id)
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resolveAlert(_ alert: AlertRecord) async {
        do {
            _ = try await api.resolveAlert(id: alert.id)
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func snoozeAlert(_ alert: AlertRecord, minutes: Int) async {
        do {
            _ = try await api.snoozeAlert(id: alert.id, minutes: minutes)
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        guard isAuthenticated else { return }
        isLoading = true
        lastError = nil
        do {
            async let dashTask = api.dashboard()
            async let provTask = api.providers()
            async let sessTask = api.sessions()
            async let alertTask = api.alerts()

            dashboard = try await dashTask
            providers = try await provTask
            sessions = try await sessTask
            alerts = try await alertTask
            serverOnline = true
            lastRefresh = Date()
        } catch {
            serverOnline = false
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    func startRefreshLoop() {
        stopRefreshLoop()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
    }

    func stopRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Session Restore

    private func restoreSession() async {
        if isDemoMode {
            isAuthenticated = true
            isPaired = true
            userName = "Demo User"
            userEmail = "demo@clipulse.app"
            return
        }

        let token = KeychainHelper.load(key: "cli_pulse_token") ?? ""
        let refreshToken = KeychainHelper.load(key: "cli_pulse_refresh_token")
        guard !token.isEmpty else { return }

        switch await authManager.restoreSession(isDemoMode: false, accessToken: token, refreshToken: refreshToken) {
        case .restored(let authState):
            userName = authState.userName
            userEmail = authState.userEmail
            isPaired = authState.isPaired
            isAuthenticated = true
            startRefreshLoop()
            await refreshAll()
        case .demoMode:
            break
        default:
            break
        }
    }

    // MARK: - WCSession Fallback

    func applyFallbackData(from sessionManager: WatchSessionManager) {
        if dashboard == nil, let dash = sessionManager.lastReceivedDashboard {
            dashboard = dash
        }
        if providers.isEmpty, !sessionManager.lastReceivedProviders.isEmpty {
            providers = sessionManager.lastReceivedProviders
        }
        if sessions.isEmpty, !sessionManager.lastReceivedSessions.isEmpty {
            sessions = sessionManager.lastReceivedSessions
        }
        if alerts.isEmpty, !sessionManager.lastReceivedAlerts.isEmpty {
            alerts = sessionManager.lastReceivedAlerts
        }
    }
}
