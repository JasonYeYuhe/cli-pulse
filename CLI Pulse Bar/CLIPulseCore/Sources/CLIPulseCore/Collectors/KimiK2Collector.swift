#if os(macOS)
import Foundation

/// Fetches credit balance from Kimi K2 via REST API.
///
/// Endpoint: `GET https://kimi-k2.ai/api/user/credits`
/// Auth: Bearer token from `KIMI_K2_API_KEY`, `KIMI_API_KEY`, `KIMI_KEY` env vars, or `config.apiKey`.
public struct KimiK2Collector: ProviderCollector, Sendable {
    public let kind = ProviderKind.kimiK2

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveToken(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let token = resolveToken(config: config) else {
            throw CollectorError.missingCredentials("Kimi K2: no API key found")
        }
        let data = try await fetchCredits(token: token)
        let parsed = try KimiK2Collector.parseResponse(data)
        return buildResult(parsed)
    }

    private func resolveToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        for env in ["KIMI_K2_API_KEY", "KIMI_API_KEY", "KIMI_KEY"] {
            if let k = ProcessInfo.processInfo.environment[env], !k.isEmpty { return k }
        }
        return nil
    }

    private func fetchCredits(token: String) async throws -> Data {
        guard let url = URL(string: "https://kimi-k2.ai/api/user/credits") else {
            throw CollectorError.invalidURL("kimi-k2 credits")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Kimi K2")
        }
        return data
    }

    // MARK: - Parsing

    struct KimiK2Credits: Sendable {
        let consumed: Double
        let remaining: Double
    }

    static func parseResponse(_ data: Data) throws -> KimiK2Credits {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Kimi K2: invalid JSON")
        }

        // Flexible field search — the API may nest under "data" or be flat
        let searchRoot: [String: Any]
        if let inner = json["data"] as? [String: Any] {
            // Check for nested usage object
            if let usage = inner["usage"] as? [String: Any] {
                return try extractCredits(from: usage)
            }
            return try extractCredits(from: inner)
        }
        searchRoot = json
        return try extractCredits(from: searchRoot)
    }

    private static let consumedKeys = [
        "total_credits_consumed", "totalCreditsConsumed", "total_credits_used",
        "credits_consumed", "creditsConsumed", "consumedCredits", "usedCredits",
        "consumed", "total", "used"
    ]
    private static let remainingKeys = [
        "credits_remaining", "creditsRemaining", "remaining_credits",
        "available_credits", "availableCredits", "credits_left",
        "remaining", "available", "balance"
    ]

    private static func extractCredits(from dict: [String: Any]) throws -> KimiK2Credits {
        var consumed: Double? = nil
        var remaining: Double? = nil

        for key in consumedKeys {
            if let v = (dict[key] as? NSNumber)?.doubleValue { consumed = v; break }
        }
        for key in remainingKeys {
            if let v = (dict[key] as? NSNumber)?.doubleValue { remaining = v; break }
        }

        guard consumed != nil || remaining != nil else {
            throw CollectorError.parseFailed("Kimi K2: no consumed/remaining fields found")
        }
        return KimiK2Credits(consumed: consumed ?? 0, remaining: remaining ?? 0)
    }

    func buildResult(_ c: KimiK2Credits) -> CollectorResult {
        let total = c.consumed + c.remaining
        let scale = 100_000.0
        var tiers: [TierDTO] = []
        if total > 0 {
            tiers.append(TierDTO(name: "Credits", quota: Int(total * scale),
                                 remaining: Int(c.remaining * scale), reset_time: nil))
        }

        let usage = ProviderUsage(
            provider: ProviderKind.kimiK2.rawValue,
            today_usage: Int(c.consumed * scale), week_usage: Int(c.consumed * scale),
            estimated_cost_today: c.consumed, estimated_cost_week: c.consumed,
            cost_status_today: "Exact", cost_status_week: "Exact",
            quota: total > 0 ? Int(total * scale) : nil,
            remaining: Int(c.remaining * scale),
            plan_type: "Credits", reset_time: nil, tiers: tiers,
            status_text: String(format: "%.2f / %.2f credits", c.remaining, total),
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "Kimi K2", category: "cloud",
                                       supports_exact_cost: true, supports_quota: true))
        return CollectorResult(usage: usage, dataKind: .credits)
    }
}
#endif
