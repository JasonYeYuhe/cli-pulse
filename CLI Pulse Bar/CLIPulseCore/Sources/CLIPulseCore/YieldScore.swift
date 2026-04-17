import Foundation

/// One day's worth of yield data for a single provider, decoded directly
/// from the `yield_score_daily` rollup table in Supabase.
public struct YieldScoreRow: Codable, Sendable, Hashable {
    public let provider: String
    public let day: String              // ISO date (YYYY-MM-DD)
    public let total_cost: Double
    public let weighted_commit_count: Double
    public let raw_commit_count: Int
    public let ambiguous_commit_count: Int

    public var providerKind: ProviderKind? { ProviderKind(rawValue: provider) }
    public var dayDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: day)
    }
}

/// A per-provider yield summary aggregated over a user-chosen window
/// (e.g. last 7/30/90 days). Computed client-side from `YieldScoreRow`s.
public struct YieldScoreSummary: Identifiable, Sendable, Hashable {
    public let id: String                    // provider name doubles as identifier
    public let provider: String
    public let totalCost: Double
    /// Sum of normalized weights across the window. May be fractional when
    /// commits are co-attributed across multiple overlapping sessions.
    public let weightedCommits: Double
    /// Total commit count, ignoring weighting (informational only).
    public let rawCommits: Int
    public let ambiguousCommits: Int
    public let rangeStart: Date
    public let rangeEnd: Date

    /// Cost per weighted commit, or nil when no commits attributed.
    public var costPerCommit: Double? {
        guard weightedCommits > 0 else { return nil }
        return totalCost / weightedCommits
    }

    public var providerKind: ProviderKind? { ProviderKind(rawValue: provider) }

    public init(
        provider: String, totalCost: Double, weightedCommits: Double,
        rawCommits: Int, ambiguousCommits: Int,
        rangeStart: Date, rangeEnd: Date
    ) {
        self.id = provider
        self.provider = provider
        self.totalCost = totalCost
        self.weightedCommits = weightedCommits
        self.rawCommits = rawCommits
        self.ambiguousCommits = ambiguousCommits
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }
}

public enum YieldScoreRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"

    public var id: String { rawValue }

    public var days: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        }
    }

    public var label: String {
        switch self {
        case .sevenDays: return "Last 7 days"
        case .thirtyDays: return "Last 30 days"
        case .ninetyDays: return "Last 90 days"
        }
    }
}

public enum YieldScoreAggregator {
    /// Aggregate raw daily rows into per-provider summaries over a date window.
    /// `now` defaults to the current date so callers in tests can pin time.
    public static func summarize(
        rows: [YieldScoreRow],
        range: YieldScoreRange,
        now: Date = Date()
    ) -> [YieldScoreSummary] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: now) ?? now
        let windowStart = Calendar.current.startOfDay(for: cutoff)
        let windowEnd = now

        // Bucket by provider, summing weights/cost within the window
        var buckets: [String: (cost: Double, weighted: Double, raw: Int, ambiguous: Int)] = [:]
        for row in rows {
            guard let day = row.dayDate, day >= windowStart, day <= windowEnd else { continue }
            var entry = buckets[row.provider] ?? (0, 0, 0, 0)
            entry.cost += row.total_cost
            entry.weighted += row.weighted_commit_count
            entry.raw += row.raw_commit_count
            entry.ambiguous += row.ambiguous_commit_count
            buckets[row.provider] = entry
        }

        return buckets.map { (provider, data) in
            YieldScoreSummary(
                provider: provider,
                totalCost: data.cost,
                weightedCommits: data.weighted,
                rawCommits: data.raw,
                ambiguousCommits: data.ambiguous,
                rangeStart: windowStart,
                rangeEnd: windowEnd
            )
        }.sorted { ($0.costPerCommit ?? .infinity) < ($1.costPerCommit ?? .infinity) }
    }
}
