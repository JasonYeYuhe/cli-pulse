#if os(macOS)
import Foundation

/// Fetches usage/quota data from Volcano Engine (火山引擎) Ark platform.
///
/// Endpoint: `GET https://ark.cn-beijing.volces.com/api/v3/models`
/// Auth: Bearer token from `ARK_API_KEY` env var or `config.apiKey`.
///
/// The Ark platform uses OpenAI-compatible APIs for model inference.
/// Quota/billing management APIs at `open.volcengineapi.com` require AK/SK HMAC
/// signing which is more complex; this collector uses the simpler API key path.
public struct VolcanoEngineCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.volcanoEngine

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveToken(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let token = resolveToken(config: config) else {
            throw CollectorError.missingCredentials("Volcano Engine: no API key found")
        }
        let data = try await fetchUsage(token: token)
        let parsed = try VolcanoEngineCollector.parseUsageResponse(data)
        return buildResult(parsed)
    }

    // MARK: - Token Resolution

    private func resolveToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["ARK_API_KEY"], !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["VOLC_ACCESSKEY"], !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["VOLCANO_ENGINE_API_KEY"], !k.isEmpty { return k }
        return nil
    }

    // MARK: - Network

    private func fetchUsage(token: String) async throws -> Data {
        let host = ProcessInfo.processInfo.environment["ARK_API_HOST"]
            ?? "ark.cn-beijing.volces.com"
        let urlStr = "https://\(host)/api/v3/models"
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
                provider: "Volcano Engine"
            )
        }
        return data
    }

    // MARK: - Parsing

    struct VolcanoUsage: Sendable {
        let modelCount: Int
        let quota: Int
        let remaining: Int
        let endTime: String?
    }

    /// Parse the Ark API response.
    ///
    /// Supports two response shapes:
    /// 1. Models list: `{"data": [{"id": "...", ...}, ...]}` — counts available models
    /// 2. Usage/quota: `{"total": N, "remaining": N}` — direct quota info
    static func parseUsageResponse(_ data: Data) throws -> VolcanoUsage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Volcano Engine: invalid JSON")
        }

        // Shape 1: direct quota fields (preferred if available)
        if let total = json["total"] as? Int {
            let remaining = (json["remaining"] as? NSNumber)?.intValue ?? 0
            let endTime = json["end_time"] as? String ?? json["reset_time"] as? String
            return VolcanoUsage(modelCount: 0, quota: total, remaining: remaining, endTime: endTime)
        }

        // Shape 2: models list — use model count as a connectivity probe
        if let models = json["data"] as? [[String: Any]] {
            return VolcanoUsage(modelCount: models.count, quota: 0, remaining: 0, endTime: nil)
        }

        // Shape 3: wrapped in "result" or "Response"
        if let result = json["result"] as? [String: Any] ?? json["Response"] as? [String: Any] {
            let total = (result["total"] as? NSNumber)?.intValue ?? 0
            let remaining = (result["remaining"] as? NSNumber)?.intValue ?? 0
            let endTime = result["end_time"] as? String ?? result["reset_time"] as? String
            return VolcanoUsage(modelCount: 0, quota: total, remaining: remaining, endTime: endTime)
        }

        throw CollectorError.parseFailed("Volcano Engine: unexpected response structure")
    }

    // MARK: - Result Building

    func buildResult(_ u: VolcanoUsage) -> CollectorResult {
        let used = max(0, u.quota - u.remaining)
        var tiers: [TierDTO] = []
        if u.quota > 0 {
            tiers.append(TierDTO(name: "Ark Plan", quota: u.quota,
                                 remaining: u.remaining, reset_time: u.endTime))
        }

        let statusText: String
        if u.quota > 0 {
            statusText = "\(used)/\(u.quota) used"
        } else if u.modelCount > 0 {
            statusText = "\(u.modelCount) models available"
        } else {
            statusText = "Connected"
        }

        let usage = ProviderUsage(
            provider: ProviderKind.volcanoEngine.rawValue,
            today_usage: used, week_usage: used,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: u.quota > 0 ? u.quota : nil,
            remaining: u.quota > 0 ? u.remaining : nil,
            plan_type: nil, reset_time: u.endTime, tiers: tiers,
            status_text: statusText,
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "Volcano Engine (豆包)",
                                       category: "cloud",
                                       supports_exact_cost: false,
                                       supports_quota: true))
        let dataKind: CollectorDataKind = u.quota > 0 ? .quota : .statusOnly
        return CollectorResult(usage: usage, dataKind: dataKind)
    }
}
#endif
