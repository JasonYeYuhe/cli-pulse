#if os(macOS)
import Foundation

/// Defines the contract between the sandboxed app and the unsandboxed helper
/// for Claude data that cannot be collected inside the app sandbox.
///
/// ## Architecture
///
/// The app process is sandboxed and cannot:
/// - Read browser cookie SQLite databases (Safari/Chrome/Firefox)
/// - Run PTY-heavy processes reliably in all contexts
/// - Access cross-app Keychain items without user prompts
///
/// The helper (Python `cli_pulse_helper.py` or future bundled CLI) runs
/// outside the sandbox and performs:
/// 1. Browser cookie extraction → claude.ai web API calls
/// 2. PTY-based `claude /usage` probes
/// 3. Writing normalized results to the app group container or a legacy
///    `~/.clipulse/claude_snapshot.json` fallback when app-group access is unavailable.
///
/// The app reads this file via `ClaudeWebStrategy.readHelperSnapshot()`.
///
/// ## File Paths
///
/// | File | Writer | Reader | Purpose |
/// |------|--------|--------|---------|
/// | `~/Library/Group Containers/group.yyh.CLI-Pulse/claude_snapshot.json` | Helper | App (WebStrategy) | Complete pre-fetched usage data |
/// | `~/Library/Group Containers/group.yyh.CLI-Pulse/claude_session.json` | Helper | App (WebStrategy) | Session key for app-side API calls |
/// | `~/.clipulse/claude_snapshot.json` | Helper | Legacy fallback | Pre-app-group compatibility |
/// | `~/.clipulse/claude_session.json` | Helper | Legacy fallback | Pre-app-group compatibility |
/// | `$TMPDIR/clipulse_claude_resolver.log` | App | Debug | Strategy chain execution log |
/// | `$TMPDIR/clipulse_claude_fallback.log` | App | Debug | Fallback chain failure log |
/// | `$TMPDIR/clipulse_merge_diagnostic.json` | App | Debug | Cloud/local merge verification |
///
/// ## Snapshot JSON Schema
///
/// ```json
/// {
///   "session_used": 45,
///   "weekly_used": 60,
///   "opus_used": 75,
///   "sonnet_used": null,
///   "session_reset": "2026-04-02T22:00:00Z",
///   "weekly_reset": "2026-04-09T00:00:00Z",
///   "rate_limit_tier": "pro",
///   "account_email": "user@example.com",
///   "extra_usage": {
///     "is_enabled": true,
///     "monthly_limit": 50.0,
///     "used_credits": 12.34,
///     "currency": "USD"
///   },
///   "fetched_at": "2026-04-02T14:30:00Z",
///   "source": "web"
/// }
/// ```
///
/// ## Freshness
///
/// Snapshots older than 10 minutes are rejected. The helper should write
/// a new snapshot at least every 5 minutes during active use.
public enum ClaudeHelperContract {
    public static let appGroupID = "group.yyh.CLI-Pulse"

    /// Legacy helper directory before the app-group migration.
    public static var legacyHelperDir: String {
        (ClaudeCredentials.realHomeDir as NSString).appendingPathComponent(".clipulse")
    }

    /// App-group container directory when available to the running process.
    public static var appGroupHelperDir: String? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .path
    }

    /// Directory where helper writes Claude data files.
    public static var helperDir: String {
        appGroupHelperDir ?? legacyHelperDir
    }

    /// Path to the complete snapshot file.
    public static var snapshotPath: String {
        (helperDir as NSString).appendingPathComponent("claude_snapshot.json")
    }

    /// Path to the session key file.
    public static var sessionKeyPath: String {
        (helperDir as NSString).appendingPathComponent("claude_session.json")
    }

    /// Snapshot paths to probe in priority order.
    public static var snapshotCandidatePaths: [String] {
        var paths: [String] = []
        if let appGroupHelperDir {
            paths.append((appGroupHelperDir as NSString).appendingPathComponent("claude_snapshot.json"))
        }
        paths.append((legacyHelperDir as NSString).appendingPathComponent("claude_snapshot.json"))
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    /// Session key paths to probe in priority order.
    public static var sessionKeyCandidatePaths: [String] {
        var paths: [String] = []
        if let appGroupHelperDir {
            paths.append((appGroupHelperDir as NSString).appendingPathComponent("claude_session.json"))
        }
        paths.append((legacyHelperDir as NSString).appendingPathComponent("claude_session.json"))
        return Array(NSOrderedSet(array: paths)) as? [String] ?? paths
    }

    /// Maximum age (seconds) before a snapshot is considered stale.
    public static let maxSnapshotAge: TimeInterval = 600 // 10 minutes

    /// Extended age for last-known-good cache fallback.
    /// This is intentionally much longer than `maxSnapshotAge` so the app can
    /// keep showing the last successful bars during transient OAuth 429 windows.
    public static let cacheSnapshotAge: TimeInterval = 86_400 // 24 hours

    /// Ensure the helper directory exists.
    public static func ensureHelperDir() {
        try? FileManager.default.createDirectory(
            atPath: helperDir, withIntermediateDirectories: true)
    }

    /// Write a snapshot from the helper side.
    /// Called by helper/CLI tools running outside the sandbox.
    public static func writeSnapshot(_ snapshot: ClaudeSnapshot) throws {
        ensureHelperDir()
        var dict: [String: Any] = [
            "fetched_at": ISO8601DateFormatter().string(from: Date()),
            "source": snapshot.sourceLabel,
        ]
        if let v = snapshot.sessionUsed { dict["session_used"] = v }
        if let v = snapshot.weeklyUsed { dict["weekly_used"] = v }
        if let v = snapshot.opusUsed { dict["opus_used"] = v }
        if let v = snapshot.sonnetUsed { dict["sonnet_used"] = v }
        if let v = snapshot.sessionReset { dict["session_reset"] = v }
        if let v = snapshot.weeklyReset { dict["weekly_reset"] = v }
        if let v = snapshot.rateLimitTier { dict["rate_limit_tier"] = v }
        if let v = snapshot.accountEmail { dict["account_email"] = v }
        if let e = snapshot.extraUsage {
            var extra: [String: Any] = ["is_enabled": e.isEnabled]
            if let v = e.monthlyLimit { extra["monthly_limit"] = v }
            if let v = e.usedCredits { extra["used_credits"] = v }
            if let v = e.currency { extra["currency"] = v }
            dict["extra_usage"] = extra
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
    }

    /// Write a session key from the helper side.
    public static func writeSessionKey(_ sessionKey: String, source: String = "browser") throws {
        ensureHelperDir()
        let dict: [String: Any] = [
            "sessionKey": sessionKey,
            "source": source,
            "fetched_at": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: sessionKeyPath), options: .atomic)
    }

    /// Check if a fresh helper snapshot exists.
    public static func hasFreshSnapshot() -> Bool {
        ClaudeWebStrategy.readHelperSnapshot() != nil
    }

    /// Read a helper snapshot with a caller-provided TTL.
    /// Returns nil when the file is missing, malformed, or older than `maxAge`.
    public static func readSnapshot(maxAge: TimeInterval, sourceLabel: String) -> ClaudeSnapshot? {
        for path in snapshotCandidatePaths {
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let fetchedDate = (json["fetched_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            if let date = fetchedDate,
               Date().timeIntervalSince(date) > maxAge {
                continue
            }

            var extra: ClaudeExtraUsage? = nil
            if let e = json["extra_usage"] as? [String: Any] {
                let isEnabled = e["is_enabled"] as? Bool ?? false
                if isEnabled {
                    extra = ClaudeExtraUsage(
                        isEnabled: true,
                        monthlyLimit: (e["monthly_limit"] as? NSNumber)?.doubleValue,
                        usedCredits: (e["used_credits"] as? NSNumber)?.doubleValue,
                        currency: e["currency"] as? String
                    )
                }
            }

            let normalizedSessionReset = normalizeSessionReset(
                json["session_reset"] as? String,
                reference: fetchedDate ?? Date()
            )
            let normalizedWeeklyReset = normalizeWeeklyReset(
                json["weekly_reset"] as? String,
                reference: fetchedDate ?? Date()
            )

            return ClaudeSnapshot(
                sessionUsed: json["session_used"] as? Int,
                weeklyUsed: json["weekly_used"] as? Int,
                opusUsed: json["opus_used"] as? Int,
                sonnetUsed: json["sonnet_used"] as? Int,
                sessionReset: normalizedSessionReset,
                weeklyReset: normalizedWeeklyReset,
                extraUsage: extra,
                rateLimitTier: json["rate_limit_tier"] as? String,
                accountEmail: json["account_email"] as? String,
                sourceLabel: sourceLabel
            )
        }
        return nil
    }

    /// Claude's weekly usage page currently resets on Friday 11:00 PM local time.
    /// Helper snapshots have occasionally persisted incorrect UTC-midnight placeholders;
    /// when that happens, prefer the canonical weekly reset instead of showing a bogus 6d+ countdown.
    static func normalizeWeeklyReset(_ raw: String?, reference: Date) -> String? {
        let canonical = canonicalWeeklyReset(after: reference)
        guard let canonical else { return raw }
        guard let raw,
              let parsed = parseISO8601(raw)
        else {
            return ISO8601DateFormatter().string(from: canonical)
        }

        let delta = abs(parsed.timeIntervalSince(canonical))
        if delta <= 6 * 3600 {
            return ISO8601DateFormatter().string(from: parsed)
        }
        return ISO8601DateFormatter().string(from: canonical)
    }

    /// Session resets are rolling; if a cached reset is already behind the snapshot fetch time,
    /// hide it rather than displaying `ago` or a stale future.
    static func normalizeSessionReset(_ raw: String?, reference: Date) -> String? {
        guard let raw,
              let parsed = parseISO8601(raw)
        else {
            return raw
        }
        guard parsed.timeIntervalSince(reference) > 60 else {
            return nil
        }
        return ISO8601DateFormatter().string(from: parsed)
    }

    static func canonicalWeeklyReset(after reference: Date, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.weekday = 6 // Friday in Gregorian calendars where Sunday == 1
        components.hour = 23
        components.minute = 0
        components.second = 0
        return calendar.nextDate(
            after: reference,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw)
    }

    /// Diagnostic: summarize helper file state.
    public static func diagnosticSummary() -> String {
        let fm = FileManager.default
        var lines: [String] = []

        let diagnosticPath = snapshotCandidatePaths.first(where: { fm.fileExists(atPath: $0) })

        if let diagnosticPath {
            if let data = FileManager.default.contents(atPath: diagnosticPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let fetchedAt = json["fetched_at"] as? String,
               let fetched = ISO8601DateFormatter().date(from: fetchedAt) {
                let age = Int(Date().timeIntervalSince(fetched))
                let liveFresh = age < Int(maxSnapshotAge)
                let cacheFresh = age < Int(cacheSnapshotAge)
                lines.append("snapshot: exists, age=\(age)s, liveFresh=\(liveFresh), cacheFresh=\(cacheFresh), path=\(diagnosticPath)")
            } else if let attrs = try? fm.attributesOfItem(atPath: diagnosticPath),
                      let modified = attrs[.modificationDate] as? Date {
                let age = Int(Date().timeIntervalSince(modified))
                let liveFresh = age < Int(maxSnapshotAge)
                let cacheFresh = age < Int(cacheSnapshotAge)
                lines.append("snapshot: exists, age=\(age)s, liveFresh=\(liveFresh), cacheFresh=\(cacheFresh), source=fileDate, path=\(diagnosticPath)")
            } else {
                lines.append("snapshot: exists, age=unknown")
            }
        } else {
            lines.append("snapshot: missing")
        }

        if fm.fileExists(atPath: sessionKeyPath) {
            lines.append("session_key: exists")
        } else {
            lines.append("session_key: missing")
        }

        return lines.joined(separator: ", ")
    }
}
#endif
