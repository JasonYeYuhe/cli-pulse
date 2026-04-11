#if os(macOS)
import Foundation
import os

private let helperLogger = Logger(subsystem: "com.clipulse", category: "HelperAPI")

/// Lightweight Supabase RPC client for the helper daemon.
/// Uses the anon key (not user tokens) — helper authenticates via device secret.
public actor HelperAPIClient {

    private let supabaseURL: String
    private let anonKey: String

    public init(supabaseURL: String, anonKey: String) {
        self.supabaseURL = supabaseURL
        self.anonKey = anonKey
    }

    /// Convenience init reading Supabase config from CLIPulseCore constants.
    public init() {
        self.supabaseURL = SupabaseConstants.url
        self.anonKey = SupabaseConstants.anonKey
    }

    // MARK: - RPCs (matching backend/supabase/helper_rpc.sql)

    /// Register a helper device via pairing code.
    /// Returns: { device_id, user_id, helper_secret }
    public func registerHelper(
        pairingCode: String,
        deviceName: String,
        deviceType: String = "macOS",
        system: String = "",
        helperVersion: String = "1.0.0"
    ) async throws -> HelperConfig {
        let result: [String: Any] = try await rpc("register_helper", params: [
            "p_pairing_code": pairingCode,
            "p_device_name": deviceName,
            "p_device_type": deviceType,
            "p_system": system,
            "p_helper_version": helperVersion,
        ])
        guard let deviceId = result["device_id"] as? String,
              let userId = result["user_id"] as? String,
              let secret = result["helper_secret"] as? String else {
            throw HelperAPIError.parseFailed("register_helper response missing fields")
        }
        return HelperConfig(
            deviceId: deviceId, userId: userId,
            deviceName: deviceName, helperVersion: helperVersion,
            helperSecret: secret
        )
    }

    /// Send a heartbeat with device metrics.
    public func heartbeat(
        config: HelperConfig,
        cpuUsage: Int,
        memoryUsage: Int,
        activeSessionCount: Int
    ) async throws {
        let _: [String: Any] = try await rpc("helper_heartbeat", params: [
            "p_device_id": config.deviceId,
            "p_helper_secret": config.helperSecret,
            "p_cpu_usage": cpuUsage,
            "p_memory_usage": memoryUsage,
            "p_active_session_count": activeSessionCount,
        ])
    }

    /// Sync sessions, alerts, and provider quota data.
    ///
    /// - `sessions`: array of session dicts with id, name, provider, project, etc.
    /// - `alerts`: array of alert dicts with id, type, severity, title, etc.
    /// - `providerRemaining`: flat { provider: remaining } for legacy compat
    /// - `providerTiers`: full { provider: { quota, remaining, plan_type, reset_time, tiers: [...] } }
    public func sync(
        config: HelperConfig,
        sessions: [[String: Any]],
        alerts: [[String: Any]],
        providerRemaining: [String: Int],
        providerTiers: [String: Any]
    ) async throws -> (sessionsSynced: Int, alertsSynced: Int) {
        let result: [String: Any] = try await rpc("helper_sync", params: [
            "p_device_id": config.deviceId,
            "p_helper_secret": config.helperSecret,
            "p_sessions": sessions,
            "p_alerts": alerts,
            "p_provider_remaining": providerRemaining,
            "p_provider_tiers": providerTiers,
        ])
        return (
            sessionsSynced: result["sessions_synced"] as? Int ?? 0,
            alertsSynced: result["alerts_synced"] as? Int ?? 0
        )
    }

    // MARK: - Generic RPC

    /// True when the client has a non-empty Supabase URL and anon key.
    /// Callers can check this before attempting RPCs to surface a clear
    /// "not configured" state rather than chasing mysterious HTTP failures.
    public var isConfigured: Bool {
        !supabaseURL.isEmpty && !anonKey.isEmpty
    }

    private func rpc<T>(_ function: String, params: [String: Any]) async throws -> T {
        guard isConfigured else {
            throw HelperAPIError.notConfigured
        }
        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/\(function)") else {
            throw HelperAPIError.invalidURL(function)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CLIPulseHelper/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HelperAPIError.parseFailed("non-HTTP response from \(function)")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HelperAPIError.httpError(status: http.statusCode, function: function, body: body)
        }

        guard let result = try JSONSerialization.jsonObject(with: data) as? T else {
            throw HelperAPIError.parseFailed("cannot decode \(function) response as \(T.self)")
        }
        return result
    }
}

// MARK: - Supabase Constants (centralized)

public enum SupabaseConstants {
    public static let url = "https://gkjwsxotmwrgqsvfijzs.supabase.co"
    public static let anonKey: String = {
        if let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["CLI_PULSE_SUPABASE_ANON_KEY"], !key.isEmpty {
            return key
        }
        #if DEBUG
        fatalError("SUPABASE_ANON_KEY missing from Info.plist and environment")
        #else
        helperLogger.error("SUPABASE_ANON_KEY missing — API calls will fail")
        return ""
        #endif
    }()
}

// MARK: - Errors

public enum HelperAPIError: LocalizedError {
    case notConfigured
    case invalidURL(String)
    case httpError(status: Int, function: String, body: String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "HelperAPIClient is not configured — SUPABASE_ANON_KEY is missing or empty"
        case .invalidURL(let fn): return "Invalid URL for \(fn)"
        case .httpError(let s, let fn, let body): return "HTTP \(s) from \(fn): \(body.prefix(200))"
        case .parseFailed(let msg): return "Parse failed: \(msg)"
        }
    }
}
#endif
