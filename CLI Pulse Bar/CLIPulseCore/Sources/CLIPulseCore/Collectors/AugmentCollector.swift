#if os(macOS)
import Foundation

/// Fetches credit usage from Augment via cookie-based session auth.
///
/// Endpoints:
///   `GET https://app.augmentcode.com/api/credits`
///   `GET https://app.augmentcode.com/api/subscription`
/// Auth: Cookie header from `config.manualCookieHeader` or `AUGMENT_COOKIE` env var.
///
/// NOTE: Cookie-based auth. Requires browser session cookies from augmentcode.com.
public struct AugmentCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.augment

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolveCookie(config: config) != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let cookie = resolveCookie(config: config) else {
            throw CollectorError.missingCredentials("Augment: no session cookie configured")
        }
        let creditsData = try await fetchEndpoint(path: "/api/credits", cookie: cookie)
        let credits = try AugmentCollector.parseCredits(creditsData)
        let subData = try? await fetchEndpoint(path: "/api/subscription", cookie: cookie)
        let sub = subData.flatMap { try? AugmentCollector.parseSubscription($0) }
        return buildResult(credits: credits, subscription: sub)
    }

    private func resolveCookie(config: ProviderConfig) -> String? {
        if let c = config.manualCookieHeader, !c.isEmpty { return c }
        if let c = ProcessInfo.processInfo.environment["AUGMENT_COOKIE"], !c.isEmpty { return c }
        return nil
    }

    private func fetchEndpoint(path: String, cookie: String) async throws -> Data {
        guard let url = URL(string: "https://app.augmentcode.com\(path)") else {
            throw CollectorError.invalidURL("augment \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CollectorError.httpError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, provider: "Augment")
        }
        return data
    }

    // MARK: - Parsing

    struct AugmentCredits: Sendable {
        let remaining: Int
        let consumed: Int
        let available: Int
    }

    struct AugmentSubscription: Sendable {
        let planName: String?
        let billingPeriodEnd: String?
    }

    static func parseCredits(_ data: Data) throws -> AugmentCredits {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Augment credits: invalid JSON")
        }
        let remaining = (json["usageUnitsRemaining"] as? NSNumber)?.intValue ?? 0
        let consumed = (json["usageUnitsConsumedThisBillingCycle"] as? NSNumber)?.intValue ?? 0
        let available = (json["usageUnitsAvailable"] as? NSNumber)?.intValue ?? 0
        return AugmentCredits(remaining: remaining, consumed: consumed, available: available)
    }

    static func parseSubscription(_ data: Data) throws -> AugmentSubscription {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("Augment subscription: invalid JSON")
        }
        return AugmentSubscription(planName: json["planName"] as? String,
                                   billingPeriodEnd: json["billingPeriodEnd"] as? String)
    }

    func buildResult(credits: AugmentCredits, subscription: AugmentSubscription?) -> CollectorResult {
        let total = credits.remaining + credits.consumed
        var tiers: [TierDTO] = []
        if total > 0 {
            tiers.append(TierDTO(name: "Credits", quota: total, remaining: credits.remaining,
                                 reset_time: subscription?.billingPeriodEnd))
        }

        let usage = ProviderUsage(
            provider: ProviderKind.augment.rawValue,
            today_usage: credits.consumed, week_usage: credits.consumed,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: total > 0 ? total : nil, remaining: credits.remaining,
            plan_type: subscription?.planName, reset_time: subscription?.billingPeriodEnd,
            tiers: tiers,
            status_text: total > 0 ? "\(credits.consumed)/\(total) used" : "Operational",
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "Augment", category: "ide",
                                       supports_exact_cost: false, supports_quota: true))
        return CollectorResult(usage: usage, dataKind: .quota)
    }
}
#endif
