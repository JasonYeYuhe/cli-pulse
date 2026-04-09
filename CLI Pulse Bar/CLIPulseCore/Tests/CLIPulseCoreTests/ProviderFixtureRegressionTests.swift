#if os(macOS)
import XCTest
@testable import CLIPulseCore

final class ProviderFixtureRegressionTests: XCTestCase {

    private func assertTierNames(_ usage: ProviderUsage, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(usage.tiers.map(\.name), expected, file: file, line: line)
    }

    private func assertDataKind(_ result: CollectorResult, _ expected: CollectorDataKind, file: StaticString = #filePath, line: UInt = #line) {
        switch (result.dataKind, expected) {
        case (.quota, .quota), (.credits, .credits), (.statusOnly, .statusOnly):
            break
        default:
            XCTFail("Unexpected CollectorDataKind: \(result.dataKind), expected \(expected)", file: file, line: line)
        }
    }

    func testCodexFixtureProducesSessionWeeklyCard() throws {
        let json = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {"used_percent": 29, "reset_at": 1775100000, "limit_window_seconds": 18000},
            "secondary_window": {"used_percent": 29, "reset_at": 1775618400, "limit_window_seconds": 604800}
          }
        }
        """.data(using: .utf8)!

        let parsed = try CodexCollector.parseUsage(json)
        let result = CodexCollector().buildResult(usage: parsed)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Plus")
        XCTAssertEqual(result.usage.remaining, 71)
        assertTierNames(result.usage, ["5h Window", "Weekly"])
        XCTAssertEqual(result.usage.tiers.first?.remaining, 71)
    }

    func testGeminiFixturePrefersProAsPrimarySummary() throws {
        let json = """
        {
          "buckets": [
            {"modelId": "gemini-2.5-flash", "remainingFraction": 0.99, "resetTime": "2026-04-03T09:07:49Z"},
            {"modelId": "gemini-2.5-pro", "remainingFraction": 0.70, "resetTime": "2026-04-03T04:43:26Z"},
            {"modelId": "gemini-2.5-flash-lite", "remainingFraction": 0.99, "resetTime": "2026-04-03T09:04:08Z"}
          ]
        }
        """.data(using: .utf8)!

        let buckets = try GeminiCollector.parseQuota(json)
        let result = GeminiCollector().buildResult(
            buckets: buckets,
            tierInfo: GeminiCollector.TierInfo(tierId: "standard-tier", projectId: "fixture-project")
        )

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Paid")
        XCTAssertEqual(result.usage.remaining, 70)
        XCTAssertEqual(result.usage.reset_time, "2026-04-03T04:43:26Z")
        assertTierNames(result.usage, ["Pro", "Flash", "Flash Lite"])
    }

    func testOpenRouterFixtureStaysCreditsBased() throws {
        let creditsJSON = """
        {"data":{"total_credits":50.0,"total_usage":12.5}}
        """.data(using: .utf8)!
        let keyJSON = """
        {"data":{"limit":20.0,"usage":5.0}}
        """.data(using: .utf8)!

        let credits = try OpenRouterCollector.parseCredits(creditsJSON)
        let key = try OpenRouterCollector.parseKeyInfo(keyJSON)
        let result = OpenRouterCollector().buildResult(credits: credits, keyInfo: key)

        assertDataKind(result, .credits)
        XCTAssertEqual(result.usage.plan_type, "Credits")
        assertTierNames(result.usage, ["Credits", "Key Limit"])
        XCTAssertTrue(result.usage.status_text.contains("$37.50"))
    }

    func testClaudeFixtureProducesThreeQuotaBars() {
        let snapshot = ClaudeSnapshot(
            sessionUsed: 3,
            weeklyUsed: 77,
            opusUsed: nil,
            sonnetUsed: 5,
            sessionReset: "2026-04-02T12:00:00Z",
            weeklyReset: "2026-04-03T14:00:00Z",
            rateLimitTier: "default_claude_max_20x",
            accountEmail: "fixture@example.com",
            sourceLabel: "fixture"
        )

        let result = ClaudeResultBuilder.build(from: snapshot)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Max 20x")
        XCTAssertEqual(result.usage.remaining, 97)
        XCTAssertEqual(result.usage.reset_time, "2026-04-02T12:00:00Z")
        assertTierNames(result.usage, ["5h Window", "Weekly", "Sonnet only"])
    }

    func testJetBrainsFixtureProducesCreditsAndTariff() throws {
        let xml = """
        <application>
          <component name="AIAssistantQuotaManager">
            <option name="quotaInfo" value="{&quot;type&quot;:&quot;monthly&quot;,&quot;current&quot;:120,&quot;maximum&quot;:500,&quot;until&quot;:&quot;2026-05-01T00:00:00Z&quot;,&quot;tariffQuota&quot;:{&quot;available&quot;:200}}" />
            <option name="nextRefill" value="{&quot;next&quot;:&quot;2026-05-01T00:00:00Z&quot;}" />
          </component>
        </application>
        """

        let quota = try JetBrainsAICollector.parseQuotaXML(xml)
        let result = JetBrainsAICollector().buildResult(quota: quota)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Monthly")
        XCTAssertEqual(result.usage.remaining, 380)
        assertTierNames(result.usage, ["AI Credits", "Tariff Credits"])
    }

    func testCopilotFixtureKeepsPremiumBeforeChat() throws {
        let json = """
        {"copilotPlan":"pro","quotaResetDate":"2026-05-01T00:00:00Z","quotaSnapshots":{"premiumInteractions":{"entitlement":300,"remaining":200,"percentRemaining":66.7},"chat":{"entitlement":1000,"remaining":800,"percentRemaining":80.0}}}
        """.data(using: .utf8)!

        let parsed = try CopilotCollector.parseResponse(json)
        let result = CopilotCollector().buildResult(parsed)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Pro")
        XCTAssertEqual(result.usage.quota, 300)
        XCTAssertEqual(result.usage.remaining, 200)
        assertTierNames(result.usage, ["Premium", "Chat"])
    }

    func testCursorFixtureKeepsPlanThenOnDemand() throws {
        let json = """
        {"membershipType":"pro","billingCycleEnd":"2026-05-01T00:00:00Z","individualUsage":{"plan":{"used":5000,"limit":20000,"remaining":15000,"totalPercentUsed":25.0},"onDemand":{"used":150,"limit":10000}}}
        """.data(using: .utf8)!

        let parsed = try CursorCollector.parseResponse(json)
        let result = CursorCollector().buildResult(parsed)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Pro")
        XCTAssertEqual(result.usage.remaining, 15000)
        assertTierNames(result.usage, ["Plan", "On-Demand"])
        XCTAssertEqual(result.usage.reset_time, "2026-05-01T00:00:00Z")
    }

    func testAlibabaFixtureOrdersFiveHourWeeklyMonthly() throws {
        let json = """
        {"data":{"codingPlanInstanceInfos":[{"planName":"Standard","codingPlanQuotaInfo":{"per5HourUsedQuota":10,"per5HourTotalQuota":100,"per5HourQuotaNextRefreshTime":"2026-04-02T22:00:00Z","perWeekUsedQuota":50,"perWeekTotalQuota":500,"perWeekQuotaNextRefreshTime":"2026-04-09T00:00:00Z","perBillMonthUsedQuota":200,"perBillMonthTotalQuota":2000,"perBillMonthQuotaNextRefreshTime":"2026-05-01T00:00:00Z"}}]}}
        """.data(using: .utf8)!

        let parsed = try AlibabaCollector.parseResponse(json)
        let result = AlibabaCollector().buildResult(parsed)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Standard")
        XCTAssertEqual(result.usage.remaining, 90)
        assertTierNames(result.usage, ["5h Window", "Weekly", "Monthly"])
    }

    func testZaiFixtureKeepsTokensAsPrimaryLimit() throws {
        let json = """
        {"code":200,"data":{"limits":[{"type":"TOKENS_LIMIT","usage":500000,"remaining":500000,"nextResetTime":1745337600000},{"type":"TIME_LIMIT","usage":50,"remaining":250}],"planName":"Pro"}}
        """.data(using: .utf8)!

        let parsed = try ZaiCollector.parseResponse(json)
        let result = ZaiCollector().buildResult(parsed)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Pro")
        XCTAssertEqual(result.usage.quota, 1_000_000)
        XCTAssertEqual(result.usage.remaining, 500_000)
        assertTierNames(result.usage, ["Tokens", "Time"])
    }

    func testKimiFixtureKeepsWeeklyThenFiveHourRateLimit() throws {
        let json = """
        {"usages":[{"scope":"FEATURE_CODING","detail":{"limit":"1024","used":"500","remaining":"524","resetTime":"2026-04-09T00:00:00Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","used":"50","remaining":"150","resetTime":"2026-04-02T22:00:00Z"}}]}]}
        """.data(using: .utf8)!

        let parsed = try KimiCollector.parseResponse(json)
        let result = KimiCollector().buildResult(parsed)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.quota, 1024)
        XCTAssertEqual(result.usage.remaining, 524)
        XCTAssertEqual(result.usage.reset_time, "2026-04-09T00:00:00Z")
        assertTierNames(result.usage, ["Weekly", "5h Rate Limit"])
    }

    func testKimiK2FixtureRemainsCreditBased() throws {
        let json = """
        {"data":{"usage":{"total_credits_consumed":1000.50,"credits_remaining":500.25}}}
        """.data(using: .utf8)!

        let parsed = try KimiK2Collector.parseResponse(json)
        let result = KimiK2Collector().buildResult(parsed)

        assertDataKind(result, .credits)
        XCTAssertEqual(result.usage.plan_type, "Credits")
        XCTAssertEqual(result.usage.tiers.count, 1)
        XCTAssertEqual(result.usage.tiers.first?.name, "Credits")
        XCTAssertTrue(result.usage.status_text.contains("500.25"))
    }

    func testKiloFixtureKeepsCreditsAndPassOrdering() throws {
        let json = """
        [{"result":{"data":{"json":{"creditBlocks":[{"amount_mUsd":50000000,"balance_mUsd":25000000}]}}}},{"result":{"data":{"json":{"subscription":{"currentPeriodUsageUsd":25.0,"currentPeriodBaseCreditsUsd":50.0,"currentPeriodBonusCreditsUsd":10.0,"tier":"tier_49","nextBillingAt":"2026-05-02T00:00:00Z"}}}}}]
        """.data(using: .utf8)!

        let parsed = try KiloCollector.parseResponse(json)
        let result = KiloCollector().buildResult(parsed)

        assertDataKind(result, .credits)
        XCTAssertEqual(result.usage.plan_type, "Pro")
        assertTierNames(result.usage, ["Credits", "Kilo Pass"])
        XCTAssertEqual(result.usage.reset_time, "2026-05-02T00:00:00Z")
    }

    func testMiniMaxFixtureProducesSingleCodingPlanTier() throws {
        let json = """
        {"model_remains":800,"total":1000,"end_time":"2026-05-01T00:00:00Z"}
        """.data(using: .utf8)!

        let parsed = try MiniMaxCollector.parseRemainsResponse(json)
        let result = MiniMaxCollector().buildResult(parsed)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Coding Plan")
        XCTAssertEqual(result.usage.remaining, 800)
        assertTierNames(result.usage, ["Coding Plan"])
    }

    func testAugmentFixtureProducesCreditsQuotaCard() throws {
        let creditsJSON = """
        {"usageUnitsRemaining":350,"usageUnitsConsumedThisBillingCycle":150,"usageUnitsAvailable":500}
        """.data(using: .utf8)!
        let subJSON = """
        {"planName":"Pro","billingPeriodEnd":"2026-05-01T00:00:00Z","email":"user@test.com"}
        """.data(using: .utf8)!

        let credits = try AugmentCollector.parseCredits(creditsJSON)
        let subscription = try AugmentCollector.parseSubscription(subJSON)
        let result = AugmentCollector().buildResult(credits: credits, subscription: subscription)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Pro")
        XCTAssertEqual(result.usage.quota, 500)
        XCTAssertEqual(result.usage.remaining, 350)
        assertTierNames(result.usage, ["Credits"])
    }

    func testWarpFixtureSeparatesRequestsAndBonusCredits() throws {
        let json = """
        {"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":false,"nextRefreshTime":"2026-04-15T10:30:00Z","requestLimit":1000,"requestsUsedSinceLastRefresh":250},"bonusGrants":[{"requestCreditsGranted":100,"requestCreditsRemaining":50,"expiration":"2026-05-02T00:00:00Z"}]}}}}
        """.data(using: .utf8)!

        let parsed = try WarpCollector.parseResponse(json)
        let result = WarpCollector().buildResult(parsed)

        assertDataKind(result, .quota)
        XCTAssertEqual(result.usage.plan_type, "Free")
        XCTAssertEqual(result.usage.remaining, 750)
        assertTierNames(result.usage, ["Requests", "Bonus Credits"])
    }

    func testOllamaFixtureRemainsStatusOnly() throws {
        let modelsJSON = """
        {"models":[{"name":"llama3","size":123456789},{"name":"qwen2.5-coder","size":234567890}]}
        """.data(using: .utf8)!
        let runningJSON = """
        {"models":[{"name":"qwen2.5-coder"}]}
        """.data(using: .utf8)!

        let models = try OllamaCollector.parseTags(modelsJSON)
        let running = try OllamaCollector.parseRunning(runningJSON)
        let result = OllamaCollector().buildResult(models: models, running: running)

        assertDataKind(result, .statusOnly)
        XCTAssertEqual(result.usage.plan_type, "Local")
        XCTAssertTrue(result.usage.tiers.isEmpty)
        XCTAssertEqual(result.usage.status_text, "1 running, 2 installed")
    }
}
#endif
