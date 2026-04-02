#if os(macOS)
import XCTest
@testable import CLIPulseCore

final class GeminiCollectorTests: XCTestCase {

    // MARK: - Quota parsing

    func testParseQuotaMultiModel() throws {
        let json = """
        {
            "buckets": [
                {"modelId": "gemini-2.0-pro", "remainingFraction": 0.85, "resetTime": "2026-04-02T15:00:00Z"},
                {"modelId": "gemini-2.0-flash", "remainingFraction": 0.60, "resetTime": "2026-04-02T15:00:00Z"},
                {"modelId": "gemini-2.0-flash-lite", "remainingFraction": 0.95, "resetTime": "2026-04-02T15:00:00Z"}
            ]
        }
        """.data(using: .utf8)!

        let buckets = try GeminiCollector.parseQuota(json)
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets[0].modelId, "gemini-2.0-pro")
        XCTAssertEqual(buckets[0].remainingFraction, 0.85, accuracy: 0.001)
        XCTAssertEqual(buckets[1].modelId, "gemini-2.0-flash")
        XCTAssertEqual(buckets[1].remainingFraction, 0.60, accuracy: 0.001)
        XCTAssertEqual(buckets[2].modelId, "gemini-2.0-flash-lite")
        XCTAssertEqual(buckets[2].remainingFraction, 0.95, accuracy: 0.001)
    }

    func testParseQuotaEmpty() throws {
        let json = """
        { "buckets": [] }
        """.data(using: .utf8)!

        let buckets = try GeminiCollector.parseQuota(json)
        XCTAssertTrue(buckets.isEmpty)
    }

    func testParseQuotaNoBucketsKey() {
        let json = """
        { "error": "no data" }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try GeminiCollector.parseQuota(json))
    }

    func testParseQuotaInvalidJSON() {
        let bad = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try GeminiCollector.parseQuota(bad))
    }

    func testParseQuotaDefaultFraction() throws {
        // Missing remainingFraction should default to 1.0
        let json = """
        { "buckets": [{"modelId": "gemini-pro"}] }
        """.data(using: .utf8)!

        let buckets = try GeminiCollector.parseQuota(json)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].remainingFraction, 1.0, accuracy: 0.001)
    }

    // MARK: - Availability

    func testCollectorKind() {
        XCTAssertEqual(GeminiCollector().kind, .gemini)
    }
}
#endif
