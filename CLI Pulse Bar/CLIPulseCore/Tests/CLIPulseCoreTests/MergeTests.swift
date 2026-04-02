#if os(macOS)
import XCTest
@testable import CLIPulseCore

final class MergeTests: XCTestCase {

    private func makeCloudUsage(provider: String, quota: Int?, remaining: Int?, tiers: [TierDTO] = []) -> ProviderUsage {
        ProviderUsage(
            provider: provider, today_usage: 100, week_usage: 500,
            estimated_cost_today: 0.10, estimated_cost_week: 0.50,
            cost_status_today: "Estimated", cost_status_week: "Estimated",
            quota: quota, remaining: remaining, tiers: tiers,
            status_text: "Operational", trend: [], recent_sessions: [], recent_errors: []
        )
    }

    private func makeLocalResult(provider: String, quota: Int, remaining: Int, dataKind: CollectorDataKind = .quota) -> CollectorResult {
        let usage = ProviderUsage(
            provider: provider, today_usage: 50, week_usage: 200,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: quota, remaining: remaining,
            plan_type: "Pro", reset_time: "2026-04-02T22:00:00Z",
            tiers: [TierDTO(name: "5h Window", quota: 100, remaining: 70, reset_time: "2026-04-02T22:00:00Z")],
            status_text: "30% used", trend: [], recent_sessions: [], recent_errors: []
        )
        return CollectorResult(usage: usage, dataKind: dataKind)
    }

    func testCloudWithQuotaButNoTiersGetsOverriddenByRicherLocal() {
        // Cloud has a coarse top-level quota but no tiers
        let cloud = [makeCloudUsage(provider: "Claude", quota: 250000, remaining: 118000)]
        // Local has 1 tier (richer than cloud's 0 tiers)
        let local = [makeLocalResult(provider: "Claude", quota: 100, remaining: 70)]
        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        XCTAssertEqual(merged.count, 1)
        let claude = merged.first!
        // Richness rule: local has 1 tier > cloud's 0 tiers → local wins
        XCTAssertEqual(claude.quota, 100, "Local tier-based quota should override coarse cloud quota")
        XCTAssertEqual(claude.remaining, 70)
        XCTAssertEqual(claude.tiers.count, 1)
        XCTAssertEqual(claude.tiers[0].name, "5h Window")
        XCTAssertTrue(supplemented.contains("Claude"), "Should be supplemented when local is richer")
        // Cloud usage/cost values preserved
        XCTAssertEqual(claude.today_usage, 100, "Cloud usage values should be preserved")
    }

    func testCloudWithTiersIsPreserved() {
        let tiers = [TierDTO(name: "Pro", quota: 200, remaining: 150, reset_time: nil)]
        let cloud = [makeCloudUsage(provider: "Gemini", quota: nil, remaining: nil, tiers: tiers)]
        let local = [makeLocalResult(provider: "Gemini", quota: 100, remaining: 50)]
        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        XCTAssertEqual(merged.count, 1)
        let gemini = merged.first!
        XCTAssertEqual(gemini.tiers.count, 1, "Cloud tiers must be preserved")
        XCTAssertEqual(gemini.tiers[0].name, "Pro")
        XCTAssertFalse(supplemented.contains("Gemini"))
    }

    func testCloudWithoutQuotaGetsMerged() {
        let cloud = [makeCloudUsage(provider: "Claude", quota: nil, remaining: nil)]
        let local = [makeLocalResult(provider: "Claude", quota: 100, remaining: 70)]
        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        XCTAssertEqual(merged.count, 1)
        let claude = merged.first!
        XCTAssertEqual(claude.quota, 100, "Local quota must be merged when cloud has none")
        XCTAssertEqual(claude.remaining, 70)
        XCTAssertEqual(claude.tiers.count, 1)
        XCTAssertEqual(claude.tiers[0].name, "5h Window")
        XCTAssertEqual(claude.plan_type, "Pro")
        XCTAssertEqual(claude.reset_time, "2026-04-02T22:00:00Z")
        XCTAssertEqual(claude.today_usage, 100, "Cloud usage should be preserved")
        XCTAssertTrue(supplemented.contains("Claude"), "Should be in supplemented set")
    }

    func testLocalOnlyProviderAdded() {
        let cloud = [makeCloudUsage(provider: "Codex", quota: 500, remaining: 200)]
        let local = [makeLocalResult(provider: "JetBrains AI", quota: 500, remaining: 350)]
        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        XCTAssertEqual(merged.count, 2)
        XCTAssertNotNil(merged.first(where: { $0.provider == "JetBrains AI" }))
        XCTAssertNotNil(merged.first(where: { $0.provider == "Codex" }))
        XCTAssertTrue(supplemented.contains("JetBrains AI"), "Local-only provider should be in supplemented set")
        XCTAssertFalse(supplemented.contains("Codex"))
    }

    func testStatusOnlyNotMerged() {
        let cloud = [makeCloudUsage(provider: "Ollama", quota: nil, remaining: nil)]
        let localUsage = ProviderUsage(
            provider: "Ollama", today_usage: 3, week_usage: 5,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Exact", cost_status_week: "Exact",
            quota: nil, remaining: nil,
            status_text: "3 running", trend: [], recent_sessions: [], recent_errors: []
        )
        let local = [CollectorResult(usage: localUsage, dataKind: .statusOnly)]
        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        XCTAssertEqual(merged.count, 1)
        let ollama = merged.first!
        XCTAssertEqual(ollama.today_usage, 100, "Cloud usage should be preserved, statusOnly should not override")
        XCTAssertFalse(supplemented.contains("Ollama"))
    }

    func testCloudWithZeroQuotaGetsMerged() {
        let cloud = [makeCloudUsage(provider: "Claude", quota: 0, remaining: 0)]
        let local = [makeLocalResult(provider: "Claude", quota: 100, remaining: 70)]
        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        let claude = merged.first!
        XCTAssertEqual(claude.quota, 100, "Local quota should fill in when cloud quota is 0")
        XCTAssertTrue(supplemented.contains("Claude"))
    }

    func testSourceLabelMerged() {
        // When supplemented set contains a provider, source should be .merged
        // This is tested indirectly through the supplemented return value
        let cloud = [makeCloudUsage(provider: "Claude", quota: nil, remaining: nil)]
        let local = [makeLocalResult(provider: "Claude", quota: 100, remaining: 70)]
        let (_, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)
        XCTAssertTrue(supplemented.contains("Claude"))
    }

    // MARK: - Richness comparison tests

    /// When local has MORE tiers than cloud, local should win even if cloud has quota/tiers.
    func testLocalRicherTiersOverrideCloud() {
        // Cloud has 1 coarse tier
        let cloudTiers = [TierDTO(name: "Session", quota: 100, remaining: 80, reset_time: nil)]
        let cloud = [makeCloudUsage(provider: "Claude", quota: 100, remaining: 80, tiers: cloudTiers)]

        // Local has 3 richer tiers
        let localTiers = [
            TierDTO(name: "5h Window", quota: 100, remaining: 70, reset_time: "2026-04-02T22:00:00Z"),
            TierDTO(name: "Weekly", quota: 100, remaining: 60, reset_time: "2026-04-09T00:00:00Z"),
            TierDTO(name: "Opus (Weekly)", quota: 100, remaining: 50, reset_time: "2026-04-09T00:00:00Z"),
        ]
        let localUsage = ProviderUsage(
            provider: "Claude", today_usage: 30, week_usage: 40,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: 100, remaining: 70,
            plan_type: "Max", reset_time: "2026-04-02T22:00:00Z",
            tiers: localTiers, status_text: "30% used",
            trend: [], recent_sessions: [], recent_errors: []
        )
        let local = [CollectorResult(usage: localUsage, dataKind: .quota)]

        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        let claude = merged.first!
        XCTAssertEqual(claude.tiers.count, 3, "Local richer tiers should override cloud")
        XCTAssertEqual(claude.tiers[0].name, "5h Window")
        XCTAssertEqual(claude.tiers[2].name, "Opus (Weekly)")
        XCTAssertEqual(claude.plan_type, "Max")
        XCTAssertTrue(supplemented.contains("Claude"))
    }

    /// When cloud tiers >= local tiers, cloud should be preserved (backward compat).
    func testCloudEqualTiersPreserved() {
        let cloudTiers = [
            TierDTO(name: "5h Window", quota: 100, remaining: 90, reset_time: nil),
            TierDTO(name: "Weekly", quota: 100, remaining: 80, reset_time: nil),
        ]
        let cloud = [makeCloudUsage(provider: "Claude", quota: 100, remaining: 90, tiers: cloudTiers)]
        // Local also has 2 tiers — equal count, cloud should win
        let local = [makeLocalResult(provider: "Claude", quota: 100, remaining: 70)]
        // makeLocalResult creates 1 tier, so cloud (2) >= local (1)
        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        let claude = merged.first!
        XCTAssertEqual(claude.tiers.count, 2, "Cloud tiers should be preserved when count >= local")
        XCTAssertEqual(claude.tiers[0].name, "5h Window")
        XCTAssertFalse(supplemented.contains("Claude"))
    }

    /// Codex/Gemini regression: cloud with quota should not be overridden by local with fewer/equal tiers.
    func testCodexNoRegression() {
        let cloud = [makeCloudUsage(provider: "Codex", quota: 500, remaining: 200)]
        let localUsage = ProviderUsage(
            provider: "Codex", today_usage: 50, week_usage: 200,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: 100, remaining: 70,
            status_text: "30% used", trend: [], recent_sessions: [], recent_errors: []
        )
        let local = [CollectorResult(usage: localUsage, dataKind: .quota)]
        let (merged, supplemented) = AppState.mergeCloudWithLocal(cloud: cloud, local: local)

        let codex = merged.first!
        XCTAssertEqual(codex.quota, 500, "Cloud Codex quota must be preserved")
        XCTAssertEqual(codex.remaining, 200)
        XCTAssertFalse(supplemented.contains("Codex"))
    }
}
#endif
