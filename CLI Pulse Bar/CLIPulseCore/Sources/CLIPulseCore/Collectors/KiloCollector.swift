#if os(macOS)
import Foundation

/// Fetches credit blocks and subscription usage from Kilo via tRPC batch API.
///
/// Endpoint: `GET https://app.kilo.ai/api/trpc/user.getCreditBlocks,kiloPass.getState?batch=1`
/// Auth: Bearer token from `KILO_API_KEY` env var, `config.apiKey`, or `~/.local/share/kilo/auth.json`.
public struct KiloCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.kilo

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveToken(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let token = resolveToken(config: config) else {
            throw CollectorError.missingCredentials("Kilo: no API key found")
        }
        let data = try await fetchBatch(token: token)
        let parsed = try KiloCollector.parseResponse(data)
        return buildResult(parsed)
    }

    private func resolveToken(config: ProviderConfig) -> String? {
        if let k = config.apiKey, !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["KILO_API_KEY"], !k.isEmpty { return k }
        // CLI session file fallback
        let authPath = (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/kilo/auth.json")
        if let data = FileManager.default.contents(atPath: authPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let kilo = json["kilo"] as? [String: Any],
           let token = kilo["access"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }

    private func fetchBatch(token: String) async throws -> Data {
        let inputJSON = #"{"0":{"json":null},"1":{"json":null}}"#
        let encoded = inputJSON.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? inputJSON
        let urlStr = "https://app.kilo.ai/api/trpc/user.getCreditBlocks,kiloPass.getState?batch=1&input=\(encoded)"
        guard let url = URL(string: urlStr) else { throw CollectorError.invalidURL("kilo trpc") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Kilo")
        }
        return data
    }

    // MARK: - Parsing

    struct KiloUsage: Sendable {
        let creditsTotalMuUsd: Int64
        let creditsRemainingMuUsd: Int64
        let subscriptionUsageUsd: Double?
        let subscriptionBaseUsd: Double?
        let subscriptionBonusUsd: Double?
        let tier: String?
        let nextBillingAt: String?
    }

    static func parseResponse(_ data: Data) throws -> KiloUsage {
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CollectorError.parseFailed("Kilo: expected JSON array")
        }

        // Procedure 0: user.getCreditBlocks
        var totalMu: Int64 = 0, remainingMu: Int64 = 0
        if let first = arr.first,
           let result = first["result"] as? [String: Any],
           let d = result["data"] as? [String: Any],
           let j = d["json"] as? [String: Any],
           let blocks = j["creditBlocks"] as? [[String: Any]] {
            for b in blocks {
                totalMu += (b["amount_mUsd"] as? NSNumber)?.int64Value ?? 0
                remainingMu += (b["balance_mUsd"] as? NSNumber)?.int64Value ?? 0
            }
        }

        // Procedure 1: kiloPass.getState
        var subUsage: Double? = nil, subBase: Double? = nil, subBonus: Double? = nil
        var tier: String? = nil, nextBilling: String? = nil
        if arr.count > 1,
           let second = arr.dropFirst().first,
           let result = second["result"] as? [String: Any],
           let d = result["data"] as? [String: Any],
           let j = d["json"] as? [String: Any],
           let sub = j["subscription"] as? [String: Any] {
            subUsage = (sub["currentPeriodUsageUsd"] as? NSNumber)?.doubleValue
            subBase = (sub["currentPeriodBaseCreditsUsd"] as? NSNumber)?.doubleValue
            subBonus = (sub["currentPeriodBonusCreditsUsd"] as? NSNumber)?.doubleValue
            tier = sub["tier"] as? String
            nextBilling = sub["nextBillingAt"] as? String
                ?? sub["nextRenewalAt"] as? String
                ?? sub["renewsAt"] as? String
        }

        return KiloUsage(creditsTotalMuUsd: totalMu, creditsRemainingMuUsd: remainingMu,
                         subscriptionUsageUsd: subUsage, subscriptionBaseUsd: subBase,
                         subscriptionBonusUsd: subBonus, tier: tier, nextBillingAt: nextBilling)
    }

    func buildResult(_ k: KiloUsage) -> CollectorResult {
        let scale = 1_000_000.0  // micro-USD to USD
        let creditsTotal = Double(k.creditsTotalMuUsd) / scale
        let creditsRemaining = Double(k.creditsRemainingMuUsd) / scale
        let displayScale = 100_000.0  // $1 = 100,000 display units

        var tiers: [TierDTO] = []
        if creditsTotal > 0 {
            tiers.append(TierDTO(name: "Credits", quota: Int(creditsTotal * displayScale),
                                 remaining: Int(creditsRemaining * displayScale), reset_time: nil))
        }
        if let base = k.subscriptionBaseUsd, let bonus = k.subscriptionBonusUsd {
            let subTotal = base + bonus
            let subUsed = k.subscriptionUsageUsd ?? 0
            let subRemaining = max(0, subTotal - subUsed)
            tiers.append(TierDTO(name: "Kilo Pass", quota: Int(subTotal * displayScale),
                                 remaining: Int(subRemaining * displayScale),
                                 reset_time: k.nextBillingAt))
        }

        let planName: String
        switch k.tier {
        case "tier_19": planName = "Starter"
        case "tier_49": planName = "Pro"
        case "tier_199": planName = "Expert"
        default: planName = k.tier ?? "Credits"
        }

        let usage = ProviderUsage(
            provider: ProviderKind.kilo.rawValue,
            today_usage: Int((creditsTotal - creditsRemaining) * displayScale),
            week_usage: Int((creditsTotal - creditsRemaining) * displayScale),
            estimated_cost_today: creditsTotal - creditsRemaining,
            estimated_cost_week: creditsTotal - creditsRemaining,
            cost_status_today: "Exact", cost_status_week: "Exact",
            quota: creditsTotal > 0 ? Int(creditsTotal * displayScale) : nil,
            remaining: Int(creditsRemaining * displayScale),
            plan_type: planName, reset_time: k.nextBillingAt, tiers: tiers,
            status_text: String(format: "$%.2f / $%.2f", creditsRemaining, creditsTotal),
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "Kilo", category: "cloud",
                                       supports_exact_cost: true, supports_quota: true))
        return CollectorResult(usage: usage, dataKind: .credits)
    }
}
#endif
