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
        switch status {
        case "Running": return .green
        case "Idle": return .orange
        case "Failed": return .red
        case "Syncing": return .blue
        case "Online": return .green
        case "Degraded": return .orange
        case "Offline": return .red
        case "Operational": return .green
        case "Down": return .red
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
        case .free: return "FREE"
        case .pro: return "PRO"
        case .team: return "TEAM"
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
    public static func format(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return isoString
        }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return L10n.time.justNow }
        let ago = L10n.time.ago
        if interval < 3600 { return "\(Int(interval / 60))m \(ago)" }
        if interval < 86400 { return "\(Int(interval / 3600))h \(ago)" }
        return "\(Int(interval / 86400))d \(ago)"
    }
}
