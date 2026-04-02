#if os(macOS)
import Foundation

/// Fetches coding plan quota from Alibaba via REST API with region routing.
///
/// Endpoint: `POST {host}/data/api.json?action=...queryCodingPlanInstanceInfoV2...`
/// Auth: Bearer token from `ALIBABA_CODING_PLAN_API_KEY` env var or `config.apiKey`.
/// Regions: International (modelstudio.console.alibabacloud.com) → China fallback (bailian.console.aliyun.com).
public struct AlibabaCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.alibaba

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveToken(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let token = resolveToken(config: config) else {
            throw CollectorError.missingCredentials("Alibaba: no API key found")
        }

        // Try international first, fall back to China mainland
        do {
            let data = try await fetchQuota(token: token, host: "https://modelstudio.console.alibabacloud.com",
                                            commodityCode: "broadscope-bailian-intl")
            let parsed = try AlibabaCollector.parseResponse(data)
            return buildResult(parsed)
        } catch {
            let data = try await fetchQuota(token: token, host: "https://bailian.console.aliyun.com",
                                            commodityCode: "broadscope-bailian")
            let parsed = try AlibabaCollector.parseResponse(data)
            return buildResult(parsed)
        }
    }

    private func resolveToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["ALIBABA_CODING_PLAN_API_KEY"], !k.isEmpty { return k }
        return nil
    }

    private func fetchQuota(token: String, host: String, commodityCode: String) async throws -> Data {
        let path = "/data/api.json?action=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2&product=broadscope-bailian&api=queryCodingPlanInstanceInfoV2"
        guard let url = URL(string: host + path) else { throw CollectorError.invalidURL(host + path) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(token, forHTTPHeaderField: "x-api-key")
        request.setValue(token, forHTTPHeaderField: "X-DashScope-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "queryCodingPlanInstanceInfoRequest": ["commodityCode": commodityCode]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Alibaba")
        }
        return data
    }

    // MARK: - Parsing

    struct AlibabaQuota: Sendable {
        let planName: String?
        let fiveHourUsed: Int; let fiveHourTotal: Int; let fiveHourReset: String?
        let weeklyUsed: Int; let weeklyTotal: Int; let weeklyReset: String?
        let monthlyUsed: Int; let monthlyTotal: Int; let monthlyReset: String?
    }

    static func parseResponse(_ data: Data) throws -> AlibabaQuota {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any],
              let infos = inner["codingPlanInstanceInfos"] as? [[String: Any]],
              let first = infos.first else {
            throw CollectorError.parseFailed("Alibaba: no codingPlanInstanceInfos")
        }

        let planName = first["planName"] as? String ?? first["packageName"] as? String
        let q = first["codingPlanQuotaInfo"] as? [String: Any] ?? [:]

        return AlibabaQuota(
            planName: planName,
            fiveHourUsed: q["per5HourUsedQuota"] as? Int ?? 0,
            fiveHourTotal: q["per5HourTotalQuota"] as? Int ?? 0,
            fiveHourReset: q["per5HourQuotaNextRefreshTime"] as? String,
            weeklyUsed: q["perWeekUsedQuota"] as? Int ?? 0,
            weeklyTotal: q["perWeekTotalQuota"] as? Int ?? 0,
            weeklyReset: q["perWeekQuotaNextRefreshTime"] as? String,
            monthlyUsed: q["perBillMonthUsedQuota"] as? Int ?? 0,
            monthlyTotal: q["perBillMonthTotalQuota"] as? Int ?? 0,
            monthlyReset: q["perBillMonthQuotaNextRefreshTime"] as? String
        )
    }

    func buildResult(_ a: AlibabaQuota) -> CollectorResult {
        var tiers: [TierDTO] = []
        if a.fiveHourTotal > 0 {
            tiers.append(TierDTO(name: "5h Window", quota: a.fiveHourTotal,
                                 remaining: max(0, a.fiveHourTotal - a.fiveHourUsed),
                                 reset_time: a.fiveHourReset))
        }
        if a.weeklyTotal > 0 {
            tiers.append(TierDTO(name: "Weekly", quota: a.weeklyTotal,
                                 remaining: max(0, a.weeklyTotal - a.weeklyUsed),
                                 reset_time: a.weeklyReset))
        }
        if a.monthlyTotal > 0 {
            tiers.append(TierDTO(name: "Monthly", quota: a.monthlyTotal,
                                 remaining: max(0, a.monthlyTotal - a.monthlyUsed),
                                 reset_time: a.monthlyReset))
        }

        let primary = a.fiveHourTotal > 0 ? (a.fiveHourUsed, a.fiveHourTotal, a.fiveHourReset) : (a.monthlyUsed, a.monthlyTotal, a.monthlyReset)
        let usage = ProviderUsage(
            provider: ProviderKind.alibaba.rawValue,
            today_usage: primary.0, week_usage: a.weeklyUsed,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: primary.1 > 0 ? primary.1 : nil,
            remaining: primary.1 > 0 ? max(0, primary.1 - primary.0) : nil,
            plan_type: a.planName, reset_time: primary.2, tiers: tiers,
            status_text: primary.1 > 0 ? "\(primary.0)/\(primary.1) used" : "Unknown",
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "Alibaba Coding Plan", category: "cloud",
                                       supports_exact_cost: false, supports_quota: true))
        return CollectorResult(usage: usage, dataKind: .quota)
    }
}
#endif
