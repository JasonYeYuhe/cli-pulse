#if os(macOS)
import XCTest
@testable import CLIPulseCore

// MARK: - MiniMax

final class MiniMaxCollectorTests: XCTestCase {
    func testParseRemains() throws {
        let json = """
        {"model_remains":800,"total":1000,"end_time":"2026-05-01T00:00:00Z"}
        """.data(using: .utf8)!
        let m = try MiniMaxCollector.parseRemainsResponse(json)
        XCTAssertEqual(m.modelRemains, 800)
        XCTAssertEqual(m.total, 1000)
        XCTAssertEqual(m.endTime, "2026-05-01T00:00:00Z")
    }

    func testParseZeroRemains() throws {
        let json = """
        {"model_remains":0,"total":500}
        """.data(using: .utf8)!
        let m = try MiniMaxCollector.parseRemainsResponse(json)
        XCTAssertEqual(m.modelRemains, 0)
        XCTAssertEqual(m.total, 500)
    }

    func testParseInvalid() {
        XCTAssertThrowsError(try MiniMaxCollector.parseRemainsResponse("bad".data(using: .utf8)!))
    }

    func testAvailabilityAPIKey() {
        let c = MiniMaxCollector()
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .minimax, apiKey: "key")))
    }

    func testAvailabilityCookie() {
        let c = MiniMaxCollector()
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .minimax, manualCookieHeader: "session=x")))
    }

    func testAvailabilityNone() {
        let c = MiniMaxCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .minimax)))
    }
}

// MARK: - Volcano Engine

final class VolcanoEngineCollectorTests: XCTestCase {
    func testParseQuotaResponse() throws {
        let json = """
        {"total":10000,"remaining":7500,"end_time":"2026-05-01T00:00:00Z"}
        """.data(using: .utf8)!
        let u = try VolcanoEngineCollector.parseUsageResponse(json)
        XCTAssertEqual(u.quota, 10000)
        XCTAssertEqual(u.remaining, 7500)
        XCTAssertEqual(u.endTime, "2026-05-01T00:00:00Z")
    }

    func testParseModelsList() throws {
        let json = """
        {"data":[{"id":"doubao-1.5-pro"},{"id":"doubao-1.5-lite"}]}
        """.data(using: .utf8)!
        let u = try VolcanoEngineCollector.parseUsageResponse(json)
        XCTAssertEqual(u.modelCount, 2)
        XCTAssertEqual(u.quota, 0)
    }

    func testParseWrappedResponse() throws {
        let json = """
        {"result":{"total":5000,"remaining":3000,"end_time":"2026-06-01T00:00:00Z"}}
        """.data(using: .utf8)!
        let u = try VolcanoEngineCollector.parseUsageResponse(json)
        XCTAssertEqual(u.quota, 5000)
        XCTAssertEqual(u.remaining, 3000)
    }

    func testParseInvalid() {
        XCTAssertThrowsError(try VolcanoEngineCollector.parseUsageResponse("bad".data(using: .utf8)!))
    }

    func testAvailabilityAPIKey() {
        let c = VolcanoEngineCollector()
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .volcanoEngine, apiKey: "key")))
    }

    func testAvailabilityNone() {
        let c = VolcanoEngineCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .volcanoEngine)))
    }
}

// MARK: - Augment

final class AugmentCollectorTests: XCTestCase {
    func testParseCredits() throws {
        let json = """
        {"usageUnitsRemaining":350,"usageUnitsConsumedThisBillingCycle":150,"usageUnitsAvailable":500}
        """.data(using: .utf8)!
        let c = try AugmentCollector.parseCredits(json)
        XCTAssertEqual(c.remaining, 350)
        XCTAssertEqual(c.consumed, 150)
        XCTAssertEqual(c.available, 500)
    }

    func testParseSubscription() throws {
        let json = """
        {"planName":"Pro","billingPeriodEnd":"2026-05-01T00:00:00Z","email":"user@test.com"}
        """.data(using: .utf8)!
        let s = try AugmentCollector.parseSubscription(json)
        XCTAssertEqual(s.planName, "Pro")
        XCTAssertEqual(s.billingPeriodEnd, "2026-05-01T00:00:00Z")
    }

    func testParseCreditsInvalid() {
        XCTAssertThrowsError(try AugmentCollector.parseCredits("bad".data(using: .utf8)!))
    }

    func testAvailability() {
        let c = AugmentCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .augment)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .augment, manualCookieHeader: "session=x")))
    }
}
#endif
