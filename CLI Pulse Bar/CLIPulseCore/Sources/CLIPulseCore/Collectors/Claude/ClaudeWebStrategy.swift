#if os(macOS)
import Foundation

/// Fetches Claude usage via the claude.ai web API using a session cookie.
///
/// Session key sources (in order):
/// 1. Manual cookie header from ProviderConfig (user-provided in Settings)
/// 2. Helper-written snapshot file (`~/.clipulse/claude_snapshot.json`)
/// 3. Helper-written session key file (`~/.clipulse/claude_session.json`)
///
/// API endpoints (matches CodexBar's documented set):
/// - `GET https://claude.ai/api/organizations` → org UUID + email
/// - `GET https://claude.ai/api/organizations/{orgId}/usage` → session/weekly/opus utilization
/// - `GET https://claude.ai/api/organizations/{orgId}/overage_spend_limit` → extra usage credits
/// - `GET https://claude.ai/api/account` → email, plan hints, login method
///
/// NOT implemented (requires unsandboxed helper):
/// - Browser cookie import (Safari/Chrome/Firefox SQLite access)
/// - Browser cookie caching in Keychain
public struct ClaudeWebStrategy: ClaudeSourceStrategy, Sendable {
    public let sourceLabel = "web"
    public let sourceType: SourceType = .web

    private static let baseURL = "https://claude.ai/api"

    public func isAvailable(config: ProviderConfig) -> Bool {
        // Check helper snapshot first (no network needed)
        if Self.readHelperSnapshot() != nil { return true }
        // Manual cookie header from settings
        if let cookie = config.manualCookieHeader, !cookie.isEmpty { return true }
        // Helper-written session key file
        return Self.findSessionKeyFromFile() != nil
    }

    public func fetch(config: ProviderConfig) async throws -> ClaudeSnapshot {
        // Fast path: if helper has written a complete snapshot, use it directly
        if let helperSnapshot = Self.readHelperSnapshot() {
            return helperSnapshot
        }

        // Slow path: fetch via web API using session key
        let sessionKey = try resolveSessionKey(config: config)

        // Step 1: Get organization
        let org = try await fetchOrganization(sessionKey: sessionKey)

        // Step 2: Get usage
        let usage = try await fetchUsage(orgId: org.id, sessionKey: sessionKey)

        // Step 3: Get overage/spend limit (CodexBar endpoint, optional)
        let extra = await fetchOverageSpendLimit(orgId: org.id, sessionKey: sessionKey)

        // Step 4: Get account info for email/plan hints (optional)
        let account = await fetchAccount(sessionKey: sessionKey)

        return ClaudeSnapshot(
            sessionUsed: usage.sessionPercent,
            weeklyUsed: usage.weeklyPercent,
            opusUsed: usage.opusPercent,
            sessionReset: usage.sessionResetISO,
            weeklyReset: usage.weeklyResetISO,
            extraUsage: extra,
            rateLimitTier: account?.rateLimitTier ?? usage.planType,
            accountEmail: account?.email ?? org.email,
            sourceLabel: sourceLabel
        )
    }

    // MARK: - Session key resolution

    private func resolveSessionKey(config: ProviderConfig) throws -> String {
        // 1. Manual cookie header from settings
        if let cookie = config.manualCookieHeader, !cookie.isEmpty {
            if let key = Self.extractSessionKey(from: cookie) { return key }
            // If the whole string looks like a bare session key, use it directly
            if cookie.count > 20 && !cookie.contains("=") { return cookie }
        }

        // 2. Helper-written session key file
        if let key = Self.findSessionKeyFromFile() { return key }

        throw ClaudeStrategyError.noSessionKey
    }

    /// Extract `sessionKey` value from a cookie header string.
    static func extractSessionKey(from cookieHeader: String) -> String? {
        let pairs = cookieHeader.components(separatedBy: ";")
        for pair in pairs {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("sessionKey=") {
                let value = String(trimmed.dropFirst("sessionKey=".count))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Read session key from helper-written file.
    /// Path: ~/.clipulse/claude_session.json
    static func findSessionKeyFromFile() -> String? {
        let path = (ClaudeCredentials.realHomeDir as NSString)
            .appendingPathComponent(".clipulse/claude_session.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["sessionKey"] as? String, !key.isEmpty else { return nil }
        return key
    }

    /// Read a complete pre-fetched snapshot from the helper.
    /// Path: ~/.clipulse/claude_snapshot.json
    ///
    /// The helper (Python or bundled CLI) runs outside the sandbox,
    /// performs browser cookie extraction + web API calls, and writes
    /// the result to this file. The app simply reads it.
    ///
    /// Expected JSON schema:
    /// ```json
    /// {
    ///   "session_used": 45,
    ///   "weekly_used": 60,
    ///   "opus_used": 75,
    ///   "session_reset": "2026-04-02T22:00:00Z",
    ///   "weekly_reset": "2026-04-09T00:00:00Z",
    ///   "rate_limit_tier": "pro",
    ///   "account_email": "user@example.com",
    ///   "extra_usage": { "is_enabled": true, "monthly_limit": 50.0, "used_credits": 12.34 },
    ///   "fetched_at": "2026-04-02T14:30:00Z",
    ///   "source": "web"
    /// }
    /// ```
    /// Read snapshot from the canonical path (`ClaudeHelperContract.snapshotPath`).
    /// Rejects snapshots older than 10 minutes (live freshness).
    static func readHelperSnapshot() -> ClaudeSnapshot? {
        let path = ClaudeHelperContract.snapshotPath  // single source of truth
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Check freshness: reject snapshots older than 10 minutes (live)
        if let fetchedAt = json["fetched_at"] as? String,
           let date = ISO8601DateFormatter().date(from: fetchedAt),
           Date().timeIntervalSince(date) > ClaudeHelperContract.maxSnapshotAge {
            return nil
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

        return ClaudeSnapshot(
            sessionUsed: json["session_used"] as? Int,
            weeklyUsed: json["weekly_used"] as? Int,
            opusUsed: json["opus_used"] as? Int,
            sonnetUsed: json["sonnet_used"] as? Int,
            sessionReset: json["session_reset"] as? String,
            weeklyReset: json["weekly_reset"] as? String,
            extraUsage: extra,
            rateLimitTier: json["rate_limit_tier"] as? String,
            accountEmail: json["account_email"] as? String,
            sourceLabel: "helper-web"
        )
    }

    // MARK: - API calls (CodexBar-parity endpoint set)

    private struct OrgInfo {
        let id: String
        let email: String?
    }

    /// `GET /api/organizations` — returns org UUID and email.
    private func fetchOrganization(sessionKey: String) async throws -> OrgInfo {
        let data = try await apiRequest(path: "/organizations", sessionKey: sessionKey)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let id = first["uuid"] as? String ?? first["id"] as? String else {
            throw ClaudeStrategyError.parseFailed("no organization found")
        }
        let email = first["email_address"] as? String
        return OrgInfo(id: id, email: email)
    }

    private struct UsageData {
        let sessionPercent: Int?
        let weeklyPercent: Int?
        let opusPercent: Int?
        let sessionResetISO: String?
        let weeklyResetISO: String?
        let planType: String?
    }

    /// `GET /api/organizations/{orgId}/usage` — session/weekly/opus utilization.
    private func fetchUsage(orgId: String, sessionKey: String) async throws -> UsageData {
        let data = try await apiRequest(path: "/organizations/\(orgId)/usage", sessionKey: sessionKey)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeStrategyError.parseFailed("usage response not a dictionary")
        }

        let isoFormatter = ISO8601DateFormatter()

        func parsePercent(_ key: String) -> Int? {
            if let val = json[key] as? Double { return Int(val.rounded()) }
            if let val = json[key] as? Int { return val }
            return nil
        }

        func parseReset(_ key: String) -> String? {
            if let str = json[key] as? String { return str }
            if let ts = json[key] as? Double {
                return isoFormatter.string(from: Date(timeIntervalSince1970: ts))
            }
            return nil
        }

        let sessionPct = parsePercent("session_percent_used")
            ?? parsePercent("sessionPercentUsed")
            ?? parsePercent("five_hour_utilization")
        let weeklyPct = parsePercent("weekly_percent_used")
            ?? parsePercent("weeklyPercentUsed")
            ?? parsePercent("seven_day_utilization")
        let opusPct = parsePercent("opus_percent_used")
            ?? parsePercent("opusPercentUsed")
            ?? parsePercent("seven_day_opus_utilization")

        let sessionReset = parseReset("session_resets_at") ?? parseReset("sessionResetsAt")
        let weeklyReset = parseReset("weekly_resets_at") ?? parseReset("weeklyResetsAt")
        let plan = json["plan_type"] as? String ?? json["planType"] as? String

        return UsageData(
            sessionPercent: sessionPct, weeklyPercent: weeklyPct, opusPercent: opusPct,
            sessionResetISO: sessionReset, weeklyResetISO: weeklyReset, planType: plan
        )
    }

    /// `GET /api/organizations/{orgId}/overage_spend_limit` — extra usage credits.
    /// This is the CodexBar-documented endpoint (NOT `/extra_usage`).
    /// Response: `{ monthlyCreditLimit, currency, usedCredits, isEnabled }`
    /// Credits are in cents — divide by 100 for dollars.
    private func fetchOverageSpendLimit(orgId: String, sessionKey: String) async -> ClaudeExtraUsage? {
        guard let data = try? await apiRequest(path: "/organizations/\(orgId)/overage_spend_limit", sessionKey: sessionKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // CodexBar decodes as: monthlyCreditLimit, usedCredits (both in cents)
        let isEnabled = json["isEnabled"] as? Bool ?? json["is_enabled"] as? Bool ?? false
        guard isEnabled else { return nil }

        // Cents → dollars (matching CodexBar's / 100 conversion)
        let limitCents = (json["monthlyCreditLimit"] as? NSNumber)?.doubleValue
            ?? (json["monthly_credit_limit"] as? NSNumber)?.doubleValue
        let usedCents = (json["usedCredits"] as? NSNumber)?.doubleValue
            ?? (json["used_credits"] as? NSNumber)?.doubleValue

        return ClaudeExtraUsage(
            isEnabled: true,
            monthlyLimit: limitCents.map { $0 / 100.0 },
            usedCredits: usedCents.map { $0 / 100.0 },
            currency: json["currency"] as? String ?? "USD"
        )
    }

    private struct AccountInfo {
        let email: String?
        let rateLimitTier: String?
    }

    /// `GET /api/account` — account email, plan/tier hints.
    /// CodexBar uses this to extract email and infer plan type from memberships.
    private func fetchAccount(sessionKey: String) async -> AccountInfo? {
        guard let data = try? await apiRequest(path: "/account", sessionKey: sessionKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let email = json["email_address"] as? String
            ?? json["emailAddress"] as? String
            ?? json["email"] as? String

        // Extract tier from memberships (CodexBar pattern)
        var tier: String? = nil
        if let memberships = json["memberships"] as? [[String: Any]] {
            for membership in memberships {
                if let org = membership["organization"] as? [String: Any] {
                    if let t = org["rate_limit_tier"] as? String ?? org["rateLimitTier"] as? String {
                        tier = t
                        break
                    }
                }
            }
        }

        return AccountInfo(email: email, rateLimitTier: tier)
    }

    // MARK: - HTTP

    private func apiRequest(path: String, sessionKey: String) async throws -> Data {
        guard let url = URL(string: Self.baseURL + path) else {
            throw ClaudeStrategyError.parseFailed("invalid URL: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh) CLIPulseBar", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeStrategyError.parseFailed("non-HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ClaudeStrategyError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ClaudeStrategyError.httpError(status: http.statusCode, provider: "Claude Web")
        }
        return data
    }
}
#endif
