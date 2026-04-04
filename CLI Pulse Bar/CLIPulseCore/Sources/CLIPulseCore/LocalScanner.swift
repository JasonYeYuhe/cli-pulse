#if os(macOS)
import Foundation

/// Scans local processes to detect running AI coding tools.
///
/// This is **process-detection only** — it finds running processes whose command
/// lines match known AI tool patterns.  It does NOT perform provider-native
/// collection (no real quota, remaining, tiers, or reset times).  All
/// `ProviderUsage` instances produced here have `quota=nil` and `remaining=nil`.
///
/// For real quota/tier data, the app relies on the backend/helper cloud path
/// (`APIClient.providers()` → `provider_summary` RPC).
public final class LocalScanner: @unchecked Sendable {
    public static let shared = LocalScanner()

    // Patterns for process-based detection of running AI coding tools.
    // NOTE: This is process scanning only — it detects running processes, not
    // provider-native quota/usage data. All results have quota=nil, remaining=nil.
    //
    // Order matters: more-specific patterns must come before less-specific ones
    // for the same keyword (e.g. "Kimi K2" before "Kimi").
    private static let processPatterns: [(provider: String, pattern: String, confidence: String)] = [
        ("Codex", #"\bcodex\b"#, "high"),
        ("Codex", #"\bopenai\b"#, "medium"),
        ("Gemini", #"\bgemini\b"#, "high"),
        ("Claude", #"\bclaude\b"#, "high"),
        ("Cursor", #"\bcursor\b"#, "high"),
        ("OpenCode", #"\bopencode\b"#, "high"),
        ("Copilot", #"\bcopilot\b|\bgithub\.copilot\b"#, "high"),
        ("Ollama", #"\bollama\b"#, "high"),
        ("OpenRouter", #"\bopenrouter\b"#, "high"),
        ("Kilo", #"\bkilo\b|\bkilo[_-]?code\b"#, "high"),
        ("Warp", #"\bwarp\b"#, "medium"),
        ("Augment", #"\baugment\b"#, "medium"),
        ("JetBrains AI", #"\bjetbrains[\s-]?ai\b|\bjbai\b"#, "high"),
        ("Kimi K2", #"\bkimi[\s_-]*k2\b"#, "high"),
        ("Kimi", #"\bkimi\b"#, "high"),
        ("Amp", #"\bamp\b"#, "low"),
        ("MiniMax", #"\bminimax\b"#, "high"),
        ("Alibaba", #"\balibaba\b|\bqwen\b|\btongyi\b"#, "high"),
        ("z.ai", #"\bz\.ai\b|\bzai\b"#, "high"),
        ("Antigravity", #"\bantigravity\b"#, "high"),
        ("Droid", #"\bdroid\b"#, "low"),
        ("Synthetic", #"\bsynthetic\b"#, "medium"),
        ("Kiro", #"\bkiro\b"#, "high"),
        ("Vertex AI", #"\bvertex[\s_-]?ai\b|\bgcloud\b.*\baiplatform\b"#, "high"),
        ("Perplexity", #"\bperplexity\b|\bpplx\b"#, "high"),
        ("Volcano Engine", #"\bvecli\b|\bvolcengine\b|\bdoubao\b|\bvolcano[\s_-]?engine\b|\bark\b.*\bvolc"#, "high"),
    ]

    private static let ignoredPatterns: [String] = [
        #"crashpad"#,
        #"--type=renderer"#,
        #"--type=gpu-process"#,
        #"--utility-sub-type"#,
        #"codex helper"#,
        #"electron framework"#,
        #"\.vscode-server"#,
        #"--ms-enable-electron"#,
        #"node_modules/\.bin"#,
    ]

    private static let confidenceRank: [String: Int] = ["high": 3, "medium": 2, "low": 1]

    /// Pre-compiled regex patterns (compiled once, reused every scan)
    private static let compiledProcessPatterns: [(provider: String, regex: NSRegularExpression, confidence: String)] = {
        processPatterns.compactMap { entry in
            guard let regex = try? NSRegularExpression(pattern: entry.pattern, options: .caseInsensitive) else { return nil }
            return (entry.provider, regex, entry.confidence)
        }
    }()

    private static let compiledIgnorePatterns: [NSRegularExpression] = {
        ignoredPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private init() {}

    /// Scan running processes and return detected AI sessions + provider summary.
    /// - Parameter costRateLookup: Optional closure to look up cost rate per 1K tokens by provider name.
    ///   Falls back to `ProviderKind.defaultCostRate` if nil or if the closure returns nil.
    public func scan(costRateLookup: ((String) -> Double?)? = nil) -> LocalScanResult {
        let rows = listProcesses()
        var sessions: [SessionRecord] = []
        var providerUsage: [String: (usage: Int, sessions: Int, cost: Double)] = [:]
        let now = ISO8601DateFormatter().string(from: Date())
        let hostName = ProcessInfo.processInfo.hostName

        // Track best match per PID to deduplicate
        var bestByPID: [String: (provider: String, confidence: String, row: ProcessRow)] = [:]

        for row in rows {
            guard !shouldIgnore(row.command) else { continue }
            guard let (provider, confidence) = detectProvider(row.command) else { continue }

            if let existing = bestByPID[row.pid] {
                let existingRank = Self.confidenceRank[existing.confidence] ?? 0
                let newRank = Self.confidenceRank[confidence] ?? 0
                if newRank > existingRank {
                    bestByPID[row.pid] = (provider, confidence, row)
                }
            } else {
                bestByPID[row.pid] = (provider, confidence, row)
            }
        }

        for (pid, match) in bestByPID {
            let row = match.row
            let elapsed = elapsedToSeconds(row.etime)
            let cpu = Double(row.pcpu) ?? 0
            let usage = max(500, Int(Double(elapsed) * max(1.5, cpu + 1.0)))
            let cost = estimateCost(provider: match.provider, usage: usage, rateLookup: costRateLookup)
            let project = guessProject(row.command)

            let session = SessionRecord(
                id: "local-\(pid)",
                name: prettyName(row.command),
                provider: match.provider,
                project: project,
                device_name: hostName,
                started_at: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(elapsed))),
                last_active_at: now,
                status: "Running",
                total_usage: usage,
                estimated_cost: cost,
                cost_status: cost > 1 ? "warning" : "normal",
                requests: max(1, elapsed / 45),
                error_count: 0,
                collection_confidence: match.confidence
            )
            sessions.append(session)

            var entry = providerUsage[match.provider] ?? (usage: 0, sessions: 0, cost: 0)
            entry.usage += usage
            entry.sessions += 1
            entry.cost += cost
            providerUsage[match.provider] = entry
        }

        let providers = providerUsage.map { (name, data) in
            ProviderUsage(
                provider: name,
                today_usage: data.usage,
                week_usage: data.usage,
                estimated_cost_today: data.cost,
                estimated_cost_week: data.cost,
                cost_status_today: "normal",
                cost_status_week: "normal",
                quota: nil,
                remaining: nil,
                status_text: "\(data.sessions) active",
                trend: [],
                recent_sessions: [],
                recent_errors: [],
                metadata: nil
            )
        }.sorted { $0.today_usage > $1.today_usage }

        let totalUsage = sessions.reduce(0) { $0 + $1.total_usage }
        let totalCost = sessions.reduce(0) { $0 + $1.estimated_cost }

        return LocalScanResult(
            sessions: sessions,
            providers: providers,
            totalUsage: totalUsage,
            totalCost: totalCost,
            activeSessionCount: sessions.count
        )
    }

    // MARK: - Process listing

    private struct ProcessRow {
        let pid: String
        let pcpu: String
        let pmem: String
        let etime: String
        let command: String
    }

    private func listProcesses() -> [ProcessRow] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,pcpu=,pmem=,etime=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var rows: [ProcessRow] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Parse: PID  CPU  MEM  ETIME  COMMAND...
            let parts = trimmed.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5 else { continue }

            rows.append(ProcessRow(
                pid: parts[0],
                pcpu: parts[1],
                pmem: parts[2],
                etime: parts[3],
                command: parts[4]
            ))
        }
        return rows
    }

    // MARK: - Detection

    /// Detect provider from a command string. Returns (providerName, confidence) or nil.
    /// Exposed as internal for testing.
    func detectProvider(_ command: String) -> (String, String)? {
        let lower = command.lowercased()
        var best: (String, String)? = nil
        var bestRank = 0
        let range = NSRange(lower.startIndex..., in: lower)
        for entry in Self.compiledProcessPatterns {
            if entry.regex.firstMatch(in: lower, range: range) != nil {
                let rank = Self.confidenceRank[entry.confidence] ?? 0
                if rank > bestRank {
                    best = (entry.provider, entry.confidence)
                    bestRank = rank
                }
            }
        }
        return best
    }

    private func shouldIgnore(_ command: String) -> Bool {
        let lower = command.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        for regex in Self.compiledIgnorePatterns {
            if regex.firstMatch(in: lower, range: range) != nil {
                return true
            }
        }
        return false
    }

    private func elapsedToSeconds(_ etime: String) -> Int {
        // Format: [[DD-]HH:]MM:SS
        let parts = etime.replacingOccurrences(of: "-", with: ":").split(separator: ":").map(String.init)
        var seconds = 0
        let nums = parts.compactMap { Int($0) }
        switch nums.count {
        case 4: seconds = nums[0] * 86400 + nums[1] * 3600 + nums[2] * 60 + nums[3]
        case 3: seconds = nums[0] * 3600 + nums[1] * 60 + nums[2]
        case 2: seconds = nums[0] * 60 + nums[1]
        case 1: seconds = nums[0]
        default: break
        }
        return max(1, seconds)
    }

    private func estimateCost(provider: String, usage: Int, rateLookup: ((String) -> Double?)? = nil) -> Double {
        let rate = rateLookup?(provider)
            ?? ProviderKind(rawValue: provider)?.defaultCostRate
            ?? 0.001
        return Double(usage) / 1000.0 * rate
    }

    private func guessProject(_ command: String) -> String {
        // Extract only the leaf directory name — never transmit full paths
        let parts = command.split(separator: " ").map(String.init)
        for part in parts.reversed() {
            if part.contains("/") && !part.hasPrefix("-") && !part.hasPrefix("/usr") && !part.hasPrefix("/bin") && !part.hasPrefix("/opt") {
                let components = part.split(separator: "/")
                if let last = components.last, !last.isEmpty {
                    // Only return the basename, never the full path
                    let name = String(last)
                    // Skip names that look like secrets, tokens, or config files
                    if name.contains("token") || name.contains("secret") || name.contains("key") || name.hasPrefix(".") {
                        continue
                    }
                    return name
                }
            }
        }
        return "unknown"
    }

    private func prettyName(_ command: String) -> String {
        let parts = command.split(separator: " ").map(String.init)
        guard let first = parts.first else { return command }
        let basename = (first as NSString).lastPathComponent
        if basename.count > 30 { return String(basename.prefix(30)) }
        return basename
    }
}

public struct LocalScanResult: Sendable {
    public let sessions: [SessionRecord]
    public let providers: [ProviderUsage]
    public let totalUsage: Int
    public let totalCost: Double
    public let activeSessionCount: Int

    public var isEmpty: Bool { sessions.isEmpty }
}
#endif
