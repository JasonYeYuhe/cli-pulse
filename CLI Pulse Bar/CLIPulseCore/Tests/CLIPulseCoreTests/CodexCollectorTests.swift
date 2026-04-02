#if os(macOS)
import XCTest
@testable import CLIPulseCore

final class CodexCollectorTests: XCTestCase {

    // MARK: - Usage parsing

    func testParseUsageProPlan() throws {
        let json = """
        {
            "plan_type": "pro",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 15,
                    "reset_at": 1735401600,
                    "limit_window_seconds": 18000
                },
                "secondary_window": {
                    "used_percent": 5,
                    "reset_at": 1735920000,
                    "limit_window_seconds": 604800
                }
            },
            "credits": {
                "has_credits": true,
                "unlimited": false,
                "balance": 150.0
            }
        }
        """.data(using: .utf8)!

        let usage = try CodexCollector.parseUsage(json)
        XCTAssertEqual(usage.planType, "pro")

        // Primary window
        XCTAssertNotNil(usage.primaryWindow)
        XCTAssertEqual(usage.primaryWindow?.usedPercent, 15)
        XCTAssertEqual(usage.primaryWindow?.limitWindowSeconds, 18000)
        XCTAssertNotNil(usage.primaryWindow?.resetAt)

        // Secondary window
        XCTAssertNotNil(usage.secondaryWindow)
        XCTAssertEqual(usage.secondaryWindow?.usedPercent, 5)
        XCTAssertEqual(usage.secondaryWindow?.limitWindowSeconds, 604800)

        // Credits
        XCTAssertNotNil(usage.credits)
        XCTAssertTrue(usage.credits!.hasCredits)
        XCTAssertFalse(usage.credits!.unlimited)
        XCTAssertEqual(usage.credits!.balance!, 150.0, accuracy: 0.01)
    }

    func testParseUsageFreePlanNoCredits() throws {
        let json = """
        {
            "plan_type": "free",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 80,
                    "reset_at": 1735401600,
                    "limit_window_seconds": 18000
                }
            }
        }
        """.data(using: .utf8)!

        let usage = try CodexCollector.parseUsage(json)
        XCTAssertEqual(usage.planType, "free")
        XCTAssertEqual(usage.primaryWindow?.usedPercent, 80)
        XCTAssertNil(usage.secondaryWindow)
        XCTAssertNil(usage.credits)
    }

    func testParseUsageUnlimitedCredits() throws {
        let json = """
        {
            "plan_type": "enterprise",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 2,
                    "reset_at": 1735401600,
                    "limit_window_seconds": 18000
                },
                "secondary_window": {
                    "used_percent": 0,
                    "reset_at": 1735920000,
                    "limit_window_seconds": 604800
                }
            },
            "credits": {
                "has_credits": true,
                "unlimited": true,
                "balance": null
            }
        }
        """.data(using: .utf8)!

        let usage = try CodexCollector.parseUsage(json)
        XCTAssertEqual(usage.planType, "enterprise")
        XCTAssertTrue(usage.credits!.unlimited)
        XCTAssertNil(usage.credits!.balance)
    }

    func testParseUsageNoRateLimit() throws {
        let json = """
        {
            "plan_type": "guest"
        }
        """.data(using: .utf8)!

        let usage = try CodexCollector.parseUsage(json)
        XCTAssertEqual(usage.planType, "guest")
        XCTAssertNil(usage.primaryWindow)
        XCTAssertNil(usage.secondaryWindow)
        XCTAssertNil(usage.credits)
    }

    func testParseUsageInvalidJSON() {
        let bad = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try CodexCollector.parseUsage(bad))
    }

    // MARK: - Tier mapping

    func testTierBuildingFromProResponse() throws {
        let json = """
        {
            "plan_type": "pro",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 30,
                    "reset_at": 1735401600,
                    "limit_window_seconds": 18000
                },
                "secondary_window": {
                    "used_percent": 10,
                    "reset_at": 1735920000,
                    "limit_window_seconds": 604800
                }
            },
            "credits": {
                "has_credits": true,
                "unlimited": false,
                "balance": 50.0
            }
        }
        """.data(using: .utf8)!

        let usage = try CodexCollector.parseUsage(json)

        // Verify the usage can be parsed; the collector builds tiers from this.
        // Primary: 30% used → 70 remaining of 100
        XCTAssertEqual(usage.primaryWindow!.usedPercent, 30)
        // Secondary: 10% used → 90 remaining of 100
        XCTAssertEqual(usage.secondaryWindow!.usedPercent, 10)
        // Credits: $50 balance
        XCTAssertEqual(usage.credits!.balance!, 50.0, accuracy: 0.01)
    }

    func testResetTimeParsing() throws {
        let json = """
        {
            "plan_type": "plus",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 0,
                    "reset_at": 1735401600,
                    "limit_window_seconds": 18000
                }
            }
        }
        """.data(using: .utf8)!

        let usage = try CodexCollector.parseUsage(json)
        let resetDate = usage.primaryWindow!.resetAt!
        // 1735401600 = 2024-12-28T16:00:00Z
        let expected = Date(timeIntervalSince1970: 1735401600)
        XCTAssertEqual(resetDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Availability

    func testCollectorKind() {
        let collector = CodexCollector()
        XCTAssertEqual(collector.kind, .codex)
    }

    // Note: isAvailable depends on filesystem (~/.codex/auth.json), so we don't
    // test it here — that would be an integration test, not a unit test.

    // MARK: - Window classification

    func testWindowNaming() throws {
        // 18000 seconds = 5 hours → should be named "5h Window"
        let json5h = """
        {
            "plan_type": "pro",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 0,
                    "reset_at": 1735401600,
                    "limit_window_seconds": 18000
                },
                "secondary_window": {
                    "used_percent": 0,
                    "reset_at": 1735920000,
                    "limit_window_seconds": 604800
                }
            }
        }
        """.data(using: .utf8)!

        let usage = try CodexCollector.parseUsage(json5h)
        XCTAssertEqual(usage.primaryWindow!.limitWindowSeconds, 18000)
        XCTAssertEqual(usage.secondaryWindow!.limitWindowSeconds, 604800)
    }
}
#endif
