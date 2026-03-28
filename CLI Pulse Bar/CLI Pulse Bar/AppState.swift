import Foundation
import SwiftUI
import UserNotifications
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Auth State
    @Published var isAuthenticated = false
    @Published var isPaired = false
    @Published var userName: String = ""
    @Published var userEmail: String = ""

    // MARK: - Data
    @Published var dashboard: DashboardSummary?
    @Published var providers: [ProviderUsage] = []
    @Published var sessions: [SessionRecord] = []
    @Published var devices: [DeviceRecord] = []
    @Published var alerts: [AlertRecord] = []

    // MARK: - UI State
    @Published var selectedTab: Tab = .overview
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastRefresh: Date?
    @Published var serverOnline = false

    // MARK: - Settings
    @AppStorage("cli_pulse_token") var storedToken = ""
    @AppStorage("cli_pulse_refresh_interval") var refreshInterval: Int = 30
    @AppStorage("cli_pulse_show_cost") var showCost = true
    @AppStorage("cli_pulse_notifications") var notificationsEnabled = true
    @AppStorage("cli_pulse_compact_mode") var compactMode = false

    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case providers = "Providers"
        case sessions = "Sessions"
        case alerts = "Alerts"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.33percent"
            case .providers: return "cpu"
            case .sessions: return "terminal"
            case .alerts: return "bell.badge"
            case .settings: return "gear"
            }
        }
    }

    let api: APIClient
    private var refreshTimer: Timer?
    private var previousAlertIDs: Set<String> = []

    // MARK: - Menu Bar Label
    var menuBarLabel: String {
        guard isAuthenticated, isPaired else { return "" }
        let unresolvedCount = alerts.filter { !$0.is_resolved }.count
        if unresolvedCount > 0 {
            return "\(unresolvedCount)"
        }
        return ""
    }

    var menuBarIcon: String {
        guard isAuthenticated, isPaired else { return "waveform.path.ecg" }
        let unresolvedCount = alerts.filter { !$0.is_resolved }.count
        if unresolvedCount > 0 { return "exclamationmark.triangle.fill" }
        if !serverOnline { return "wifi.slash" }
        return "waveform.path.ecg"
    }

    init() {
        self.api = APIClient()
        Task {
            if !storedToken.isEmpty {
                await api.updateToken(storedToken)
                await restoreSession()
            }
        }
    }

    // MARK: - Auth

    func signIn(email: String, name: String) async {
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

    func signInWithApple(identityToken: String, fullName: String?, email: String?) async {
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

    func signOut() {
        stopRefreshLoop()
        storedToken = ""
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

    func restoreSession() async {
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

    func refreshAll() async {
        guard isAuthenticated, isPaired else { return }
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
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
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

    // MARK: - Refresh Timer

    func startRefreshLoop() {
        stopRefreshLoop()
        let interval = TimeInterval(refreshInterval)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshAll()
            }
        }
    }

    func stopRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func updateRefreshInterval(_ seconds: Int) {
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

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
