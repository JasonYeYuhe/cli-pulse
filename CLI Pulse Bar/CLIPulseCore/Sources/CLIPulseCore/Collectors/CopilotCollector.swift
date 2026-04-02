#if os(macOS)
import Foundation

/// Fetches quota snapshots from GitHub Copilot via `copilot_internal/user` API.
///
/// Endpoint: `GET https://api.github.com/copilot_internal/user`
/// Auth: Bearer token from `COPILOT_API_TOKEN` env var or `config.apiKey`.
public struct CopilotCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.copilot

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveToken(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let token = resolveToken(config: config) else {
            throw CollectorError.missingCredentials("Copilot: no API token found")
        }
        let data = try await fetchUsage(token: token)
        let parsed = try CopilotCollector.parseResponse(data)
        return buildResult(parsed)
    }

    private func resolveToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["COPILOT_API_TOKEN"], !k.isEmpty { return k }
        return nil
    }

    private func fetchUsage(token: String) async throws -> Data {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            throw CollectorError.invalidURL("copilot_internal/user")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Copilot")
        }
        return data
    }

    // MARK: - Parsing

    struct CopilotUsage: Sendable {
        let plan: String
        let quotaResetDate: String?
        let premiumEntitlement: Double?
        let premiumRemaining: Double?
        let premiumPercentRemaining: Double?
        let chatEntitlement: Double?
        let chatRemaining: Double?
        let chatPercentRemaining: Double?
    }

    static func parseResponse(_ data: Data) throws -> CopilotUsage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Copilot: invalid JSON")
        }
        let plan = json["copilotPlan"] as? String ?? json["copilot_plan"] as? String ?? "unknown"
        let resetDate = json["quotaResetDate"] as? String ?? json["quota_reset_date"] as? String
        let snapshots = json["quotaSnapshots"] as? [String: Any]
            ?? json["quota_snapshots"] as? [String: Any] ?? [:]

        func extract(_ key: String) -> (Double?, Double?, Double?) {
            guard let s = snapshots[key] as? [String: Any] else { return (nil, nil, nil) }
            return ((s["entitlement"] as? NSNumber)?.doubleValue,
                    (s["remaining"] as? NSNumber)?.doubleValue,
                    (s["percentRemaining"] as? NSNumber)?.doubleValue
                        ?? (s["percent_remaining"] as? NSNumber)?.doubleValue)
        }

        let (pe, pr, pp) = extract("premiumInteractions")
        let (ce, cr, cp) = extract("chat")

        return CopilotUsage(plan: plan, quotaResetDate: resetDate,
                            premiumEntitlement: pe, premiumRemaining: pr, premiumPercentRemaining: pp,
                            chatEntitlement: ce, chatRemaining: cr, chatPercentRemaining: cp)
    }

    func buildResult(_ c: CopilotUsage) -> CollectorResult {
        var tiers: [TierDTO] = []

        if let ent = c.premiumEntitlement, ent > 0 {
            let remaining = c.premiumRemaining ?? (c.premiumPercentRemaining.map { $0 / 100.0 * ent } ?? ent)
            tiers.append(TierDTO(name: "Premium", quota: Int(ent), remaining: Int(remaining),
                                 reset_time: c.quotaResetDate))
        }
        if let ent = c.chatEntitlement, ent > 0 {
            let remaining = c.chatRemaining ?? (c.chatPercentRemaining.map { $0 / 100.0 * ent } ?? ent)
            tiers.append(TierDTO(name: "Chat", quota: Int(ent), remaining: Int(remaining),
                                 reset_time: c.quotaResetDate))
        }

        let overallQuota = c.premiumEntitlement.map { Int($0) }
        let overallRemaining = c.premiumRemaining.map { Int($0) }
        let statusText: String
        if let pct = c.premiumPercentRemaining {
            statusText = "\(Int(100 - pct))% used"
        } else {
            statusText = "Operational"
        }

        let usage = ProviderUsage(
            provider: ProviderKind.copilot.rawValue,
            today_usage: overallQuota.map { $0 - (overallRemaining ?? $0) } ?? 0,
            week_usage: overallQuota.map { $0 - (overallRemaining ?? $0) } ?? 0,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: overallQuota, remaining: overallRemaining,
            plan_type: c.plan.capitalized, reset_time: c.quotaResetDate, tiers: tiers,
            status_text: statusText, trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "GitHub Copilot", category: "ide",
                                       supports_exact_cost: false, supports_quota: true))
        return CollectorResult(usage: usage, dataKind: .quota)
    }
}
#endif
