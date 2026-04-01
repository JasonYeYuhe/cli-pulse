import Foundation
import SwiftUI

// MARK: - Provider Configuration (local state, not from API)

public struct ProviderConfig: Codable, Identifiable, Sendable {
    public let kind: ProviderKind
    public var isEnabled: Bool
    public var sortOrder: Int

    public var id: String { kind.rawValue }

    public init(kind: ProviderKind, isEnabled: Bool = true, sortOrder: Int = 0) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    public static func defaults() -> [ProviderConfig] {
        ProviderKind.allCases.enumerated().map { index, kind in
            ProviderConfig(kind: kind, isEnabled: true, sortOrder: index)
        }
    }
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

// MARK: - Cost Summary

public struct CostSummary: Sendable {
    public let todayTotal: Double
    public let todayByProvider: [(provider: String, cost: Double)]
    public let thirtyDayTotal: Double
    public let thirtyDayByProvider: [(provider: String, cost: Double)]

    public init(
        todayTotal: Double = 0,
        todayByProvider: [(provider: String, cost: Double)] = [],
        thirtyDayTotal: Double = 0,
        thirtyDayByProvider: [(provider: String, cost: Double)] = []
    ) {
        self.todayTotal = todayTotal
        self.todayByProvider = todayByProvider
        self.thirtyDayTotal = thirtyDayTotal
        self.thirtyDayByProvider = thirtyDayByProvider
    }
}
