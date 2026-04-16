#if os(macOS)
import Foundation

/// Fetches usage/balance data from Zhipu AI (智谱AI) GLM platform.
///
/// Endpoint: `GET https://open.bigmodel.cn/api/paas/v4/models`
/// Auth: Bearer token from `GLM_API_KEY` env var or `config.apiKey`.
///
/// The GLM platform uses prepaid credits (CNY). This collector probes
/// connectivity via the models list endpoint.
public struct GLMCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.glm

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveToken(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let token = resolveToken(config: config) else {
            throw CollectorError.missingCredentials("GLM: no API key found")
        }
        let data = try await fetchModels(token: token)
        let parsed = try GLMCollector.parseModelsResponse(data)
        return buildResult(parsed)
    }

    // MARK: - Token Resolution

    private func resolveToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["GLM_API_KEY"], !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["ZHIPU_API_KEY"], !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["CHATGLM_API_KEY"], !k.isEmpty { return k }
        return nil
    }

    // MARK: - Network

    private func fetchModels(token: String) async throws -> Data {
        let host = ProcessInfo.processInfo.environment["GLM_API_HOST"]
            ?? "open.bigmodel.cn"
        let urlStr = "https://\(host)/api/paas/v4/models"
        guard let url = URL(string: urlStr) else {
            throw CollectorError.invalidURL(urlStr)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                provider: "GLM"
            )
        }
        return data
    }

    // MARK: - Parsing

    struct GLMUsage: Sendable {
        let modelCount: Int
        let balance: Double?
        let currency: String?
    }

    /// Parse the GLM API response.
    ///
    /// Supports multiple response shapes:
    /// 1. Models list: `{"data": [{"id": "...", ...}, ...]}` — counts available models
    /// 2. Balance info: `{"data": {"balance": 50.0, "currency": "CNY"}}` — credit balance
    static func parseModelsResponse(_ data: Data) throws -> GLMUsage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("GLM: invalid JSON")
        }

        // Shape 1: balance/credits (if finance endpoint is used)
        if let dataObj = json["data"] as? [String: Any],
           let balance = dataObj["balance"] as? Double
        {
            let currency = dataObj["currency"] as? String
            return GLMUsage(modelCount: 0, balance: balance, currency: currency)
        }

        // Shape 2: models list — use model count as a connectivity probe
        if let models = json["data"] as? [[String: Any]] {
            return GLMUsage(modelCount: models.count, balance: nil, currency: nil)
        }

        // Shape 3: wrapped in "result"
        if let result = json["result"] as? [String: Any] {
            let balance = result["balance"] as? Double
            let currency = result["currency"] as? String
            if balance != nil {
                return GLMUsage(modelCount: 0, balance: balance, currency: currency)
            }
        }

        throw CollectorError.parseFailed("GLM: unexpected response structure")
    }

    // MARK: - Result Building

    func buildResult(_ u: GLMUsage) -> CollectorResult {
        let statusText: String
        let dataKind: CollectorDataKind

        if let balance = u.balance {
            let currency = u.currency ?? "CNY"
            statusText = String(format: "%.2f %@ remaining", balance, currency)
            dataKind = .credits
        } else if u.modelCount > 0 {
            statusText = "\(u.modelCount) models available"
            dataKind = .statusOnly
        } else {
            statusText = "Connected"
            dataKind = .statusOnly
        }

        let usage = ProviderUsage(
            provider: ProviderKind.glm.rawValue,
            today_usage: 0, week_usage: 0,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: nil, remaining: nil,
            plan_type: nil, reset_time: nil, tiers: [],
            status_text: statusText,
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "GLM (智谱)",
                                       category: "cloud",
                                       supports_exact_cost: false,
                                       supports_quota: false))
        return CollectorResult(usage: usage, dataKind: dataKind)
    }
}
#endif
