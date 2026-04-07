import Foundation

// MARK: - Scan Result (available on all platforms for model compatibility)

/// Result of scanning local JSONL logs for precise token usage and costs.
public struct CostUsageScanResult: Sendable {
    public struct DailyEntry: Sendable {
        public let date: String       // "2026-04-07"
        public let provider: String   // "Codex", "Claude"
        public let model: String      // normalized model name
        public let inputTokens: Int
        public let cachedTokens: Int
        public let outputTokens: Int
        public let costUSD: Double?
    }

    public let entries: [DailyEntry]

    public func totalCost(for date: String) -> Double {
        entries.filter { $0.date == date }.compactMap(\.costUSD).reduce(0, +)
    }

    public func totalCost(provider: String) -> Double {
        entries.filter { $0.provider == provider }.compactMap(\.costUSD).reduce(0, +)
    }

    public var totalCost: Double {
        entries.compactMap(\.costUSD).reduce(0, +)
    }

    public func todayCost(todayKey: String) -> Double {
        totalCost(for: todayKey)
    }
}

#if os(macOS)

// MARK: - Scanner

public enum CostUsageScanner {

    public struct Options: Sendable {
        public var codexSessionsRoot: URL?
        public var claudeProjectsRoots: [URL]?
        public var cacheRoot: URL?
        public var refreshMinIntervalSeconds: TimeInterval = 60
        public var forceRescan: Bool = false
        public var daysToScan: Int = 30

        public init(
            codexSessionsRoot: URL? = nil,
            claudeProjectsRoots: [URL]? = nil,
            cacheRoot: URL? = nil,
            daysToScan: Int = 30
        ) {
            self.codexSessionsRoot = codexSessionsRoot
            self.claudeProjectsRoots = claudeProjectsRoots
            self.cacheRoot = cacheRoot
            self.daysToScan = daysToScan
        }
    }

    /// Main entry point. Scans Codex and Claude JSONL logs for the last N days.
    public static func scan(options: Options = Options()) -> CostUsageScanResult {
        let now = Date()
        let since = Calendar.current.date(byAdding: .day, value: -options.daysToScan, to: now) ?? now
        let range = DayRange(since: since, until: now)

        var allEntries: [CostUsageScanResult.DailyEntry] = []

        // Scan Codex
        let codexCache = scanCodexProvider(range: range, now: now, options: options)
        allEntries.append(contentsOf: entriesFromCodexCache(codexCache, range: range))

        // Scan Claude
        let claudeCache = scanClaudeProvider(range: range, now: now, options: options)
        allEntries.append(contentsOf: entriesFromClaudeCache(claudeCache, range: range))

        return CostUsageScanResult(entries: allEntries)
    }

    // MARK: - Convert cache to result entries

    private static func entriesFromCodexCache(_ cache: CostUsageCache, range: DayRange) -> [CostUsageScanResult.DailyEntry] {
        var result: [CostUsageScanResult.DailyEntry] = []
        let dayKeys = cache.days.keys.sorted().filter {
            DayRange.isInRange(dayKey: $0, since: range.sinceKey, until: range.untilKey)
        }
        for day in dayKeys {
            guard let models = cache.days[day] else { continue }
            for (model, packed) in models {
                let input = packed[safeIdx: 0] ?? 0
                let cached = packed[safeIdx: 1] ?? 0
                let output = packed[safeIdx: 2] ?? 0
                guard input > 0 || cached > 0 || output > 0 else { continue }
                let cost = Pricing.codexCostUSD(model: model, inputTokens: input, cachedInputTokens: cached, outputTokens: output)
                result.append(.init(date: day, provider: "Codex", model: model, inputTokens: input, cachedTokens: cached, outputTokens: output, costUSD: cost))
            }
        }
        return result
    }

    private static func entriesFromClaudeCache(_ cache: CostUsageCache, range: DayRange) -> [CostUsageScanResult.DailyEntry] {
        var result: [CostUsageScanResult.DailyEntry] = []
        let costScale = 1_000_000_000.0
        let dayKeys = cache.days.keys.sorted().filter {
            DayRange.isInRange(dayKey: $0, since: range.sinceKey, until: range.untilKey)
        }
        for day in dayKeys {
            guard let models = cache.days[day] else { continue }
            for (model, packed) in models {
                let input = packed[safeIdx: 0] ?? 0
                let cacheRead = packed[safeIdx: 1] ?? 0
                let cacheCreate = packed[safeIdx: 2] ?? 0
                let output = packed[safeIdx: 3] ?? 0
                let costNanos = packed[safeIdx: 4] ?? 0
                guard input > 0 || cacheRead > 0 || cacheCreate > 0 || output > 0 else { continue }
                let cost: Double? = costNanos > 0
                    ? Double(costNanos) / costScale
                    : Pricing.claudeCostUSD(model: model, inputTokens: input, cacheReadInputTokens: cacheRead, cacheCreationInputTokens: cacheCreate, outputTokens: output)
                result.append(.init(date: day, provider: "Claude", model: model, inputTokens: input, cachedTokens: cacheRead + cacheCreate, outputTokens: output, costUSD: cost))
            }
        }
        return result
    }

    // MARK: - Day Range

    public struct DayRange {
        let sinceKey: String
        let untilKey: String
        let scanSinceKey: String
        let scanUntilKey: String

        init(since: Date, until: Date) {
            self.sinceKey = Self.dayKey(from: since)
            self.untilKey = Self.dayKey(from: until)
            self.scanSinceKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: -1, to: since) ?? since)
            self.scanUntilKey = Self.dayKey(from: Calendar.current.date(byAdding: .day, value: 1, to: until) ?? until)
        }

        public static func dayKey(from date: Date) -> String {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", comps.year ?? 1970, comps.month ?? 1, comps.day ?? 1)
        }

        static func isInRange(dayKey: String, since: String, until: String) -> Bool {
            dayKey >= since && dayKey <= until
        }
    }

    // MARK: - JSONL Parser

    private struct JsonlLine {
        let bytes: Data
        let wasTruncated: Bool
    }

    @discardableResult
    private static func scanJsonl(
        fileURL: URL,
        offset: Int64 = 0,
        maxLineBytes: Int,
        prefixBytes: Int,
        onLine: (JsonlLine) -> Void
    ) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let startOffset = max(0, offset)
        if startOffset > 0 {
            try handle.seek(toOffset: UInt64(startOffset))
        }

        var current = Data()
        current.reserveCapacity(4 * 1024)
        var lineBytes = 0
        var truncated = false
        var bytesRead: Int64 = 0

        func appendSegment(_ segment: Data.SubSequence) {
            guard !segment.isEmpty else { return }
            lineBytes += segment.count
            guard !truncated else { return }
            if lineBytes > maxLineBytes || lineBytes > prefixBytes {
                truncated = true
                current.removeAll(keepingCapacity: true)
                return
            }
            current.append(contentsOf: segment)
        }

        func flushLine() {
            guard lineBytes > 0 else { return }
            onLine(JsonlLine(bytes: current, wasTruncated: truncated))
            current.removeAll(keepingCapacity: true)
            lineBytes = 0
            truncated = false
        }

        while true {
            let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty {
                flushLine()
                break
            }
            bytesRead += Int64(chunk.count)
            var segmentStart = chunk.startIndex
            while let nl = chunk[segmentStart...].firstIndex(of: 0x0A) {
                appendSegment(chunk[segmentStart..<nl])
                flushLine()
                segmentStart = chunk.index(after: nl)
            }
            if segmentStart < chunk.endIndex {
                appendSegment(chunk[segmentStart..<chunk.endIndex])
            }
        }

        return startOffset + bytesRead
    }

    // MARK: - Timestamp Parsing

    static func dayKeyFromTimestamp(_ text: String) -> String? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 20 else { return nil }
        guard bytes[safeUInt8: 4] == 45, bytes[safeUInt8: 7] == 45 else { return nil }
        guard let year = parse4(bytes, at: 0),
              let month = parse2(bytes, at: 5),
              let day = parse2(bytes, at: 8) else { return nil }

        var hour = 0, minute = 0, second = 0
        if bytes[safeUInt8: 10] == 84 {
            guard bytes.count >= 19,
                  bytes[safeUInt8: 13] == 58, bytes[safeUInt8: 16] == 58,
                  let h = parse2(bytes, at: 11), let m = parse2(bytes, at: 14), let s = parse2(bytes, at: 17)
            else { return nil }
            hour = h; minute = m; second = s
        }

        var tzSign = 0
        var tzIndex: Int?
        for idx in stride(from: bytes.count - 1, through: 11, by: -1) {
            let byte = bytes[idx]
            if byte == 90 { tzIndex = idx; tzSign = 0; break }
            if byte == 43 { tzIndex = idx; tzSign = 1; break }
            if byte == 45 { tzIndex = idx; tzSign = -1; break }
        }
        guard let tzStart = tzIndex else { return nil }

        var offsetSeconds = 0
        if tzSign != 0 {
            let offsetStart = tzStart + 1
            guard let hours = parse2(bytes, at: offsetStart) else { return nil }
            var minutes = 0
            if bytes.count > offsetStart + 2 {
                if bytes[safeUInt8: offsetStart + 2] == 58 {
                    if let m = parse2(bytes, at: offsetStart + 3) { minutes = m }
                } else if let m = parse2(bytes, at: offsetStart + 2) {
                    minutes = m
                }
            }
            offsetSeconds = tzSign * (hours * 3600 + minutes * 60)
        }

        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: offsetSeconds)
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        guard let date = comps.date else { return nil }
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let ly = local.year, let lm = local.month, let ld = local.day else { return nil }
        return String(format: "%04d-%02d-%02d", ly, lm, ld)
    }

    private static let isoBox: ISOFormatterBox = ISOFormatterBox()

    static func dayKeyFromParsedISO(_ text: String) -> String? {
        guard let date = isoBox.parse(text) else { return nil }
        return DayRange.dayKey(from: date)
    }

    private static func parse2(_ bytes: [UInt8], at index: Int) -> Int? {
        guard let d0 = parseDigit(bytes[safeUInt8: index]),
              let d1 = parseDigit(bytes[safeUInt8: index + 1]) else { return nil }
        return d0 * 10 + d1
    }

    private static func parse4(_ bytes: [UInt8], at index: Int) -> Int? {
        guard let d0 = parseDigit(bytes[safeUInt8: index]),
              let d1 = parseDigit(bytes[safeUInt8: index + 1]),
              let d2 = parseDigit(bytes[safeUInt8: index + 2]),
              let d3 = parseDigit(bytes[safeUInt8: index + 3]) else { return nil }
        return d0 * 1000 + d1 * 100 + d2 * 10 + d3
    }

    private static func parseDigit(_ byte: UInt8?) -> Int? {
        guard let byte, byte >= 48, byte <= 57 else { return nil }
        return Int(byte - 48)
    }

    // MARK: - Pricing

    enum Pricing {
        struct CodexModel {
            let inputCostPerToken: Double
            let outputCostPerToken: Double
            let cacheReadCostPerToken: Double?
        }

        struct ClaudeModel {
            let inputCostPerToken: Double
            let outputCostPerToken: Double
            let cacheCreationCostPerToken: Double
            let cacheReadCostPerToken: Double
            let thresholdTokens: Int?
            let inputAbove: Double?
            let outputAbove: Double?
            let cacheCreationAbove: Double?
            let cacheReadAbove: Double?
        }

        private static let codexModels: [String: CodexModel] = [
            "gpt-5": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
            "gpt-5-codex": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
            "gpt-5-mini": .init(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadCostPerToken: 2.5e-8),
            "gpt-5-nano": .init(inputCostPerToken: 5e-8, outputCostPerToken: 4e-7, cacheReadCostPerToken: 5e-9),
            "gpt-5-pro": .init(inputCostPerToken: 1.5e-5, outputCostPerToken: 1.2e-4, cacheReadCostPerToken: nil),
            "gpt-5.1": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
            "gpt-5.1-codex": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
            "gpt-5.1-codex-max": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
            "gpt-5.1-codex-mini": .init(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadCostPerToken: 2.5e-8),
            "gpt-5.2": .init(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadCostPerToken: 1.75e-7),
            "gpt-5.2-codex": .init(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadCostPerToken: 1.75e-7),
            "gpt-5.2-pro": .init(inputCostPerToken: 2.1e-5, outputCostPerToken: 1.68e-4, cacheReadCostPerToken: nil),
            "gpt-5.3-codex": .init(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadCostPerToken: 1.75e-7),
            "gpt-5.3-codex-spark": .init(inputCostPerToken: 0, outputCostPerToken: 0, cacheReadCostPerToken: 0),
            "gpt-5.4": .init(inputCostPerToken: 2.5e-6, outputCostPerToken: 1.5e-5, cacheReadCostPerToken: 2.5e-7),
            "gpt-5.4-mini": .init(inputCostPerToken: 7.5e-7, outputCostPerToken: 4.5e-6, cacheReadCostPerToken: 7.5e-8),
            "gpt-5.4-nano": .init(inputCostPerToken: 2e-7, outputCostPerToken: 1.25e-6, cacheReadCostPerToken: 2e-8),
            "gpt-5.4-pro": .init(inputCostPerToken: 3e-5, outputCostPerToken: 1.8e-4, cacheReadCostPerToken: nil),
        ]

        private static let claudeModels: [String: ClaudeModel] = [
            "claude-haiku-4-5-20251001": .init(inputCostPerToken: 1e-6, outputCostPerToken: 5e-6, cacheCreationCostPerToken: 1.25e-6, cacheReadCostPerToken: 1e-7, thresholdTokens: nil, inputAbove: nil, outputAbove: nil, cacheCreationAbove: nil, cacheReadAbove: nil),
            "claude-haiku-4-5": .init(inputCostPerToken: 1e-6, outputCostPerToken: 5e-6, cacheCreationCostPerToken: 1.25e-6, cacheReadCostPerToken: 1e-7, thresholdTokens: nil, inputAbove: nil, outputAbove: nil, cacheCreationAbove: nil, cacheReadAbove: nil),
            "claude-opus-4-5-20251101": .init(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationCostPerToken: 6.25e-6, cacheReadCostPerToken: 5e-7, thresholdTokens: nil, inputAbove: nil, outputAbove: nil, cacheCreationAbove: nil, cacheReadAbove: nil),
            "claude-opus-4-5": .init(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationCostPerToken: 6.25e-6, cacheReadCostPerToken: 5e-7, thresholdTokens: nil, inputAbove: nil, outputAbove: nil, cacheCreationAbove: nil, cacheReadAbove: nil),
            "claude-opus-4-6-20260205": .init(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationCostPerToken: 6.25e-6, cacheReadCostPerToken: 5e-7, thresholdTokens: nil, inputAbove: nil, outputAbove: nil, cacheCreationAbove: nil, cacheReadAbove: nil),
            "claude-opus-4-6": .init(inputCostPerToken: 5e-6, outputCostPerToken: 2.5e-5, cacheCreationCostPerToken: 6.25e-6, cacheReadCostPerToken: 5e-7, thresholdTokens: nil, inputAbove: nil, outputAbove: nil, cacheCreationAbove: nil, cacheReadAbove: nil),
            "claude-sonnet-4-5": .init(inputCostPerToken: 3e-6, outputCostPerToken: 1.5e-5, cacheCreationCostPerToken: 3.75e-6, cacheReadCostPerToken: 3e-7, thresholdTokens: 200_000, inputAbove: 6e-6, outputAbove: 2.25e-5, cacheCreationAbove: 7.5e-6, cacheReadAbove: 6e-7),
            "claude-sonnet-4-5-20250929": .init(inputCostPerToken: 3e-6, outputCostPerToken: 1.5e-5, cacheCreationCostPerToken: 3.75e-6, cacheReadCostPerToken: 3e-7, thresholdTokens: 200_000, inputAbove: 6e-6, outputAbove: 2.25e-5, cacheCreationAbove: 7.5e-6, cacheReadAbove: 6e-7),
            "claude-sonnet-4-6": .init(inputCostPerToken: 3e-6, outputCostPerToken: 1.5e-5, cacheCreationCostPerToken: 3.75e-6, cacheReadCostPerToken: 3e-7, thresholdTokens: 200_000, inputAbove: 6e-6, outputAbove: 2.25e-5, cacheCreationAbove: 7.5e-6, cacheReadAbove: 6e-7),
            "claude-opus-4-20250514": .init(inputCostPerToken: 1.5e-5, outputCostPerToken: 7.5e-5, cacheCreationCostPerToken: 1.875e-5, cacheReadCostPerToken: 1.5e-6, thresholdTokens: nil, inputAbove: nil, outputAbove: nil, cacheCreationAbove: nil, cacheReadAbove: nil),
            "claude-opus-4-1": .init(inputCostPerToken: 1.5e-5, outputCostPerToken: 7.5e-5, cacheCreationCostPerToken: 1.875e-5, cacheReadCostPerToken: 1.5e-6, thresholdTokens: nil, inputAbove: nil, outputAbove: nil, cacheCreationAbove: nil, cacheReadAbove: nil),
            "claude-sonnet-4-20250514": .init(inputCostPerToken: 3e-6, outputCostPerToken: 1.5e-5, cacheCreationCostPerToken: 3.75e-6, cacheReadCostPerToken: 3e-7, thresholdTokens: 200_000, inputAbove: 6e-6, outputAbove: 2.25e-5, cacheCreationAbove: 7.5e-6, cacheReadAbove: 6e-7),
        ]

        static func normalizeCodexModel(_ raw: String) -> String {
            var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("openai/") { trimmed = String(trimmed.dropFirst("openai/".count)) }
            if codexModels[trimmed] != nil { return trimmed }
            if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
                let base = String(trimmed[..<datedSuffix.lowerBound])
                if codexModels[base] != nil { return base }
            }
            return trimmed
        }

        static func normalizeClaudeModel(_ raw: String) -> String {
            var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("anthropic.") { trimmed = String(trimmed.dropFirst("anthropic.".count)) }
            if let lastDot = trimmed.lastIndex(of: "."), trimmed.contains("claude-") {
                let tail = String(trimmed[trimmed.index(after: lastDot)...])
                if tail.hasPrefix("claude-") { trimmed = tail }
            }
            if let vRange = trimmed.range(of: #"-v\d+:\d+$"#, options: .regularExpression) {
                trimmed.removeSubrange(vRange)
            }
            if let baseRange = trimmed.range(of: #"-\d{8}$"#, options: .regularExpression) {
                let base = String(trimmed[..<baseRange.lowerBound])
                if claudeModels[base] != nil { return base }
            }
            return trimmed
        }

        static func codexCostUSD(model: String, inputTokens: Int, cachedInputTokens: Int, outputTokens: Int) -> Double? {
            let key = normalizeCodexModel(model)
            guard let p = codexModels[key] else { return nil }
            let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
            let nonCached = max(0, inputTokens - cached)
            let cachedRate = p.cacheReadCostPerToken ?? p.inputCostPerToken
            return Double(nonCached) * p.inputCostPerToken + Double(cached) * cachedRate + Double(max(0, outputTokens)) * p.outputCostPerToken
        }

        static func claudeCostUSD(model: String, inputTokens: Int, cacheReadInputTokens: Int, cacheCreationInputTokens: Int, outputTokens: Int) -> Double? {
            let key = normalizeClaudeModel(model)
            guard let p = claudeModels[key] else { return nil }

            func tiered(_ tokens: Int, base: Double, above: Double?, threshold: Int?) -> Double {
                guard let threshold, let above else { return Double(tokens) * base }
                let below = min(tokens, threshold)
                let over = max(tokens - threshold, 0)
                return Double(below) * base + Double(over) * above
            }

            return tiered(max(0, inputTokens), base: p.inputCostPerToken, above: p.inputAbove, threshold: p.thresholdTokens)
                + tiered(max(0, cacheReadInputTokens), base: p.cacheReadCostPerToken, above: p.cacheReadAbove, threshold: p.thresholdTokens)
                + tiered(max(0, cacheCreationInputTokens), base: p.cacheCreationCostPerToken, above: p.cacheCreationAbove, threshold: p.thresholdTokens)
                + tiered(max(0, outputTokens), base: p.outputCostPerToken, above: p.outputAbove, threshold: p.thresholdTokens)
        }
    }

    // MARK: - Codex Scanning

    private struct CodexParseResult {
        let days: [String: [String: [Int]]]
        let parsedBytes: Int64
        let lastModel: String?
        let lastTotals: CostUsageCodexTotals?
        let sessionId: String?
    }

    private struct CodexScanState {
        var seenSessionIds: Set<String> = []
        var seenFileIds: Set<String> = []
    }

    private static func defaultCodexSessionsRoot(options: Options) -> URL {
        if let override = options.codexSessionsRoot { return override }
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return URL(fileURLWithPath: env).appendingPathComponent("sessions", isDirectory: true)
        }
        return URL(fileURLWithPath: realUserHome())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func codexSessionsRoots(options: Options) -> [URL] {
        let root = defaultCodexSessionsRoot(options: options)
        var roots = [root]
        if root.lastPathComponent == "sessions" {
            let archived = root.deletingLastPathComponent().appendingPathComponent("archived_sessions", isDirectory: true)
            roots.append(archived)
        }
        return roots
    }

    private static func listCodexSessionFiles(root: URL, scanSinceKey: String, scanUntilKey: String) -> [URL] {
        var out: [URL] = []
        var seen: Set<String> = []

        // Date-partitioned: YYYY/MM/DD/*.jsonl
        if FileManager.default.fileExists(atPath: root.path) {
            var date = parseDayKey(scanSinceKey) ?? Date()
            let untilDate = parseDayKey(scanUntilKey) ?? date
            while date <= untilDate {
                let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
                let y = String(format: "%04d", comps.year ?? 1970)
                let m = String(format: "%02d", comps.month ?? 1)
                let d = String(format: "%02d", comps.day ?? 1)
                let dayDir = root.appendingPathComponent(y).appendingPathComponent(m).appendingPathComponent(d)
                if let items = try? FileManager.default.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for item in items where item.pathExtension.lowercased() == "jsonl" && !seen.contains(item.path) {
                        seen.insert(item.path)
                        out.append(item)
                    }
                }
                date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? untilDate.addingTimeInterval(1)
            }
        }

        // Flat: *.jsonl in root
        if let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for item in items where item.pathExtension.lowercased() == "jsonl" && !seen.contains(item.path) {
                if let dayKey = dayKeyFromFilename(item.lastPathComponent) {
                    if !DayRange.isInRange(dayKey: dayKey, since: scanSinceKey, until: scanUntilKey) { continue }
                }
                seen.insert(item.path)
                out.append(item)
            }
        }

        return out.sorted { $0.path < $1.path }
    }

    private static let codexFilenameDateRegex = try? NSRegularExpression(pattern: "(\\d{4}-\\d{2}-\\d{2})")

    private static func dayKeyFromFilename(_ filename: String) -> String? {
        guard let regex = codexFilenameDateRegex else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range),
              let matchRange = Range(match.range(at: 1), in: filename) else { return nil }
        return String(filename[matchRange])
    }

    private static func fileIdentityString(fileURL: URL) -> String? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let identifier = values.fileResourceIdentifier else { return nil }
        if let data = identifier as? Data { return data.base64EncodedString() }
        return String(describing: identifier)
    }

    private static func parseCodexFile(
        fileURL: URL, range: DayRange,
        startOffset: Int64 = 0,
        initialModel: String? = nil,
        initialTotals: CostUsageCodexTotals? = nil
    ) -> CodexParseResult {
        var currentModel = initialModel
        var previousTotals = initialTotals
        var sessionId: String?
        var days: [String: [String: [Int]]] = [:]

        func add(dayKey: String, model: String, input: Int, cached: Int, output: Int) {
            guard DayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey) else { return }
            let normModel = Pricing.normalizeCodexModel(model)
            var dayModels = days[dayKey] ?? [:]
            var packed = dayModels[normModel] ?? [0, 0, 0]
            packed[0] = (packed[safeIdx: 0] ?? 0) + input
            packed[1] = (packed[safeIdx: 1] ?? 0) + cached
            packed[2] = (packed[safeIdx: 2] ?? 0) + output
            dayModels[normModel] = packed
            days[dayKey] = dayModels
        }

        let maxLineBytes = 256 * 1024
        let prefixBytes = 32 * 1024

        let parsedBytes = (try? scanJsonl(fileURL: fileURL, offset: startOffset, maxLineBytes: maxLineBytes, prefixBytes: prefixBytes, onLine: { line in
            guard !line.bytes.isEmpty, !line.wasTruncated else { return }
            guard line.bytes.asciiContains(#""type":"event_msg""#)
                || line.bytes.asciiContains(#""type":"turn_context""#)
                || line.bytes.asciiContains(#""type":"session_meta""#) else { return }
            if line.bytes.asciiContains(#""type":"event_msg""#), !line.bytes.asciiContains(#""token_count""#) { return }

            guard let obj = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                  let type = obj["type"] as? String else { return }

            if type == "session_meta" {
                if sessionId == nil {
                    let payload = obj["payload"] as? [String: Any]
                    sessionId = payload?["session_id"] as? String ?? payload?["sessionId"] as? String ?? payload?["id"] as? String ?? obj["session_id"] as? String
                }
                return
            }

            guard let tsText = obj["timestamp"] as? String,
                  let dayKey = dayKeyFromTimestamp(tsText) ?? dayKeyFromParsedISO(tsText) else { return }

            if type == "turn_context" {
                if let payload = obj["payload"] as? [String: Any] {
                    if let model = payload["model"] as? String { currentModel = model }
                    else if let info = payload["info"] as? [String: Any], let model = info["model"] as? String { currentModel = model }
                }
                return
            }

            guard type == "event_msg",
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count" else { return }

            let info = payload["info"] as? [String: Any]
            let modelFromInfo = info?["model"] as? String ?? info?["model_name"] as? String ?? payload["model"] as? String ?? obj["model"] as? String
            let model = modelFromInfo ?? currentModel ?? "gpt-5"

            func toInt(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

            let total = info?["total_token_usage"] as? [String: Any]
            let last = info?["last_token_usage"] as? [String: Any]
            var deltaInput = 0, deltaCached = 0, deltaOutput = 0

            if let total {
                let input = toInt(total["input_tokens"])
                let cached = toInt(total["cached_input_tokens"] ?? total["cache_read_input_tokens"])
                let output = toInt(total["output_tokens"])
                deltaInput = max(0, input - (previousTotals?.input ?? 0))
                deltaCached = max(0, cached - (previousTotals?.cached ?? 0))
                deltaOutput = max(0, output - (previousTotals?.output ?? 0))
                previousTotals = CostUsageCodexTotals(input: input, cached: cached, output: output)
            } else if let last {
                deltaInput = max(0, toInt(last["input_tokens"]))
                deltaCached = max(0, toInt(last["cached_input_tokens"] ?? last["cache_read_input_tokens"]))
                deltaOutput = max(0, toInt(last["output_tokens"]))
            } else { return }

            if deltaInput == 0, deltaCached == 0, deltaOutput == 0 { return }
            add(dayKey: dayKey, model: model, input: deltaInput, cached: min(deltaCached, deltaInput), output: deltaOutput)
        })) ?? startOffset

        return CodexParseResult(days: days, parsedBytes: parsedBytes, lastModel: currentModel, lastTotals: previousTotals, sessionId: sessionId)
    }

    private static func scanCodexFile(fileURL: URL, range: DayRange, cache: inout CostUsageCache, state: inout CodexScanState) {
        let path = fileURL.path
        let attrs = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeMs = Int64(mtime * 1000)
        let fileId = fileIdentityString(fileURL: fileURL)

        func dropCachedFile(_ cached: CostUsageFileUsage?) {
            if let cached { applyFileDays(cache: &cache, fileDays: cached.days, sign: -1) }
            cache.files.removeValue(forKey: path)
        }

        if let fileId, state.seenFileIds.contains(fileId) { dropCachedFile(cache.files[path]); return }

        let cached = cache.files[path]
        if let cachedSessionId = cached?.sessionId, state.seenSessionIds.contains(cachedSessionId) { dropCachedFile(cached); return }

        let needsSessionId = cached != nil && cached?.sessionId == nil
        if let cached, cached.mtimeUnixMs == mtimeMs, cached.size == size, !needsSessionId {
            if let sid = cached.sessionId { state.seenSessionIds.insert(sid) }
            if let fid = fileId { state.seenFileIds.insert(fid) }
            return
        }

        // Try incremental parse
        if let cached, cached.sessionId != nil {
            let startOffset = cached.parsedBytes ?? cached.size
            let canIncremental = size > cached.size && startOffset > 0 && startOffset <= size && cached.lastTotals != nil
            if canIncremental {
                let delta = parseCodexFile(fileURL: fileURL, range: range, startOffset: startOffset, initialModel: cached.lastModel, initialTotals: cached.lastTotals)
                let sid = delta.sessionId ?? cached.sessionId
                if let sid, state.seenSessionIds.contains(sid) { dropCachedFile(cached); return }
                if !delta.days.isEmpty { applyFileDays(cache: &cache, fileDays: delta.days, sign: 1) }
                var mergedDays = cached.days
                mergeFileDays(existing: &mergedDays, delta: delta.days)
                cache.files[path] = CostUsageFileUsage(mtimeUnixMs: mtimeMs, size: size, days: mergedDays, parsedBytes: delta.parsedBytes, lastModel: delta.lastModel, lastTotals: delta.lastTotals, sessionId: sid)
                if let sid { state.seenSessionIds.insert(sid) }
                if let fid = fileId { state.seenFileIds.insert(fid) }
                return
            }
        }

        // Full re-parse
        if let cached { applyFileDays(cache: &cache, fileDays: cached.days, sign: -1) }
        let parsed = parseCodexFile(fileURL: fileURL, range: range)
        let sid = parsed.sessionId ?? cached?.sessionId
        if let sid, state.seenSessionIds.contains(sid) { cache.files.removeValue(forKey: path); return }
        let usage = CostUsageFileUsage(mtimeUnixMs: mtimeMs, size: size, days: parsed.days, parsedBytes: parsed.parsedBytes, lastModel: parsed.lastModel, lastTotals: parsed.lastTotals, sessionId: sid)
        cache.files[path] = usage
        applyFileDays(cache: &cache, fileDays: usage.days, sign: 1)
        if let sid { state.seenSessionIds.insert(sid) }
        if let fid = fileId { state.seenFileIds.insert(fid) }
    }

    private static func scanCodexProvider(range: DayRange, now: Date, options: Options) -> CostUsageCache {
        var cache = CostUsageCacheIO.load(provider: "codex", cacheRoot: options.cacheRoot)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let refreshMs = Int64(max(0, options.refreshMinIntervalSeconds) * 1000)
        let shouldRefresh = options.forceRescan || refreshMs == 0 || cache.lastScanUnixMs == 0 || nowMs - cache.lastScanUnixMs > refreshMs

        let roots = codexSessionsRoots(options: options)
        var seenPaths: Set<String> = []
        var files: [URL] = []
        for root in roots {
            for fileURL in listCodexSessionFiles(root: root, scanSinceKey: range.scanSinceKey, scanUntilKey: range.scanUntilKey) where !seenPaths.contains(fileURL.path) {
                seenPaths.insert(fileURL.path)
                files.append(fileURL)
            }
        }
        let filePathsInScan = Set(files.map(\.path))

        if shouldRefresh {
            if options.forceRescan { cache = CostUsageCache() }
            var scanState = CodexScanState()
            for fileURL in files { scanCodexFile(fileURL: fileURL, range: range, cache: &cache, state: &scanState) }
            for key in cache.files.keys where !filePathsInScan.contains(key) {
                if let old = cache.files[key] { applyFileDays(cache: &cache, fileDays: old.days, sign: -1) }
                cache.files.removeValue(forKey: key)
            }
            pruneDays(cache: &cache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
            cache.lastScanUnixMs = nowMs
            CostUsageCacheIO.save(provider: "codex", cache: cache, cacheRoot: options.cacheRoot)
        }
        return cache
    }

    // MARK: - Claude Scanning

    private struct ClaudeParseResult {
        let days: [String: [String: [Int]]]
        let parsedBytes: Int64
    }

    private static func defaultClaudeProjectsRoots(options: Options) -> [URL] {
        if let override = options.claudeProjectsRoots { return override }
        let home = URL(fileURLWithPath: realUserHome())
        return [
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
            home.appendingPathComponent(".claude/projects", isDirectory: true),
        ]
    }

    private static func parseClaudeFile(fileURL: URL, range: DayRange, startOffset: Int64 = 0) -> ClaudeParseResult {
        var days: [String: [String: [Int]]] = [:]
        var seenKeys: Set<String> = []
        let costScale = 1_000_000_000.0

        func add(dayKey: String, model: String, input: Int, cacheRead: Int, cacheCreate: Int, output: Int, costNanos: Int) {
            guard DayRange.isInRange(dayKey: dayKey, since: range.scanSinceKey, until: range.scanUntilKey) else { return }
            let normModel = Pricing.normalizeClaudeModel(model)
            var dayModels = days[dayKey] ?? [:]
            var packed = dayModels[normModel] ?? [0, 0, 0, 0, 0]
            packed[0] = (packed[safeIdx: 0] ?? 0) + input
            packed[1] = (packed[safeIdx: 1] ?? 0) + cacheRead
            packed[2] = (packed[safeIdx: 2] ?? 0) + cacheCreate
            packed[3] = (packed[safeIdx: 3] ?? 0) + output
            packed[4] = (packed[safeIdx: 4] ?? 0) + costNanos
            dayModels[normModel] = packed
            days[dayKey] = dayModels
        }

        let maxLineBytes = 512 * 1024
        let prefixBytes = maxLineBytes

        let parsedBytes = (try? scanJsonl(fileURL: fileURL, offset: startOffset, maxLineBytes: maxLineBytes, prefixBytes: prefixBytes, onLine: { line in
            guard !line.bytes.isEmpty, !line.wasTruncated else { return }
            guard line.bytes.asciiContains(#""type":"assistant""#), line.bytes.asciiContains(#""usage""#) else { return }

            guard let obj = (try? JSONSerialization.jsonObject(with: line.bytes)) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let tsText = obj["timestamp"] as? String,
                  let dayKey = dayKeyFromTimestamp(tsText) ?? dayKeyFromParsedISO(tsText),
                  let message = obj["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let usage = message["usage"] as? [String: Any] else { return }

            // Deduplicate by message.id + requestId
            let messageId = message["id"] as? String
            let requestId = obj["requestId"] as? String
            if let messageId, let requestId {
                let key = "\(messageId):\(requestId)"
                if seenKeys.contains(key) { return }
                seenKeys.insert(key)
            }

            func toInt(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
            let input = max(0, toInt(usage["input_tokens"]))
            let cacheCreate = max(0, toInt(usage["cache_creation_input_tokens"]))
            let cacheRead = max(0, toInt(usage["cache_read_input_tokens"]))
            let output = max(0, toInt(usage["output_tokens"]))
            if input == 0, cacheCreate == 0, cacheRead == 0, output == 0 { return }

            let cost = Pricing.claudeCostUSD(model: model, inputTokens: input, cacheReadInputTokens: cacheRead, cacheCreationInputTokens: cacheCreate, outputTokens: output)
            let costNanos = cost.map { Int(($0 * costScale).rounded()) } ?? 0
            add(dayKey: dayKey, model: model, input: input, cacheRead: cacheRead, cacheCreate: cacheCreate, output: output, costNanos: costNanos)
        })) ?? startOffset

        return ClaudeParseResult(days: days, parsedBytes: parsedBytes)
    }

    private static func processClaudeFile(url: URL, size: Int64, mtimeMs: Int64, cache: inout CostUsageCache, touched: inout Set<String>, range: DayRange) {
        let path = url.path
        touched.insert(path)

        if let cached = cache.files[path], cached.mtimeUnixMs == mtimeMs, cached.size == size { return }

        // Try incremental
        if let cached = cache.files[path] {
            let startOffset = cached.parsedBytes ?? cached.size
            let canIncremental = size > cached.size && startOffset > 0 && startOffset <= size
            if canIncremental {
                let delta = parseClaudeFile(fileURL: url, range: range, startOffset: startOffset)
                if !delta.days.isEmpty { applyFileDays(cache: &cache, fileDays: delta.days, sign: 1) }
                var mergedDays = cached.days
                mergeFileDays(existing: &mergedDays, delta: delta.days)
                cache.files[path] = CostUsageFileUsage(mtimeUnixMs: mtimeMs, size: size, days: mergedDays, parsedBytes: delta.parsedBytes)
                return
            }
            applyFileDays(cache: &cache, fileDays: cached.days, sign: -1)
        }

        // Full parse
        let parsed = parseClaudeFile(fileURL: url, range: range)
        let usage = CostUsageFileUsage(mtimeUnixMs: mtimeMs, size: size, days: parsed.days, parsedBytes: parsed.parsedBytes)
        cache.files[path] = usage
        applyFileDays(cache: &cache, fileDays: usage.days, sign: 1)
    }

    private static func scanClaudeRoot(root: URL, cache: inout CostUsageCache, touched: inout Set<String>, range: DayRange) {
        let rootPath = root.path
        // Handle /var/ vs /private/var/ paths
        let rootCandidates = rootPath.hasPrefix("/var/") ? ["/private" + rootPath, rootPath]
            : rootPath.hasPrefix("/private/var/") ? [rootPath, String(rootPath.dropFirst("/private".count))]
            : [rootPath]
        guard rootCandidates.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            let prefixes = Set(rootCandidates).map { $0.hasSuffix("/") ? $0 : "\($0)/" }
            for path in cache.files.keys where prefixes.contains(where: { path.hasPrefix($0) }) {
                if let old = cache.files[path] { applyFileDays(cache: &cache, fileDays: old.days, sign: -1) }
                cache.files.removeValue(forKey: path)
            }
            return
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            if size <= 0 { continue }
            let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            processClaudeFile(url: url, size: size, mtimeMs: Int64(mtime * 1000), cache: &cache, touched: &touched, range: range)
        }
    }

    private static func scanClaudeProvider(range: DayRange, now: Date, options: Options) -> CostUsageCache {
        var cache = CostUsageCacheIO.load(provider: "claude", cacheRoot: options.cacheRoot)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let refreshMs = Int64(max(0, options.refreshMinIntervalSeconds) * 1000)
        let shouldRefresh = options.forceRescan || refreshMs == 0 || cache.lastScanUnixMs == 0 || nowMs - cache.lastScanUnixMs > refreshMs

        let roots = defaultClaudeProjectsRoots(options: options)
        var touched: Set<String> = []

        if shouldRefresh {
            if options.forceRescan { cache = CostUsageCache() }
            for root in roots { scanClaudeRoot(root: root, cache: &cache, touched: &touched, range: range) }
            for key in cache.files.keys where !touched.contains(key) {
                if let old = cache.files[key] { applyFileDays(cache: &cache, fileDays: old.days, sign: -1) }
                cache.files.removeValue(forKey: key)
            }
            pruneDays(cache: &cache, sinceKey: range.scanSinceKey, untilKey: range.scanUntilKey)
            cache.lastScanUnixMs = nowMs
            CostUsageCacheIO.save(provider: "claude", cache: cache, cacheRoot: options.cacheRoot)
        }
        return cache
    }

    // MARK: - Shared Cache Mutations

    static func applyFileDays(cache: inout CostUsageCache, fileDays: [String: [String: [Int]]], sign: Int) {
        for (day, models) in fileDays {
            var dayModels = cache.days[day] ?? [:]
            for (model, packed) in models {
                let existing = dayModels[model] ?? []
                let merged = addPacked(a: existing, b: packed, sign: sign)
                if merged.allSatisfy({ $0 == 0 }) { dayModels.removeValue(forKey: model) }
                else { dayModels[model] = merged }
            }
            if dayModels.isEmpty { cache.days.removeValue(forKey: day) }
            else { cache.days[day] = dayModels }
        }
    }

    static func mergeFileDays(existing: inout [String: [String: [Int]]], delta: [String: [String: [Int]]]) {
        for (day, models) in delta {
            var dayModels = existing[day] ?? [:]
            for (model, packed) in models {
                let merged = addPacked(a: dayModels[model] ?? [], b: packed, sign: 1)
                if merged.allSatisfy({ $0 == 0 }) { dayModels.removeValue(forKey: model) }
                else { dayModels[model] = merged }
            }
            if dayModels.isEmpty { existing.removeValue(forKey: day) }
            else { existing[day] = dayModels }
        }
    }

    static func pruneDays(cache: inout CostUsageCache, sinceKey: String, untilKey: String) {
        for key in cache.days.keys where !DayRange.isInRange(dayKey: key, since: sinceKey, until: untilKey) {
            cache.days.removeValue(forKey: key)
        }
    }

    static func addPacked(a: [Int], b: [Int], sign: Int) -> [Int] {
        let len = max(a.count, b.count)
        var out = Array(repeating: 0, count: len)
        for idx in 0..<len {
            out[idx] = max(0, (a[safeIdx: idx] ?? 0) + sign * (b[safeIdx: idx] ?? 0))
        }
        return out
    }

    // MARK: - Helpers

    private static func parseDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        return comps.date
    }
}

// MARK: - ISO Formatter Box

private final class ISOFormatterBox: @unchecked Sendable {
    let lock = NSLock()
    let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func parse(_ text: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return withFractional.date(from: text) ?? plain.date(from: text)
    }
}

// MARK: - Safe Subscript Extensions

extension [Int] {
    subscript(safeIdx index: Int) -> Int? {
        index >= 0 && index < count ? self[index] : nil
    }
}

extension [UInt8] {
    subscript(safeUInt8 index: Int) -> UInt8? {
        index >= 0 && index < count ? self[index] : nil
    }
}

extension Data {
    func asciiContains(_ needle: String) -> Bool {
        guard let n = needle.data(using: .utf8) else { return false }
        return self.range(of: n) != nil
    }
}

#endif
