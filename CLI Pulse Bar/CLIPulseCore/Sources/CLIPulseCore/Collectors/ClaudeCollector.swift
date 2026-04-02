#if os(macOS)
import Foundation
import Security

/// Fetches real usage/quota data from Claude (Anthropic) via a multi-source strategy chain.
///
/// Strategy priority (configurable via `ProviderConfig.sourceMode`):
/// 1. **OAuth API** — `GET https://api.anthropic.com/api/oauth/usage`
/// 2. **Web session** — `claude.ai/api/organizations/.../usage` via manual cookie header
/// 3. **CLI PTY** — runs `claude /usage` in a pseudo-terminal, handles TUI prompts
///
/// Each strategy is tried in order; failures trigger fallback to the next strategy.
/// Errors are logged to `$TMPDIR/clipulse_claude_resolver.log` for diagnostics.
public struct ClaudeCollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.claude

    private let resolver = ClaudeSourceResolver()

    public func isAvailable(config: ProviderConfig) -> Bool {
        resolver.isAvailable(config: config)
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        try await resolver.resolve(config: config)
    }

    // MARK: - Backward-compatible static methods (used by tests)

    /// Parse OAuth usage JSON response.
    static func parseUsage(_ data: Data) throws -> ClaudeOAuthStrategy.OAuthUsageResponse {
        try ClaudeOAuthStrategy.parseUsage(data)
    }

    /// Parse credentials JSON (snake_case or camelCase).
    static func parseCredentialsJSON(_ data: Data) -> ClaudeCredentials.Creds? {
        ClaudeCredentials.parseCredentialsJSON(data)
    }

    /// Strip ANSI escape codes.
    static func stripANSI(_ text: String) -> String {
        ClaudeCredentials.stripANSI(text)
    }

    /// Extract percentage from line with used/left semantics.
    static func percentUsedFromLine(_ line: String) -> Int? {
        ClaudeCLIPTYStrategy.percentUsedFromLine(line)
    }

    /// Parse raw CLI output into a snapshot.
    static func parseCLIOutput(_ text: String) throws -> ClaudeCLIPTYStrategy.CLISnapshot {
        try ClaudeCLIPTYStrategy.parseCLIOutput(text)
    }

    /// Find the claude CLI binary.
    func findClaudeBinary() -> String? {
        ClaudeCLIPTYStrategy.findClaudeBinary()
    }

    /// Typealias for test compatibility.
    typealias UsageResponse = ClaudeOAuthStrategy.OAuthUsageResponse
    typealias CLISnapshot = ClaudeCLIPTYStrategy.CLISnapshot
    typealias CaudeCreds = ClaudeCredentials.Creds

    struct ClaudeCreds {
        let accessToken: String
        let rateLimitTier: String?
    }
}
#endif
