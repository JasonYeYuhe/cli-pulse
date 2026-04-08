#if os(macOS)
import Darwin
import Foundation
import os

private let logger = Logger(subsystem: "com.clipulse", category: "ClaudeCLIPTY")

/// Fetches Claude usage by running `claude /usage` inside a PTY.
///
/// Unlike plain Process + stdout pipes, the PTY approach:
/// - Handles interactive prompts (trust folder, command palette)
/// - Processes TUI initialization delays
/// - Properly captures output from Claude's rich terminal UI
///
/// Modeled after CodexBar's `ClaudeCLISession` + `ClaudeStatusProbe`.
public struct ClaudeCLIPTYStrategy: ClaudeSourceStrategy, Sendable {
    public let sourceLabel = "cli-pty"
    public let sourceType: SourceType = .cli

    /// Timeout for the entire PTY capture.
    private let timeout: TimeInterval = 20

    public func isAvailable(config: ProviderConfig) -> Bool {
        Self.findClaudeBinary() != nil
    }

    public func fetch(config: ProviderConfig) async throws -> ClaudeSnapshot {
        guard let binary = Self.findClaudeBinary() else {
            throw ClaudeStrategyError.noBinary
        }

        let rawOutput = try await capturePTY(binary: binary, subcommand: "/usage")

        // Dump raw output for debugging
        Self.dumpRawOutput(rawOutput)

        let snapshot: CLISnapshot
        do {
            snapshot = try Self.parseCLIOutput(rawOutput)
        } catch {
            // If parse fails, try once more with a longer wait
            let retryOutput = try await capturePTY(binary: binary, subcommand: "/usage")
            Self.dumpRawOutput(retryOutput)
            snapshot = try Self.parseCLIOutput(retryOutput)
        }

        // Try to get tier from credentials if available
        let tier = ClaudeCredentials.readCredentialsFile()?.rateLimitTier
            ?? ClaudeCredentials.readKeychainCredentials()?.rateLimitTier

        return ClaudeSnapshot(
            sessionUsed: snapshot.sessionPercentLeft.map { 100 - $0 },
            weeklyUsed: snapshot.weeklyPercentLeft.map { 100 - $0 },
            opusUsed: snapshot.opusPercentLeft.map { 100 - $0 },
            sessionReset: snapshot.primaryResetDescription,
            weeklyReset: snapshot.secondaryResetDescription,
            rateLimitTier: tier,
            sourceLabel: sourceLabel
        )
    }

    // MARK: - Binary discovery

    static func findClaudeBinary() -> String? {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"],
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let realHome = ClaudeCredentials.realHomeDir
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            (realHome as NSString).appendingPathComponent(".npm-global/bin/claude"),
            (realHome as NSString).appendingPathComponent(".local/bin/claude"),
            (realHome as NSString).appendingPathComponent(".local/share/claude/cli/claude"),
            (realHome as NSString).appendingPathComponent(".claude/local/claude"),
        ]
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        // Fallback: search PATH via which (synchronous — completes in <1s)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["claude"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty { return path }
            }
        } catch {
            logger.debug("claude binary lookup failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - PTY capture

    /// Prompts the PTY auto-responds to (matching CodexBar).
    /// Claude v2.x uses selection-style prompts; Enter confirms the default choice.
    private static let promptResponses: [(needle: String, response: String)] = [
        ("Do you trust the files in this folder?", "y\r"),
        ("Quick safety check:", "\r"),           // v2.x trust prompt (Enter confirms default "Yes")
        ("Yes, I trust this folder", "\r"),
        ("Ready to code here?", "\r"),
        ("Press Enter to continue", "\r"),
        // MCP server prompts — accept default (option 1: "Use this and all future MCP servers")
        ("New MCP server found", "\r"),
        ("Use this and all future MCP servers", "\r"),
        ("Use this MCP server", "\r"),
        ("Continue without using this MCP server", "\r"),
        // Command palette entries for /usage
        ("Show plan", "\r"),
        ("Show plan usage limits", "\r"),
    ]

    private func capturePTY(binary: String, subcommand: String) async throws -> String {
        // Open a PTY pair
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw ClaudeStrategyError.parseFailed("openpty failed")
        }
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: false)

        defer {
            close(primaryFD)
            close(secondaryFD)
        }

        // Launch process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["--bare", "--allowed-tools", "", "--strict-mcp-config"]
        proc.standardInput = secondaryHandle
        proc.standardOutput = secondaryHandle
        proc.standardError = secondaryHandle

        let workDir = Self.probeWorkingDirectory()
        proc.currentDirectoryURL = URL(fileURLWithPath: workDir)

        var env = ProcessInfo.processInfo.environment
        for key in env.keys where key.hasPrefix("ANTHROPIC_") || key.hasPrefix("CODEXBAR_") {
            env.removeValue(forKey: key)
        }
        env["PWD"] = workDir
        proc.environment = env

        do {
            try proc.run()
        } catch {
            throw ClaudeStrategyError.parseFailed("failed to launch claude CLI: \(error.localizedDescription)")
        }

        let pid = proc.processIdentifier
        _ = setpgid(pid, pid)

        defer {
            Self.writeToPTY(primaryFD, "/exit\r")
            proc.terminate()
            kill(-pid, SIGTERM)
            let killDeadline = Date().addingTimeInterval(1.0)
            while proc.isRunning && Date() < killDeadline { usleep(100_000) }
            if proc.isRunning { kill(-pid, SIGKILL); kill(pid, SIGKILL) }
        }

        // Phase 1: Startup — read output, handle trust prompts, wait for TUI ready.
        // We run a continuous read loop instead of sleep-then-read, so we can
        // respond to prompts immediately as they appear.
        let cursorQueryBytes = Data([0x1B, 0x5B, 0x36, 0x6E]) // ESC[6n
        var allOutput = Data()
        var triggeredPrompts = Set<String>()
        var commandSent = false
        var lastOutputAt = Date()
        let launchTime = Date()
        let overallDeadline = Date().addingTimeInterval(timeout)
        let commandIdleTimeout: TimeInterval = 4.0  // idle after /usage sent

        while Date() < overallDeadline {
            let chunk = Self.readFromPTY(primaryFD)
            if !chunk.isEmpty {
                allOutput.append(chunk)
                lastOutputAt = Date()

                // Respond to cursor position queries
                if chunk.range(of: cursorQueryBytes) != nil {
                    Self.writeToPTY(primaryFD, "\u{1b}[1;1R")
                }

                // Check all accumulated output for prompts
                if let text = String(data: allOutput, encoding: .utf8) {
                    let normalized = ClaudeCredentials.stripANSI(text).lowercased()
                    for prompt in Self.promptResponses where !triggeredPrompts.contains(prompt.needle) {
                        if normalized.contains(prompt.needle.lowercased()) {
                            Self.writeToPTY(primaryFD, prompt.response)
                            triggeredPrompts.insert(prompt.needle)
                        }
                    }
                }
            }

            // Phase 2: After initial startup stabilizes (2s of output + 0.5s idle),
            // send the subcommand and switch to command-output mode.
            if !commandSent {
                let sinceStart = Date().timeIntervalSince(launchTime)
                let idleSinceOutput = Date().timeIntervalSince(lastOutputAt)

                // Send command when: we've waited at least 2s AND output has been idle for 0.5s
                // OR we've waited 4s total (safety fallback)
                if (sinceStart >= 2.0 && idleSinceOutput >= 0.5 && !allOutput.isEmpty) || sinceStart >= 4.0 {
                    // Clear buffer — we only want post-command output for parsing
                    allOutput.removeAll()
                    triggeredPrompts.removeAll()
                    Self.writeToPTY(primaryFD, subcommand + "\r")
                    commandSent = true
                    lastOutputAt = Date()
                }
            }

            // After command is sent, use idle timeout to detect completion
            if commandSent && !allOutput.isEmpty {
                if Date().timeIntervalSince(lastOutputAt) >= commandIdleTimeout {
                    break
                }
            }

            if !proc.isRunning {
                if !commandSent {
                    // Process died during startup
                    let text = String(data: allOutput, encoding: .utf8) ?? "(no output)"
                    Self.dumpRawOutput("PROCESS EXITED DURING STARTUP (status=\(proc.terminationStatus)): " + text)
                    throw ClaudeStrategyError.processExited
                }
                break
            }

            try await Task.sleep(nanoseconds: 60_000_000) // 60ms poll
        }

        guard !allOutput.isEmpty, let text = String(data: allOutput, encoding: .utf8) else {
            throw ClaudeStrategyError.timedOut
        }
        return text
    }

    // MARK: - PTY I/O helpers

    private static func readFromPTY(_ fd: Int32) -> Data {
        var result = Data()
        var tmp = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &tmp, tmp.count)
            if n > 0 {
                result.append(contentsOf: tmp.prefix(n))
                continue
            }
            break
        }
        return result
    }

    @discardableResult
    private static func writeToPTY(_ fd: Int32, _ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            var retries = 0
            while offset < raw.count {
                let written = write(fd, base.advanced(by: offset), raw.count - offset)
                if written > 0 { offset += written; retries = 0; continue }
                if written == 0 { break }
                let err = errno
                if err == EINTR || err == EAGAIN || err == EWOULDBLOCK {
                    retries += 1
                    if retries > 100 { return false }
                    usleep(5000)
                    continue
                }
                return false
            }
            return offset == raw.count
        }
    }

    /// Working directory for the probe process.
    /// Uses /tmp to avoid inheriting ~/.mcp.json or other configs via directory walk-up.
    private static func probeWorkingDirectory() -> String {
        let tmpDir = NSTemporaryDirectory() + "clipulse_probe_dir"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        // Create a minimal .claude/settings.json to auto-trust
        let claudeDir = (tmpDir as NSString).appendingPathComponent(".claude")
        try? FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
        let settingsPath = (claudeDir as NSString).appendingPathComponent("settings.json")
        if !FileManager.default.fileExists(atPath: settingsPath) {
            try? "{}".write(toFile: settingsPath, atomically: true, encoding: .utf8)
        }
        return tmpDir
    }

    // MARK: - Diagnostics

    private static func dumpRawOutput(_ output: String) {
        let clean = ClaudeCredentials.stripANSI(output)
        let path = NSTemporaryDirectory() + "clipulse_claude_pty_raw.txt"
        let timestamp = sharedISO8601Formatter.string(from: Date())
        let entry = "=== PTY dump \(timestamp) ===\n\(clean)\n=== END ===\n\n"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(entry.data(using: .utf8) ?? Data())
            fh.closeFile()
        } else {
            try? entry.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - CLI output parsing

    struct CLISnapshot: Sendable {
        let sessionPercentLeft: Int?
        let weeklyPercentLeft: Int?
        let opusPercentLeft: Int?
        let primaryResetDescription: String?
        let secondaryResetDescription: String?
    }

    /// Extract a percentage from a line, interpreting "left/remaining" vs "used" semantics.
    /// Returns percent USED (0-100).
    static func percentUsedFromLine(_ line: String) -> Int? {
        let pattern = #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let valRange = Range(match.range(at: 1), in: line),
              let val = Double(line[valRange]) else { return nil }
        let clamped = max(0, min(100, val))
        let lower = line.lowercased()
        if lower.contains("left") || lower.contains("remaining") || lower.contains("available") {
            return Int((100 - clamped).rounded())
        } else if lower.contains("used") || lower.contains("spent") || lower.contains("consumed") {
            return Int(clamped.rounded())
        }
        return Int((100 - clamped).rounded())
    }

    /// Parse the raw CLI /usage text output into a structured snapshot.
    static func parseCLIOutput(_ rawText: String) throws -> CLISnapshot {
        let text = ClaudeCredentials.stripANSI(rawText)
        let lines = text.components(separatedBy: .newlines)

        var sessionPct: Int? = nil
        var weeklyPct: Int? = nil
        var opusPct: Int? = nil
        var primaryReset: String? = nil
        var secondaryReset: String? = nil

        enum Section { case none, session, weekly, opus }
        var currentSection: Section = .none

        for line in lines {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            let normalized = lower.replacingOccurrences(of: " ", with: "")

            if normalized.contains("currentsession") {
                currentSection = .session; continue
            } else if normalized.contains("currentweek") && (normalized.contains("opus") || normalized.contains("sonnet")) {
                currentSection = .opus; continue
            } else if normalized.contains("currentweek") {
                currentSection = .weekly; continue
            }

            if let pct = percentUsedFromLine(line) {
                switch currentSection {
                case .session where sessionPct == nil: sessionPct = pct
                case .weekly where weeklyPct == nil: weeklyPct = pct
                case .opus where opusPct == nil: opusPct = pct
                default: break
                }
            }

            if lower.contains("resets") || lower.contains("reset") {
                let resetText = line.trimmingCharacters(in: .whitespaces)
                switch currentSection {
                case .session where primaryReset == nil: primaryReset = resetText
                case .weekly where secondaryReset == nil: secondaryReset = resetText
                default: break
                }
            }
        }

        guard sessionPct != nil || weeklyPct != nil else {
            throw ClaudeStrategyError.parseFailed("no usage percentages found in CLI output")
        }

        return CLISnapshot(
            sessionPercentLeft: sessionPct.map { max(0, 100 - $0) },
            weeklyPercentLeft: weeklyPct.map { max(0, 100 - $0) },
            opusPercentLeft: opusPct.map { max(0, 100 - $0) },
            primaryResetDescription: primaryReset,
            secondaryResetDescription: secondaryReset
        )
    }
}
#endif
