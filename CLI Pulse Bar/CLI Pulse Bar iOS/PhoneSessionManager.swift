import Foundation
import WatchConnectivity
import CLIPulseCore

/// Manages WatchConnectivity on the iPhone side.
/// Sends auth tokens and dashboard data to the paired Apple Watch.
final class PhoneSessionManager: NSObject, ObservableObject {
    static let shared = PhoneSessionManager()

    @Published var isWatchReachable = false

    private override init() {
        super.init()
    }

    /// Activate the WCSession if supported (iPhone only).
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        // Observe auth events from CLIPulseCore
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidAuthenticate(_:)),
                                                name: .cliPulseDidAuthenticate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidSignOut),
                                                name: .cliPulseDidSignOut, object: nil)
    }

    @objc private func handleDidAuthenticate(_ notification: Notification) {
        guard let info = notification.userInfo,
              let token = info["access_token"] as? String, !token.isEmpty else { return }
        sendAuthToWatch(
            accessToken: token,
            refreshToken: info["refresh_token"] as? String,
            email: info["email"] as? String ?? "",
            name: info["name"] as? String ?? ""
        )
    }

    @objc private func handleDidSignOut() {
        sendLogoutToWatch()
    }

    // MARK: - Send Auth to Watch

    /// Transfer auth tokens to the watch after successful login.
    /// Uses `transferUserInfo` for guaranteed delivery (queued, survives app exit).
    func sendAuthToWatch(accessToken: String, refreshToken: String?, email: String, name: String) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired else { return }

        var payload: [String: Any] = [
            "cli_pulse_auth": true,
            "access_token": accessToken,
            "email": email,
            "name": name,
        ]
        if let rt = refreshToken {
            payload["refresh_token"] = rt
        }
        WCSession.default.transferUserInfo(payload)
    }

    /// Send logout signal to watch.
    func sendLogoutToWatch() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired else { return }

        WCSession.default.transferUserInfo(["cli_pulse_logout": true])
    }

    // MARK: - Send Dashboard Data

    /// Update application context with fresh dashboard data.
    func sendDashboardToWatch(dashboard: DashboardSummary?, providers: [ProviderUsage],
                               sessions: [SessionRecord], alerts: [AlertRecord]) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired else { return }

        let encoder = JSONEncoder()
        var context: [String: Any] = [:]

        if let dash = dashboard, let data = try? encoder.encode(dash) {
            context["dashboard"] = data
        }
        if !providers.isEmpty, let data = try? encoder.encode(providers) {
            context["providers"] = data
        }
        if !sessions.isEmpty, let data = try? encoder.encode(sessions) {
            context["sessions"] = data
        }
        if !alerts.isEmpty, let data = try? encoder.encode(alerts) {
            context["alerts"] = data
        }

        guard !context.isEmpty else { return }
        try? WCSession.default.updateApplicationContext(context)
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for multi-watch support
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }
}
