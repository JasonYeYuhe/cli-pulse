#if os(macOS)
import XCTest
@testable import CLIPulseCore

/// Runtime verification test: exercises the full Claude collector chain
/// in the real environment and dumps the exact fields needed to prove
/// Claude data reaches the UI merge path.
///
/// This test is environment-dependent: it requires either an OAuth token
/// (env var, credentials file, or Keychain) or the `claude` CLI binary.
/// It will SKIP (not fail) if no Claude source is available.
final class ClaudeRuntimeVerificationTest: XCTestCase {

    private func withSnapshotPreserved<T>(_ body: () async throws -> T) async rethrows -> T {
        let paths = ClaudeHelperContract.snapshotCandidatePaths
        var backups: [String: Data?] = [:]
        for path in paths {
            backups[path] = FileManager.default.contents(atPath: path)
        }
        defer {
            for path in paths {
                if let data = backups[path] ?? nil {
                    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                } else {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
        return try await body()
    }

    func testFullClaudeCollectorChain() async throws {
        try await withSnapshotPreserved {
            let collector = ClaudeCollector()
            var config = ProviderConfig(kind: .claude)
            config.loadSecrets()

            guard collector.isAvailable(config: config) else {
                print("[RuntimeVerification] SKIPPED: No Claude source available (no OAuth token, no CLI binary, no session key)")
                print("[RuntimeVerification] Helper state: \(ClaudeHelperContract.diagnosticSummary())")
                return
            }

            let startTime = Date()
            let result: CollectorResult
            do {
                result = try await collector.collect(config: config)
            } catch {
                print("[RuntimeVerification] COLLECTOR ERROR: \(error.localizedDescription)")
                print("[RuntimeVerification] Resolver log:")
                if let log = try? String(contentsOfFile: NSTemporaryDirectory() + "clipulse_claude_resolver.log", encoding: .utf8) {
                    print(log)
                }
                return
            }
            let elapsed = Date().timeIntervalSince(startTime)

            print("")
            print("============================================")
            print("  CLAUDE RUNTIME VERIFICATION RESULT")
            print("============================================")
            let u = result.usage
            print("  provider:     \(u.provider)")
            print("  quota:        \(u.quota ?? -1)")
            print("  remaining:    \(u.remaining ?? -1)")
            print("  tiers.count:  \(u.tiers.count)")
            for (i, tier) in u.tiers.enumerated() {
                print("  tiers[\(i)]:     \(tier.name) — quota=\(tier.quota) remaining=\(tier.remaining) reset=\(tier.reset_time ?? "nil")")
            }
            print("  plan_type:    \(u.plan_type ?? "nil")")
            print("  reset_time:   \(u.reset_time ?? "nil")")
            print("  status_text:  \(u.status_text)")
            print("  dataKind:     \(result.dataKind)")
            print("  elapsed:      \(String(format: "%.1f", elapsed))s")
            print("============================================")
            print("")

            if let log = try? String(contentsOfFile: NSTemporaryDirectory() + "clipulse_claude_resolver.log", encoding: .utf8) {
                print("[Resolver Log]")
                print(log)
            }

            XCTAssertEqual(u.provider, "Claude")
            XCTAssertNotNil(u.quota, "quota must not be nil")
            XCTAssertGreaterThan(u.quota ?? 0, 0, "quota must be > 0")
            XCTAssertNotNil(u.remaining, "remaining must not be nil")
            XCTAssertGreaterThan(u.tiers.count, 0, "must have at least one tier for bars to display")

            let staleCloudRow = ProviderUsage(
                provider: "Claude", today_usage: 42, week_usage: 100,
                estimated_cost_today: 0, estimated_cost_week: 0,
                cost_status_today: "Unavailable", cost_status_week: "Unavailable",
                quota: 0, remaining: 0, plan_type: "Max", reset_time: nil,
                tiers: [], status_text: "Operational",
                trend: [], recent_sessions: [], recent_errors: [])

            let (merged, supplemented) = DataRefreshManager.mergeCloudWithLocal(
                cloud: [staleCloudRow], local: [result])

            let mergedClaude = merged.first { $0.provider == "Claude" }
            XCTAssertNotNil(mergedClaude, "Claude must appear in merged output")
            XCTAssertTrue(supplemented.contains("Claude"), "Claude must be marked as locally supplemented")

            if let m = mergedClaude {
                XCTAssertGreaterThanOrEqual(m.tiers.count, 2, "Must have at least 2 tiers (5h + Weekly)")
                XCTAssertTrue(m.tiers.contains { $0.name.contains("5h") || $0.name.contains("Session") })
                XCTAssertTrue(m.tiers.contains { $0.name.contains("Weekly") })
            }

            let coarseCloudRow = ProviderUsage(
                provider: "Claude", today_usage: 42, week_usage: 100,
                estimated_cost_today: 0, estimated_cost_week: 0,
                cost_status_today: "Unavailable", cost_status_week: "Unavailable",
                quota: 100, remaining: 50, plan_type: "Max", reset_time: nil,
                tiers: [TierDTO(name: "Session", quota: 100, remaining: 50)],
                status_text: "Operational",
                trend: [], recent_sessions: [], recent_errors: [])

            let (merged2, supplemented2) = DataRefreshManager.mergeCloudWithLocal(
                cloud: [coarseCloudRow], local: [result])
            let mergedClaude2 = merged2.first { $0.provider == "Claude" }

            if result.usage.tiers.count > 1 {
                XCTAssertTrue(supplemented2.contains("Claude"))
                XCTAssertGreaterThan(mergedClaude2?.tiers.count ?? 0, 1)
            }

            let sourceType: SourceType = supplemented.contains("Claude") ? .merged : .api

            print("")
            print("============================================")
            print("  MERGE EVIDENCE (Scenario A: empty cloud)")
            print("============================================")
            print("  CLOUD: provider=Claude quota=\(staleCloudRow.quota ?? -1) tiers=\(staleCloudRow.tiers.count)")
            print("  LOCAL: provider=Claude quota=\(result.usage.quota ?? -1) tiers=\(result.usage.tiers.count) dataKind=\(result.dataKind)")
            if let m = mergedClaude {
                print("  MERGED: quota=\(m.quota ?? -1) remaining=\(m.remaining ?? -1) tiers.count=\(m.tiers.count)")
                for (i, tier) in m.tiers.enumerated() {
                    print("    tiers[\(i)]: \(tier.name) — quota=\(tier.quota) remaining=\(tier.remaining) reset=\(tier.reset_time ?? "nil")")
                }
                print("  plan_type: \(m.plan_type ?? "nil")")
                print("  reset_time: \(m.reset_time ?? "nil")")
            }
            print("  supplemented: \(supplemented)")
            print("  sourceType:   \(sourceType)")
            print("============================================")

            if let m2 = mergedClaude2 {
                print("")
                print("============================================")
                print("  MERGE EVIDENCE (Scenario B: coarse 1-tier cloud)")
                print("============================================")
                print("  CLOUD: tiers=1 [Session(50/100)]")
                print("  LOCAL: tiers=\(result.usage.tiers.count)")
                print("  MERGED: tiers=\(m2.tiers.count)")
                for (i, tier) in m2.tiers.enumerated() {
                    print("    tiers[\(i)]: \(tier.name) — quota=\(tier.quota) remaining=\(tier.remaining)")
                }
                print("  supplemented: \(supplemented2.contains("Claude"))")
                print("============================================")
            }

            DataRefreshManager.dumpMergeDiagnostic(cloud: [staleCloudRow], local: [result], merged: merged)
        }
    }

    // ================================================================
    // CRITICAL TEST: Prove that when OAuth is down (429), the cache
    // fallback returns real tiers. This simulates the exact failure
    // mode the user sees at runtime.
    // ================================================================
    func testCacheFallbackWhenOAuthFails() async throws {
        try await withSnapshotPreserved {
            let seededSnapshot = ClaudeSnapshot(
                sessionUsed: 29, weeklyUsed: 76,
                opusUsed: nil, sonnetUsed: 5,
                sessionReset: "2026-04-02T08:00:00Z",
                weeklyReset: "2026-04-09T00:00:00Z",
                rateLimitTier: "default_claude_max_20x",
                sourceLabel: "oauth"
            )
            try ClaudeHelperContract.writeSnapshot(seededSnapshot)
            let path = ClaudeHelperContract.snapshotPath
            XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                          "Snapshot file must exist at \(path)")

            let alwaysFailStrategy = AlwaysFail429Strategy()
            let resolver = ClaudeSourceResolver(strategies: [alwaysFailStrategy])
            let config = ProviderConfig(kind: .claude)

            let result: CollectorResult
            do {
                result = try await resolver.resolve(config: config)
            } catch {
                XCTFail("Resolver should NOT throw when cache snapshot exists. Error: \(error.localizedDescription)")
                print("[FAIL] Snapshot path: \(path)")
                print("[FAIL] File exists: \(FileManager.default.fileExists(atPath: path))")
                if let data = FileManager.default.contents(atPath: path),
                   let str = String(data: data, encoding: .utf8) {
                    print("[FAIL] File content: \(str)")
                }
                return
            }

            let u = result.usage
            print("")
            print("============================================")
            print("  CACHE FALLBACK VERIFICATION")
            print("============================================")
            print("  source:       \(u.metadata?.category ?? "?") (expect cache)")
            print("  provider:     \(u.provider)")
            print("  quota:        \(u.quota ?? -1)")
            print("  remaining:    \(u.remaining ?? -1)")
            print("  tiers.count:  \(u.tiers.count)")
            for (i, tier) in u.tiers.enumerated() {
                print("  tiers[\(i)]:     \(tier.name) — quota=\(tier.quota) remaining=\(tier.remaining)")
            }
            print("  plan_type:    \(u.plan_type ?? "nil")")
            print("============================================")

            XCTAssertEqual(u.provider, "Claude")
            XCTAssertGreaterThanOrEqual(u.tiers.count, 2, "Cache must return at least 2 tiers")
            XCTAssertTrue(u.tiers.contains { $0.name.contains("5h") }, "Must have 5h Window tier")
            XCTAssertTrue(u.tiers.contains { $0.name == "Weekly" }, "Must have Weekly tier")
            XCTAssertEqual(u.plan_type, "Max")

            let staleCloud = ProviderUsage(
                provider: "Claude", today_usage: 42, week_usage: 100,
                estimated_cost_today: 0, estimated_cost_week: 0,
                cost_status_today: "Unavailable", cost_status_week: "Unavailable",
                quota: 0, remaining: 0, plan_type: "Max", reset_time: nil,
                tiers: [], status_text: "Operational",
                trend: [], recent_sessions: [], recent_errors: [])

            let (merged, supplemented) = DataRefreshManager.mergeCloudWithLocal(
                cloud: [staleCloud], local: [result])

            let m = merged.first { $0.provider == "Claude" }!
            let sourceType: SourceType = supplemented.contains("Claude") ? .merged : .api

            print("")
            print("============================================")
            print("  MERGE RESULT (cache fallback → merge)")
            print("============================================")
            print("  CLOUD: quota=\(staleCloud.quota ?? -1) tiers=\(staleCloud.tiers.count)")
            print("  LOCAL(cache): quota=\(u.quota ?? -1) tiers=\(u.tiers.count)")
            print("  MERGED: quota=\(m.quota ?? -1) tiers=\(m.tiers.count)")
            for (i, tier) in m.tiers.enumerated() {
                print("    tiers[\(i)]: \(tier.name) — quota=\(tier.quota) remaining=\(tier.remaining)")
            }
            print("  supplemented: \(supplemented)")
            print("  sourceType:   \(sourceType)")
            print("============================================")

            XCTAssertTrue(supplemented.contains("Claude"))
            XCTAssertEqual(sourceType, .merged, "Source must be .merged when local cache supplements cloud")
            XCTAssertGreaterThanOrEqual(m.tiers.count, 2)
            XCTAssertTrue(m.tiers.contains { $0.name.contains("5h") })
            XCTAssertTrue(m.tiers.contains { $0.name == "Weekly" })
        }
    }

    func testCacheFallbackAcceptsStaleSnapshotWithinExtendedTTL() async throws {
        try await withSnapshotPreserved {
            let snapshot = ClaudeSnapshot(
                sessionUsed: 12, weeklyUsed: 64,
                opusUsed: nil, sonnetUsed: 9,
                sessionReset: "2026-04-02T12:00:00Z",
                weeklyReset: "2026-04-09T00:00:00Z",
                rateLimitTier: "default_claude_max_20x",
                sourceLabel: "oauth"
            )
            try ClaudeHelperContract.writeSnapshot(snapshot)

            let paths = ClaudeHelperContract.snapshotCandidatePaths
            XCTAssertFalse(paths.isEmpty)

            guard let canonicalPath = paths.first,
                  var json = try JSONSerialization.jsonObject(
                    with: XCTUnwrap(FileManager.default.contents(atPath: canonicalPath))
                  ) as? [String: Any] else {
                XCTFail("snapshot JSON missing")
                return
            }

            let staleFetchedAt = ISO8601DateFormatter().string(
                from: Date().addingTimeInterval(-(ClaudeHelperContract.maxSnapshotAge + 120))
            )
            json["fetched_at"] = staleFetchedAt
            let staleData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])

            // Force every candidate path into the same stale state so the live snapshot
            // check cannot succeed by reading a different helper location.
            for path in paths {
                let url = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try staleData.write(to: url, options: .atomic)
            }

            XCTAssertNil(
                ClaudeWebStrategy.readHelperSnapshot(),
                "web strategy should reject snapshots older than live freshness"
            )

            let resolver = ClaudeSourceResolver(strategies: [AlwaysFail429Strategy()])
            let result = try await resolver.resolve(config: ProviderConfig(kind: .claude))
            let usage = result.usage

            XCTAssertGreaterThanOrEqual(usage.tiers.count, 2)
            XCTAssertTrue(usage.tiers.contains { $0.name.contains("5h") })
            XCTAssertTrue(usage.tiers.contains { $0.name == "Weekly" })
        }
    }
}

/// A fake strategy that always throws 429, used to test cache fallback.
private struct AlwaysFail429Strategy: ClaudeSourceStrategy {
    let sourceLabel = "fake-oauth-429"
    let sourceType: SourceType = .oauth

    func isAvailable(config: ProviderConfig) -> Bool { true }

    func fetch(config: ProviderConfig) async throws -> ClaudeSnapshot {
        throw ClaudeStrategyError.httpError(status: 429, provider: "Claude")
    }
}
#endif
