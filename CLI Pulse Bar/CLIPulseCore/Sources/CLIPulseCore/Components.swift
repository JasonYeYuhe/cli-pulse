import SwiftUI

// MARK: - Theme

public enum PulseTheme {
    public static let accent = Color(red: 0.36, green: 0.51, blue: 1.0)
    public static let secondaryAccent = Color(red: 0.58, green: 0.39, blue: 0.98)
    #if os(macOS)
    public static let background = Color(nsColor: .windowBackgroundColor)
    public static let cardBackground = Color(nsColor: .controlBackgroundColor)
    #elseif os(watchOS)
    public static let background = Color.black
    public static let cardBackground = Color(white: 0.15)
    #else
    public static let background = Color(uiColor: .systemBackground)
    public static let cardBackground = Color(uiColor: .secondarySystemBackground)
    #endif
    public static let dimText = Color.secondary

    public static func providerColor(_ provider: String) -> Color {
        switch provider {
        case "Codex": return Color(red: 0.36, green: 0.51, blue: 1.0)
        case "Gemini": return Color(red: 0.58, green: 0.39, blue: 0.98)
        case "Claude": return Color(red: 0.90, green: 0.55, blue: 0.20)
        case "Cursor": return Color(red: 0.40, green: 0.80, blue: 0.40)
        case "OpenCode": return Color(red: 0.50, green: 0.50, blue: 0.80)
        case "Droid": return Color(red: 0.70, green: 0.40, blue: 0.70)
        case "Antigravity": return Color(red: 0.85, green: 0.35, blue: 0.55)
        case "Copilot": return Color(red: 0.30, green: 0.70, blue: 0.90)
        case "z.ai": return Color(red: 0.95, green: 0.60, blue: 0.10)
        case "MiniMax": return Color(red: 0.60, green: 0.30, blue: 0.90)
        case "Augment": return Color(red: 0.25, green: 0.75, blue: 0.55)
        case "JetBrains AI": return Color(red: 0.95, green: 0.30, blue: 0.50)
        case "Kimi K2": return Color(red: 0.40, green: 0.60, blue: 0.95)
        case "Amp": return Color(red: 0.90, green: 0.75, blue: 0.20)
        case "Synthetic": return Color(red: 0.55, green: 0.45, blue: 0.85)
        case "Warp": return Color(red: 0.20, green: 0.80, blue: 0.80)
        case "Kilo": return Color(red: 0.75, green: 0.55, blue: 0.35)
        case "OpenRouter": return Color(red: 0.20, green: 0.65, blue: 0.90)
        case "Ollama": return Color(red: 0.30, green: 0.80, blue: 0.65)
        case "Alibaba": return Color(red: 0.95, green: 0.50, blue: 0.15)
        case "Kimi": return Color(red: 0.35, green: 0.55, blue: 0.90)
        case "Kiro": return Color(red: 0.20, green: 0.70, blue: 0.50)
        case "Vertex AI": return Color(red: 0.26, green: 0.52, blue: 0.96)
        case "Perplexity": return Color(red: 0.10, green: 0.75, blue: 0.75)
        default: return .gray
        }
    }

    public static func severityColor(_ severity: String) -> Color {
        switch severity {
        case "Critical": return .red
        case "Warning": return .orange
        case "Info": return .blue
        default: return .gray
        }
    }

    public static func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "running": return .green
        case "idle": return .orange
        case "failed": return .red
        case "syncing": return .blue
        case "online": return .green
        case "degraded": return .orange
        case "offline": return .red
        case "operational": return .green
        case "down": return .red
        default: return .gray
        }
    }
}

// MARK: - Usage Bar

public struct UsageBar: View {
    public let label: String
    public let value: Double
    public let color: Color
    public let detail: String?

    public init(label: String, value: Double, color: Color, detail: String? = nil) {
        self.label = label
        self.value = min(1.0, max(0, value))
        self.color = color
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * value), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Metric Card

public struct MetricCard: View {
    public let title: String
    public let value: String
    public let subtitle: String?
    public let icon: String
    public let color: Color

    public init(title: String, value: String, subtitle: String? = nil, icon: String, color: Color = PulseTheme.accent) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(PulseTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Status Badge

public struct StatusBadge: View {
    public let text: String
    public let color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Severity Dot

public struct SeverityDot: View {
    public let severity: String

    public init(severity: String) {
        self.severity = severity
    }

    public var body: some View {
        Circle()
            .fill(PulseTheme.severityColor(severity))
            .frame(width: 8, height: 8)
    }
}

// MARK: - Section Header

public struct SectionHeader: View {
    public let title: String
    public let icon: String

    public init(title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PulseTheme.accent)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Empty State

public struct EmptyStateView: View {
    public let icon: String
    public let title: String
    public let subtitle: String

    public init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Subscription Badge

public struct SubscriptionBadge: View {
    public let tier: SubscriptionTier

    public init(tier: SubscriptionTier) {
        self.tier = tier
    }

    private var label: String {
        switch tier {
        case .free: return L10n.badge.free
        case .pro: return L10n.badge.pro
        case .team: return L10n.badge.team
        }
    }

    private var color: Color {
        switch tier {
        case .free: return .gray
        case .pro: return PulseTheme.accent
        case .team: return PulseTheme.secondaryAccent
        }
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Cost Status Badge

public struct CostStatusBadge: View {
    public let status: String

    public init(status: String) {
        self.status = status
    }

    private var label: String {
        switch status {
        case "Exact": return L10n.badge.exact
        case "Estimated": return L10n.badge.estimated
        case "Unavailable": return L10n.badge.unavailable
        default: return status.uppercased()
        }
    }

    private var color: Color {
        switch status {
        case "Exact": return .green
        case "Estimated": return .orange
        case "Unavailable": return .gray
        default: return .gray
        }
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Collection Confidence Badge

public struct ConfidenceBadge: View {
    public let confidence: String

    public init(confidence: String) {
        self.confidence = confidence
    }

    private var icon: String {
        switch confidence {
        case "high": return "checkmark.shield.fill"
        case "medium": return "shield.lefthalf.filled"
        case "low": return "questionmark.diamond"
        default: return "questionmark.diamond"
        }
    }

    private var color: Color {
        switch confidence {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }

    private var localizedConfidence: String {
        switch confidence {
        case "high": return L10n.badge.high
        case "medium": return L10n.badge.medium
        case "low": return L10n.badge.low
        default: return confidence.capitalized
        }
    }

    public var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(localizedConfidence)
                .font(.system(size: 8, weight: .medium))
        }
        .foregroundStyle(color)
    }
}

// MARK: - Category Badge

public struct CategoryBadge: View {
    public let category: String

    public init(category: String) {
        self.category = category
    }

    private var icon: String {
        switch category {
        case "cloud": return "cloud"
        case "local": return "desktopcomputer"
        case "aggregator": return "arrow.triangle.branch"
        case "ide": return "hammer"
        default: return "questionmark"
        }
    }

    private var label: String {
        switch category {
        case "cloud": return L10n.badge.cloud
        case "local": return L10n.badge.local
        case "aggregator": return L10n.badge.aggregator
        case "ide": return L10n.badge.ide
        default: return category.uppercased()
        }
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(label)
                .font(.system(size: 7, weight: .semibold))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(PulseTheme.dimText.opacity(0.1))
        .foregroundStyle(.secondary)
        .clipShape(Capsule())
    }
}

// MARK: - Cost Formatter

public enum CostFormatter {
    public static func format(_ cost: Double) -> String {
        if cost < 0.01 { return "<$0.01" }
        if cost < 1.0 { return String(format: "$%.2f", cost) }
        return String(format: "$%.1f", cost)
    }

    public static func formatUsage(_ usage: Int) -> String {
        if usage >= 1_000_000 { return String(format: "%.1fM", Double(usage) / 1_000_000) }
        if usage >= 1_000 { return String(format: "%.1fK", Double(usage) / 1_000) }
        return "\(usage)"
    }
}

// MARK: - Relative Time

public enum RelativeTime {
    private static let formatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let formatterBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func format(_ isoString: String) -> String {
        guard let date = formatterWithFractional.date(from: isoString) ?? formatterBasic.date(from: isoString) else {
            return isoString
        }
        let interval = Date().timeIntervalSince(date)
        if interval >= 0 {
            // Past
            if interval < 60 { return L10n.time.justNow }
            let ago = L10n.time.ago
            if interval < 3600 { return "\(Int(interval / 60))m \(ago)" }
            if interval < 86400 { return "\(Int(interval / 3600))h \(ago)" }
            return "\(Int(interval / 86400))d \(ago)"
        } else {
            // Future (for reset times)
            let remaining = -interval
            if remaining < 60 { return "in <1m" }
            if remaining < 3600 { return "in \(Int(remaining / 60))m" }
            let hours = Int(remaining / 3600)
            let mins = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
            if remaining < 86400 { return mins > 0 ? "in \(hours)h \(mins)m" : "in \(hours)h" }
            let days = Int(remaining / 86400)
            let remHours = Int(remaining.truncatingRemainder(dividingBy: 86400) / 3600)
            return remHours > 0 ? "in \(days)d \(remHours)h" : "in \(days)d"
        }
    }

    /// Format reset times for quota windows.
    /// Reset timestamps should only be shown when they are in the future.
    public static func formatReset(_ isoString: String) -> String? {
        guard let date = formatterWithFractional.date(from: isoString) ?? formatterBasic.date(from: isoString) else {
            return nil
        }

        let interval = Date().timeIntervalSince(date)
        guard interval < 0 else { return nil }

        let totalMinutes = max(1, Int(ceil((-interval) / 60.0)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let mins = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "in \(days)d \(hours)h" : "in \(days)d"
        }
        if hours > 0 {
            return mins > 0 ? "in \(hours)h \(mins)m" : "in \(hours)h"
        }
        return "in \(totalMinutes)m"
    }
}
