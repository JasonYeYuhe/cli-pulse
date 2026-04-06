import Foundation
import CryptoKit

public actor APIClient {
    private let supabaseURL: String
    private let supabaseAnonKey: String

    private var accessToken: String?
    private var refreshToken: String?
    public private(set) var userId: String?

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

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
        request.httpBody = try encoder.encode(RefreshTokenRequest(refresh_token: currentRefreshToken))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // Refresh failed — token is invalid
            self.accessToken = nil
            self.refreshToken = nil
            throw APIError.tokenExpired
        }

        let auth = try decode(SupabaseAuthResponse.self, from: data)
        let newAccess = auth.access_token
        let newRefresh = auth.refresh_token ?? currentRefreshToken

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

    private struct EmptyBody: Codable {}

    private struct RefreshTokenRequest: Encodable {
        let refresh_token: String
    }

    private struct AppleSignInRequest: Encodable {
        let provider: String
        let id_token: String
        let nonce: String?
        let name: String?
    }

    private struct SendOTPRequest: Encodable {
        let email: String
        let create_user: Bool
    }

    private struct VerifyOTPRequest: Encodable {
        let email: String
        let token: String
        let type: String
    }

    private struct PasswordSignInRequest: Encodable {
        let email: String
        let password: String
    }

    private struct PairingCodeRequest: Encodable {
        let code: String
        let user_id: String
        let created_at: String
        let expires_at: String
    }

    private struct AcknowledgeAlertRequest: Encodable {
        let acknowledged_at: String
        let is_read: Bool
    }

    private struct ResolveAlertRequest: Encodable {
        let is_resolved: Bool
    }

    private struct SnoozeAlertRequest: Encodable {
        let snoozed_until: String
    }

    private struct SupabaseUserMetadata: Decodable {
        let name: String?
    }

    private struct SupabaseUser: Decodable {
        let id: String
        let email: String?
        let user_metadata: SupabaseUserMetadata?
    }

    private struct SupabaseAuthResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let user: SupabaseUser?
    }

    private struct SupabaseProfileRecord: Decodable {
        let paired: Bool?
        let name: String?
        let email: String?
    }

    private struct DashboardSummaryPayload: Decodable {
        let today_usage: Int?
        let today_cost: Double?
        let active_sessions: Int?
        let online_devices: Int?
        let unresolved_alerts: Int?
        let today_sessions: Int?
    }

    private struct ProviderSummaryPayload: Decodable {
        let provider: String?
        let today_usage: Int?
        let total_usage: Int?
        let estimated_cost: Double?
        let quota: Int?
        let remaining: Int?
        let plan_type: String?
        let reset_time: String?
        let tiers: [TierDTO]?
    }

    private struct SessionDevicePayload: Decodable {
        let name: String?
    }

    private struct SessionRecordPayload: Decodable {
        let id: String?
        let name: String?
        let provider: String?
        let project: String?
        let devices: SessionDevicePayload?
        let started_at: String?
        let last_active_at: String?
        let status: String?
        let total_usage: Int?
        let estimated_cost: Double?
        let requests: Int?
        let error_count: Int?
        let collection_confidence: String?
    }

    private struct DeviceRecordPayload: Decodable {
        let id: String?
        let name: String?
        let type: String?
        let system: String?
        let status: String?
        let last_seen_at: String?
        let helper_version: String?
        let cpu_usage: Int?
        let memory_usage: Int?
    }

    private struct AlertRecordPayload: Decodable {
        let id: String?
        let type: String?
        let severity: String?
        let title: String?
        let message: String?
        let created_at: String?
        let is_read: Bool?
        let is_resolved: Bool?
        let acknowledged_at: String?
        let snoozed_until: String?
        let related_project_id: String?
        let related_project_name: String?
        let related_session_id: String?
        let related_session_name: String?
        let related_provider: String?
        let related_device_name: String?
        let source_kind: String?
        let source_id: String?
        let grouping_key: String?
        let suppression_key: String?
    }

    private struct SettingsPayload: Decodable {
        let notifications_enabled: Bool?
        let push_policy: String?
        let digest_notifications_enabled: Bool?
        let digest_interval_minutes: Int?
        let usage_spike_threshold: Int?
        let project_budget_threshold_usd: Double?
        let session_too_long_threshold_minutes: Int?
        let offline_grace_period_minutes: Int?
        let repeated_failure_threshold: Int?
        let alert_cooldown_minutes: Int?
        let data_retention_days: Int?
    }

    private struct UserTierPayload: Decodable {
        let tier: String?
    }

    private struct ValidateReceiptRequest: Encodable {
        let transactionJWS: String
        let productId: String
    }

    private struct ValidateReceiptResponse: Decodable {
        let verified: Bool
        let tier: String?
        let error: String?
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    private func fetchProfile(select: String) async throws -> SupabaseProfileRecord? {
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let profiles: [SupabaseProfileRecord] = try await restGet(
            "/rest/v1/profiles?id=eq.\(safeUserId)&select=\(select)"
        )
        return profiles.first
    }

    // MARK: - Auth (Sign in with Apple via Supabase)

    public func signInWithApple(identityToken: String, nonce: String? = nil, fullName: String?, email: String?) async throws -> AuthResponse {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=id_token") else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        request.httpBody = try encoder.encode(
            AppleSignInRequest(
                provider: "apple",
                id_token: identityToken,
                nonce: nonce,
                name: fullName
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }

        let auth = try decode(SupabaseAuthResponse.self, from: data)
        let token = auth.access_token
        let refresh = auth.refresh_token
        let user = auth.user

        self.accessToken = token
        self.refreshToken = refresh
        self.userId = user?.id

        let profile = try await fetchProfile(select: "paired")
        let paired = profile?.paired ?? false

        let name = fullName ?? user?.user_metadata?.name ?? ""
        let userEmail = email ?? user?.email ?? ""

        return AuthResponse(
            access_token: token,
            refresh_token: refresh,
            user: UserDTO(id: user?.id ?? "", name: name, email: userEmail),
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

        request.httpBody = try encoder.encode(SendOTPRequest(email: email, create_user: true))

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

        request.httpBody = try encoder.encode(VerifyOTPRequest(email: email, token: code, type: "email"))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: errorBody)
        }

        let auth = try decode(SupabaseAuthResponse.self, from: data)
        let token = auth.access_token
        let refresh = auth.refresh_token
        let user = auth.user

        self.accessToken = token
        self.refreshToken = refresh
        self.userId = user?.id

        let profile = try await fetchProfile(select: "paired,name,email")
        let paired = profile?.paired ?? false
        let profileName = profile?.name ?? ""
        let profileEmail = profile?.email ?? email

        return AuthResponse(
            access_token: token,
            refresh_token: refresh,
            user: UserDTO(id: user?.id ?? "", name: profileName, email: profileEmail),
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

        request.httpBody = try encoder.encode(PasswordSignInRequest(email: email, password: password))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: errorBody)
        }

        let auth = try decode(SupabaseAuthResponse.self, from: data)
        let token = auth.access_token
        let refresh = auth.refresh_token
        let user = auth.user

        self.accessToken = token
        self.refreshToken = refresh
        self.userId = user?.id

        let profile = try await fetchProfile(select: "paired,name,email")
        let paired = profile?.paired ?? false
        let profileName = profile?.name ?? ""
        let profileEmail = profile?.email ?? email

        return AuthResponse(
            access_token: token,
            refresh_token: refresh,
            user: UserDTO(id: user?.id ?? "", name: profileName, email: profileEmail),
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

        let user = try decode(SupabaseUser.self, from: data)
        self.userId = user.id

        let profile = try await fetchProfile(select: "paired,name,email")
        let paired = profile?.paired ?? false
        let name = profile?.name ?? user.user_metadata?.name ?? ""
        let email = profile?.email ?? user.email ?? ""

        return AuthResponse(
            access_token: accessToken ?? "",
            refresh_token: refreshToken,
            user: UserDTO(id: user.id, name: name, email: email),
            paired: paired
        )
    }

    // MARK: - Dashboard

    public func dashboard() async throws -> DashboardSummary {
        let summary: DashboardSummaryPayload = try await rpc("dashboard_summary")

        let todayUsage = summary.today_usage ?? 0
        let todayCost = summary.today_cost ?? 0
        let activeSessions = summary.active_sessions ?? 0
        let onlineDevices = summary.online_devices ?? 0
        let unresolvedAlerts = summary.unresolved_alerts ?? 0
        let todaySessions = summary.today_sessions ?? 0

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
        let providers: [ProviderSummaryPayload] = try await rpc("provider_summary")
        return providers.map { provider in
            return ProviderUsage(
                provider: provider.provider ?? "",
                today_usage: provider.today_usage ?? 0,
                week_usage: provider.total_usage ?? 0,
                estimated_cost_today: 0,
                estimated_cost_week: provider.estimated_cost ?? 0,
                cost_status_today: "Estimated",
                cost_status_week: "Estimated",
                quota: provider.quota,
                remaining: provider.remaining,
                plan_type: provider.plan_type,
                reset_time: provider.reset_time,
                tiers: provider.tiers ?? [],
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
        let rows: [SessionRecordPayload] = try await restGet(
            "/rest/v1/sessions?user_id=eq.\(safeUserId)&select=*,devices(name)&order=last_active_at.desc&limit=50"
        )
        return rows.map { row in
            return SessionRecord(
                id: row.id ?? "",
                name: row.name ?? "",
                provider: row.provider ?? "",
                project: row.project ?? "",
                device_name: row.devices?.name ?? "",
                started_at: row.started_at ?? "",
                last_active_at: row.last_active_at ?? "",
                status: row.status ?? "Running",
                total_usage: row.total_usage ?? 0,
                estimated_cost: row.estimated_cost ?? 0,
                cost_status: "Estimated",
                requests: row.requests ?? 0,
                error_count: row.error_count ?? 0,
                collection_confidence: row.collection_confidence
            )
        }
    }

    // MARK: - Devices

    public func devices() async throws -> [DeviceRecord] {
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let rows: [DeviceRecordPayload] = try await restGet(
            "/rest/v1/devices?user_id=eq.\(safeUserId)&select=*&order=last_seen_at.desc"
        )
        return rows.map { row in
            DeviceRecord(
                id: row.id ?? "",
                name: row.name ?? "",
                type: row.type ?? "macOS",
                system: row.system ?? "",
                status: row.status ?? "Offline",
                last_sync_at: row.last_seen_at,
                helper_version: row.helper_version ?? "",
                current_session_count: 0,
                cpu_usage: row.cpu_usage,
                memory_usage: row.memory_usage
            )
        }
    }

    // MARK: - Alerts

    public func alerts() async throws -> [AlertRecord] {
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let rows: [AlertRecordPayload] = try await restGet(
            "/rest/v1/alerts?user_id=eq.\(safeUserId)&select=*&order=created_at.desc&limit=50"
        )
        return rows.map { row in
            AlertRecord(
                id: row.id ?? "",
                type: row.type ?? "",
                severity: row.severity ?? "Info",
                title: row.title ?? "",
                message: row.message ?? "",
                created_at: row.created_at ?? "",
                is_read: row.is_read ?? false,
                is_resolved: row.is_resolved ?? false,
                acknowledged_at: row.acknowledged_at,
                snoozed_until: row.snoozed_until,
                related_project_id: row.related_project_id,
                related_project_name: row.related_project_name,
                related_session_id: row.related_session_id,
                related_session_name: row.related_session_name,
                related_provider: row.related_provider,
                related_device_name: row.related_device_name,
                source_kind: row.source_kind,
                source_id: row.source_id,
                grouping_key: row.grouping_key,
                suppression_key: row.suppression_key
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
        try await restPatch(
            "/rest/v1/alerts?id=eq.\(safeId)&user_id=eq.\(safeUserId)",
            body: AcknowledgeAlertRequest(
                acknowledged_at: Self.isoFormatter.string(from: Date()),
                is_read: true
            )
        )
        return SuccessResponse(ok: true)
    }

    public func resolveAlert(id: String) async throws -> SuccessResponse {
        let safeId = Self.sanitizeParam(id)
        let safeUserId = Self.sanitizeParam(userId ?? "")
        try await restPatch(
            "/rest/v1/alerts?id=eq.\(safeId)&user_id=eq.\(safeUserId)",
            body: ResolveAlertRequest(is_resolved: true)
        )
        return SuccessResponse(ok: true)
    }

    public func snoozeAlert(id: String, minutes: Int) async throws -> SuccessResponse {
        let safeId = Self.sanitizeParam(id)
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let snoozeUntil = Self.isoFormatter.string(from: Date().addingTimeInterval(Double(minutes) * 60))
        try await restPatch(
            "/rest/v1/alerts?id=eq.\(safeId)&user_id=eq.\(safeUserId)",
            body: SnoozeAlertRequest(snoozed_until: snoozeUntil)
        )
        return SuccessResponse(ok: true)
    }

    // MARK: - Settings

    public func settings() async throws -> SettingsSnapshot {
        let safeUserId = Self.sanitizeParam(userId ?? "")
        let rows: [SettingsPayload] = try await restGet("/rest/v1/user_settings?user_id=eq.\(safeUserId)&select=*")
        let settings = rows.first
        return SettingsSnapshot(
            notifications_enabled: settings?.notifications_enabled ?? true,
            push_policy: settings?.push_policy ?? "Warnings + Critical",
            digest_enabled: settings?.digest_notifications_enabled ?? true,
            digest_interval_hours: max(1, (settings?.digest_interval_minutes ?? 60) / 60),
            usage_spike_threshold: settings?.usage_spike_threshold ?? 500,
            project_budget_threshold_usd: settings?.project_budget_threshold_usd ?? 0.25,
            session_too_long_threshold_minutes: settings?.session_too_long_threshold_minutes ?? 180,
            offline_grace_period_minutes: settings?.offline_grace_period_minutes ?? 5,
            repeated_failure_threshold: settings?.repeated_failure_threshold ?? 3,
            alert_cooldown_minutes: settings?.alert_cooldown_minutes ?? 30,
            data_retention_days: settings?.data_retention_days ?? 7
        )
    }

    /// Update user settings on the server.
    public func updateSettings(_ patch: SettingsPatch) async throws {
        guard let uid = userId, Self.isValidUUID(uid) else { throw APIError.invalidResponse }
        let safeUid = Self.sanitizeParam(uid)
        _ = try await restPatch("/rest/v1/user_settings?user_id=eq.\(safeUid)", body: patch)
    }

    /// Encodable patch for user settings — only include fields you want to change.
    public struct SettingsPatch: Encodable {
        public var notifications_enabled: Bool?
        public var push_policy: String?
        public var usage_spike_threshold: Int?
        public var project_budget_threshold_usd: Double?
        public var session_too_long_threshold_minutes: Int?
        public var offline_grace_period_minutes: Int?
        public var data_retention_days: Int?
        public var webhook_url: String?
        public var webhook_enabled: Bool?

        public init(
            notifications_enabled: Bool? = nil,
            push_policy: String? = nil,
            usage_spike_threshold: Int? = nil,
            project_budget_threshold_usd: Double? = nil,
            session_too_long_threshold_minutes: Int? = nil,
            offline_grace_period_minutes: Int? = nil,
            data_retention_days: Int? = nil,
            webhook_url: String? = nil,
            webhook_enabled: Bool? = nil
        ) {
            self.notifications_enabled = notifications_enabled
            self.push_policy = push_policy
            self.usage_spike_threshold = usage_spike_threshold
            self.project_budget_threshold_usd = project_budget_threshold_usd
            self.session_too_long_threshold_minutes = session_too_long_threshold_minutes
            self.offline_grace_period_minutes = offline_grace_period_minutes
            self.data_retention_days = data_retention_days
            self.webhook_url = webhook_url
            self.webhook_enabled = webhook_enabled
        }
    }

    // MARK: - Webhook

    /// Invoke the send-webhook Edge Function for a given alert.
    public func sendWebhook(alert: AlertRecord) async throws {
        guard let uid = userId else { return }
        guard let url = URL(string: "\(supabaseURL)/functions/v1/send-webhook") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        let body: [String: Any] = [
            "user_id": uid,
            "alert": [
                "type": alert.type,
                "severity": alert.severity,
                "title": alert.title,
                "message": alert.message,
                "related_provider": alert.related_provider ?? "",
                "grouping_key": alert.grouping_key ?? "",
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await dataWithRetry(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Pairing

    public func pairingCode() async throws -> PairingInfo {
        let code = "PULSE-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).uppercased())"
        let now = Self.isoFormatter.string(from: Date())
        let expires = Self.isoFormatter.string(from: Date().addingTimeInterval(600))

        guard let uid = userId, Self.isValidUUID(uid) else { throw APIError.invalidResponse }
        guard let url = URL(string: "\(supabaseURL)/rest/v1/pairing_codes") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try encoder.encode(
            PairingCodeRequest(
                code: code,
                user_id: uid,
                created_at: now,
                expires_at: expires
            )
        )
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
        request.httpBody = try encoder.encode(EmptyBody())
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
            let response: UserTierPayload = try await rpc("get_user_tier")
            return response.tier ?? "free"
        } catch {
            return "free"
        }
    }

    /// Evaluate budget alerts server-side. Returns number of new alerts created.
    public func evaluateBudgetAlerts() async throws -> Int {
        struct BudgetResult: Decodable { let alerts_created: Int? }
        let result: BudgetResult = try await rpc("evaluate_budget_alerts")
        return result.alerts_created ?? 0
    }

    // MARK: - Teams

    public func createTeam(name: String) async throws -> TeamDTO {
        struct Params: Encodable { let p_name: String }
        struct Result: Decodable { let team_id: String; let name: String }
        let result: Result = try await rpc("create_team", params: Params(p_name: name))
        return TeamDTO(id: result.team_id, name: result.name, owner_id: userId ?? "", created_at: sharedISO8601Formatter.string(from: Date()), member_count: 1, role: "owner")
    }

    public func teamDetails(teamId: String) async throws -> TeamDetailDTO {
        struct Params: Encodable { let p_team_id: String }
        return try await rpc("team_details", params: Params(p_team_id: teamId))
    }

    public func myTeams() async throws -> [TeamDTO] {
        guard let uid = userId, Self.isValidUUID(uid) else { throw APIError.invalidResponse }
        let safeUid = Self.sanitizeParam(uid)
        return try await restGet("/rest/v1/team_members?user_id=eq.\(safeUid)&select=team_id,role,joined_at,teams(id,name,owner_id,created_at)")
    }

    public func inviteMember(teamId: String, email: String) async throws {
        struct Params: Encodable { let p_team_id: String; let p_email: String; let p_role: String }
        let _: [String: String] = try await rpc("invite_member", params: Params(p_team_id: teamId, p_email: email, p_role: "member"))
    }

    public func acceptInvite(inviteId: String) async throws {
        struct Params: Encodable { let p_invite_id: String }
        let _: [String: String] = try await rpc("accept_invite", params: Params(p_invite_id: inviteId))
    }

    public func removeMember(teamId: String, userId: String) async throws {
        struct Params: Encodable { let p_team_id: String; let p_user_id: String }
        let _: [String: String] = try await rpc("remove_member", params: Params(p_team_id: teamId, p_user_id: userId))
    }

    public func updateMemberRole(teamId: String, userId: String, role: String) async throws {
        struct Params: Encodable { let p_team_id: String; let p_user_id: String; let p_role: String }
        let _: [String: String] = try await rpc("update_member_role", params: Params(p_team_id: teamId, p_user_id: userId, p_role: role))
    }

    public func teamUsageSummary(teamId: String) async throws -> TeamUsageSummaryDTO {
        struct Params: Encodable { let p_team_id: String }
        return try await rpc("team_usage_summary", params: Params(p_team_id: teamId))
    }

    // MARK: - OAuth (Google / GitHub via Supabase)

    /// Build the Supabase OAuth authorization URL for a given provider with PKCE.
    /// Returns (authorizationURL, codeVerifier) — caller opens URL in browser/ASWebAuthenticationSession.
    public func oauthAuthorizeURL(provider: String, redirectTo: String) -> (URL, String)? {
        // Generate PKCE code verifier + challenge
        let verifier = generateCodeVerifier()
        guard let challenge = sha256Base64URL(verifier) else { return nil }

        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectTo),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else { return nil }
        return (url, verifier)
    }

    /// Exchange an OAuth authorization code for a Supabase session (PKCE flow).
    public func exchangeOAuthCode(code: String, codeVerifier: String) async throws -> AuthResponse {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=pkce") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        struct PKCEExchange: Encodable {
            let auth_code: String
            let code_verifier: String
        }
        request.httpBody = try encoder.encode(PKCEExchange(auth_code: code, code_verifier: codeVerifier))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }

        let auth = try decode(SupabaseAuthResponse.self, from: data)
        let token = auth.access_token
        let refresh = auth.refresh_token
        let user = auth.user

        self.accessToken = token
        self.refreshToken = refresh
        self.userId = user?.id

        let profile = try await fetchProfile(select: "paired,name,email")
        let paired = profile?.paired ?? false
        let name = profile?.name ?? user?.user_metadata?.name ?? ""
        let userEmail = profile?.email ?? user?.email ?? ""

        return AuthResponse(
            access_token: token,
            refresh_token: refresh,
            user: UserDTO(id: user?.id ?? "", name: name, email: userEmail),
            paired: paired
        )
    }

    /// Exchange a Google ID token for a Supabase session (same as Apple flow).
    public func signInWithGoogle(idToken: String, nonce: String? = nil, name: String?, email: String?) async throws -> AuthResponse {
        guard let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=id_token") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        struct GoogleSignInRequest: Encodable {
            let provider: String
            let id_token: String
            let nonce: String?
            let name: String?
        }
        request.httpBody = try encoder.encode(GoogleSignInRequest(provider: "google", id_token: idToken, nonce: nonce, name: name))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }

        let auth = try decode(SupabaseAuthResponse.self, from: data)
        let token = auth.access_token
        let refresh = auth.refresh_token
        let user = auth.user

        self.accessToken = token
        self.refreshToken = refresh
        self.userId = user?.id

        let profile = try await fetchProfile(select: "paired,name,email")
        let paired = profile?.paired ?? false
        let userName = name ?? profile?.name ?? user?.user_metadata?.name ?? ""
        let userEmail = email ?? profile?.email ?? user?.email ?? ""

        return AuthResponse(
            access_token: token,
            refresh_token: refresh,
            user: UserDTO(id: user?.id ?? "", name: userName, email: userEmail),
            paired: paired
        )
    }

    // PKCE helpers
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func sha256Base64URL(_ input: String) -> String? {
        guard let data = input.data(using: .utf8) else { return nil }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Receipt Validation

    /// Validate a StoreKit 2 JWS signed transaction server-side.
    /// Returns the verified tier from the server, or nil on failure.
    public func validateReceipt(transactionJWS: String, productId: String) async -> (verified: Bool, tier: String) {
        do {
            guard let url = URL(string: "\(supabaseURL)/functions/v1/validate-receipt") else {
                return (false, "free")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            applyHeaders(&request)
            request.httpBody = try encoder.encode(
                ValidateReceiptRequest(transactionJWS: transactionJWS, productId: productId)
            )
            let (data, response) = try await dataWithRetry(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return (false, "free")
            }
            let result = try decode(ValidateReceiptResponse.self, from: data)
            return (result.verified, result.tier ?? "free")
        } catch {
            return (false, "free")
        }
    }

    // MARK: - Provider Quota Sync

    #if os(macOS)
    /// Push locally collected provider quotas to Supabase (upsert into provider_quotas table).
    /// Non-throwing — sync failures are logged but not propagated.
    public func syncProviderQuotas(_ results: [CollectorResult]) async {
        guard let userId else { return }
        let quotaResults = results.filter { $0.dataKind == .quota || $0.dataKind == .credits }
        guard !quotaResults.isEmpty else { return }

        guard let url = URL(string: "\(supabaseURL)/rest/v1/provider_quotas") else { return }

        var rows: [[String: Any]] = []
        for r in quotaResults {
            let u = r.usage
            var row: [String: Any] = [
                "user_id": userId,
                "provider": u.provider,
                "remaining": u.remaining ?? 0,
                "updated_at": sharedISO8601Formatter.string(from: Date()),
            ]
            if let q = u.quota { row["quota"] = q }
            if let pt = u.plan_type { row["plan_type"] = pt }
            if let rt = u.reset_time { row["reset_time"] = rt }

            let tiersArr: [[String: Any]] = u.tiers.map { t in
                var d: [String: Any] = ["name": t.name, "quota": t.quota, "remaining": t.remaining]
                if let rt = t.reset_time { d["reset_time"] = rt }
                return d
            }
            row["tiers"] = tiersArr
            rows.append(row)
        }

        guard let body = try? JSONSerialization.data(withJSONObject: rows) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(status) {
                print("[syncProviderQuotas] failed: HTTP \(status)")
            }
        } catch {
            print("[syncProviderQuotas] error: \(error.localizedDescription)")
        }
    }
    #endif

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

    private func restGet<Response: Decodable>(_ path: String, retried: Bool = false) async throws -> Response {
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
        return try decode(Response.self, from: data)
    }

    @discardableResult
    private func restPatch<Body: Encodable>(_ path: String, body: Body, retried: Bool = false) async throws -> Data {
        guard let url = URL(string: supabaseURL + path) else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        applyHeaders(&request)
        request.httpBody = try encoder.encode(body)
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

    private func restPatch<Response: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        responseType: Response.Type,
        retried: Bool = false
    ) async throws -> Response {
        let data = try await restPatch(path, body: body, retried: retried)
        return try decode(responseType, from: data)
    }

    private func rpc<Response: Decodable>(_ function: String, retried: Bool = false) async throws -> Response {
        try await rpc(function, params: EmptyBody(), retried: retried)
    }

    private func rpc<Response: Decodable, Params: Encodable>(
        _ function: String,
        params: Params,
        retried: Bool = false
    ) async throws -> Response {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/\(function)") else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try encoder.encode(params)
        let (data, response) = try await dataWithRetry(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 401, !retried {
            let _ = try await refreshAccessToken()
            return try await rpc(function, params: params, retried: true)
        }
        guard let httpOK = http, (200...299).contains(httpOK.statusCode) else {
            throw APIError.httpError(status: http?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try decode(Response.self, from: data)
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
