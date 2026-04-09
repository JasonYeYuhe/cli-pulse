#if os(macOS)
import Foundation

// MARK: - Strategy protocol

/// A single source strategy for fetching Claude usage data.
/// Each strategy represents one method of obtaining quota information
/// (OAuth API, Web session, CLI PTY probe).
public protocol ClaudeSourceStrategy: Sendable {
    /// Human-readable identifier for logging/diagnostics.
    var sourceLabel: String { get }

    /// The SourceType this strategy produces.
    var sourceType: SourceType { get }

    /// Quick check: can this strategy plausibly run with the given config?
    /// Must not perform network I/O.
    func isAvailable(config: ProviderConfig) -> Bool

    /// Fetch Claude usage data. Throws on failure.
    func fetch(config: ProviderConfig) async throws -> ClaudeSnapshot
}

// MARK: - Unified snapshot from any source

/// Normalized Claude usage data that any strategy produces.
/// Maps directly to CollectorResult via `ClaudeResultBuilder`.
public struct ClaudeSnapshot: Sendable {
    public let sessionUsed: Int?        // 0-100 utilization %
    public let weeklyUsed: Int?
    public let opusUsed: Int?
    public let sonnetUsed: Int?
    public let sessionReset: String?    // ISO8601 or human-readable
    public let weeklyReset: String?
    public let extraUsage: ClaudeExtraUsage?
    public let rateLimitTier: String?
    public let accountEmail: String?
    public let sourceLabel: String

    public init(
        sessionUsed: Int? = nil, weeklyUsed: Int? = nil,
        opusUsed: Int? = nil, sonnetUsed: Int? = nil,
        sessionReset: String? = nil, weeklyReset: String? = nil,
        extraUsage: ClaudeExtraUsage? = nil,
        rateLimitTier: String? = nil,
        accountEmail: String? = nil,
        sourceLabel: String
    ) {
        self.sessionUsed = sessionUsed
        self.weeklyUsed = weeklyUsed
        self.opusUsed = opusUsed
        self.sonnetUsed = sonnetUsed
        self.sessionReset = sessionReset
        self.weeklyReset = weeklyReset
        self.extraUsage = extraUsage
        self.rateLimitTier = rateLimitTier
        self.accountEmail = accountEmail
        self.sourceLabel = sourceLabel
    }
}

/// Extra usage / credit info from Claude.
public struct ClaudeExtraUsage: Sendable {
    public let isEnabled: Bool
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let currency: String?

    public init(isEnabled: Bool, monthlyLimit: Double? = nil,
                usedCredits: Double? = nil, currency: String? = nil) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.currency = currency
    }
}

// MARK: - Result builder

/// Converts a `ClaudeSnapshot` into a `CollectorResult`.
public enum ClaudeResultBuilder {
    public static func build(from snapshot: ClaudeSnapshot) -> CollectorResult {
        var tiers: [TierDTO] = []
        if let u = snapshot.sessionUsed {
            tiers.append(TierDTO(name: "5h Window", quota: 100, remaining: max(0, 100 - u), reset_time: snapshot.sessionReset))
        }
        if let u = snapshot.weeklyUsed {
            tiers.append(TierDTO(name: "Weekly", quota: 100, remaining: max(0, 100 - u), reset_time: snapshot.weeklyReset))
        }
        if let u = snapshot.sonnetUsed ?? snapshot.opusUsed {
            tiers.append(TierDTO(name: "Sonnet only", quota: 100, remaining: max(0, 100 - u), reset_time: snapshot.weeklyReset))
        }

        let planType: String
        let tierLower = (snapshot.rateLimitTier ?? "").lowercased()
        // Match specific Max tiers first (20x before generic max)
        if tierLower.contains("max_20x") || tierLower.contains("max 20x") { planType = "Max 20x" }
        else if tierLower.contains("max_5x") || tierLower.contains("max 5x") { planType = "Max 5x" }
        else if tierLower.contains("max") { planType = "Max 5x" }  // default Max → 5x
        else if tierLower.contains("ultra") { planType = "Ultra" }
        else if tierLower.contains("pro") { planType = "Pro" }
        else if tierLower.contains("team") { planType = "Team" }
        else if tierLower.contains("enterprise") { planType = "Enterprise" }
        else if tierLower.contains("free") { planType = "Free" }
        else if tierLower.isEmpty { planType = "Unknown" }
        else { planType = "Unknown" }

        let overallRemaining = snapshot.sessionUsed.map { max(0, 100 - $0) } ?? 100
        let statusText = snapshot.sessionUsed.map { "\($0)% used" } ?? "Operational"

        let providerUsage = ProviderUsage(
            provider: ProviderKind.claude.rawValue,
            today_usage: snapshot.sessionUsed ?? 0,
            week_usage: snapshot.weeklyUsed ?? 0,
            estimated_cost_today: 0, estimated_cost_week: 0,
            cost_status_today: "Unavailable", cost_status_week: "Unavailable",
            quota: 100, remaining: overallRemaining, plan_type: planType,
            reset_time: snapshot.sessionReset, tiers: tiers, status_text: statusText,
            trend: [], recent_sessions: [], recent_errors: [],
            metadata: ProviderMetadata(display_name: "Claude", category: "cloud",
                                       supports_exact_cost: false, supports_quota: true))
        return CollectorResult(usage: providerUsage, dataKind: .quota)
    }
}

// MARK: - Shared credential helpers

/// Shared helpers for Claude credential resolution, used by multiple strategies.
public enum ClaudeCredentials {
    /// Real home directory (not sandbox-remapped).
    public static var realHomeDir: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        let nsHome = NSHomeDirectory()
        if let range = nsHome.range(of: "/Library/Containers/") {
            return String(nsHome[nsHome.startIndex..<range.lowerBound])
        }
        return nsHome
    }

    public struct Creds: Sendable {
        public let accessToken: String
        public let rateLimitTier: String?
    }

    /// Parse credentials from JSON data (supports both snake_case and camelCase).
    public static func parseCredentialsJSON(_ data: Data) -> Creds? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let oauth = json["claude_ai_oauth"] as? [String: Any],
           let token = oauth["access_token"] as? String, !token.isEmpty {
            return Creds(accessToken: token, rateLimitTier: oauth["rate_limit_tier"] as? String)
        }
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return Creds(accessToken: token, rateLimitTier: oauth["rateLimitTier"] as? String)
        }
        return nil
    }

    /// Read credentials from ~/.claude/.credentials.json file.
    public static func readCredentialsFile() -> Creds? {
        let path = (realHomeDir as NSString).appendingPathComponent(".claude/.credentials.json")
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return parseCredentialsJSON(data)
    }

    /// Read credentials from macOS Keychain (Claude Code's keychain item).
    ///
    /// The sandboxed app cannot access cross-app keychain items without
    /// triggering a macOS authorization dialog. To avoid prompting the
    /// user on every launch, we cache the credentials in the app's own
    /// keychain after the first successful read.
    public static func readKeychainCredentials() -> Creds? {
        // 1. Try the app's own keychain cache (never triggers a prompt)
        if let cached = KeychainHelper.load(key: keychainCacheKey),
           let data = cached.data(using: .utf8),
           let creds = parseCredentialsJSON(data) {
            return creds
        }

        // 2. Read from Claude Code's keychain (may trigger one-time prompt)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        guard let creds = parseCredentialsJSON(data) else { return nil }

        // 3. Cache in the app's own keychain so the prompt never recurs
        if let jsonStr = String(data: data, encoding: .utf8) {
            KeychainHelper.save(key: keychainCacheKey, value: jsonStr)
        }
        return creds
    }

    /// Clear the cached Claude Code credentials.
    /// Call this when the cached token is known to be invalid (e.g. after
    /// an OAuth 401) so the next `readKeychainCredentials()` re-reads
    /// from the real keychain.
    public static func clearCachedKeychainCredentials() {
        KeychainHelper.delete(key: keychainCacheKey)
    }

    private static let keychainCacheKey = "claude-code-creds-cache"

    /// Resolve an OAuth token from all available sources.
    public static func resolveToken(config: ProviderConfig) -> (token: String, tier: String?) {
        // Check environment variables: app-specific first, then Claude Code's own
        for envKey in ["CODEXBAR_CLAUDE_OAUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"] {
            if let envToken = ProcessInfo.processInfo.environment[envKey],
               !envToken.isEmpty, envToken.hasPrefix("sk-ant-oat") {
                return (envToken, nil)
            }
        }
        if let configKey = config.apiKey, configKey.hasPrefix("sk-ant-oat") {
            return (configKey, nil)
        }
        if let fileCreds = readCredentialsFile() {
            return (fileCreds.accessToken, fileCreds.rateLimitTier)
        }
        if let keychainCreds = readKeychainCredentials() {
            return (keychainCreds.accessToken, keychainCreds.rateLimitTier)
        }
        return ("", nil)
    }

    /// Strip ANSI escape codes from text.
    /// Cursor-movement sequences (like ESC[1C used by TUI between words) become spaces
    /// so that "Quick[1Csafety[1Ccheck" → "Quick safety check" instead of "Quicksafetycheck".
    public static func stripANSI(_ text: String) -> String {
        // First replace cursor-movement sequences with spaces (ESC[nC = cursor forward)
        var result = text
        if let cursorFwd = try? NSRegularExpression(pattern: "\\x1B\\[\\d*C") {
            result = cursorFwd.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        // Then strip remaining ANSI escape sequences
        if let ansi = try? NSRegularExpression(pattern: "\\x1B\\[[0-?]*[ -/]*[@-~]") {
            result = ansi.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Also strip OSC sequences (ESC]...BEL)
        if let osc = try? NSRegularExpression(pattern: "\\x1B\\][^\\x07]*\\x07") {
            result = osc.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result
    }
}

// MARK: - Error types

public enum ClaudeStrategyError: LocalizedError, Sendable {
    case noToken
    case httpError(status: Int, provider: String)
    case parseFailed(String)
    case noBinary
    case noSessionKey
    case unauthorized
    case timedOut
    case processExited

    public var errorDescription: String? {
        switch self {
        case .noToken: return "No Claude OAuth token available"
        case .httpError(let s, _): return "Claude API HTTP \(s)"
        case .parseFailed(let m): return "Claude parse failed: \(m)"
        case .noBinary: return "Claude CLI binary not found"
        case .noSessionKey: return "No Claude session key available"
        case .unauthorized: return "Claude session expired or unauthorized"
        case .timedOut: return "Claude probe timed out"
        case .processExited: return "Claude CLI process exited unexpectedly"
        }
    }

    /// Whether this error should trigger fallback to the next strategy.
    public var shouldFallback: Bool {
        switch self {
        case .httpError(let status, _):
            return status == 429 || status == 401 || status == 403
        case .noToken, .noBinary, .noSessionKey, .unauthorized, .timedOut, .processExited:
            return true
        case .parseFailed:
            return true
        }
    }
}
#endif
