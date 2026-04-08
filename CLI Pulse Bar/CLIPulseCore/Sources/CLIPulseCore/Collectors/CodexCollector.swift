#if os(macOS)
import Foundation

/// Fetches real quota/rate-limit data from Codex (OpenAI) via the local OAuth
/// credentials stored in `~/.codex/auth.json`.
///
/// Data source: `GET https://chatgpt.com/backend-api/wham/usage`
/// Auth: Bearer token from local auth file, refreshed if stale.
///
/// Returns up to three tiers:
///   - "5h Window"  — primary rate limit (used_percent + reset_at)
///   - "Weekly"     — secondary rate limit
///   - "Credits"    — dollar balance (if account has credits)
public struct CodexCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.codex

    /// Available when `~/.codex/auth.json` contains an access token.
    public func isAvailable(config: ProviderConfig) -> Bool {
        let auth = readAuthFile()
        return auth?.accessToken != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard var auth = readAuthFile(), let accessToken = auth.accessToken else {
            throw CollectorError.missingCredentials("Codex auth.json not found or has no access token")
        }

        // Refresh token if stale (>8 days since last refresh)
        if auth.needsRefresh {
            if let refreshed = try? await refreshTokens(auth: auth) {
                auth = refreshed
                writeAuthFile(auth)
            }
            // Non-fatal: proceed with existing token even if refresh fails
        }

        guard let currentToken = auth.accessToken else {
            throw CollectorError.missingCredentials("Codex access token became nil after refresh")
        }
        let usageData = try await fetchUsage(accessToken: currentToken, accountId: auth.accountId)
        return buildResult(usage: usageData)
    }

    // MARK: - Auth file

    struct CodexAuth {
        var accessToken: String?
        var refreshToken: String?
        var idToken: String?
        var accountId: String?
        var lastRefresh: Date?

        var needsRefresh: Bool {
            guard lastRefresh != nil else { return true }
            guard let lr = lastRefresh else { return true }
            return Date().timeIntervalSince(lr) > 8 * 86400 // 8 days
        }
    }

    private func codexHomePath() -> String {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return env
        }
        return (realUserHome() as NSString).appendingPathComponent(".codex")
    }

    func readAuthFile() -> CodexAuth? {
        let path = (codexHomePath() as NSString).appendingPathComponent("auth.json")

        // Try sandbox-aware read first, then bridged credentials
        guard let data = SandboxFileAccess.read(path: path)
                ?? readFromBridgedCredentials(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let tokens = json["tokens"] as? [String: Any] ?? [:]
        var auth = CodexAuth()
        auth.accessToken = tokens["access_token"] as? String
        auth.refreshToken = tokens["refresh_token"] as? String
        auth.idToken = tokens["id_token"] as? String
        auth.accountId = tokens["account_id"] as? String

        if let lrStr = json["last_refresh"] as? String {
            auth.lastRefresh = sharedISO8601Formatter.date(from: lrStr)
        }

        // Fallback: check for direct API key
        if auth.accessToken == nil, let apiKey = json["OPENAI_API_KEY"] as? String, !apiKey.isEmpty {
            auth.accessToken = apiKey
        }

        return auth
    }

    /// Read Codex tokens from bridged credentials (app group) as fallback
    private func readFromBridgedCredentials() -> Data? {
        guard let creds = CredentialBridge.readBridgedCredentials(provider: "Codex"),
              let accessToken = creds["access_token"] as? String, !accessToken.isEmpty else {
            return nil
        }
        // Reconstruct the auth.json format so the existing parser works
        let reconstructed: [String: Any] = [
            "tokens": [
                "access_token": accessToken,
                "refresh_token": creds["refresh_token"] as? String ?? "",
                "id_token": creds["id_token"] as? String ?? "",
                "account_id": creds["account_id"] as? String ?? "",
            ],
            "last_refresh": creds["last_refresh"] as? String ?? "",
        ]
        return try? JSONSerialization.data(withJSONObject: reconstructed)
    }

    private func writeAuthFile(_ auth: CodexAuth) {
        let path = (codexHomePath() as NSString).appendingPathComponent("auth.json")
        guard let existingData = FileManager.default.contents(atPath: path),
              var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else { return }

        var tokens = json["tokens"] as? [String: Any] ?? [:]
        if let at = auth.accessToken { tokens["access_token"] = at }
        if let rt = auth.refreshToken { tokens["refresh_token"] = rt }
        if let it = auth.idToken { tokens["id_token"] = it }
        json["tokens"] = tokens
        json["last_refresh"] = sharedISO8601Formatter.string(from: Date())

        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Token refresh

    private static let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let refreshURL = "https://auth.openai.com/oauth/token"

    private func refreshTokens(auth: CodexAuth) async throws -> CodexAuth {
        guard let refreshToken = auth.refreshToken else {
            throw CollectorError.missingCredentials("Codex: no refresh token")
        }
        guard let url = URL(string: Self.refreshURL) else {
            throw CollectorError.invalidURL(Self.refreshURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CollectorError.httpError(status: status, provider: "Codex")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Codex token refresh: invalid JSON")
        }

        var updated = auth
        updated.accessToken = json["access_token"] as? String ?? auth.accessToken
        updated.refreshToken = json["refresh_token"] as? String ?? auth.refreshToken
        updated.idToken = json["id_token"] as? String ?? auth.idToken
        updated.lastRefresh = Date()
        return updated
    }

    // MARK: - Usage API

    private func fetchUsage(accessToken: String, accountId: String?) async throws -> UsageResponse {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw CollectorError.invalidURL("https://chatgpt.com/backend-api/wham/usage")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CLIPulseBar", forHTTPHeaderField: "User-Agent")
        if let aid = accountId, !aid.isEmpty {
            request.setValue(aid, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CollectorError.httpError(status: status, provider: "Codex")
        }

        return try CodexCollector.parseUsage(data)
    }

    // MARK: - Parsing (internal for testing)

    struct RateWindow: Sendable {
        let usedPercent: Int
        let resetAt: Date?
        let limitWindowSeconds: Int
    }

    struct Credits: Sendable {
        let hasCredits: Bool
        let unlimited: Bool
        let balance: Double?
    }

    struct UsageResponse: Sendable {
        let planType: String
        let primaryWindow: RateWindow?
        let secondaryWindow: RateWindow?
        let credits: Credits?
    }

    static func parseUsage(_ data: Data) throws -> UsageResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Codex usage: invalid JSON")
        }

        let planType = json["plan_type"] as? String ?? "unknown"
        let rateLimit = json["rate_limit"] as? [String: Any]

        let primaryWindow = parseWindow(rateLimit?["primary_window"] as? [String: Any])
        let secondaryWindow = parseWindow(rateLimit?["secondary_window"] as? [String: Any])

        var credits: Credits? = nil
        if let c = json["credits"] as? [String: Any] {
            credits = Credits(
                hasCredits: c["has_credits"] as? Bool ?? false,
                unlimited: c["unlimited"] as? Bool ?? false,
                balance: (c["balance"] as? NSNumber)?.doubleValue
            )
        }

        return UsageResponse(
            planType: planType,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            credits: credits
        )
    }

    private static func parseWindow(_ dict: [String: Any]?) -> RateWindow? {
        guard let d = dict else { return nil }
        // API may return used_percent as Int or Double
        let usedPercent: Int
        if let intVal = d["used_percent"] as? Int {
            usedPercent = intVal
        } else if let numVal = (d["used_percent"] as? NSNumber)?.doubleValue {
            usedPercent = Int(numVal.rounded())
        } else {
            usedPercent = 0
        }
        var resetDate: Date? = nil
        if let resetAt = (d["reset_at"] as? NSNumber)?.doubleValue {
            resetDate = Date(timeIntervalSince1970: resetAt)
        } else if let resetAtStr = d["reset_at"] as? String {
            // ISO 8601 string format
            resetDate = sharedISO8601Formatter.date(from: resetAtStr)
        }
        let windowSecs: Int
        if let intSecs = d["limit_window_seconds"] as? Int {
            windowSecs = intSecs
        } else if let numSecs = (d["limit_window_seconds"] as? NSNumber)?.intValue {
            windowSecs = numSecs
        } else {
            windowSecs = 0
        }
        return RateWindow(usedPercent: usedPercent, resetAt: resetDate, limitWindowSeconds: windowSecs)
    }

    // MARK: - Result building

    func buildResult(usage: UsageResponse) -> CollectorResult {
        var tiers: [TierDTO] = []
        let isoFormatter = sharedISO8601Formatter

        // Rate limit windows use percentage: quota=100, remaining=100-used
        if let pw = usage.primaryWindow {
            let name = "5h Window"
            tiers.append(TierDTO(
                name: name,
                quota: 100,
                remaining: max(0, 100 - pw.usedPercent),
                reset_time: pw.resetAt.map { isoFormatter.string(from: $0) }
            ))
        }

        if let sw = usage.secondaryWindow {
            let name = "Weekly"
            tiers.append(TierDTO(
                name: name,
                quota: 100,
                remaining: max(0, 100 - sw.usedPercent),
                reset_time: sw.resetAt.map { isoFormatter.string(from: $0) }
            ))
        }

        // Credits tier (dollar balance, scaled like OpenRouter for display)
        if let c = usage.credits, c.hasCredits, !c.unlimited, let balance = c.balance {
            // Scale: $1 = 100,000 units for UI display consistency
            let scale = 100_000.0
            let balanceUnits = Int(balance * scale)
            // We don't know total credit allocation, use balance as both quota and remaining
            tiers.append(TierDTO(
                name: "Credits",
                quota: balanceUnits,
                remaining: balanceUnits,
                reset_time: nil
            ))
        }

        // Overall quota from primary window (percentage-based)
        let overallQuota = 100
        let overallRemaining = usage.primaryWindow.map { max(0, 100 - $0.usedPercent) } ?? 100
        let resetTime = usage.primaryWindow?.resetAt.map { isoFormatter.string(from: $0) }

        // Status text
        let statusText: String
        if let pw = usage.primaryWindow {
            statusText = "\(pw.usedPercent)% used"
        } else {
            statusText = "Operational"
        }

        let providerUsage = ProviderUsage(
            provider: ProviderKind.codex.rawValue,
            today_usage: usage.primaryWindow?.usedPercent ?? 0,
            week_usage: usage.secondaryWindow?.usedPercent ?? 0,
            estimated_cost_today: 0,
            estimated_cost_week: 0,
            cost_status_today: "Unavailable",
            cost_status_week: "Unavailable",
            quota: overallQuota,
            remaining: overallRemaining,
            plan_type: usage.planType.capitalized,
            reset_time: resetTime,
            tiers: tiers,
            status_text: statusText,
            trend: [],
            recent_sessions: [],
            recent_errors: [],
            metadata: ProviderMetadata(
                display_name: "Codex",
                category: "cloud",
                supports_exact_cost: false,
                supports_quota: true
            )
        )

        return CollectorResult(usage: providerUsage, dataKind: .quota)
    }
}
#endif
