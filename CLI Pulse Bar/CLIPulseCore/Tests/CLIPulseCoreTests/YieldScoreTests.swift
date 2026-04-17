import XCTest
@testable import CLIPulseCore

final class YieldScoreTests: XCTestCase {

    // MARK: - YieldScoreSummary.costPerCommit

    func testCostPerCommitWithCommits() throws {
        let s = makeSummary(totalCost: 10.0, weighted: 5.0, raw: 5)
        XCTAssertEqual(try XCTUnwrap(s.costPerCommit), 2.0, accuracy: 0.001)
    }

    func testCostPerCommitNilWhenNoCommits() {
        let s = makeSummary(totalCost: 5.0, weighted: 0.0, raw: 0)
        XCTAssertNil(s.costPerCommit)
    }

    func testCostPerCommitWithFractionalWeights() {
        // Co-attributed commits produce fractional weight totals
        let s = makeSummary(totalCost: 6.0, weighted: 1.5, raw: 3)
        XCTAssertEqual(s.costPerCommit ?? 0, 4.0, accuracy: 0.001)
    }

    // MARK: - YieldScoreRange

    func testRangeDays() {
        XCTAssertEqual(YieldScoreRange.sevenDays.days, 7)
        XCTAssertEqual(YieldScoreRange.thirtyDays.days, 30)
        XCTAssertEqual(YieldScoreRange.ninetyDays.days, 90)
    }

    func testRangeAllCasesUnique() {
        let ids = YieldScoreRange.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - YieldScoreAggregator.summarize

    func testAggregatorEmptyInputProducesEmptyOutput() {
        let result = YieldScoreAggregator.summarize(rows: [], range: .thirtyDays)
        XCTAssertTrue(result.isEmpty)
    }

    func testAggregatorBucketsByProvider() {
        let now = fixedNow()
        let rows = [
            row(provider: "Claude", daysAgo: 1, cost: 10, weighted: 5, raw: 5, ambig: 0, now: now),
            row(provider: "Claude", daysAgo: 2, cost: 4, weighted: 2, raw: 2, ambig: 1, now: now),
            row(provider: "Cursor", daysAgo: 1, cost: 8, weighted: 4, raw: 5, ambig: 0, now: now),
        ]
        let summaries = YieldScoreAggregator.summarize(rows: rows, range: .thirtyDays, now: now)
        XCTAssertEqual(summaries.count, 2)
        let claude = summaries.first { $0.provider == "Claude" }
        XCTAssertEqual(claude?.totalCost ?? 0, 14, accuracy: 0.001)
        XCTAssertEqual(claude?.weightedCommits ?? 0, 7, accuracy: 0.001)
        XCTAssertEqual(claude?.rawCommits, 7)
        XCTAssertEqual(claude?.ambiguousCommits, 1)
    }

    func testAggregatorExcludesRowsOutsideRange() {
        let now = fixedNow()
        let rows = [
            row(provider: "Claude", daysAgo: 5, cost: 10, weighted: 5, raw: 5, ambig: 0, now: now),
            row(provider: "Claude", daysAgo: 25, cost: 999, weighted: 999, raw: 999, ambig: 0, now: now),
        ]
        let summaries = YieldScoreAggregator.summarize(rows: rows, range: .sevenDays, now: now)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.totalCost ?? 0, 10, accuracy: 0.001,
                       "Row from 25 days ago must be excluded from a 7-day window")
    }

    func testAggregatorIncludesAllRowsForLargestRange() {
        let now = fixedNow()
        let rows = [
            row(provider: "Claude", daysAgo: 1, cost: 1, weighted: 1, raw: 1, ambig: 0, now: now),
            row(provider: "Claude", daysAgo: 89, cost: 1, weighted: 1, raw: 1, ambig: 0, now: now),
        ]
        let summaries = YieldScoreAggregator.summarize(rows: rows, range: .ninetyDays, now: now)
        XCTAssertEqual(summaries.first?.totalCost ?? 0, 2, accuracy: 0.001)
    }

    func testAggregatorRanksByCostPerCommitAscending() {
        // Cursor: $8 / 4 commits = $2.00 (better)
        // Claude: $10 / 2 commits = $5.00 (worse)
        let now = fixedNow()
        let rows = [
            row(provider: "Cursor", daysAgo: 1, cost: 8, weighted: 4, raw: 4, ambig: 0, now: now),
            row(provider: "Claude", daysAgo: 1, cost: 10, weighted: 2, raw: 2, ambig: 0, now: now),
        ]
        let summaries = YieldScoreAggregator.summarize(rows: rows, range: .thirtyDays, now: now)
        XCTAssertEqual(summaries.first?.provider, "Cursor")
        XCTAssertEqual(summaries.last?.provider, "Claude")
    }

    func testAggregatorPushesNoCommitProvidersToBottom() {
        let now = fixedNow()
        let rows = [
            row(provider: "Claude", daysAgo: 1, cost: 5, weighted: 5, raw: 5, ambig: 0, now: now),
            row(provider: "Cursor", daysAgo: 1, cost: 5, weighted: 0, raw: 0, ambig: 0, now: now),
        ]
        let summaries = YieldScoreAggregator.summarize(rows: rows, range: .thirtyDays, now: now)
        XCTAssertEqual(summaries.first?.provider, "Claude",
                       "Provider with commits should rank ahead of provider with none")
        XCTAssertNil(summaries.last?.costPerCommit)
    }

    // MARK: - YieldScoreRow.dayDate parsing

    func testRowDateParsing() {
        let row = YieldScoreRow(
            provider: "Claude", day: "2026-04-17",
            total_cost: 1, weighted_commit_count: 1, raw_commit_count: 1,
            ambiguous_commit_count: 0
        )
        XCTAssertNotNil(row.dayDate)
    }

    func testRowDateParsingInvalid() {
        let row = YieldScoreRow(
            provider: "Claude", day: "not-a-date",
            total_cost: 1, weighted_commit_count: 1, raw_commit_count: 1,
            ambiguous_commit_count: 0
        )
        XCTAssertNil(row.dayDate)
    }

    // MARK: - Helpers

    private func fixedNow() -> Date {
        // Pin to a known UTC midnight so daysAgo arithmetic is stable
        var components = DateComponents()
        components.year = 2026; components.month = 4; components.day = 17
        components.hour = 12; components.minute = 0; components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func row(
        provider: String, daysAgo: Int, cost: Double, weighted: Double,
        raw: Int, ambig: Int, now: Date
    ) -> YieldScoreRow {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return YieldScoreRow(
            provider: provider, day: f.string(from: day),
            total_cost: cost, weighted_commit_count: weighted,
            raw_commit_count: raw, ambiguous_commit_count: ambig
        )
    }

    private func makeSummary(totalCost: Double, weighted: Double, raw: Int) -> YieldScoreSummary {
        YieldScoreSummary(
            provider: "TestProvider", totalCost: totalCost,
            weightedCommits: weighted, rawCommits: raw, ambiguousCommits: 0,
            rangeStart: Date(timeIntervalSince1970: 0),
            rangeEnd: Date(timeIntervalSince1970: 86400)
        )
    }
}
