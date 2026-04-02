#if os(macOS)
import Foundation

/// Fetches usage summary from Cursor via cookie-based session auth.
///
/// Endpoint: `GET https://cursor.com/api/usage-summary`
/// Auth: Cookie header — session cookies from browser import or manual `config.manualCookieHeader`.
///
/// NOTE: This collector requires browser session cookies. It does not support
/// API key auth. The cookies must contain a valid Cursor session token.
public struct CursorCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.cursor

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveCookie(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let cookie = resolveCookie(config: config) else {
            throw CollectorError.missingCredentials("Cursor: no session cookie configured")
        }
        let data = try await fetchUsageSummary(cookie: cookie)
        let parsed = try CursorCollector.parseResponse(data)
        return buildResult(parsed)
    }

    private func resolveCookie(config: ProviderConfig) -> String? {
        if let c = config.manualCookieHeader, !c.isEmpty { return c }
        if let c = ProcessInfo.processInfo.environment["CURSOR_COOKIE"], !c.isEmpty { return c }
        return nil
    }

    private func fetchUsageSummary(cookie: String) async throws -> Data {
        guard let url = URL(string: "https://cursor.com/api/usage-summary") else {
            throw CollectorError.invalidURL("cursor usage-summary")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Cursor")
        }
        return data
    }

    // MARK: - Parsing

    struct CursorUsage: Sendable {
        let membershipType: String?
        let planUsedCents: Int
        let planLimitCents: Int
        let planRemainingCents: Int
        let onDemandUsedCents: Int
        let onDemandLimitCents: Int?
        let billingCycleEnd: String?
        let totalPercentUsed: Double?
    }

    static func parseResponse(_ data: Data) throws -> CursorUsage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Cursor: invalid JSON")
        }

        let membership = json["membershipType"] as? String
        let cycleEnd = json["billingCycleEnd"] as? String

        let indiv = json["individualUsage"] as? [String: Any] ?? [:]
        let plan = indiv["plan"] as? [String: Any] ?? [:]
        let onDemand = indiv["onDemand"] as? [String: Any] ?? [:]

        let planUsed = plan["used"] as? Int ?? 0
        let planLimit = plan["limit"] as? Int ?? 0
        let planRemaining = plan["remaining"] as? Int ?? planLimit - planUsed
        let odUsed = onDemand["used"] as? Int ?? 0
        let odLimit = onDemand["limit"] as? Int
        let totalPct = (plan["totalPercentUsed"] as? NSNumber)?.doubleValue

        return CursorUsage(membershipType: membership, planUsedCents: planUsed,
                           planLimitCents: planLimit, planRemainingCents: planRemaining,
                           onDemandUsedCents: odUsed, onDemandLimitCents: odLimit,
                           billingCycleEnd: cycleEnd, totalPercentUsed: totalPct)
    }

    func buildResult(_ c: CursorUsage) -> CollectorResult {
        var tiers: [TierDTO] = []
        if c.planLimitCents > 0 {
            tiers.append(TierDTO(name: "Plan", quota: c.planLimitCents,
                                 remaining: c.planRemainingCents, reset_time: c.billingCycleEnd))
        }
        if let odLimit = c.onDemandLimitCents, odLimit > 0 {
            tiers.append(TierDTO(name: "On-Demand", quota: odLimit,
                                 remaining: max(0, odLimit - c.onDemandUsedCents),
                                 reset_time: c.billingCycleEnd))
        }

        let pctUsed = c.totalPercentUsed ?? (c.planLimitCents > 0
            ? Double(c.planUsedCents) / Double(c.planLimitCents) * 100.0 : 0)

        let usage = ProviderUsage(
            provider: ProviderKind.cursor.rawValue,
            today_usage: c.planUsedCents, week_usage: c.planUsedCents,
            estimated_cost_today: Double(c.onDemandUsedCents) / 100.0,
            estimated_cost_week: Double(c.onDemandUsedCents) / 100.0,
            cost_status_today: c.onDemandUsedCents > 0 ? "Exact" : "Unavailable",
            cost_status_week: c.onDemandUsedCents > 0 ? "Exact" : "Unavailable",
            quota: c.planLimitCents > 0 ? c.planLimitCents : nil,
            remaining: c.planRemainingCents,
            plan_type: c.membershipType?.capitalized ?? "Unknown",
            reset_time: c.billingCycleEnd, tiers: tiers,
            status_text: String(format: "%.0f%% used", pctUsed),
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "Cursor", category: "ide",
                                       supports_exact_cost: true, supports_quota: true))
        return CollectorResult(usage: usage, dataKind: .quota)
    }
}
#endif
