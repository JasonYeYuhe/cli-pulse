#if os(macOS)
import Foundation

/// Fetches coding plan remaining quota from MiniMax via API token.
///
/// Endpoint: `GET https://api.minimax.io/v1/coding_plan/remains`
/// Auth: Bearer token from `MINIMAX_API_KEY` env var or `config.apiKey`.
/// Falls back to `MINIMAX_COOKIE` env var or `config.manualCookieHeader` for cookie auth.
///
/// NOTE: API token is the preferred and most stable auth method.
/// Cookie auth is less reliable (MiniMax often returns HTTP 1004 with cookies alone).
public struct MiniMaxCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.minimax

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveAPIToken(config: config) != nil || resolveCookie(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        if let token = resolveAPIToken(config: config) {
            let data = try await fetchRemainsAPI(token: token)
            let parsed = try MiniMaxCollector.parseRemainsResponse(data)
            return buildResult(parsed)
        }
        if let cookie = resolveCookie(config: config) {
            let data = try await fetchRemainsCookie(cookie: cookie)
            let parsed = try MiniMaxCollector.parseRemainsResponse(data)
            return buildResult(parsed)
        }
        throw CollectorError.missingCredentials("MiniMax: no API key or cookie found")
    }

    private func resolveAPIToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"], !k.isEmpty { return k }
        return nil
    }

    private func resolveCookie(config: ProviderConfig) -> String? {
        if let c = config.manualCookieHeader, !c.isEmpty { return c }
        if let c = ProcessInfo.processInfo.environment["MINIMAX_COOKIE"], !c.isEmpty { return c }
        if let c = ProcessInfo.processInfo.environment["MINIMAX_COOKIE_HEADER"], !c.isEmpty { return c }
        return nil
    }

    private func remainsURL() -> String {
        if let override = ProcessInfo.processInfo.environment["MINIMAX_REMAINS_URL"], !override.isEmpty {
            return override
        }
        let host = ProcessInfo.processInfo.environment["MINIMAX_HOST"] ?? "api.minimax.io"
        return "https://\(host)/v1/coding_plan/remains"
    }

    private func fetchRemainsAPI(token: String) async throws -> Data {
        guard let url = URL(string: remainsURL()) else { throw CollectorError.invalidURL("minimax remains") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CLIPulseBar", forHTTPHeaderField: "MM-API-Source")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "MiniMax")
        }
        return data
    }

    private func fetchRemainsCookie(cookie: String) async throws -> Data {
        let host = ProcessInfo.processInfo.environment["MINIMAX_HOST"] ?? "platform.minimax.io"
        let urlStr = "https://\(host)/v1/api/openplatform/coding_plan/remains"
        guard let url = URL(string: urlStr) else { throw CollectorError.invalidURL(urlStr) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "MiniMax")
        }
        return data
    }

    // MARK: - Parsing

    struct MiniMaxRemains: Sendable {
        let modelRemains: Int
        let total: Int
        let endTime: String?
    }

    static func parseRemainsResponse(_ data: Data) throws -> MiniMaxRemains {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("MiniMax: invalid JSON")
        }
        let remains = (json["model_remains"] as? NSNumber)?.intValue ?? 0
        let total = (json["total"] as? NSNumber)?.intValue ?? 0
        let endTime = json["end_time"] as? String ?? json["remains_time"] as? String
        return MiniMaxRemains(modelRemains: remains, total: total, endTime: endTime)
    }

    func buildResult(_ m: MiniMaxRemains) -> CollectorResult {
        let used = max(0, m.total - m.modelRemains)
        var tiers: [TierDTO] = []
        if m.total > 0 {
            tiers.append(TierDTO(name: "Coding Plan", quota: m.total,
                                 remaining: m.modelRemains, reset_time: m.endTime))
        }

        let usage = ProviderUsage(
            provider: ProviderKind.minimax.rawValue,
            today_usage: used, week_usage: used,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: m.total > 0 ? m.total : nil, remaining: m.modelRemains,
            plan_type: "Coding Plan", reset_time: m.endTime, tiers: tiers,
            status_text: m.total > 0 ? "\(used)/\(m.total) used" : "Unknown",
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "MiniMax", category: "cloud",
                                       supports_exact_cost: false, supports_quota: true))
        return CollectorResult(usage: usage, dataKind: .quota)
    }
}
#endif
