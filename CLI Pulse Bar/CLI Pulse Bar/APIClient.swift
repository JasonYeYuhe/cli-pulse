import Foundation

actor APIClient {
    private let supabaseURL = "https://gkjwsxotmwrgqsvfijzs.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdrandzeG90bXdyZ3FzdmZpanpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2OTAzNzAsImV4cCI6MjA5MDI2NjM3MH0.uPHYnh0psr2-KQynBw2NiQZOhz5eZiEaWpfCwdXrNQM"

    private var accessToken: String?
    private var userId: String?

    init(token: String? = nil) {
        self.accessToken = token
    }

    func updateToken(_ token: String?) {
        self.accessToken = token
    }

    func getToken() -> String? {
        return accessToken
    }

    // MARK: - Auth (Sign in with Apple via Supabase)

    func signInWithApple(identityToken: String, fullName: String?, email: String?) async throws -> AuthResponse {
        let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=id_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        var body: [String: Any] = [
            "provider": "apple",
            "id_token": identityToken
        ]
        if let fullName = fullName {
            body["name"] = fullName
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let token = json["access_token"] as? String ?? ""
        let user = json["user"] as? [String: Any] ?? [:]

        self.accessToken = token
        self.userId = user["id"] as? String

        // Check if user is paired
        let profile: [[String: Any]] = try await restGet("/rest/v1/profiles?id=eq.\(userId ?? "")&select=paired")
        let paired = profile.first?["paired"] as? Bool ?? false

        let name = fullName ?? (user["user_metadata"] as? [String: Any])?["name"] as? String ?? ""
        let userEmail = email ?? user["email"] as? String ?? ""

        return AuthResponse(
            access_token: token,
            user: UserDTO(id: userId ?? "", name: name, email: userEmail),
            paired: paired
        )
    }

    /// Legacy sign-in for demo/review (email-based, creates user via Supabase magic link or password)
    func signIn(email: String, name: String) async throws -> AuthResponse {
        // Use Supabase email sign-up/sign-in
        let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email, "password": "DemoReview2026!"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // Try sign-up if sign-in fails
            return try await signUp(email: email, name: name)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let token = json["access_token"] as? String ?? ""
        let user = json["user"] as? [String: Any] ?? [:]

        self.accessToken = token
        self.userId = user["id"] as? String

        let profile: [[String: Any]] = try await restGet("/rest/v1/profiles?id=eq.\(userId ?? "")&select=paired,name,email")
        let paired = profile.first?["paired"] as? Bool ?? false
        let profileName = profile.first?["name"] as? String ?? name
        let profileEmail = profile.first?["email"] as? String ?? email

        return AuthResponse(
            access_token: token,
            user: UserDTO(id: userId ?? "", name: profileName, email: profileEmail),
            paired: paired
        )
    }

    private func signUp(email: String, name: String) async throws -> AuthResponse {
        let url = URL(string: "\(supabaseURL)/auth/v1/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: Any] = [
            "email": email,
            "password": "DemoReview2026!",
            "data": ["name": name]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let token = json["access_token"] as? String ?? ""
        let user = json["user"] as? [String: Any] ?? [:]

        self.accessToken = token
        self.userId = user["id"] as? String

        return AuthResponse(
            access_token: token,
            user: UserDTO(id: userId ?? "", name: name, email: email),
            paired: false
        )
    }

    func me() async throws -> AuthResponse {
        let url = URL(string: "\(supabaseURL)/auth/v1/user")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }

        let user = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        self.userId = user["id"] as? String
        let metadata = user["user_metadata"] as? [String: Any] ?? [:]

        let profile: [[String: Any]] = try await restGet("/rest/v1/profiles?id=eq.\(userId ?? "")&select=paired,name,email")
        let paired = profile.first?["paired"] as? Bool ?? false
        let name = profile.first?["name"] as? String ?? metadata["name"] as? String ?? ""
        let email = profile.first?["email"] as? String ?? user["email"] as? String ?? ""

        return AuthResponse(
            access_token: accessToken ?? "",
            user: UserDTO(id: userId ?? "", name: name, email: email),
            paired: paired
        )
    }

    // MARK: - Dashboard

    func dashboard() async throws -> DashboardSummary {
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

    func providers() async throws -> [ProviderUsage] {
        let json: [[String: Any]] = try await rpc("provider_summary", params: [:])
        return json.map { p in
            ProviderUsage(
                provider: p["provider"] as? String ?? "",
                today_usage: p["today_usage"] as? Int ?? 0,
                week_usage: p["total_usage"] as? Int ?? 0,
                estimated_cost_today: 0,
                estimated_cost_week: (p["estimated_cost"] as? NSNumber)?.doubleValue ?? 0,
                cost_status_today: "Estimated",
                cost_status_week: "Estimated",
                quota: nil,
                remaining: p["remaining"] as? Int,
                status_text: "Operational",
                trend: [],
                recent_sessions: [],
                recent_errors: []
            )
        }
    }

    // MARK: - Sessions

    func sessions() async throws -> [SessionRecord] {
        let rows: [[String: Any]] = try await restGet(
            "/rest/v1/sessions?user_id=eq.\(userId ?? "")&select=*,devices(name)&order=last_active_at.desc&limit=50"
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
                error_count: r["error_count"] as? Int ?? 0
            )
        }
    }

    // MARK: - Devices

    func devices() async throws -> [DeviceRecord] {
        let rows: [[String: Any]] = try await restGet(
            "/rest/v1/devices?user_id=eq.\(userId ?? "")&select=*&order=last_seen_at.desc"
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

    func alerts() async throws -> [AlertRecord] {
        let rows: [[String: Any]] = try await restGet(
            "/rest/v1/alerts?user_id=eq.\(userId ?? "")&select=*&order=created_at.desc&limit=50"
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
                related_device_name: r["related_device_name"] as? String
            )
        }
    }

    func acknowledgeAlert(id: String) async throws -> SuccessResponse {
        try await restPatch("/rest/v1/alerts?id=eq.\(id)&user_id=eq.\(userId ?? "")", body: ["acknowledged_at": ISO8601DateFormatter().string(from: Date()), "is_read": true])
        return SuccessResponse(ok: true)
    }

    func resolveAlert(id: String) async throws -> SuccessResponse {
        try await restPatch("/rest/v1/alerts?id=eq.\(id)&user_id=eq.\(userId ?? "")", body: ["is_resolved": true])
        return SuccessResponse(ok: true)
    }

    func snoozeAlert(id: String, minutes: Int) async throws -> SuccessResponse {
        let snoozeUntil = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(minutes) * 60))
        try await restPatch("/rest/v1/alerts?id=eq.\(id)&user_id=eq.\(userId ?? "")", body: ["snoozed_until": snoozeUntil])
        return SuccessResponse(ok: true)
    }

    // MARK: - Settings

    func settings() async throws -> SettingsSnapshot {
        let rows: [[String: Any]] = try await restGet("/rest/v1/user_settings?user_id=eq.\(userId ?? "")&select=*")
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

    func pairingCode() async throws -> PairingInfo {
        let json: [String: Any] = try await rpc("generate_pairing_code", params: [:])
        let code = json["code"] as? String ?? ""
        return PairingInfo(
            code: code,
            install_command: "python3 cli_pulse_helper.py pair --pairing-code \(code)"
        )
    }

    func completePairing() async throws -> SuccessResponse {
        return SuccessResponse(ok: true)
    }

    // MARK: - Health

    func health() async throws -> Bool {
        let url = URL(string: "\(supabaseURL)/rest/v1/")!
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Supabase REST Helpers

    private func restGet<T>(_ path: String) async throws -> T where T: Any {
        let url = URL(string: supabaseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONSerialization.jsonObject(with: data) as! T
    }

    @discardableResult
    private func restPatch(_ path: String, body: [String: Any]) async throws -> Data {
        let url = URL(string: supabaseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func rpc<T>(_ function: String, params: [String: Any]) async throws -> T where T: Any {
        let url = URL(string: "\(supabaseURL)/rest/v1/rpc/\(function)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONSerialization.jsonObject(with: data) as! T
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let status, let body):
            return "HTTP \(status): \(body)"
        }
    }
}
