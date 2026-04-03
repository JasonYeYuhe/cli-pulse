import Foundation

/// Pairing configuration shared between the main app and the Login Item helper.
/// Stored in the app group UserDefaults so both processes can access it.
public struct HelperConfig: Codable, Sendable {
    public let deviceId: String
    public let userId: String
    public let deviceName: String
    public let helperVersion: String
    public let helperSecret: String

    public init(deviceId: String, userId: String, deviceName: String,
                helperVersion: String, helperSecret: String) {
        self.deviceId = deviceId
        self.userId = userId
        self.deviceName = deviceName
        self.helperVersion = helperVersion
        self.helperSecret = helperSecret
    }

    // MARK: - App Group Persistence

    private static let suiteName = "group.yyh.CLI-Pulse"
    private static let key = "helper_config"

    /// Read config from shared UserDefaults.
    public static func load() -> HelperConfig? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HelperConfig.self, from: data)
    }

    /// Write config to shared UserDefaults.
    public static func save(_ config: HelperConfig) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }

    /// Remove config from shared UserDefaults.
    public static func remove() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: key)
    }

    // MARK: - Migration from Python helper

    /// Attempt to import config from the legacy Python helper JSON file.
    /// Path: ~/.cli-pulse-helper.json
    public static func importFromLegacy() -> HelperConfig? {
        let home = NSHomeDirectory()
        let path = (home as NSString).appendingPathComponent(".cli-pulse-helper.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceId = json["device_id"] as? String,
              let userId = json["user_id"] as? String,
              let helperSecret = json["helper_secret"] as? String else {
            return nil
        }
        return HelperConfig(
            deviceId: deviceId,
            userId: userId,
            deviceName: json["device_name"] as? String ?? Host.current().localizedName ?? "Mac",
            helperVersion: json["helper_version"] as? String ?? "1.0.0",
            helperSecret: helperSecret
        )
    }
}
