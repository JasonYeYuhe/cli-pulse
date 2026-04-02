#if os(macOS)
import XCTest
@testable import CLIPulseCore

final class ClaudeCollectorTests: XCTestCase {

    // MARK: - OAuth API parsing

    func testParseUsageProPlan() throws {
        let json = """
        {
            "five_hour": { "utilization": 45, "resets_at": "2026-04-02T22:00:00Z" },
            "seven_day": { "utilization": 60, "resets_at": "2026-04-09T00:00:00Z" },
            "seven_day_opus": { "utilization": 75, "resets_at": "2026-04-09T00:00:00Z" },
            "seven_day_sonnet": { "utilization": 55, "resets_at": "2026-04-09T00:00:00Z" }
        }
        """.data(using: .utf8)!
        let usage = try ClaudeCollector.parseUsage(json)
        XCTAssertEqual(usage.fiveHour?.utilization, 45)
        XCTAssertEqual(usage.fiveHour?.resetsAt, "2026-04-02T22:00:00Z")
        XCTAssertEqual(usage.sevenDay?.utilization, 60)
        XCTAssertEqual(usage.sevenDayOpus?.utilization, 75)
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 55)
        XCTAssertNil(usage.extraUsage)
    }

    func testParseUsageWithExtraUsage() throws {
        let json = """
        {
            "five_hour": { "utilization": 10, "resets_at": "2026-04-02T22:00:00Z" },
            "seven_day": { "utilization": 20, "resets_at": "2026-04-09T00:00:00Z" },
            "extra_usage": {
                "is_enabled": true, "monthly_limit": 5000.00,
                "used_credits": 1234.56, "utilization": 24, "currency": "USD"
            }
        }
        """.data(using: .utf8)!
        let usage = try ClaudeCollector.parseUsage(json)
        XCTAssertNotNil(usage.extraUsage)
        XCTAssertTrue(usage.extraUsage!.isEnabled)
        XCTAssertEqual(usage.extraUsage!.monthlyLimit!, 5000.0, accuracy: 0.01)
        XCTAssertEqual(usage.extraUsage!.usedCredits!, 1234.56, accuracy: 0.01)
    }

    func testParseUsageMinimal() throws {
        let json = """
        { "five_hour": { "utilization": 0, "resets_at": "2026-04-02T22:00:00Z" } }
        """.data(using: .utf8)!
        let usage = try ClaudeCollector.parseUsage(json)
        XCTAssertEqual(usage.fiveHour?.utilization, 0)
        XCTAssertNil(usage.sevenDay)
    }

    func testParseUsageInvalidJSON() {
        XCTAssertThrowsError(try ClaudeCollector.parseUsage("bad".data(using: .utf8)!))
    }

    func testParseUsageEmptyObject() throws {
        let usage = try ClaudeCollector.parseUsage("{}".data(using: .utf8)!)
        XCTAssertNil(usage.fiveHour)
        XCTAssertNil(usage.sevenDay)
    }

    // MARK: - Credentials parsing

    func testParseSnakeCaseCredentials() {
        let json = """
        {"claude_ai_oauth":{"access_token":"sk-ant-oat01-test","rate_limit_tier":"pro"}}
        """.data(using: .utf8)!
        let creds = ClaudeCollector.parseCredentialsJSON(json)
        XCTAssertNotNil(creds)
        XCTAssertEqual(creds?.accessToken, "sk-ant-oat01-test")
        XCTAssertEqual(creds?.rateLimitTier, "pro")
    }

    func testParseCamelCaseCredentials() {
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-keychain","rateLimitTier":"max"}}
        """.data(using: .utf8)!
        let creds = ClaudeCollector.parseCredentialsJSON(json)
        XCTAssertNotNil(creds)
        XCTAssertEqual(creds?.accessToken, "sk-ant-oat01-keychain")
        XCTAssertEqual(creds?.rateLimitTier, "max")
    }

    func testParseEmptyCredentials() {
        XCTAssertNil(ClaudeCollector.parseCredentialsJSON("{}".data(using: .utf8)!))
    }

    // MARK: - ANSI stripping

    func testStripANSI() {
        let input = "\u{001B}[32m42% left\u{001B}[0m"
        let stripped = ClaudeCollector.stripANSI(input)
        XCTAssertEqual(stripped, "42% left")
    }

    func testStripANSIMultipleCodes() {
        let input = "\u{001B}[1;32mCurrent session\u{001B}[0m\n\u{001B}[33m75% left\u{001B}[0m"
        let stripped = ClaudeCollector.stripANSI(input)
        XCTAssertEqual(stripped, "Current session\n75% left")
    }

    func testStripANSINoOp() {
        XCTAssertEqual(ClaudeCollector.stripANSI("plain text"), "plain text")
    }

    // MARK: - Percentage extraction

    func testPercentUsedFromLineLeft() {
        // "42% left" → 42% remaining → 58% used
        XCTAssertEqual(ClaudeCollector.percentUsedFromLine("42% left"), 58)
    }

    func testPercentUsedFromLineUsed() {
        XCTAssertEqual(ClaudeCollector.percentUsedFromLine("75% used"), 75)
    }

    func testPercentUsedFromLineRemaining() {
        // "30% remaining" → 30% remaining → 70% used
        XCTAssertEqual(ClaudeCollector.percentUsedFromLine("30% remaining"), 70)
    }

    func testPercentUsedFromLineAmbiguous() {
        // Ambiguous (no keyword) → assume "left" → 100 - 50 = 50% used
        XCTAssertEqual(ClaudeCollector.percentUsedFromLine("50%"), 50)
    }

    func testPercentUsedFromLineNoPercent() {
        XCTAssertNil(ClaudeCollector.percentUsedFromLine("no percentage here"))
    }

    func testPercentUsedFromLineDecimal() {
        XCTAssertEqual(ClaudeCollector.percentUsedFromLine("42.5% left"), 58)
    }

    // MARK: - CLI output parsing

    func testParseCLIOutputNormal() throws {
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
        Resets Monday 12:00 AM
        """
        let snapshot = try ClaudeCollector.parseCLIOutput(text)
        XCTAssertEqual(snapshot.sessionPercentLeft, 42)
        XCTAssertEqual(snapshot.weeklyPercentLeft, 75)
        XCTAssertEqual(snapshot.opusPercentLeft, 60)
        XCTAssertNotNil(snapshot.primaryResetDescription)
        XCTAssertTrue(snapshot.primaryResetDescription!.contains("Resets"))
    }

    func testParseCLIOutputWithANSI() throws {
        let text = """
        \u{001B}[1mCurrent session\u{001B}[0m
        \u{001B}[32m30% left\u{001B}[0m
        Resets in 1 hour

        \u{001B}[1mCurrent week (all models)\u{001B}[0m
        \u{001B}[33m50% left\u{001B}[0m
        """
        let snapshot = try ClaudeCollector.parseCLIOutput(text)
        XCTAssertEqual(snapshot.sessionPercentLeft, 30)
        XCTAssertEqual(snapshot.weeklyPercentLeft, 50)
    }

    func testParseCLIOutputNoUsageData() {
        let text = "Loading...\nPlease wait"
        XCTAssertThrowsError(try ClaudeCollector.parseCLIOutput(text))
    }

    func testParseCLIOutputUsedSemantics() throws {
        let text = """
        Current session
        58% used
        Resets in 2 hours

        Current week (all models)
        25% used
        """
        let snapshot = try ClaudeCollector.parseCLIOutput(text)
        // 58% used → sessionPct=58 → sessionPercentLeft=100-58=42
        XCTAssertEqual(snapshot.sessionPercentLeft, 42)
        // 25% used → weeklyPct=25 → weeklyPercentLeft=100-25=75
        XCTAssertEqual(snapshot.weeklyPercentLeft, 75)
    }

    // MARK: - Availability

    func testCollectorKind() {
        XCTAssertEqual(ClaudeCollector().kind, .claude)
    }

    func testIsAvailableWithCLIBinary() {
        // If claude CLI exists in PATH, isAvailable should return true even without OAuth token
        let collector = ClaudeCollector()
        let hasCLI = collector.findClaudeBinary() != nil
        let config = ProviderConfig(kind: .claude) // no apiKey, no env var
        if hasCLI {
            XCTAssertTrue(collector.isAvailable(config: config),
                          "Should be available via CLI fallback")
        }
        // If no CLI, this test is a no-op (environment-dependent)
    }
}
#endif
