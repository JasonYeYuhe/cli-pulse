#if os(macOS)
import Foundation

/// Fetches real credit balance and usage from OpenRouter's API.
///
/// Endpoints:
///   GET https://openrouter.ai/api/v1/credits  → { data: { total_credits, total_usage } }
///   GET https://openrouter.ai/api/v1/key      → { data: { limit, usage, rate_limit } }
///
/// Requires: `config.apiKey` set to a valid OpenRouter API key.
public struct OpenRouterCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.openRouter

    public func isAvailable(config: ProviderConfig) -> Bool {
        guard let key = config.apiKey, !key.isEmpty else { return false }
        return true
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw CollectorError.missingCredentials("OpenRouter API key not configured")
        }

        let baseURL = ProcessInfo.processInfo.environment["OPENROUTER_API_URL"]
            ?? "https://openrouter.ai/api/v1"

        // Fetch credits (primary)
        let credits = try await fetchCredits(baseURL: baseURL, apiKey: apiKey)

        // Fetch key info (optional — short timeout, non-fatal)
        let keyInfo = try? await fetchKeyInfo(baseURL: baseURL, apiKey: apiKey)

        return buildResult(credits: credits, keyInfo: keyInfo)
    }

    // MARK: - API calls

    private func fetchCredits(baseURL: String, apiKey: String) async throws -> CreditsResponse {
        guard let url = URL(string: "\(baseURL)/credits") else {
            throw CollectorError.invalidURL("\(baseURL)/credits")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CollectorError.httpError(status: status, provider: "OpenRouter")
        }
        return try OpenRouterCollector.parseCredits(data)
    }

    private func fetchKeyInfo(baseURL: String, apiKey: String) async throws -> KeyResponse {
        guard let url = URL(string: "\(baseURL)/key") else {
            throw CollectorError.invalidURL("\(baseURL)/key")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 3

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CollectorError.httpError(status: status, provider: "OpenRouter")
        }
        return try OpenRouterCollector.parseKeyInfo(data)
    }

    // MARK: - Parsing (internal for testing)

    struct CreditsResponse: Sendable {
        let totalCredits: Double
        let totalUsage: Double
        var balance: Double { max(0, totalCredits - totalUsage) }
    }

    struct KeyResponse: Sendable {
        let limit: Double?
        let usage: Double?
        let rateLimitRequests: Int?
        let rateLimitInterval: String?
    }

    static func parseCredits(_ data: Data) throws -> CreditsResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any] else {
            throw CollectorError.parseFailed("OpenRouter credits: unexpected JSON structure")
        }
        let totalCredits = (inner["total_credits"] as? NSNumber)?.doubleValue ?? 0
        let totalUsage = (inner["total_usage"] as? NSNumber)?.doubleValue ?? 0
        return CreditsResponse(totalCredits: totalCredits, totalUsage: totalUsage)
    }

    static func parseKeyInfo(_ data: Data) throws -> KeyResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any] else {
            throw CollectorError.parseFailed("OpenRouter key: unexpected JSON structure")
        }
        let limit = (inner["limit"] as? NSNumber)?.doubleValue
        let usage = (inner["usage"] as? NSNumber)?.doubleValue
        let rateLimit = inner["rate_limit"] as? [String: Any]
        return KeyResponse(
            limit: limit,
            usage: usage,
            rateLimitRequests: rateLimit?["requests"] as? Int,
            rateLimitInterval: rateLimit?["interval"] as? String
        )
    }

    // MARK: - Result building

    func buildResult(credits: CreditsResponse, keyInfo: KeyResponse?) -> CollectorResult {
        // Convert dollar credits to integer "token equivalent" for display compatibility.
        // Multiply by 100_000 so $1.00 = 100,000 units — matches the scale of token counts
        // shown for other providers in the UI.
        let scale = 100_000.0
        let quotaUnits = Int(credits.totalCredits * scale)
        let remainingUnits = Int(credits.balance * scale)
        let usedUnits = Int(credits.totalUsage * scale)

        var tiers: [TierDTO] = []
        tiers.append(TierDTO(
            name: "Credits",
            quota: quotaUnits,
            remaining: remainingUnits,
            reset_time: nil  // OpenRouter credits don't reset on a schedule
        ))

        // If key-level limit exists, add as a separate tier
        if let keyLimit = keyInfo?.limit, keyLimit > 0 {
            let keyUsage = keyInfo?.usage ?? 0
            let keyRemaining = max(0, keyLimit - keyUsage)
            tiers.append(TierDTO(
                name: "Key Limit",
                quota: Int(keyLimit * scale),
                remaining: Int(keyRemaining * scale),
                reset_time: nil
            ))
        }

        let usage = ProviderUsage(
            provider: ProviderKind.openRouter.rawValue,
            today_usage: usedUnits,
            week_usage: usedUnits,
            estimated_cost_today: credits.totalUsage,
            estimated_cost_week: credits.totalUsage,
            cost_status_today: "Exact",
            cost_status_week: "Exact",
            quota: quotaUnits,
            remaining: remainingUnits,
            plan_type: "Credits",
            reset_time: nil,
            tiers: tiers,
            status_text: String(format: "$%.2f / $%.2f", credits.balance, credits.totalCredits),
            trend: [],
            recent_sessions: [],
            recent_errors: [],
            metadata: ProviderMetadata(
                display_name: "OpenRouter",
                category: "aggregator",
                supports_exact_cost: true,
                supports_quota: true
            )
        )

        return CollectorResult(usage: usage, dataKind: .credits)
    }
}

// MARK: - Collector errors

public enum CollectorError: LocalizedError, Sendable {
    case missingCredentials(String)
    case invalidURL(String)
    case httpError(status: Int, provider: String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials(let msg): return msg
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .httpError(let status, let provider): return "\(provider) HTTP \(status)"
        case .parseFailed(let msg): return "Parse error: \(msg)"
        }
    }
}
#endif
