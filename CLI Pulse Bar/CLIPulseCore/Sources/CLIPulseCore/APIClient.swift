import Foundation

public actor APIClient {
    private let supabaseURL: String
    private let supabaseAnonKey: String

    private var accessToken: String?
    private var refreshToken: String?
    private var userId: String?

    private let session: URLSession

    /// Called after a successful token refresh with (newAccessToken, newRefreshToken).
    /// Set by AppState to persist rotated tokens to Keychain.
    public var onTokenRefreshed: (@Sendable (String, String) -> Void)?

    public init(
        token: String? = nil,
        supabaseURL: String? = nil,
        supabaseAnonKey: String? = nil
    ) {
        self.accessToken = token
        self.supabaseURL = supabaseURL
            ?? Bundle.main.infoDictionary?["SUPABASE_URL"] as? String
            ?? ProcessInfo.processInfo.environment["CLI_PULSE_SUPABASE_URL"]
            ?? "https://gkjwsxotmwrgqsvfijzs.supabase.co"
        self.supabaseAnonKey = supabaseAnonKey
            ?? Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String
            ?? ProcessInfo.processInfo.environment["CLI_PULSE_SUPABASE_ANON_KEY"]
            ?? ""
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    public func updateToken(_ token: String?) {
        self.accessToken = token
    }

    public func updateRefreshToken(_ token: String?) {
        self.refreshToken = token
    }

    public func setTokenRefreshHandler(_ handler: @escaping @Sendable (String, String) -> Void) {
        self.onTokenRefreshed = handler
    }

    public func getToken() -> String? {
        return accessToken
    }

    public func getRefreshToken() -> String? {
        return refreshToken
    }

    // MARK: - Token Refresh

    /// Attempt to refresh the access token using the stored refresh token.
    /// Returns the new access token and refresh token, or throws on failure.
    public func refreshAccessToken() async throws -> (accessToken: String, refreshToken: String) {
        guard let currentRefreshToken = refreshToken else {
            throw APIError.tokenExpired
        }
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": currentRefreshToken])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // Refresh failed — token is invalid
            self.accessToken = nil
            self.refreshToken = nil
            throw APIError.tokenExpired
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let newAccess = json["access_token"] as? String ?? ""
        let newRefresh = json["refresh_token"] as? String ?? currentRefreshToken

        self.accessToken = newAccess
        self.refreshToken = newRefresh

        // Notify so caller can persist to Keychain
        onTokenRefreshed?(newAccess, newRefresh)

        return (newAccess, newRefresh)
    }

    // MARK: - Sign Out (server-side token revocation)

    public func signOutServer() async {
        // Capture token before clearing to avoid race with new sign-in
        let tokenToRevoke = accessToken
        self.accessToken = nil
        self.refreshToken = nil
        self.userId = nil

        guard let tokenToRevoke, let url = URL(string: "\(supabaseURL)/auth/v1/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(tokenToRevoke)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    // MARK: - UUID Validation

    private static func isValidUUID(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }

    private static func sanitizeParam(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    // MARK: - Auth (Sign in with Apple via Supabase)

    public func signInWithApple(identityToken: String, nonce: String? = nil, fullName: String?, email: String?) async throws -> AuthResponse {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=id_token") else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        var body: [String: Any] = [
            "provider": "apple",
            "id_token": identityToken
        ]
        if let nonce = nonce {
            body["nonce"] = nonce
        }
        if let fullName = fullName {
            body["name"] = fullName
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let token = json["access_token"] as? String ?? ""
        let refresh = json["refresh_token"] as? String
        let user = json["user"] as? [String: Any] ?? [:]

        self.accessToken = token
        self.refreshToken = refresh
        self.userId = user["id"] as? String

        let safeUserId = Self.sanitizeParam(userId ?? "")
        let profile: [[String: Any]] = try await restGet("/rest/v1/profiles?id=eq.\(safeUserId)&select=paired")
        let paired = profile.first?["paired"] as? Bool ?? false

        let name = fullName ?? (user["user_metadata"] as? [String: Any])?["name"] as? String ?? ""
        let userEmail = email ?? user["email"] as? String ?? ""

        return AuthResponse(
            access_token: token,
            refresh_token: refresh,
            user: UserDTO(id: userId ?? "", name: name, email: userEmail),
            paired: paired
        )
    }

    /// Send an OTP code to the user's email
    public func sendOTP(email: String) async throws {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/otp") else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: Any] = [
            "email": email,
            "create_user": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }
    }

    /// Verify the OTP code and sign the user in
    public func verifyOTP(email: String, code: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/verify") else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = [
            "email": email,
            "token": code,
            "type": "email"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let token = json["access_token"] as? String ?? ""
        let refresh = json["refresh_token"] as? String
        let user = json["user"] as? [String: Any] ?? [:]

        self.accessToken = token
        self.refreshToken = refresh
        self.userId = user["id"] as? String

        let safeUserId = Self.sanitizeParam(userId ?? "")
        let profile: [[String: Any]] = try await restGet("/rest/v1/profiles?id=eq.\(safeUserId)&select=paired,name,email")
        let paired = profile.first?["paired"] as? Bool ?? false
        let profileName = profile.first?["name"] as? String ?? ""
        let profileEmail = profile.first?["email"] as? String ?? email

        return AuthResponse(
            access_token: token,
            refresh_token: refresh,
            user: UserDTO(id: userId ?? "", name: profileName, email: profileEmail),
            paired: paired
        )
    }

    /// Password-based sign in (for demo / review account)
    public func signInWithPassword(email: String, password: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password") else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let token = json["access_token"] as? String ?? ""
        let refresh = json["refresh_token"] as? String
        let user = json["user"] as? [String: Any] ?? [:]

        self.accessToken = token
        self.refreshToken = refresh
        self.userId = user["id"] as? String

        let safeUserId = Self.sanitizeParam(userId ?? "")
        let profile: [[String: Any]] = try await restGet("/rest/v1/profiles?id=eq.\(safeUserId)&select=paired,name,email")
        let paired = profile.first?["paired"] as? Bool ?? false
        let profileName = profile.first?["name"] as? String ?? ""
        let profileEmail = profile.first?["email"] as? String ?? email

        return AuthResponse(
            access_token: token,
            refresh_token: refresh,
            user: UserDTO(id: userId ?? "", name: profileName, email: profileEmail),
            paired: paired
        )
    }

    public func me(retried: Bool = false) async throws -> AuthResponse {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/user") else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        // Handle 401 by attempting token refresh (once only)
        if http?.statusCode == 401, !retried {
            let _ = try await refreshAccessToken()
            return try await me(retried: true)
        }
        guard let httpOK = http, (200...299).contains(httpOK.statusCode) else {
            throw APIError.httpError(status: http?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }

        let user = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        self.userId = user["id"] as? String
        let metadata = user["user_metadata"] as? [String: Any] ?? [:]

        let safeUserId = Self.sanitizeParam(userId ?? "")
        let profile: [[String: Any]] = try await restGet("/rest/v1/profiles?id=eq.\(safeUserId)&select=paired,name,email")
        let paired = profile.first?["paired"] as? Bool ?? false
        let name = profile.first?["name"] as? String ?? metadata["name"] as? String ?? ""
        let email = profile.first?["email"] as? String ?? user["email"] as? String ?? ""

        return AuthResponse(
            access_token: accessToken ?? "",
            refresh_token: refreshToken,
            user: UserDTO(id: userId ?? "", name: name, email: email),
            paired: paired
        )
    }

    // MARK: - Dashboard

    public func dashboard() async throws -> DashboardSummary {
        let json: [String: Any] = try await rpc("dashboard_summary", params: [:])

        let todayUsage = json["today_usage"] as? Int ?? 0
        let todayCost = (json["today_cost"] as? NSNumber)?.doubleValue ?? 0
        let activeSessions = json["active_sessions"] as? Int ?? 0
        let onlineDevices = json["online_devices"] as? Int ?? 0
        let unresolvedAlerts = json["unresolved_alerts"] as? Int ?? 0
        let todaySessions = json["today_sessions"] as? Int ?? 0

        return DashboardSummary(
            total_usage_today: todayUsage,
            total_estimated_cost_today: todayCost,
            cost_status: "Estimated",
            total_requests_today: todaySessions,
            active_sessions: activeSessions,
            online_devices: onlineDevices,
            unresolved_alerts: unresolvedAlerts,
            provider_breakdown: [],
            top_projects: [],
            trend: [],
            recent_activity: [],
            risk_signals: [],
            alert_summary: AlertSummaryDTO(critical: 0, warning: 0, info: unresolvedAlerts)
        )
    }

    // MARK: - Providers

    public func providers() async throws -> [ProviderUsage] {
        let json: [[String: Any]] = try await rpc("provider_summary", params: [:])
        return json.map { p in
            // Parse tiers array from API response
            var tiers: [TierDTO] = []
            if let tiersArray = p["tiers"] as? [[String: Any]] {
                tiers = tiersArray.map { t in
                    TierDTO(
                        name: t["name"] as? String ?? "Default",
                        quota: t["quota"] as? Int ?? 0,
                        remaining: t["remaining"] as? Int ?? 0,
                        reset_time: t["reset_time"] as? String
                    )
                }
            }
            return ProviderUsage(
                provider: p["provider"] as? String ?? "",
                today_usage: p["today_usage"] as? Int ?? 0,
                week_usage: p["total_usage"] as? Int ?? 0,
                estimated_cost_today: 0,
                estimated_cost_week: (p["estimated_cost"] as? NSNumber)?.doubleValue ?? 0,
                cost_status_today: "Estimated",
                cost_status_week: "Estimated",
                quota: p["quota"] as? Int,
                remaining: p["remaining"] as? Int,
                plan_type: p["plan_type"] as? String,
                reset_time: p["reset_time"] as? String,
                tiers: tiers,
                status_text: "Operational",
                trend: [],
                recent_sessions: [],
                recent_errors: []
            )
        }
    }

    // MARK: - Sessions

    public func sessions() async throws -> [SessionRecord] {
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let rows: [[String: Any]] = try await restGet(
            "/rest/v1/sessions?user_id=eq.\(safeUserId)&select=*,devices(name)&order=last_active_at.desc&limit=50"
        )
        return rows.map { r in
            let device = r["devices"] as? [String: Any]
            return SessionRecord(
                id: r["id"] as? String ?? "",
                name: r["name"] as? String ?? "",
                provider: r["provider"] as? String ?? "",
                project: r["project"] as? String ?? "",
                device_name: device?["name"] as? String ?? "",
                started_at: r["started_at"] as? String ?? "",
                last_active_at: r["last_active_at"] as? String ?? "",
                status: r["status"] as? String ?? "Running",
                total_usage: r["total_usage"] as? Int ?? 0,
                estimated_cost: (r["estimated_cost"] as? NSNumber)?.doubleValue ?? 0,
                cost_status: "Estimated",
                requests: r["requests"] as? Int ?? 0,
                error_count: r["error_count"] as? Int ?? 0,
                collection_confidence: r["collection_confidence"] as? String
            )
        }
    }

    // MARK: - Devices

    public func devices() async throws -> [DeviceRecord] {
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let rows: [[String: Any]] = try await restGet(
            "/rest/v1/devices?user_id=eq.\(safeUserId)&select=*&order=last_seen_at.desc"
        )
        return rows.map { r in
            DeviceRecord(
                id: r["id"] as? String ?? "",
                name: r["name"] as? String ?? "",
                type: r["type"] as? String ?? "macOS",
                system: r["system"] as? String ?? "",
                status: r["status"] as? String ?? "Offline",
                last_sync_at: r["last_seen_at"] as? String,
                helper_version: r["helper_version"] as? String ?? "",
                current_session_count: 0,
                cpu_usage: r["cpu_usage"] as? Int,
                memory_usage: r["memory_usage"] as? Int
            )
        }
    }

    // MARK: - Alerts

    public func alerts() async throws -> [AlertRecord] {
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let rows: [[String: Any]] = try await restGet(
            "/rest/v1/alerts?user_id=eq.\(safeUserId)&select=*&order=created_at.desc&limit=50"
        )
        return rows.map { r in
            AlertRecord(
                id: r["id"] as? String ?? "",
                type: r["type"] as? String ?? "",
                severity: r["severity"] as? String ?? "Info",
                title: r["title"] as? String ?? "",
                message: r["message"] as? String ?? "",
                created_at: r["created_at"] as? String ?? "",
                is_read: r["is_read"] as? Bool ?? false,
                is_resolved: r["is_resolved"] as? Bool ?? false,
                acknowledged_at: r["acknowledged_at"] as? String,
                snoozed_until: r["snoozed_until"] as? String,
                related_project_id: r["related_project_id"] as? String,
                related_project_name: r["related_project_name"] as? String,
                related_session_id: r["related_session_id"] as? String,
                related_session_name: r["related_session_name"] as? String,
                related_provider: r["related_provider"] as? String,
                related_device_name: r["related_device_name"] as? String,
                source_kind: r["source_kind"] as? String,
                source_id: r["source_id"] as? String,
                grouping_key: r["grouping_key"] as? String,
                suppression_key: r["suppression_key"] as? String
            )
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public func acknowledgeAlert(id: String) async throws -> SuccessResponse {
        let safeId = Self.sanitizeParam(id)
        let safeUserId = Self.sanitizeParam(userId ?? "")
        try await restPatch("/rest/v1/alerts?id=eq.\(safeId)&user_id=eq.\(safeUserId)", body: ["acknowledged_at": Self.isoFormatter.string(from: Date()), "is_read": true])
        return SuccessResponse(ok: true)
    }

    public func resolveAlert(id: String) async throws -> SuccessResponse {
        let safeId = Self.sanitizeParam(id)
        let safeUserId = Self.sanitizeParam(userId ?? "")
        try await restPatch("/rest/v1/alerts?id=eq.\(safeId)&user_id=eq.\(safeUserId)", body: ["is_resolved": true])
        return SuccessResponse(ok: true)
    }

    public func snoozeAlert(id: String, minutes: Int) async throws -> SuccessResponse {
        let safeId = Self.sanitizeParam(id)
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let snoozeUntil = Self.isoFormatter.string(from: Date().addingTimeInterval(Double(minutes) * 60))
        try await restPatch("/rest/v1/alerts?id=eq.\(safeId)&user_id=eq.\(safeUserId)", body: ["snoozed_until": snoozeUntil])
        return SuccessResponse(ok: true)
    }

    // MARK: - Settings

    public func settings() async throws -> SettingsSnapshot {
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let rows: [[String: Any]] = try await restGet("/rest/v1/user_settings?user_id=eq.\(safeUserId)&select=*")
        let s = rows.first ?? [:]
        return SettingsSnapshot(
            notifications_enabled: s["notifications_enabled"] as? Bool ?? true,
            push_policy: s["push_policy"] as? String ?? "Warnings + Critical",
            digest_enabled: s["digest_notifications_enabled"] as? Bool ?? true,
            digest_interval_hours: (s["digest_interval_minutes"] as? Int ?? 15) / 60,
            usage_spike_threshold: s["usage_spike_threshold"] as? Int ?? 500,
            project_budget_threshold_usd: (s["project_budget_threshold_usd"] as? NSNumber)?.doubleValue ?? 0.25,
            session_too_long_threshold_minutes: s["session_too_long_threshold_minutes"] as? Int ?? 180,
            offline_grace_period_minutes: s["offline_grace_period_minutes"] as? Int ?? 5,
            repeated_failure_threshold: s["repeated_failure_threshold"] as? Int ?? 3,
            alert_cooldown_minutes: s["alert_cooldown_minutes"] as? Int ?? 30,
            data_retention_days: s["data_retention_days"] as? Int ?? 7
        )
    }

    // MARK: - Pairing

    public func pairingCode() async throws -> PairingInfo {
        let code = "PULSE-\(UUID().uuidString.prefix(6).uppercased())"
        let now = Self.isoFormatter.string(from: Date())
        let expires = Self.isoFormatter.string(from: Date().addingTimeInterval(600))

        guard let uid = userId, Self.isValidUUID(uid) else { throw APIError.invalidResponse }
        guard let url = URL(string: "\(supabaseURL)/rest/v1/pairing_codes") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code, "user_id": uid,
            "created_at": now, "expires_at": expires
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        // The native Swift Login Item (CLIPulseHelper) is the primary helper.
        // Provide the pairing code for the app to pass to the embedded helper.
        // Legacy Python install command kept as fallback for non-App-Store builds.
        #if os(macOS)
        return PairingInfo(
            code: code,
            install_command: "open -a 'CLI Pulse Bar' --args --pair \(code)"
        )
        #else
        return PairingInfo(
            code: code,
            install_command: code
        )
        #endif
    }

    // MARK: - Account Deletion

    public func deleteAccount() async throws {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/delete_user_account") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        // Revoke server-side token after account deletion
        await signOutServer()
    }

    // MARK: - Server Tier

    public func serverTier() async -> String {
        do {
            let json: [String: Any] = try await rpc("get_user_tier", params: [:])
            return (json["tier"] as? String) ?? "free"
        } catch {
            return "free"
        }
    }

    // MARK: - Health

    public func health() async throws -> Bool {
        // Use the auth health endpoint which doesn't require authentication
        guard let url = URL(string: "\(supabaseURL)/auth/v1/health") else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (200...299).contains(status)
    }

    // MARK: - Supabase REST Helpers

    private func restGet<T>(_ path: String, retried: Bool = false) async throws -> T where T: Any {
        guard let url = URL(string: supabaseURL + path) else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request)
        let (data, response) = try await dataWithRetry(for: request)
        let http = response as? HTTPURLResponse
        // Auto-retry on 401 with token refresh
        if http?.statusCode == 401, !retried {
            let _ = try await refreshAccessToken()
            return try await restGet(path, retried: true)
        }
        guard let httpOK = http, (200...299).contains(httpOK.statusCode) else {
            throw APIError.httpError(status: http?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? T else {
            throw APIError.invalidResponse
        }
        return result
    }

    @discardableResult
    private func restPatch(_ path: String, body: [String: Any], retried: Bool = false) async throws -> Data {
        guard let url = URL(string: supabaseURL + path) else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await dataWithRetry(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 401, !retried {
            let _ = try await refreshAccessToken()
            return try await restPatch(path, body: body, retried: true)
        }
        guard let httpOK = http, (200...299).contains(httpOK.statusCode) else {
            throw APIError.httpError(status: http?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func rpc<T>(_ function: String, params: [String: Any], retried: Bool = false) async throws -> T where T: Any {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/\(function)") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        let (data, response) = try await dataWithRetry(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 401, !retried {
            let _ = try await refreshAccessToken()
            return try await rpc(function, params: params, retried: true)
        }
        guard let httpOK = http, (200...299).contains(httpOK.statusCode) else {
            throw APIError.httpError(status: http?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? T else {
            throw APIError.invalidResponse
        }
        return result
    }

    /// Execute a URLRequest with automatic retry on transient network errors.
    private func dataWithRetry(for request: URLRequest, maxRetries: Int = 2) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                return try await session.data(for: request)
            } catch let error as URLError where [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code) {
                lastError = error
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                }
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

public enum APIError: LocalizedError, Equatable {
    case invalidResponse
    case httpError(status: Int, body: String)
    case tokenExpired

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let status, let body):
            return "HTTP \(status): \(body)"
        case .tokenExpired:
            return "Session expired. Please sign in again."
        }
    }
}
