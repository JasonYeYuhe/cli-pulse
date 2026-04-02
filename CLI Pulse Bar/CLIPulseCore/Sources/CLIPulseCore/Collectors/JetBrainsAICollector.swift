#if os(macOS)
import Foundation

/// Reads quota data from JetBrains AI Assistant's local XML config file.
///
/// Data source: `~/Library/Application Support/JetBrains/{IDE}{version}/options/AIAssistantQuotaManager2.xml`
/// Auth: none required — reads local file system only.
///
/// The XML contains HTML-encoded JSON with current/maximum credits and next refill date.
public struct JetBrainsAICollector: ProviderCollector, Sendable {
    public let kind = ProviderKind.jetbrainsAI

    public func isAvailable(config: ProviderConfig) -> Bool {
        findQuotaFile() != nil
    }

    public func collect(config: ProviderConfig) async throws -> CollectorResult {
        guard let path = findQuotaFile() else {
            throw CollectorError.missingCredentials("JetBrains AI: no AIAssistantQuotaManager2.xml found")
        }

        let xmlString = try String(contentsOfFile: path, encoding: .utf8)
        let parsed = try JetBrainsAICollector.parseQuotaXML(xmlString)
        return buildResult(quota: parsed)
    }

    // MARK: - File discovery

    private static let idePatterns = [
        "IntelliJIdea", "PyCharm", "WebStorm", "GoLand", "CLion",
        "DataGrip", "RubyMine", "Rider", "PhpStorm", "AppCode",
        "Fleet", "RustRover", "Aqua", "DataSpell",
    ]

    /// Searches JetBrains config dirs for the most recently modified quota file.
    func findQuotaFile() -> String? {
        let baseDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/JetBrains")
        let googleDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Google")
        let fm = FileManager.default

        var candidates: [(path: String, modified: Date)] = []

        for base in [baseDir, googleDir] {
            guard let contents = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for dir in contents {
                let quotaPath = (base as NSString)
                    .appendingPathComponent(dir)
                    .appending("/options/AIAssistantQuotaManager2.xml")
                if fm.fileExists(atPath: quotaPath),
                   let attrs = try? fm.attributesOfItem(atPath: quotaPath),
                   let modified = attrs[.modificationDate] as? Date {
                    candidates.append((quotaPath, modified))
                }
            }
        }

        // Return the most recently modified file
        return candidates.max(by: { $0.modified < $1.modified })?.path
    }

    // MARK: - Parsing (internal for testing)

    struct QuotaInfo: Sendable {
        let type: String       // e.g. "monthly"
        let current: Int       // credits used
        let maximum: Int       // total credits
        let until: String?     // ISO8601 date when quota resets
        let tariffAvailable: Int?  // additional tariff credits
        let nextRefill: String? // ISO8601 date of next refill
    }

    static func parseQuotaXML(_ xml: String) throws -> QuotaInfo {
        // Extract the quotaInfo option value
        guard let quotaJSON = extractOptionValue(xml: xml, name: "quotaInfo") else {
            throw CollectorError.parseFailed("JetBrains: quotaInfo option not found")
        }

        let decoded = htmlDecode(quotaJSON)
        guard let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.parseFailed("JetBrains: quotaInfo JSON parse failed")
        }

        let type = json["type"] as? String ?? "unknown"
        let current = (json["current"] as? NSNumber)?.intValue ?? 0
        let maximum = (json["maximum"] as? NSNumber)?.intValue ?? 0
        let until = json["until"] as? String
        let tariffAvailable = (json["tariffQuota"] as? [String: Any])?["available"] as? Int

        // Try to get nextRefill
        var nextRefill: String? = nil
        if let refillJSON = extractOptionValue(xml: xml, name: "nextRefill") {
            let refillDecoded = htmlDecode(refillJSON)
            if let refillData = refillDecoded.data(using: .utf8),
               let refillObj = try? JSONSerialization.jsonObject(with: refillData) as? [String: Any] {
                nextRefill = refillObj["next"] as? String
            }
        }

        return QuotaInfo(
            type: type,
            current: current,
            maximum: maximum,
            until: until,
            tariffAvailable: tariffAvailable,
            nextRefill: nextRefill
        )
    }

    /// Extract the value attribute from an <option name="X" value="Y"/> element.
    static func extractOptionValue(xml: String, name: String) -> String? {
        // Pattern: <option name="quotaInfo" value="..."/>
        let pattern = #"<option\s+name="\#(name)"\s+value="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range])
    }

    /// Decode HTML entities in a string.
    static func htmlDecode(_ str: String) -> String {
        str.replacingOccurrences(of: "&amp;", with: "&")
           .replacingOccurrences(of: "&lt;", with: "<")
           .replacingOccurrences(of: "&gt;", with: ">")
           .replacingOccurrences(of: "&quot;", with: "\"")
           .replacingOccurrences(of: "&#39;", with: "'")
           .replacingOccurrences(of: "&#x27;", with: "'")
    }

    // MARK: - Result building

    func buildResult(quota: QuotaInfo) -> CollectorResult {
        let remaining = max(0, quota.maximum - quota.current)

        var tiers: [TierDTO] = []
        tiers.append(TierDTO(
            name: "AI Credits",
            quota: quota.maximum,
            remaining: remaining,
            reset_time: quota.until ?? quota.nextRefill
        ))

        // If tariff credits exist, add as separate tier
        if let tariff = quota.tariffAvailable, tariff > 0 {
            tiers.append(TierDTO(
                name: "Tariff Credits",
                quota: tariff,
                remaining: tariff,  // tariff credits are "available", meaning not yet used
                reset_time: nil
            ))
        }

        let statusText = "\(quota.current)/\(quota.maximum) credits used"

        let usage = ProviderUsage(
            provider: ProviderKind.jetbrainsAI.rawValue,
            today_usage: quota.current,
            week_usage: quota.current,
            estimated_cost_today: 0,
            estimated_cost_week: 0,
            cost_status_today: "Unavailable",
            cost_status_week: "Unavailable",
            quota: quota.maximum,
            remaining: remaining,
            plan_type: quota.type.capitalized,
            reset_time: quota.until ?? quota.nextRefill,
            tiers: tiers,
            status_text: statusText,
            trend: [],
            recent_sessions: [],
            recent_errors: [],
            metadata: ProviderMetadata(
                display_name: "JetBrains AI",
                category: "ide",
                supports_exact_cost: false,
                supports_quota: true
            )
        )

        return CollectorResult(usage: usage, dataKind: .quota)
    }
}
#endif
