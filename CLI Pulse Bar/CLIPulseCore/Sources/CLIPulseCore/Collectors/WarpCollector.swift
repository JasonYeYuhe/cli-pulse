#if os(macOS)
import Foundation

/// Fetches request limits and bonus credits from Warp via GraphQL.
///
/// Endpoint: `POST https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo`
/// Auth: Bearer token from `WARP_API_KEY` or `WARP_TOKEN` env var, or `config.apiKey`.
public struct WarpCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.warp

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveToken(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let token = resolveToken(config: config) else {
            throw CollectorError.missingCredentials("Warp: no API key found")
        }
        let data = try await fetchGraphQL(token: token)
        let parsed = try WarpCollector.parseResponse(data)
        return buildResult(parsed)
    }

    private func resolveToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["WARP_API_KEY"], !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["WARP_TOKEN"], !k.isEmpty { return k }
        return nil
    }

    private static let query = """
    query GetRequestLimitInfo($requestContext:RequestContext!){user(requestContext:$requestContext){user{requestLimitInfo{isUnlimited nextRefreshTime requestLimit requestsUsedSinceLastRefresh}bonusGrants{requestCreditsGranted requestCreditsRemaining expiration}}}}
    """

    private func fetchGraphQL(token: String) async throws -> Data {
        guard let url = URL(string: "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo") else {
            throw CollectorError.invalidURL("warp graphql")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Warp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": Self.query,
            "variables": ["requestContext": [:] as [String: Any]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Warp")
        }
        return data
    }

    // MARK: - Parsing

    struct WarpUsage: Sendable {
        let isUnlimited: Bool
        let requestLimit: Int
        let requestsUsed: Int
        let nextRefreshTime: String?
        let bonusGranted: Int
        let bonusRemaining: Int
        let bonusExpiration: String?
    }

    static func parseResponse(_ data: Data) throws -> WarpUsage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let userOuter = dataObj["user"] as? [String: Any],
              let user = userOuter["user"] as? [String: Any],
              let rli = user["requestLimitInfo"] as? [String: Any] else {
            throw CollectorError.parseFailed("Warp: unexpected response structure")
        }

        let isUnlimited = rli["isUnlimited"] as? Bool ?? false
        let limit = rli["requestLimit"] as? Int ?? 0
        let used = rli["requestsUsedSinceLastRefresh"] as? Int ?? 0
        let refresh = rli["nextRefreshTime"] as? String

        var bonusGranted = 0, bonusRemaining = 0
        var bonusExp: String? = nil
        if let grants = user["bonusGrants"] as? [[String: Any]] {
            for g in grants {
                bonusGranted += g["requestCreditsGranted"] as? Int ?? 0
                bonusRemaining += g["requestCreditsRemaining"] as? Int ?? 0
                if bonusExp == nil { bonusExp = g["expiration"] as? String }
            }
        }

        return WarpUsage(isUnlimited: isUnlimited, requestLimit: limit, requestsUsed: used,
                         nextRefreshTime: refresh, bonusGranted: bonusGranted,
                         bonusRemaining: bonusRemaining, bonusExpiration: bonusExp)
    }

    func buildResult(_ w: WarpUsage) -> CollectorResult {
        var tiers: [TierDTO] = []
        if !w.isUnlimited && w.requestLimit > 0 {
            tiers.append(TierDTO(name: "Requests", quota: w.requestLimit,
                                 remaining: max(0, w.requestLimit - w.requestsUsed),
                                 reset_time: w.nextRefreshTime))
        }
        if w.bonusGranted > 0 {
            tiers.append(TierDTO(name: "Bonus Credits", quota: w.bonusGranted,
                                 remaining: w.bonusRemaining, reset_time: w.bonusExpiration))
        }

        let remaining = w.isUnlimited ? w.requestLimit : max(0, w.requestLimit - w.requestsUsed)
        let usage = ProviderUsage(
            provider: ProviderKind.warp.rawValue,
            today_usage: w.requestsUsed, week_usage: w.requestsUsed,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: w.isUnlimited ? nil : w.requestLimit, remaining: w.isUnlimited ? nil : remaining,
            plan_type: w.isUnlimited ? "Unlimited" : "Free",
            reset_time: w.nextRefreshTime, tiers: tiers,
            status_text: w.isUnlimited ? "Unlimited" : "\(w.requestsUsed)/\(w.requestLimit) used",
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "Warp", category: "cloud",
                                       supports_exact_cost: false, supports_quota: !w.isUnlimited))
        return CollectorResult(usage: usage, dataKind: .quota)
    }
}
#endif
