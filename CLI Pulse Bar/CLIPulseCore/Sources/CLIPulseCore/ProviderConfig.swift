import Foundation
import SwiftUI

// MARK: - Provider Configuration (local state, not from API)

/// Non-sensitive fields that persist in UserDefaults.
/// Secrets (apiKey, manualCookieHeader) are stored/loaded separately via Keychain.
public struct ProviderConfig: Codable, Identifiable, Sendable {
    public let kind: ProviderKind
    public var isEnabled: Bool
    public var sortOrder: Int
    public var sourceMode: SourceType
    public var cookieSource: CookieSource?
    public var accountLabel: String?

    // Transient — never encoded into UserDefaults.  Populated at runtime from Keychain.
    public var apiKey: String?
    public var manualCookieHeader: String?

    public var id: String { kind.rawValue }

    // Only encode non-sensitive fields to UserDefaults
    private enum CodingKeys: String, CodingKey {
        case kind, isEnabled, sortOrder, sourceMode, cookieSource, accountLabel
    }

    public init(
        kind: ProviderKind,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        sourceMode: SourceType = .auto,
        apiKey: String? = nil,
        cookieSource: CookieSource? = nil,
        manualCookieHeader: String? = nil,
        accountLabel: String? = nil
    ) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.sourceMode = sourceMode
        self.apiKey = apiKey
        self.cookieSource = cookieSource
        self.manualCookieHeader = manualCookieHeader
        self.accountLabel = accountLabel
    }

    public static func defaults() -> [ProviderConfig] {
        ProviderKind.allCases.enumerated().map { index, kind in
            ProviderConfig(kind: kind, isEnabled: true, sortOrder: index)
        }
    }

    /// Whether this provider has any credentials configured
    public var hasCredentials: Bool {
        (apiKey != nil && !(apiKey?.isEmpty ?? true)) ||
        (manualCookieHeader != nil && !(manualCookieHeader?.isEmpty ?? true)) ||
        cookieSource != nil
    }

    // MARK: - Keychain secret helpers

    private static func keychainKey(_ kind: ProviderKind, _ suffix: String) -> String {
        "cli_pulse_provider_\(kind.rawValue)_\(suffix)"
    }

    /// Save this config's secrets to Keychain. Call after mutating apiKey / manualCookieHeader.
    public func saveSecrets() {
        let apiKeyKey = Self.keychainKey(kind, "apiKey")
        if let key = apiKey, !key.isEmpty {
            KeychainHelper.save(key: apiKeyKey, value: key)
        } else {
            KeychainHelper.delete(key: apiKeyKey)
        }

        let cookieKey = Self.keychainKey(kind, "cookie")
        if let cookie = manualCookieHeader, !cookie.isEmpty {
            KeychainHelper.save(key: cookieKey, value: cookie)
        } else {
            KeychainHelper.delete(key: cookieKey)
        }
    }

    /// Load secrets from Keychain into the in-memory fields.
    public mutating func loadSecrets() {
        apiKey = KeychainHelper.load(key: Self.keychainKey(kind, "apiKey"))
        manualCookieHeader = KeychainHelper.load(key: Self.keychainKey(kind, "cookie"))
    }

    /// Remove all Keychain entries for this provider.
    public func deleteSecrets() {
        KeychainHelper.delete(key: Self.keychainKey(kind, "apiKey"))
        KeychainHelper.delete(key: Self.keychainKey(kind, "cookie"))
    }
}

// MARK: - Cookie Source

public enum CookieSource: String, Codable, CaseIterable, Sendable {
    case safari = "Safari"
    case chrome = "Chrome"
    case firefox = "Firefox"
    case manual = "Manual"
}

// MARK: - Usage Tier (e.g., Pro/Flash/Flash Lite for Gemini)

public struct UsageTier: Codable, Identifiable, Sendable {
    public let name: String
    public let usage: Int
    public let quota: Int?
    public let remaining: Int?
    public let resetTime: String?

    public var id: String { name }

    public var usagePercent: Double {
        guard let quota = quota, quota > 0 else { return 0 }
        let used = quota - (remaining ?? 0)
        return min(1.0, Double(used) / Double(quota))
    }

    public init(name: String, usage: Int, quota: Int?, remaining: Int?, resetTime: String?) {
        self.name = name
        self.usage = usage
        self.quota = quota
        self.remaining = remaining
        self.resetTime = resetTime
    }
}

// MARK: - Enhanced Provider Detail (combines API data + local config)

public struct ProviderDetail: Identifiable, Equatable {
    public static func == (lhs: ProviderDetail, rhs: ProviderDetail) -> Bool {
        lhs.id == rhs.id &&
        lhs.config.isEnabled == rhs.config.isEnabled &&
        lhs.config.sortOrder == rhs.config.sortOrder &&
        lhs.operationalStatus == rhs.operationalStatus &&
        lhs.sourceType == rhs.sourceType
    }

    public let provider: ProviderUsage
    public var config: ProviderConfig
    public var tiers: [UsageTier]
    public var operationalStatus: ProviderStatus
    public var accountEmail: String?
    public var planType: String?
    public var sourceType: SourceType
    public var version: String?

    public var id: String { provider.id }

    public init(
        provider: ProviderUsage,
        config: ProviderConfig,
        tiers: [UsageTier] = [],
        operationalStatus: ProviderStatus = .operational,
        accountEmail: String? = nil,
        planType: String? = nil,
        sourceType: SourceType = .auto,
        version: String? = nil
    ) {
        self.provider = provider
        self.config = config
        self.tiers = tiers
        self.operationalStatus = operationalStatus
        self.accountEmail = accountEmail
        self.planType = planType
        self.sourceType = sourceType
        self.version = version
    }
}

// MARK: - Menu Bar Display Mode

public enum MenuBarDisplayMode: String, Codable, CaseIterable, Sendable {
    case icon = "Icon"
    case percent = "Percent"
    case pace = "Pace"
    case mostUsed = "Most Used"

    public var localizedName: String {
        switch self {
        case .icon: return L10n.display.icon
        case .percent: return L10n.display.percent
        case .pace: return L10n.display.pace
        case .mostUsed: return L10n.display.mostUsed
        }
    }

    public var description: String {
        switch self {
        case .icon: return "App icon only"
        case .percent: return "Remaining % of most-used"
        case .pace: return "Usage vs expected pace"
        case .mostUsed: return "Most active provider"
        }
    }
}

// MARK: - Menu Bar Content Mode

public enum MenuBarContentMode: String, Codable, CaseIterable, Sendable {
    case usageAsUsed = "Usage (Used)"
    case resetTime = "Reset Time"
    case credits = "Credits"
    case allAccounts = "All Accounts"
}

// MARK: - Provider Descriptor (metadata + capabilities)

public struct ProviderDescriptor: Sendable {
    public let kind: ProviderKind
    public let displayName: String
    public let category: ProviderCategory
    public let supportedSources: [SourceType]
    public let supportsQuota: Bool
    public let supportsExactCost: Bool
    public let supportsCredits: Bool
    public let supportsStatusPolling: Bool
    public let requiresHelperBackend: Bool
    public let cliNames: [String]
    public let webDomain: String?

    public init(
        kind: ProviderKind,
        displayName: String,
        category: ProviderCategory,
        supportedSources: [SourceType],
        supportsQuota: Bool = true,
        supportsExactCost: Bool = false,
        supportsCredits: Bool = false,
        supportsStatusPolling: Bool = false,
        requiresHelperBackend: Bool = false,
        cliNames: [String] = [],
        webDomain: String? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.category = category
        self.supportedSources = supportedSources
        self.supportsQuota = supportsQuota
        self.supportsExactCost = supportsExactCost
        self.supportsCredits = supportsCredits
        self.supportsStatusPolling = supportsStatusPolling
        self.requiresHelperBackend = requiresHelperBackend
        self.cliNames = cliNames
        self.webDomain = webDomain
    }
}

// MARK: - Provider Registry

public enum ProviderRegistry {
    public static let all: [ProviderKind: ProviderDescriptor] = {
        var registry: [ProviderKind: ProviderDescriptor] = [:]
        for d in descriptors { registry[d.kind] = d }
        return registry
    }()

    public static func descriptor(for kind: ProviderKind) -> ProviderDescriptor {
        all[kind] ?? ProviderDescriptor(
            kind: kind, displayName: kind.rawValue, category: .cloud,
            supportedSources: [.auto]
        )
    }

    private static let descriptors: [ProviderDescriptor] = [
        ProviderDescriptor(
            kind: .codex, displayName: "Codex (OpenAI)", category: .cloud,
            supportedSources: [.auto, .web, .cli, .oauth, .api],
            supportsQuota: true, supportsExactCost: true, supportsCredits: true,
            supportsStatusPolling: true, requiresHelperBackend: true,
            cliNames: ["codex"], webDomain: "chatgpt.com"
        ),
        ProviderDescriptor(
            kind: .claude, displayName: "Claude (Anthropic)", category: .cloud,
            supportedSources: [.auto, .web, .cli, .oauth, .api],
            supportsQuota: true, supportsExactCost: true, supportsCredits: true,
            supportsStatusPolling: true, requiresHelperBackend: true,
            cliNames: ["claude"], webDomain: "claude.ai"
        ),
        ProviderDescriptor(
            kind: .gemini, displayName: "Gemini (Google)", category: .cloud,
            supportedSources: [.auto, .web, .oauth, .api],
            supportsQuota: true, supportsExactCost: false, supportsCredits: true,
            supportsStatusPolling: true, requiresHelperBackend: true,
            cliNames: ["gemini"], webDomain: "aistudio.google.com"
        ),
        ProviderDescriptor(
            kind: .cursor, displayName: "Cursor", category: .ide,
            supportedSources: [.auto, .web, .local],
            supportsQuota: true, supportsExactCost: false,
            supportsStatusPolling: true, requiresHelperBackend: true,
            cliNames: ["cursor"], webDomain: "cursor.com"
        ),
        ProviderDescriptor(
            kind: .copilot, displayName: "GitHub Copilot", category: .ide,
            supportedSources: [.auto, .web, .oauth],
            supportsQuota: true, supportsExactCost: false,
            supportsStatusPolling: true, requiresHelperBackend: true,
            cliNames: ["copilot"], webDomain: "github.com"
        ),
        ProviderDescriptor(
            kind: .openCode, displayName: "OpenCode", category: .cloud,
            supportedSources: [.auto, .cli],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["opencode"]
        ),
        ProviderDescriptor(
            kind: .droid, displayName: "Droid / Factory", category: .cloud,
            supportedSources: [.auto, .web, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["droid", "factory"], webDomain: "factory.ai"
        ),
        ProviderDescriptor(
            kind: .antigravity, displayName: "Antigravity", category: .cloud,
            supportedSources: [.auto, .local],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["antigravity"]
        ),
        ProviderDescriptor(
            kind: .zai, displayName: "z.ai", category: .cloud,
            supportedSources: [.auto, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["zai"], webDomain: "z.ai"
        ),
        ProviderDescriptor(
            kind: .minimax, displayName: "MiniMax", category: .cloud,
            supportedSources: [.auto, .web, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["minimax"], webDomain: "minimax.io"
        ),
        ProviderDescriptor(
            kind: .augment, displayName: "Augment", category: .ide,
            supportedSources: [.auto, .local],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["augment"]
        ),
        ProviderDescriptor(
            kind: .jetbrainsAI, displayName: "JetBrains AI", category: .ide,
            supportedSources: [.auto, .local],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["jbai"]
        ),
        ProviderDescriptor(
            kind: .kimiK2, displayName: "Kimi K2 (Moonshot)", category: .cloud,
            supportedSources: [.auto, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["kimi-k2"], webDomain: "kimi.moonshot.cn"
        ),
        ProviderDescriptor(
            kind: .kimi, displayName: "Kimi (Moonshot)", category: .cloud,
            supportedSources: [.auto, .web, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["kimi"], webDomain: "kimi.moonshot.cn"
        ),
        ProviderDescriptor(
            kind: .amp, displayName: "Amp", category: .cloud,
            supportedSources: [.auto, .web, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["amp"], webDomain: "amp.dev"
        ),
        ProviderDescriptor(
            kind: .synthetic, displayName: "Synthetic", category: .cloud,
            supportedSources: [.auto],
            supportsQuota: true
        ),
        ProviderDescriptor(
            kind: .warp, displayName: "Warp", category: .cloud,
            supportedSources: [.auto, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["warp"], webDomain: "warp.dev"
        ),
        ProviderDescriptor(
            kind: .kilo, displayName: "Kilo Code", category: .cloud,
            supportedSources: [.auto, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["kilo"]
        ),
        ProviderDescriptor(
            kind: .ollama, displayName: "Ollama (Local)", category: .local,
            supportedSources: [.auto, .local, .api],
            supportsQuota: false, supportsExactCost: false,
            cliNames: ["ollama"]
        ),
        ProviderDescriptor(
            kind: .openRouter, displayName: "OpenRouter", category: .aggregator,
            supportedSources: [.auto, .api],
            supportsQuota: true, supportsExactCost: true, supportsCredits: true,
            requiresHelperBackend: true,
            cliNames: ["openrouter"], webDomain: "openrouter.ai"
        ),
        ProviderDescriptor(
            kind: .alibaba, displayName: "Alibaba Coding Plan", category: .cloud,
            supportedSources: [.auto, .web, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["alibaba", "tongyi"], webDomain: "tongyi.aliyun.com"
        ),
        ProviderDescriptor(
            kind: .kiro, displayName: "Kiro (AWS)", category: .ide,
            supportedSources: [.auto, .cli],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["kiro"]
        ),
        ProviderDescriptor(
            kind: .vertexAI, displayName: "Vertex AI (Google Cloud)", category: .cloud,
            supportedSources: [.auto, .oauth, .api],
            supportsQuota: true, supportsExactCost: true,
            requiresHelperBackend: true,
            webDomain: "console.cloud.google.com"
        ),
        ProviderDescriptor(
            kind: .perplexity, displayName: "Perplexity", category: .cloud,
            supportedSources: [.auto, .api],
            supportsQuota: true, supportsExactCost: false,
            requiresHelperBackend: true,
            cliNames: ["perplexity", "pplx"], webDomain: "perplexity.ai"
        ),
        ProviderDescriptor(
            kind: .volcanoEngine, displayName: "Volcano Engine (豆包)", category: .cloud,
            supportedSources: [.auto, .web, .api],
            supportsQuota: true, requiresHelperBackend: true,
            cliNames: ["volcano", "doubao", "ark", "vecli"],
            webDomain: "console.volcengine.com"
        ),
    ]
}

// MARK: - Cost Summary

/// Per-provider subscription utilization (API equivalent cost / subscription cost)
public struct SubscriptionUtilization: Sendable {
    public let provider: String
    public let plan: String
    public let apiEquivCost: Double      // 30-day API equivalent cost from token scanning
    public let subscriptionCost: Double  // Monthly subscription price
    public let utilizationPercent: Double // apiEquivCost / subscriptionCost * 100 (0 if sub cost is 0)
    public let valueMultiplier: String   // e.g. "23x" if utilization > 100%

    public init(provider: String, plan: String, apiEquivCost: Double, subscriptionCost: Double) {
        self.provider = provider
        self.plan = plan
        self.apiEquivCost = apiEquivCost
        self.subscriptionCost = subscriptionCost
        self.utilizationPercent = subscriptionCost > 0 ? (apiEquivCost / subscriptionCost * 100) : 0
        let multiplier = subscriptionCost > 0 ? apiEquivCost / subscriptionCost : 0
        self.valueMultiplier = multiplier >= 1.0 ? String(format: "%.0fx", multiplier) : ""
    }
}

/// Per-model cost detail for breakdown views
public struct ModelCostDetail: Sendable, Identifiable {
    public var id: String { model }
    public let model: String
    public let cost: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int

    public var totalTokens: Int { inputTokens + outputTokens + cachedTokens }
}

public struct CostSummary: Sendable {
    public let todayTotal: Double
    public let todayByProvider: [(provider: String, cost: Double)]
    public let thirtyDayTotal: Double
    public let thirtyDayByProvider: [(provider: String, cost: Double)]
    /// True when costs come from precise JSONL log scanning rather than API estimates
    public let isPrecise: Bool
    /// Monthly subscription costs
    public let subscriptionTotal: Double
    public let subscriptionByProvider: [(provider: String, plan: String, monthlyCost: Double)]
    /// Grand total = subscriptionTotal + thirtyDayTotal
    public let grandTotal: Double
    /// Token totals from CostUsageScanner
    public let todayTokens: Int
    public let thirtyDayTokens: Int
    /// Subscription utilization (API equiv cost vs subscription cost)
    public let utilization: [SubscriptionUtilization]
    /// Per-model cost breakdown for 30-day period
    public let costByModel: [ModelCostDetail]

    public init(
        todayTotal: Double = 0,
        todayByProvider: [(provider: String, cost: Double)] = [],
        thirtyDayTotal: Double = 0,
        thirtyDayByProvider: [(provider: String, cost: Double)] = [],
        isPrecise: Bool = false,
        subscriptionTotal: Double = 0,
        subscriptionByProvider: [(provider: String, plan: String, monthlyCost: Double)] = [],
        grandTotal: Double = 0,
        todayTokens: Int = 0,
        thirtyDayTokens: Int = 0,
        utilization: [SubscriptionUtilization] = [],
        costByModel: [ModelCostDetail] = []
    ) {
        self.todayTotal = todayTotal
        self.todayByProvider = todayByProvider
        self.thirtyDayTotal = thirtyDayTotal
        self.thirtyDayByProvider = thirtyDayByProvider
        self.isPrecise = isPrecise
        self.subscriptionTotal = subscriptionTotal
        self.subscriptionByProvider = subscriptionByProvider
        self.grandTotal = grandTotal
        self.todayTokens = todayTokens
        self.thirtyDayTokens = thirtyDayTokens
        self.utilization = utilization
        self.costByModel = costByModel
    }
}

/// Formats token counts into compact human-readable strings: 81M, 8.6B, 12.3K
public enum TokenFormatter {
    public static func format(_ count: Int) -> String {
        let d = Double(count)
        switch d {
        case 1_000_000_000...:
            return String(format: "%.1fB", d / 1_000_000_000)
        case 1_000_000...:
            let m = d / 1_000_000
            return m >= 10 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        case 1_000...:
            let k = d / 1_000
            return k >= 10 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        default:
            return "\(count)"
        }
    }
}
