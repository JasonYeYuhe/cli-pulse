#if os(macOS)
import Foundation

/// Fetches quota/limit data from z.ai via REST API.
///
/// Endpoint: `GET https://api.z.ai/api/monitor/usage/quota/limit`
/// Auth: Bearer token from `Z_AI_API_KEY` env var or `config.apiKey`.
/// Regional: supports `Z_AI_API_HOST` override for BigModel CN.
public struct ZaiCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.zai

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveToken(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let token = resolveToken(config: config) else {
            throw CollectorError.missingCredentials("z.ai: no API key found")
        }
        let data = try await fetchQuota(token: token)
        let parsed = try ZaiCollector.parseResponse(data)
        return buildResult(parsed)
    }

    private func resolveToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["Z_AI_API_KEY"], !k.isEmpty { return k }
        return nil
    }

    private func fetchQuota(token: String) async throws -> Data {
        let fullURL: String
        if let override = ProcessInfo.processInfo.environment["Z_AI_QUOTA_URL"], !override.isEmpty {
            fullURL = override
        } else {
            let host = ProcessInfo.processInfo.environment["Z_AI_API_HOST"] ?? "api.z.ai"
            fullURL = "https://\(host)/api/monitor/usage/quota/limit"
        }
        guard let url = URL(string: fullURL) else { throw CollectorError.invalidURL(fullURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "z.ai")
        }
        return data
    }

    // MARK: - Parsing

    struct ZaiLimit: Sendable {
        let type: String       // TOKENS_LIMIT, TIME_LIMIT
        let usage: Int
        let remaining: Int
        let nextResetTime: Date?
    }

    struct ZaiUsage: Sendable {
        let limits: [ZaiLimit]
        let planName: String?
    }

    static func parseResponse(_ data: Data) throws -> ZaiUsage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any],
              let limitsArr = inner["limits"] as? [[String: Any]] else {
            throw CollectorError.parseFailed("z.ai: unexpected response structure")
        }

        let planName = inner["planName"] as? String
            ?? inner["plan"] as? String
            ?? inner["plan_type"] as? String

        let limits = limitsArr.compactMap { l -> ZaiLimit? in
            guard let type = l["type"] as? String else { return nil }
            let usage = l["usage"] as? Int ?? 0
            let remaining = l["remaining"] as? Int ?? 0
            var resetDate: Date? = nil
            if let ms = (l["nextResetTime"] as? NSNumber)?.doubleValue {
                resetDate = Date(timeIntervalSince1970: ms / 1000.0)
            }
            return ZaiLimit(type: type, usage: usage, remaining: remaining, nextResetTime: resetDate)
        }

        return ZaiUsage(limits: limits, planName: planName)
    }

    func buildResult(_ z: ZaiUsage) -> CollectorResult {
        let iso = sharedISO8601Formatter
        var tiers: [TierDTO] = []

        for limit in z.limits {
            let name: String
            switch limit.type {
            case "TOKENS_LIMIT": name = "Tokens"
            case "TIME_LIMIT": name = "Time"
            default: name = limit.type
            }
            let total = limit.usage + limit.remaining
            tiers.append(TierDTO(name: name, quota: total > 0 ? total : limit.usage,
                                 remaining: limit.remaining,
                                 reset_time: limit.nextResetTime.map { iso.string(from: $0) }))
        }

        let primary = z.limits.first
        let total = (primary?.usage ?? 0) + (primary?.remaining ?? 0)
        let usage = ProviderUsage(
            provider: ProviderKind.zai.rawValue,
            today_usage: primary?.usage ?? 0, week_usage: primary?.usage ?? 0,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: total > 0 ? total : nil, remaining: primary?.remaining,
            plan_type: z.planName, reset_time: primary?.nextResetTime.map { iso.string(from: $0) },
            tiers: tiers,
            status_text: primary.map { "\($0.usage)/\($0.usage + $0.remaining) used" } ?? "Unknown",
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "z.ai", category: "cloud",
                                       supports_exact_cost: false, supports_quota: true))
        return CollectorResult(usage: usage, dataKind: .quota)
    }
}
#endif
