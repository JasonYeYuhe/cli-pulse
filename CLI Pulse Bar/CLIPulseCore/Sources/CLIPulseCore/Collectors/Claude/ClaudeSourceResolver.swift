#if os(macOS)
import Foundation

/// Orchestrates Claude usage data fetching across multiple source strategies.
///
/// App-runtime execution order (matches CodexBar `claude.md`):
/// 1. OAuth API (fastest, no async UI issues)
/// 2. CLI PTY probe (runs `claude /usage` in a pseudo-terminal)
/// 3. Web session (cookie-based, slowest, terminal fallback)
///
/// On success from any strategy, returns the result immediately.
/// On failure, logs the error and tries the next strategy.
/// If all strategies fail, throws the most actionable error.
public struct ClaudeSourceResolver: Sendable {

    /// Default strategy order: OAuth → CLI PTY → Web.
    /// Matches CodexBar's documented app-runtime preference.
    public static let defaultStrategies: [any ClaudeSourceStrategy] = [
        ClaudeOAuthStrategy(),
        ClaudeCLIPTYStrategy(),
        ClaudeWebStrategy(),
    ]

    private let strategies: [any ClaudeSourceStrategy]

    public init(strategies: [any ClaudeSourceStrategy]? = nil) {
        self.strategies = strategies ?? Self.defaultStrategies
    }

    /// Resolve Claude usage using the configured strategy chain.
    ///
    /// Respects `config.sourceMode`:
    /// - `.auto`: tries all available strategies in order
    /// - `.oauth` / `.web` / `.cli`: uses only that specific strategy
    /// - Other modes: falls through to auto behavior
    public func resolve(config: ProviderConfig) async throws -> CollectorResult {
        Self.log("resolve start, sourceMode=\(config.sourceMode), helper=\(ClaudeHelperContract.diagnosticSummary())")

        let snapshot: ClaudeSnapshot

        switch config.sourceMode {
        case .oauth:
            snapshot = try await runSingle(ClaudeOAuthStrategy(), config: config, label: "oauth-explicit")
        case .web:
            snapshot = try await runSingle(ClaudeWebStrategy(), config: config, label: "web-explicit")
        case .cli:
            snapshot = try await runSingle(ClaudeCLIPTYStrategy(), config: config, label: "cli-explicit")
        default:
            snapshot = try await runChain(config: config)
        }

        let result = ClaudeResultBuilder.build(from: snapshot)
        Self.logResult(result, source: snapshot.sourceLabel)
        return result
    }

    /// Whether any strategy is available for the given config.
    public func isAvailable(config: ProviderConfig) -> Bool {
        strategies.contains { $0.isAvailable(config: config) }
    }

    // MARK: - Internal

    private func runSingle(_ strategy: any ClaudeSourceStrategy, config: ProviderConfig, label: String) async throws -> ClaudeSnapshot {
        return try await strategy.fetch(config: config)
    }

    private func runChain(config: ProviderConfig) async throws -> ClaudeSnapshot {
        var errors: [(source: String, error: Error)] = []

        for strategy in strategies {
            guard strategy.isAvailable(config: config) else {
                Self.log("[\(strategy.sourceLabel)] skipped: not available")
                continue
            }

            do {
                Self.log("[\(strategy.sourceLabel)] attempting...")
                let snapshot = try await strategy.fetch(config: config)
                Self.log("[\(strategy.sourceLabel)] success")
                // Cache successful result to snapshot file so subsequent
                // 429/401 failures can fall back to the cached data.
                Self.cacheSnapshot(snapshot)
                return snapshot
            } catch {
                let shouldFallback: Bool
                if let stratError = error as? ClaudeStrategyError {
                    shouldFallback = stratError.shouldFallback
                } else {
                    shouldFallback = true
                }

                errors.append((strategy.sourceLabel, error))
                Self.log("[\(strategy.sourceLabel)] failed: \(error.localizedDescription), fallback=\(shouldFallback)")

                if !shouldFallback {
                    throw error
                }
            }
        }

        // All live strategies exhausted — try the snapshot cache as last resort.
        // The cache accepts last-known-good snapshots much longer than the
        // WebStrategy live window, bridging transient 429 rate-limit windows.
        Self.log("[cache] attempting fallback, paths=\(ClaudeHelperContract.snapshotCandidatePaths.joined(separator: ", "))")
        if let cached = Self.readCachedSnapshot() {
            return cached
        }

        // Truly no data available — log and throw
        if let lastError = errors.last {
            let logPath = NSTemporaryDirectory() + "clipulse_claude_fallback.log"
            let timestamp = ISO8601DateFormatter().string(from: Date())
            var msg = "[\(timestamp)] All Claude strategies failed (including cache):\n"
            for (source, err) in errors {
                msg += "  - \(source): \(err.localizedDescription)\n"
            }
            msg += "  - cache: \(ClaudeHelperContract.snapshotCandidatePaths.joined(separator: ", ")) — see resolver log for details\n"
            if let fh = FileHandle(forWritingAtPath: logPath) {
                fh.seekToEndOfFile()
                fh.write(msg.data(using: .utf8) ?? Data())
                fh.closeFile()
            } else {
                try? msg.write(toFile: logPath, atomically: true, encoding: .utf8)
            }

            throw lastError.error
        }

        throw ClaudeStrategyError.noToken
    }

    // MARK: - Snapshot cache (single source of truth: ClaudeHelperContract.snapshotPath)

    /// Max age for cache fallback. WebStrategy stays strict (10 min), but the
    /// resolver can continue serving the last-known-good bars for much longer.
    private static let cacheMaxAge: TimeInterval = ClaudeHelperContract.cacheSnapshotAge

    /// Cache a successful snapshot to disk for fallback during rate-limit windows.
    private static func cacheSnapshot(_ snapshot: ClaudeSnapshot) {
        do {
            try ClaudeHelperContract.writeSnapshot(snapshot)
            log("[cache] wrote snapshot to \(ClaudeHelperContract.snapshotPath)")
        } catch {
            log("[cache] WRITE FAILED: \(error.localizedDescription)")
        }
    }

    /// Read a cached snapshot with full diagnostics.
    /// Accepts snapshots up to `cacheMaxAge` old.
    private static func readCachedSnapshot() -> ClaudeSnapshot? {
        for path in ClaudeHelperContract.snapshotCandidatePaths {
            let exists = FileManager.default.fileExists(atPath: path)
            guard exists else {
                log("[cache] path=\(path) exists=false")
                continue
            }

            guard let data = FileManager.default.contents(atPath: path) else {
                log("[cache] path=\(path) exists=true BUT contents()=nil (permissions?)")
                continue
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log("[cache] path=\(path) exists=true size=\(data.count) BUT JSON parse failed")
                continue
            }

            let fetchedAtStr = json["fetched_at"] as? String ?? "missing"
            let date = ISO8601DateFormatter().date(from: fetchedAtStr)
            let age = date.map { Date().timeIntervalSince($0) } ?? .infinity
            let liveFresh = age <= ClaudeHelperContract.maxSnapshotAge
            let cacheFresh = age <= cacheMaxAge

            log("[cache] path=\(path) exists=true age=\(Int(age))s liveFresh=\(liveFresh) cacheFresh=\(cacheFresh) fetched_at=\(fetchedAtStr)")

            guard cacheFresh else {
                log("[cache] REJECTED path=\(path): age \(Int(age))s > cacheMaxAge \(Int(cacheMaxAge))s")
                continue
            }

            guard let snapshot = ClaudeHelperContract.readSnapshot(
                maxAge: cacheMaxAge,
                sourceLabel: "cache"
            ) else {
                log("[cache] REJECTED path=\(path): helper contract could not parse accepted snapshot")
                continue
            }

            let tierSummary = [
                snapshot.sessionUsed.map { "session=\($0)" },
                snapshot.weeklyUsed.map { "weekly=\($0)" },
                snapshot.sonnetUsed.map { "sonnet=\($0)" },
            ].compactMap { $0 }.joined(separator: " ")
            log("[cache] ACCEPTED path=\(path): source=\(json["source"] ?? "?") \(tierSummary) tier=\(snapshot.rateLimitTier ?? "?")")
            return snapshot
        }

        return nil
    }

    private static func log(_ message: String) {
        #if DEBUG
        print("[ClaudeSourceResolver] \(message)")
        #endif
        appendToLog(message)
    }

    /// Log the final CollectorResult with all fields needed for runtime verification.
    private static func logResult(_ result: CollectorResult, source: String) {
        let u = result.usage
        let tierNames = u.tiers.map { "\($0.name)(\($0.remaining)/\($0.quota))" }.joined(separator: ", ")
        let msg = "SUCCESS source=\(source) provider=\(u.provider) quota=\(u.quota ?? 0) remaining=\(u.remaining ?? 0) tiers.count=\(u.tiers.count) tiers=[\(tierNames)] plan_type=\(u.plan_type ?? "nil") reset_time=\(u.reset_time ?? "nil")"
        log(msg)
    }

    private static func appendToLog(_ message: String) {
        let logPath = NSTemporaryDirectory() + "clipulse_claude_resolver.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile()
            fh.write(entry.data(using: .utf8) ?? Data())
            fh.closeFile()
        } else {
            try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}
#endif
