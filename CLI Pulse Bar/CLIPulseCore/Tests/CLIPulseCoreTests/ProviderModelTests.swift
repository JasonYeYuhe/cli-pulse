import XCTest
@testable import CLIPulseCore

final class ProviderModelTests: XCTestCase {

    // MARK: - ProviderKind

    func testAllTargetProvidersExist() {
        let expected: Set<String> = [
            "Codex", "Claude", "Gemini", "Cursor", "Copilot", "OpenCode",
            "Droid", "Antigravity", "z.ai", "MiniMax", "Augment",
            "JetBrains AI", "Kimi K2", "Amp", "Synthetic", "Warp",
            "Kilo", "Ollama", "OpenRouter", "Alibaba",
            "Kimi", "Kiro", "Vertex AI", "Perplexity",
        ]
        let actual = Set(ProviderKind.allCases.map(\.rawValue))
        XCTAssertEqual(expected, actual, "ProviderKind cases must match all target providers")
    }

    func testProviderKindRoundTripsViaJSON() throws {
        for kind in ProviderKind.allCases {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(ProviderKind.self, from: data)
            XCTAssertEqual(kind, decoded)
        }
    }

    func testProviderKindIconNamesAreNonEmpty() {
        for kind in ProviderKind.allCases {
            XCTAssertFalse(kind.iconName.isEmpty, "\(kind.rawValue) should have an icon")
        }
    }

    // MARK: - SourceType

    func testSourceTypeAllCases() {
        let expected: Set<String> = ["auto", "web", "cli", "oauth", "api", "local", "merged"]
        let actual = Set(SourceType.allCases.map(\.rawValue))
        XCTAssertEqual(expected, actual)
    }

    func testSourceTypeRoundTripsViaJSON() throws {
        for src in SourceType.allCases {
            let data = try JSONEncoder().encode(src)
            let decoded = try JSONDecoder().decode(SourceType.self, from: data)
            XCTAssertEqual(src, decoded)
        }
    }

    // MARK: - ProviderConfig

    func testProviderConfigDefaults() {
        let configs = ProviderConfig.defaults()
        XCTAssertEqual(configs.count, ProviderKind.allCases.count)
        for config in configs {
            XCTAssertTrue(config.isEnabled)
            XCTAssertEqual(config.sourceMode, .auto)
            XCTAssertNil(config.apiKey)
            XCTAssertNil(config.cookieSource)
            XCTAssertFalse(config.hasCredentials)
        }
    }

    func testProviderConfigHasCredentials() {
        var config = ProviderConfig(kind: .codex)
        XCTAssertFalse(config.hasCredentials)

        config.apiKey = "sk-test"
        XCTAssertTrue(config.hasCredentials)

        config.apiKey = nil
        config.cookieSource = .chrome
        XCTAssertTrue(config.hasCredentials)

        config.cookieSource = nil
        config.manualCookieHeader = "session=abc123"
        XCTAssertTrue(config.hasCredentials)
    }

    func testProviderConfigRoundTripsViaJSON() throws {
        let config = ProviderConfig(
            kind: .claude, isEnabled: false, sortOrder: 5,
            sourceMode: .oauth, apiKey: "key", cookieSource: .safari,
            manualCookieHeader: "x=1", accountLabel: "work"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: data)
        XCTAssertEqual(decoded.kind, .claude)
        XCTAssertFalse(decoded.isEnabled)
        XCTAssertEqual(decoded.sortOrder, 5)
        XCTAssertEqual(decoded.sourceMode, .oauth)
        XCTAssertEqual(decoded.cookieSource, .safari)
        XCTAssertEqual(decoded.accountLabel, "work")
    }

    func testProviderConfigSecretsExcludedFromJSON() throws {
        // Secrets (apiKey, manualCookieHeader) must NOT appear in JSON encoding
        let config = ProviderConfig(
            kind: .codex, apiKey: "sk-secret-key", manualCookieHeader: "session=abc"
        )
        let data = try JSONEncoder().encode(config)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(jsonString.contains("sk-secret-key"), "apiKey must not be in JSON")
        XCTAssertFalse(jsonString.contains("session=abc"), "manualCookieHeader must not be in JSON")
        XCTAssertFalse(jsonString.contains("apiKey"), "apiKey key must not be in JSON")
        XCTAssertFalse(jsonString.contains("manualCookieHeader"), "manualCookieHeader key must not be in JSON")

        // Decoding should leave secrets nil (they come from Keychain at runtime)
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: data)
        XCTAssertNil(decoded.apiKey)
        XCTAssertNil(decoded.manualCookieHeader)
    }

    // MARK: - ProviderRegistry

    func testRegistryCoversAllProviders() {
        for kind in ProviderKind.allCases {
            let desc = ProviderRegistry.descriptor(for: kind)
            XCTAssertEqual(desc.kind, kind)
            XCTAssertFalse(desc.displayName.isEmpty, "\(kind.rawValue) display name should not be empty")
            XCTAssertFalse(desc.supportedSources.isEmpty, "\(kind.rawValue) should support at least one source")
        }
    }

    func testRegistryCategories() {
        XCTAssertEqual(ProviderRegistry.descriptor(for: .ollama).category, .local)
        XCTAssertEqual(ProviderRegistry.descriptor(for: .openRouter).category, .aggregator)
        XCTAssertEqual(ProviderRegistry.descriptor(for: .cursor).category, .ide)
        XCTAssertEqual(ProviderRegistry.descriptor(for: .codex).category, .cloud)
    }

    // MARK: - TierDTO / UsageTier

    func testTierDTORoundTrips() throws {
        let tier = TierDTO(name: "Pro", quota: 1000, remaining: 250, reset_time: "2026-04-02T00:00:00Z")
        let data = try JSONEncoder().encode(tier)
        let decoded = try JSONDecoder().decode(TierDTO.self, from: data)
        XCTAssertEqual(decoded.name, "Pro")
        XCTAssertEqual(decoded.quota, 1000)
        XCTAssertEqual(decoded.remaining, 250)
        XCTAssertEqual(decoded.reset_time, "2026-04-02T00:00:00Z")
    }

    func testUsageTierPercentage() {
        let tier = UsageTier(name: "Pro", usage: 750, quota: 1000, remaining: 250, resetTime: nil)
        XCTAssertEqual(tier.usagePercent, 0.75, accuracy: 0.01)

        let noQuota = UsageTier(name: "Free", usage: 100, quota: nil, remaining: nil, resetTime: nil)
        XCTAssertEqual(noQuota.usagePercent, 0)

        let zeroQuota = UsageTier(name: "None", usage: 0, quota: 0, remaining: 0, resetTime: nil)
        XCTAssertEqual(zeroQuota.usagePercent, 0)
    }

    // MARK: - ProviderUsage

    func testProviderUsagePercent() {
        let usage = ProviderUsage(
            provider: "Codex", today_usage: 800, week_usage: 5000,
            estimated_cost_today: 0.10, estimated_cost_week: 0.50,
            cost_status_today: "Estimated", cost_status_week: "Estimated",
            quota: 1000, remaining: 200,
            status_text: "80% used", trend: [], recent_sessions: [], recent_errors: []
        )
        XCTAssertEqual(usage.usagePercent, 0.8, accuracy: 0.01)
        XCTAssertEqual(usage.providerKind, .codex)
    }

    func testProviderUsageNoQuota() {
        let usage = ProviderUsage(
            provider: "Ollama", today_usage: 100, week_usage: 500,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Estimated", cost_status_week: "Estimated",
            quota: nil, remaining: nil,
            status_text: "Running", trend: [], recent_sessions: [], recent_errors: []
        )
        XCTAssertEqual(usage.usagePercent, 0)
    }

    // MARK: - Provider Summary JSON Parsing (fixture)

    func testProviderSummaryParsing() throws {
        let json = """
        {
            "provider": "Gemini",
            "today_usage": 43400,
            "total_usage": 214000,
            "estimated_cost": 1.71,
            "quota": 300000,
            "remaining": 86000,
            "plan_type": "Free",
            "reset_time": "2026-04-02T07:00:00Z",
            "tiers": [
                {"name": "Pro", "quota": 200000, "remaining": 60000, "reset_time": "2026-04-02T07:00:00Z"},
                {"name": "Flash", "quota": 100000, "remaining": 26000, "reset_time": "2026-04-02T07:00:00Z"}
            ]
        }
        """.data(using: .utf8)!

        let p = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        // Simulate APIClient.providers() parsing
        var tiers: [TierDTO] = []
        if let tiersArray = p["tiers"] as? [[String: Any]] {
            tiers = tiersArray.map { t in
                TierDTO(
                    name: t["name"] as? String ?? "Default",
                    quota: t["quota"] as? Int ?? 0,
                    remaining: t["remaining"] as? Int ?? 0,
                    reset_time: t["reset_time"] as? String
                )
            }
        }

        let usage = ProviderUsage(
            provider: p["provider"] as? String ?? "",
            today_usage: p["today_usage"] as? Int ?? 0,
            week_usage: p["total_usage"] as? Int ?? 0,
            estimated_cost_today: 0,
            estimated_cost_week: (p["estimated_cost"] as? NSNumber)?.doubleValue ?? 0,
            cost_status_today: "Estimated",
            cost_status_week: "Estimated",
            quota: p["quota"] as? Int,
            remaining: p["remaining"] as? Int,
            plan_type: p["plan_type"] as? String,
            reset_time: p["reset_time"] as? String,
            tiers: tiers,
            status_text: "Operational",
            trend: [], recent_sessions: [], recent_errors: []
        )

        XCTAssertEqual(usage.provider, "Gemini")
        XCTAssertEqual(usage.providerKind, .gemini)
        XCTAssertEqual(usage.today_usage, 43400)
        XCTAssertEqual(usage.quota, 300000)
        XCTAssertEqual(usage.remaining, 86000)
        XCTAssertEqual(usage.plan_type, "Free")
        XCTAssertEqual(usage.tiers.count, 2)
        XCTAssertEqual(usage.tiers[0].name, "Pro")
        XCTAssertEqual(usage.tiers[0].quota, 200000)
        XCTAssertEqual(usage.tiers[1].name, "Flash")
    }

    // MARK: - CookieSource

    func testCookieSourceAllCases() {
        let expected: Set<String> = ["Safari", "Chrome", "Firefox", "Manual"]
        let actual = Set(CookieSource.allCases.map(\.rawValue))
        XCTAssertEqual(expected, actual)
    }

    // MARK: - LocalScanner detection (macOS only)

    #if os(macOS)
    func testDetectKimiVsKimiK2() {
        let scanner = LocalScanner.shared

        // Plain "kimi" must resolve to Kimi, not Kimi K2
        let kimiResult = scanner.detectProvider("/usr/local/bin/kimi --project foo")
        XCTAssertNotNil(kimiResult)
        XCTAssertEqual(kimiResult?.0, "Kimi")

        // "kimi k2" must resolve to Kimi K2
        let k2Result = scanner.detectProvider("/usr/local/bin/kimi k2 --project bar")
        XCTAssertNotNil(k2Result)
        XCTAssertEqual(k2Result?.0, "Kimi K2")

        // "kimi-k2" must resolve to Kimi K2
        let k2DashResult = scanner.detectProvider("kimi-k2 serve")
        XCTAssertNotNil(k2DashResult)
        XCTAssertEqual(k2DashResult?.0, "Kimi K2")

        // "kimi_k2" must resolve to Kimi K2
        let k2UnderResult = scanner.detectProvider("kimi_k2 --help")
        XCTAssertNotNil(k2UnderResult)
        XCTAssertEqual(k2UnderResult?.0, "Kimi K2")
    }

    func testDetectBasicProviders() {
        let scanner = LocalScanner.shared

        XCTAssertEqual(scanner.detectProvider("codex --help")?.0, "Codex")
        XCTAssertEqual(scanner.detectProvider("claude chat")?.0, "Claude")
        XCTAssertEqual(scanner.detectProvider("ollama serve")?.0, "Ollama")
        XCTAssertEqual(scanner.detectProvider("kiro start")?.0, "Kiro")
        XCTAssertEqual(scanner.detectProvider("perplexity query")?.0, "Perplexity")
        XCTAssertEqual(scanner.detectProvider("pplx search")?.0, "Perplexity")
        XCTAssertEqual(scanner.detectProvider("vertex-ai predict")?.0, "Vertex AI")
        XCTAssertNil(scanner.detectProvider("ls -la /tmp"))
    }
    #endif
}
