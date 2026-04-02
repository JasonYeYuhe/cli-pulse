#if os(macOS)
import XCTest
@testable import CLIPulseCore

// MARK: - Warp

final class WarpCollectorTests: XCTestCase {
    func testParseNormalResponse() throws {
        let json = """
        {"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":false,"nextRefreshTime":"2026-04-15T10:30:00Z","requestLimit":1000,"requestsUsedSinceLastRefresh":250},"bonusGrants":[{"requestCreditsGranted":100,"requestCreditsRemaining":50,"expiration":"2026-05-02T00:00:00Z"}]}}}}
        """.data(using: .utf8)!
        let w = try WarpCollector.parseResponse(json)
        XCTAssertFalse(w.isUnlimited)
        XCTAssertEqual(w.requestLimit, 1000)
        XCTAssertEqual(w.requestsUsed, 250)
        XCTAssertEqual(w.nextRefreshTime, "2026-04-15T10:30:00Z")
        XCTAssertEqual(w.bonusGranted, 100)
        XCTAssertEqual(w.bonusRemaining, 50)
    }

    func testParseUnlimited() throws {
        let json = """
        {"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":true,"requestLimit":0,"requestsUsedSinceLastRefresh":0},"bonusGrants":[]}}}}
        """.data(using: .utf8)!
        let w = try WarpCollector.parseResponse(json)
        XCTAssertTrue(w.isUnlimited)
    }

    func testParseInvalid() {
        XCTAssertThrowsError(try WarpCollector.parseResponse("bad".data(using: .utf8)!))
    }

    func testAvailability() {
        let c = WarpCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .warp)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .warp, apiKey: "wk-test")))
    }
}

// MARK: - z.ai

final class ZaiCollectorTests: XCTestCase {
    func testParseTokensLimit() throws {
        let json = """
        {"code":200,"data":{"limits":[{"type":"TOKENS_LIMIT","usage":500000,"remaining":500000,"nextResetTime":1745337600000}],"planName":"Pro"}}
        """.data(using: .utf8)!
        let z = try ZaiCollector.parseResponse(json)
        XCTAssertEqual(z.limits.count, 1)
        XCTAssertEqual(z.limits[0].type, "TOKENS_LIMIT")
        XCTAssertEqual(z.limits[0].usage, 500000)
        XCTAssertEqual(z.limits[0].remaining, 500000)
        XCTAssertNotNil(z.limits[0].nextResetTime)
        XCTAssertEqual(z.planName, "Pro")
    }

    func testParseMultipleLimits() throws {
        let json = """
        {"data":{"limits":[{"type":"TOKENS_LIMIT","usage":100,"remaining":900},{"type":"TIME_LIMIT","usage":50,"remaining":250}]}}
        """.data(using: .utf8)!
        let z = try ZaiCollector.parseResponse(json)
        XCTAssertEqual(z.limits.count, 2)
    }

    func testParseInvalid() {
        XCTAssertThrowsError(try ZaiCollector.parseResponse("{}".data(using: .utf8)!))
    }

    func testAvailability() {
        let c = ZaiCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .zai)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .zai, apiKey: "test")))
    }
}

// MARK: - Kimi K2

final class KimiK2CollectorTests: XCTestCase {
    func testParseNestedData() throws {
        let json = """
        {"data":{"usage":{"total_credits_consumed":1000.50,"credits_remaining":500.25}}}
        """.data(using: .utf8)!
        let k = try KimiK2Collector.parseResponse(json)
        XCTAssertEqual(k.consumed, 1000.50, accuracy: 0.01)
        XCTAssertEqual(k.remaining, 500.25, accuracy: 0.01)
    }

    func testParseFlatResponse() throws {
        let json = """
        {"consumed":100.0,"remaining":400.0}
        """.data(using: .utf8)!
        let k = try KimiK2Collector.parseResponse(json)
        XCTAssertEqual(k.consumed, 100.0, accuracy: 0.01)
        XCTAssertEqual(k.remaining, 400.0, accuracy: 0.01)
    }

    func testParseNoFields() {
        let json = """
        {"data":{"other":"value"}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try KimiK2Collector.parseResponse(json))
    }

    func testAvailability() {
        let c = KimiK2Collector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .kimiK2)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .kimiK2, apiKey: "key")))
    }
}

// MARK: - Kilo

final class KiloCollectorTests: XCTestCase {
    func testParseBatchResponse() throws {
        let json = """
        [{"result":{"data":{"json":{"creditBlocks":[{"amount_mUsd":50000000,"balance_mUsd":25000000}]}}}},{"result":{"data":{"json":{"subscription":{"currentPeriodUsageUsd":25.0,"currentPeriodBaseCreditsUsd":50.0,"currentPeriodBonusCreditsUsd":10.0,"tier":"tier_49","nextBillingAt":"2026-05-02T00:00:00Z"}}}}}]
        """.data(using: .utf8)!
        let k = try KiloCollector.parseResponse(json)
        XCTAssertEqual(k.creditsTotalMuUsd, 50000000)
        XCTAssertEqual(k.creditsRemainingMuUsd, 25000000)
        XCTAssertEqual(k.subscriptionUsageUsd!, 25.0, accuracy: 0.01)
        XCTAssertEqual(k.subscriptionBaseUsd!, 50.0, accuracy: 0.01)
        XCTAssertEqual(k.tier, "tier_49")
        XCTAssertEqual(k.nextBillingAt, "2026-05-02T00:00:00Z")
    }

    func testParseCreditsOnly() throws {
        let json = """
        [{"result":{"data":{"json":{"creditBlocks":[{"amount_mUsd":10000000,"balance_mUsd":10000000}]}}}}]
        """.data(using: .utf8)!
        let k = try KiloCollector.parseResponse(json)
        XCTAssertEqual(k.creditsTotalMuUsd, 10000000)
        XCTAssertNil(k.subscriptionUsageUsd)
    }

    func testParseInvalid() {
        XCTAssertThrowsError(try KiloCollector.parseResponse("not-array".data(using: .utf8)!))
    }

    func testAvailability() {
        let c = KiloCollector()
        XCTAssertFalse(c.isAvailable(config: ProviderConfig(kind: .kilo)))
        XCTAssertTrue(c.isAvailable(config: ProviderConfig(kind: .kilo, apiKey: "key")))
    }
}
#endif
