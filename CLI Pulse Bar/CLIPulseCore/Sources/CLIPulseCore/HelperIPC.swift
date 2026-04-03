import Foundation

/// Inter-process communication constants between the main app and the Login Item helper.
/// Both processes share the `group.yyh.CLI-Pulse` app group.
public enum HelperIPC {

    // MARK: - DistributedNotificationCenter names

    /// Posted by the helper after each successful sync cycle.
    /// The main app can observe this to trigger an immediate refresh.
    /// Note: treat as a hint — always validate data freshness from app group files.
    public static let didSyncNotificationName = Notification.Name("CLIPulseHelperDidSync")

    /// Posted by the helper when it starts up.
    public static let didStartNotificationName = Notification.Name("CLIPulseHelperDidStart")

    // MARK: - Shared UserDefaults keys (suite: group.yyh.CLI-Pulse)

    public static let suiteName = "group.yyh.CLI-Pulse"

    /// Helper status JSON: { "state": "running"|"idle"|"error", "lastSync": ISO8601, "error": "..." }
    public static let statusKey = "helper_status"

    /// Helper config (HelperConfig encoded as JSON data)
    public static let configKey = "helper_config"

    /// Provider configs (array of ProviderConfig, written by main app for helper to read)
    public static let providerConfigsKey = "helper_provider_configs"

    /// Sync interval in seconds (Int, written by main app, read by helper)
    public static let syncIntervalKey = "helper_sync_interval"

    // MARK: - Status

    public enum State: String, Codable, Sendable {
        case running
        case idle
        case error
    }

    public struct Status: Codable, Sendable {
        public let state: State
        public let lastSync: Date?
        public let error: String?
        public let helperVersion: String?

        public init(state: State, lastSync: Date? = nil, error: String? = nil, helperVersion: String? = nil) {
            self.state = state
            self.lastSync = lastSync
            self.error = error
            self.helperVersion = helperVersion
        }
    }

    /// Read helper status from shared UserDefaults.
    public static func readStatus() -> Status? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: statusKey) else { return nil }
        return try? JSONDecoder().decode(Status.self, from: data)
    }

    /// Write helper status to shared UserDefaults.
    public static func writeStatus(_ status: Status) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: statusKey)
    }

    /// Post a sync notification via DistributedNotificationCenter.
    #if os(macOS)
    public static func postSyncNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            didSyncNotificationName, object: nil, userInfo: nil,
            deliverImmediately: true
        )
    }

    public static func postStartNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            didStartNotificationName, object: nil, userInfo: nil,
            deliverImmediately: true
        )
    }
    #endif
}
