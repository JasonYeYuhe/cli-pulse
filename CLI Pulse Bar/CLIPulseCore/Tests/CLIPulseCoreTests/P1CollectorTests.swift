#if os(macOS)
import XCTest
@testable import CLIPulseCore

// MARK: - Copilot

final class CopilotCollectorTests: XCTestCase {
    func testParseWithSnapshots() throws {
        let json = """
        {"copilotPlan":"pro","quotaResetDate":"2026-05-01T00:00:00Z","quotaSnapshots":{"premiumInteractions":{"entitlement":300,"remaining":200,"percentRemaining":66.7},"chat":{"entitlement":1000,"remaining":800,"percentRemaining":80.0}}}
        """.data(using: .utf8)!
        let c = try CopilotCollector.parseResponse(json)
        XCTAssertEqual(c.plan, "pro")
        XCTAssertEqual(c.quotaResetDate, "2026-05-01T00:00:00Z")
        XCTAssertEqual(c.premiumEntitlement!, 300, accuracy: 0.1)
        XCTAssertEqual(c.premiumRemaining!, 200, accuracy: 0.1)
        XCTAssertEqual(c.chatEntitlement!, 1000, accuracy: 0.1)
    }

    func testParseMinimal() throws {
        let json = """
        {"copilotPlan":"free"}
        """.data(using: .utf8)!
        let c = try CopilotCollector.parseResponse(json)
        XCTAssertEqual(c.plan, "free")
        XCTAssertNil(c.premiumEntitlement)
        XCTAssertNil(c.chatEntitlement)
    }

    func testAvailability() {
        let c = CopilotCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .copilot)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .copilot, apiKey: "ghp_test")))
    }
}

// MARK: - Cursor

final class CursorCollectorTests: XCTestCase {
    func testParseUsageSummary() throws {
        let json = """
        {"membershipType":"pro","billingCycleEnd":"2026-05-01T00:00:00Z","individualUsage":{"plan":{"used":5000,"limit":20000,"remaining":15000,"totalPercentUsed":25.0},"onDemand":{"used":150,"limit":10000}}}
        """.data(using: .utf8)!
        let c = try CursorCollector.parseResponse(json)
        XCTAssertEqual(c.membershipType, "pro")
        XCTAssertEqual(c.planUsedCents, 5000)
        XCTAssertEqual(c.planLimitCents, 20000)
        XCTAssertEqual(c.planRemainingCents, 15000)
        XCTAssertEqual(c.onDemandUsedCents, 150)
        XCTAssertEqual(c.totalPercentUsed!, 25.0, accuracy: 0.1)
    }

    func testParseMinimal() throws {
        let json = "{}".data(using: .utf8)!
        let c = try CursorCollector.parseResponse(json)
        XCTAssertNil(c.membershipType)
        XCTAssertEqual(c.planUsedCents, 0)
    }

    func testAvailability() {
        let c = CursorCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .cursor)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .cursor, manualCookieHeader: "session=x")))
    }
}

// MARK: - Kimi

final class KimiCollectorTests: XCTestCase {
    func testParseWithLimits() throws {
        let json = """
        {"usages":[{"scope":"FEATURE_CODING","detail":{"limit":"1024","used":"500","remaining":"524","resetTime":"2026-04-09T00:00:00Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"200","used":"50","remaining":"150","resetTime":"2026-04-02T22:00:00Z"}}]}]}
        """.data(using: .utf8)!
        let k = try KimiCollector.parseResponse(json)
        XCTAssertEqual(k.weeklyLimit, 1024)
        XCTAssertEqual(k.weeklyUsed, 500)
        XCTAssertEqual(k.weeklyRemaining, 524)
        XCTAssertEqual(k.rateLimitTotal, 200)
        XCTAssertEqual(k.rateLimitUsed, 50)
    }

    func testParseNoLimits() throws {
        let json = """
        {"usages":[{"scope":"FEATURE_CODING","detail":{"limit":"500","used":"100"}}]}
        """.data(using: .utf8)!
        let k = try KimiCollector.parseResponse(json)
        XCTAssertEqual(k.weeklyLimit, 500)
        XCTAssertNil(k.rateLimitTotal)
    }

    func testParseEmpty() {
        XCTAssertThrowsError(try KimiCollector.parseResponse("{}".data(using: .utf8)!))
    }

    func testAvailability() {
        let c = KimiCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .kimi)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .kimi, apiKey: "jwt-token")))
    }
}

// MARK: - Alibaba

final class AlibabaCollectorTests: XCTestCase {
    func testParseFullResponse() throws {
        let json = """
        {"data":{"codingPlanInstanceInfos":[{"planName":"Standard","codingPlanQuotaInfo":{"per5HourUsedQuota":10,"per5HourTotalQuota":100,"per5HourQuotaNextRefreshTime":"2026-04-02T22:00:00Z","perWeekUsedQuota":50,"perWeekTotalQuota":500,"perWeekQuotaNextRefreshTime":"2026-04-09T00:00:00Z","perBillMonthUsedQuota":200,"perBillMonthTotalQuota":2000,"perBillMonthQuotaNextRefreshTime":"2026-05-01T00:00:00Z"}}]}}
        """.data(using: .utf8)!
        let a = try AlibabaCollector.parseResponse(json)
        XCTAssertEqual(a.planName, "Standard")
        XCTAssertEqual(a.fiveHourUsed, 10)
        XCTAssertEqual(a.fiveHourTotal, 100)
        XCTAssertEqual(a.weeklyUsed, 50)
        XCTAssertEqual(a.weeklyTotal, 500)
        XCTAssertEqual(a.monthlyUsed, 200)
        XCTAssertEqual(a.monthlyTotal, 2000)
    }

    func testParseEmpty() {
        XCTAssertThrowsError(try AlibabaCollector.parseResponse("{}".data(using: .utf8)!))
    }

    func testAvailability() {
        let c = AlibabaCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .alibaba)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .alibaba, apiKey: "key")))
    }
}
#endif
