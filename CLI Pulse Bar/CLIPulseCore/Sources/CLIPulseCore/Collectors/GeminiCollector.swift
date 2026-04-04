#if os(macOS)
import Foundation

/// Fetches real per-model quota data from Google Gemini via OAuth credentials.
///
/// Auth priority:
///   1. Keychain — CLI Pulse's own OAuth tokens (via GeminiOAuthManager)
///   2. File — `~/.gemini/oauth_creds.json` (Gemini CLI compatibility fallback)
///
/// Quota: `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`
/// Tier:  `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`
public struct GeminiCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.gemini

    public func isAvailable(config: ProviderConfig) -> Bool {
        let creds = readCredentials()
        return creds?.accessToken != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard var creds = readCredentials(), creds.accessToken != nil else {
            throw CollectorError.missingCredentials("Gemini: no credentials found")
        }

        // Refresh if expired
        if creds.isExpired {
            if let refreshed = try? await refreshToken(creds: creds) {
                creds = refreshed
                // Only persist back to file for file-sourced credentials
                if creds.source == .file { persistCredentials(creds) }
            } else if creds.source == .keychain {
                // Keychain refresh failed — fall back to file credentials
                if let fileCreds = readFileCredentials(), !fileCreds.isExpired {
                    creds = fileCreds
                }
            }
        }

        guard let token = creds.accessToken, !creds.isExpired else {
            throw CollectorError.missingCredentials("Gemini: token expired — reconnect via CLI Pulse OAuth")
        }

        // Fetch tier info for plan detection
        let tierInfo = try? await fetchTierInfo(token: token)

        // Discover project ID
        let projectId = tierInfo?.projectId

        // Fetch quota buckets
        let buckets = try await fetchQuota(token: token, projectId: projectId)

        return buildResult(buckets: buckets, tierInfo: tierInfo)
    }

    // MARK: - Credentials

    enum TokenSource { case keychain, file }

    struct GeminiCreds {
        var accessToken: String?
        var refreshToken: String?
        var idToken: String?
        var expiryDate: Date?
        var source: TokenSource = .file

        var isExpired: Bool {
            guard let exp = expiryDate else { return true }
            return exp < Date()
        }
    }

    private func credsPath() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".gemini/oauth_creds.json")
    }

    func readCredentials() -> GeminiCreds? {
        // Priority 1: Keychain tokens (CLI Pulse's own OAuth flow)
        if let stored = GeminiOAuthManager.shared.loadTokens() {
            return GeminiCreds(
                accessToken: stored.accessToken,
                refreshToken: stored.refreshToken,
                expiryDate: stored.expiry,
                source: .keychain
            )
        }

        // Priority 2: Gemini CLI's credential file (compatibility fallback)
        return readFileCredentials()
    }

    /// Read credentials from `~/.gemini/oauth_creds.json` only.
    private func readFileCredentials() -> GeminiCreds? {
        let path = credsPath()
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var creds = GeminiCreds(source: .file)
        creds.accessToken = json["access_token"] as? String
        creds.refreshToken = json["refresh_token"] as? String
        creds.idToken = json["id_token"] as? String
        if let expMs = (json["expiry_date"] as? NSNumber)?.doubleValue {
            creds.expiryDate = Date(timeIntervalSince1970: expMs / 1000.0)
        }
        return creds
    }

    private func persistCredentials(_ creds: GeminiCreds) {
        let path = credsPath()
        guard let existingData = FileManager.default.contents(atPath: path),
              var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] else { return }
        if let at = creds.accessToken { json["access_token"] = at }
        if let it = creds.idToken { json["id_token"] = it }
        if let exp = creds.expiryDate { json["expiry_date"] = Int64(exp.timeIntervalSince1970 * 1000) }
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Token refresh

    private func refreshToken(creds: GeminiCreds) async throws -> GeminiCreds {
        switch creds.source {
        case .keychain:
            // Refresh via CLI Pulse's own OAuth client (PKCE, no secret needed)
            let newToken = try await GeminiOAuthManager.shared.refreshAccessToken()
            var updated = creds
            updated.accessToken = newToken
            // Reload expiry from Keychain after refresh
            if let stored = GeminiOAuthManager.shared.loadTokens() {
                updated.expiryDate = stored.expiry
            }
            return updated

        case .file:
            // File-based tokens from Gemini CLI cannot be refreshed without the CLI's
            // client credentials. User should connect via CLI Pulse OAuth instead.
            throw CollectorError.missingCredentials(
                "Gemini: file-based token expired — connect via CLI Pulse OAuth to enable auto-refresh"
            )
        }
    }

    // MARK: - Tier info

    struct TierInfo {
        let tierId: String?  // "free-tier", "standard-tier", "legacy-tier"
        let projectId: String?
    }

    private func fetchTierInfo(token: String) async throws -> TierInfo {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist") else {
            throw CollectorError.invalidURL("loadCodeAssist")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Gemini")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Gemini loadCodeAssist: invalid JSON")
        }

        let tier = (json["currentTier"] as? [String: Any])?["id"] as? String
        var projectId: String? = nil
        if let proj = json["cloudaicompanionProject"] as? String {
            projectId = proj
        } else if let projObj = json["cloudaicompanionProject"] as? [String: Any] {
            projectId = projObj["projectId"] as? String ?? projObj["id"] as? String
        }

        return TierInfo(tierId: tier, projectId: projectId)
    }

    // MARK: - Quota API

    struct QuotaBucket: Sendable {
        let modelId: String
        let remainingFraction: Double  // 0.0 to 1.0
        let resetTime: String?
    }

    private func fetchQuota(token: String, projectId: String?) async throws -> [QuotaBucket] {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota") else {
            throw CollectorError.invalidURL("retrieveUserQuota")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        var body: [String: Any] = [:]
        if let pid = projectId { body["project"] = pid }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Gemini")
        }

        return try GeminiCollector.parseQuota(data)
    }

    // MARK: - Parsing (internal for testing)

    static func parseQuota(_ data: Data) throws -> [QuotaBucket] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["buckets"] as? [[String: Any]] else {
            throw CollectorError.parseFailed("Gemini quota: no buckets array")
        }

        // Global resetTime fallback (some responses put it at root level)
        let globalResetTime = json["resetTime"] as? String
            ?? json["reset_time"] as? String
            ?? json["quotaResetTime"] as? String

        return buckets.compactMap { b in
            guard let modelId = b["modelId"] as? String else { return nil }
            let fraction = (b["remainingFraction"] as? NSNumber)?.doubleValue ?? 1.0
            // Google API may use different key names for reset time
            let resetTime = b["resetTime"] as? String
                ?? b["reset_time"] as? String
                ?? b["resetAt"] as? String
                ?? b["quotaResetTime"] as? String
                ?? globalResetTime
            return QuotaBucket(modelId: modelId, remainingFraction: fraction, resetTime: resetTime)
        }
    }

    // MARK: - Result building

    func buildResult(buckets: [QuotaBucket], tierInfo: TierInfo?) -> CollectorResult {
        // Group by model family, keep lowest remaining fraction per family
        var familyBest: [String: (fraction: Double, resetTime: String?)] = [:]

        for bucket in buckets {
            let family = classifyModel(bucket.modelId)
            if let existing = familyBest[family] {
                if bucket.remainingFraction < existing.fraction {
                    familyBest[family] = (bucket.remainingFraction, bucket.resetTime)
                }
            } else {
                familyBest[family] = (bucket.remainingFraction, bucket.resetTime)
            }
        }

        let preferredOrder = ["Pro", "Flash", "Flash Lite"]
        var tiers: [TierDTO] = []
        for family in preferredOrder {
            guard let info = familyBest[family] else { continue }
            let percentLeft = Int(info.fraction * 100)
            tiers.append(TierDTO(
                name: family,
                quota: 100,
                remaining: max(0, percentLeft),
                reset_time: info.resetTime
            ))
        }
        for family in familyBest.keys.sorted() where !preferredOrder.contains(family) {
            guard let info = familyBest[family] else { continue }
            let percentLeft = Int(info.fraction * 100)
            tiers.append(TierDTO(
                name: family,
                quota: 100,
                remaining: max(0, percentLeft),
                reset_time: info.resetTime
            ))
        }

        // Plan type from tier ID
        let planType: String
        switch tierInfo?.tierId {
        case "standard-tier": planType = "Paid"
        case "free-tier": planType = "Free"
        case "legacy-tier": planType = "Legacy"
        default: planType = "Unknown"
        }

        // Overall: match CodexBar semantics by treating Pro as the primary Gemini window,
        // then Flash, then Flash Lite as fallback when Pro is unavailable.
        let primaryFamily = preferredOrder.first(where: { familyBest[$0] != nil })
        let primary = primaryFamily.flatMap { familyBest[$0] }
        let overallRemaining = primary.map { Int($0.fraction * 100) }
            ?? familyBest.values.map { Int($0.fraction * 100) }.min()
            ?? 100
        let overallReset = primary?.resetTime
            ?? familyBest.values.compactMap(\.resetTime).first

        let usage = ProviderUsage(
            provider: ProviderKind.gemini.rawValue,
            today_usage: 100 - overallRemaining,
            week_usage: 100 - overallRemaining,
            estimated_cost_today: 0,
            estimated_cost_week: 0,
            cost_status_today: "Unavailable",
            cost_status_week: "Unavailable",
            quota: 100,
            remaining: overallRemaining,
            plan_type: planType,
            reset_time: overallReset,
            tiers: tiers,
            status_text: "\(100 - overallRemaining)% used",
            trend: [],
            recent_sessions: [],
            recent_errors: [],
            metadata: ProviderMetadata(
                display_name: "Gemini",
                category: "cloud",
                supports_exact_cost: false,
                supports_quota: true
            )
        )

        return CollectorResult(usage: usage, dataKind: .quota)
    }

    private func classifyModel(_ modelId: String) -> String {
        let lower = modelId.lowercased()
        if lower.contains("flash-lite") || lower.contains("flash_lite") { return "Flash Lite" }
        if lower.contains("flash") { return "Flash" }
        if lower.contains("pro") { return "Pro" }
        return modelId  // Unknown model, use raw ID
    }
}
#endif
