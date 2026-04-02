#if os(macOS)
import XCTest
@testable import CLIPulseCore

final class ClaudeStrategyTests: XCTestCase {

    // MARK: - ClaudeSnapshot → CollectorResult

    func testResultBuilderFullSnapshot() {
        let snapshot = ClaudeSnapshot(
            sessionUsed: 45, weeklyUsed: 60, opusUsed: 75, sonnetUsed: 55,
            sessionReset: "2026-04-02T22:00:00Z", weeklyReset: "2026-04-09T00:00:00Z",
            rateLimitTier: "pro", sourceLabel: "oauth"
        )
        let result = ClaudeResultBuilder.build(from: snapshot)
        XCTAssertEqual(result.usage.provider, "Claude")
        XCTAssertEqual(result.usage.quota, 100)
        XCTAssertEqual(result.usage.remaining, 55) // 100 - 45
        XCTAssertEqual(result.usage.plan_type, "Pro")
        XCTAssertEqual(result.usage.tiers.count, 4) // 5h, weekly, opus, sonnet
        XCTAssertEqual(result.usage.tiers[0].name, "5h Window")
        XCTAssertEqual(result.usage.tiers[0].remaining, 55)
        XCTAssertEqual(result.usage.tiers[1].name, "Weekly")
        XCTAssertEqual(result.usage.tiers[1].remaining, 40)
        XCTAssertEqual(result.usage.tiers[2].name, "Opus (Weekly)")
        XCTAssertEqual(result.usage.tiers[2].remaining, 25)
        XCTAssertEqual(result.usage.tiers[3].name, "Sonnet (Weekly)")
        XCTAssertEqual(result.usage.tiers[3].remaining, 45)
        XCTAssertEqual(result.dataKind, .quota)
    }

    func testResultBuilderMinimalSnapshot() {
        let snapshot = ClaudeSnapshot(sessionUsed: 10, sourceLabel: "cli-pty")
        let result = ClaudeResultBuilder.build(from: snapshot)
        XCTAssertEqual(result.usage.remaining, 90)
        XCTAssertEqual(result.usage.tiers.count, 1)
        XCTAssertEqual(result.usage.plan_type, "Unknown")
    }

    func testResultBuilderExtraUsage() {
        let extra = ClaudeExtraUsage(isEnabled: true, monthlyLimit: 5000.0, usedCredits: 1234.56, currency: "USD")
        let snapshot = ClaudeSnapshot(sessionUsed: 20, extraUsage: extra, sourceLabel: "oauth")
        let result = ClaudeResultBuilder.build(from: snapshot)
        let extraTier = result.usage.tiers.first { $0.name == "Extra Usage" }
        XCTAssertNotNil(extraTier)
        XCTAssertGreaterThan(extraTier!.quota, 0)
        XCTAssertGreaterThan(extraTier!.remaining, 0)
    }

    func testResultBuilderPlanTypes() {
        for (tier, expected) in [("max", "Max"), ("default_claude_max_20x", "Max"), ("pro", "Pro"), ("team", "Team"), ("enterprise", "Enterprise"), (nil, "Unknown")] {
            let snapshot = ClaudeSnapshot(sessionUsed: 0, rateLimitTier: tier, sourceLabel: "test")
            let result = ClaudeResultBuilder.build(from: snapshot)
            XCTAssertEqual(result.usage.plan_type, expected, "tier '\(tier ?? "nil")' should map to '\(expected)'")
        }
    }

    // MARK: - ClaudeCredentials

    func testParseCredentialsSnakeCase() {
        let json = """
        {"claude_ai_oauth":{"access_token":"sk-ant-oat01-test","rate_limit_tier":"pro"}}
        """.data(using: .utf8)!
        let creds = ClaudeCredentials.parseCredentialsJSON(json)
        XCTAssertEqual(creds?.accessToken, "sk-ant-oat01-test")
        XCTAssertEqual(creds?.rateLimitTier, "pro")
    }

    func testParseCredentialsCamelCase() {
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-cc","rateLimitTier":"max"}}
        """.data(using: .utf8)!
        let creds = ClaudeCredentials.parseCredentialsJSON(json)
        XCTAssertEqual(creds?.accessToken, "sk-ant-oat01-cc")
        XCTAssertEqual(creds?.rateLimitTier, "max")
    }

    func testParseCredentialsEmpty() {
        XCTAssertNil(ClaudeCredentials.parseCredentialsJSON("{}".data(using: .utf8)!))
    }

    func testStripANSI() {
        XCTAssertEqual(ClaudeCredentials.stripANSI("\u{001B}[32m42% left\u{001B}[0m"), "42% left")
    }

    // MARK: - ClaudeWebStrategy session key extraction

    func testExtractSessionKeyFromCookieHeader() {
        XCTAssertEqual(
            ClaudeWebStrategy.extractSessionKey(from: "sessionKey=abc123; other=xyz"),
            "abc123"
        )
        XCTAssertEqual(
            ClaudeWebStrategy.extractSessionKey(from: "sessionKey=abc123"),
            "abc123"
        )
        XCTAssertNil(ClaudeWebStrategy.extractSessionKey(from: "other=xyz"))
        XCTAssertNil(ClaudeWebStrategy.extractSessionKey(from: "sessionKey="))
    }

    // MARK: - ClaudeCLIPTYStrategy parsing

    func testPTYParseCLIOutput() throws {
        let text = """
        Settings: Usage

        Current session
        42% left
        Resets in 2 hours

        Current week (all models)
        75% left
        Resets Monday 12:00 AM

        Current week (Opus)
        60% left
        """
        let snapshot = try ClaudeCLIPTYStrategy.parseCLIOutput(text)
        XCTAssertEqual(snapshot.sessionPercentLeft, 42)
        XCTAssertEqual(snapshot.weeklyPercentLeft, 75)
        XCTAssertEqual(snapshot.opusPercentLeft, 60)
    }

    func testPTYPercentUsedFromLine() {
        XCTAssertEqual(ClaudeCLIPTYStrategy.percentUsedFromLine("42% left"), 58)
        XCTAssertEqual(ClaudeCLIPTYStrategy.percentUsedFromLine("75% used"), 75)
        XCTAssertEqual(ClaudeCLIPTYStrategy.percentUsedFromLine("30% remaining"), 70)
        XCTAssertNil(ClaudeCLIPTYStrategy.percentUsedFromLine("no percentage here"))
    }

    // MARK: - ClaudeOAuthStrategy parsing

    func testOAuthParseUsage() throws {
        let json = """
        {
            "five_hour": { "utilization": 45, "resets_at": "2026-04-02T22:00:00Z" },
            "seven_day": { "utilization": 60, "resets_at": "2026-04-09T00:00:00Z" },
            "seven_day_opus": { "utilization": 75 }
        }
        """.data(using: .utf8)!
        let usage = try ClaudeOAuthStrategy.parseUsage(json)
        XCTAssertEqual(usage.fiveHour?.utilization, 45)
        XCTAssertEqual(usage.sevenDay?.utilization, 60)
        XCTAssertEqual(usage.sevenDayOpus?.utilization, 75)
        XCTAssertNil(usage.sevenDaySonnet)
    }

    func testOAuthParseUsageWithExtraUsage() throws {
        let json = """
        {
            "five_hour": { "utilization": 10 },
            "extra_usage": { "is_enabled": true, "monthly_limit": 5000.0, "used_credits": 1234.56, "currency": "USD" }
        }
        """.data(using: .utf8)!
        let usage = try ClaudeOAuthStrategy.parseUsage(json)
        XCTAssertNotNil(usage.extraUsage)
        XCTAssertTrue(usage.extraUsage!.isEnabled)
        XCTAssertEqual(usage.extraUsage!.monthlyLimit!, 5000.0, accuracy: 0.01)
    }

    // MARK: - ClaudeSourceResolver

    func testResolverDefaultOrder() {
        // Verify default strategy order: OAuth → CLI PTY → Web (CodexBar app-runtime order)
        let strategies = ClaudeSourceResolver.defaultStrategies
        XCTAssertEqual(strategies.count, 3)
        XCTAssertEqual(strategies[0].sourceLabel, "oauth")
        XCTAssertEqual(strategies[1].sourceLabel, "cli-pty")
        XCTAssertEqual(strategies[2].sourceLabel, "web")
    }

    func testResolverAvailability() {
        let resolver = ClaudeSourceResolver()
        let config = ProviderConfig(kind: .claude)
        _ = resolver.isAvailable(config: config)
    }

    // MARK: - Helper contract

    func testHelperContractPaths() {
        let home = ClaudeCredentials.realHomeDir
        XCTAssertTrue(ClaudeHelperContract.snapshotPath.hasPrefix(home))
        XCTAssertTrue(ClaudeHelperContract.snapshotPath.hasSuffix("claude_snapshot.json"))
        XCTAssertTrue(ClaudeHelperContract.sessionKeyPath.hasSuffix("claude_session.json"))
    }

    func testHelperSnapshotRoundTrip() throws {
        // Save any existing production snapshot so we can restore it after the test.
        let prodPath = ClaudeHelperContract.snapshotPath
        let hadExisting = FileManager.default.fileExists(atPath: prodPath)
        let existingData = hadExisting ? FileManager.default.contents(atPath: prodPath) : nil

        let snapshot = ClaudeSnapshot(
            sessionUsed: 45, weeklyUsed: 60, opusUsed: 75,
            sessionReset: "2026-04-02T22:00:00Z", weeklyReset: "2026-04-09T00:00:00Z",
            rateLimitTier: "pro", accountEmail: "test@example.com",
            sourceLabel: "web"
        )
        try ClaudeHelperContract.writeSnapshot(snapshot)
        defer {
            // Restore the original snapshot if one existed; otherwise remove test artifact
            if let data = existingData {
                try? data.write(to: URL(fileURLWithPath: prodPath), options: .atomic)
            } else {
                try? FileManager.default.removeItem(atPath: prodPath)
            }
        }

        let read = ClaudeWebStrategy.readHelperSnapshot()
        XCTAssertNotNil(read)
        XCTAssertEqual(read?.sessionUsed, 45)
        XCTAssertEqual(read?.weeklyUsed, 60)
        XCTAssertEqual(read?.opusUsed, 75)
        XCTAssertEqual(read?.rateLimitTier, "pro")
        XCTAssertEqual(read?.accountEmail, "test@example.com")
        XCTAssertEqual(read?.sourceLabel, "helper-web")
    }

    // MARK: - Strategy error fallback logic

    func testStrategyErrorShouldFallback() {
        XCTAssertTrue(ClaudeStrategyError.noToken.shouldFallback)
        XCTAssertTrue(ClaudeStrategyError.noBinary.shouldFallback)
        XCTAssertTrue(ClaudeStrategyError.httpError(status: 429, provider: "Claude").shouldFallback)
        XCTAssertTrue(ClaudeStrategyError.httpError(status: 401, provider: "Claude").shouldFallback)
        XCTAssertTrue(ClaudeStrategyError.httpError(status: 403, provider: "Claude").shouldFallback)
        XCTAssertTrue(ClaudeStrategyError.noSessionKey.shouldFallback)
        XCTAssertTrue(ClaudeStrategyError.unauthorized.shouldFallback)
        XCTAssertTrue(ClaudeStrategyError.timedOut.shouldFallback)
        XCTAssertTrue(ClaudeStrategyError.parseFailed("test").shouldFallback)
    }
}
#endif
