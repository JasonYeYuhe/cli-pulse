import WidgetKit
import SwiftUI
import CLIPulseCore

// MARK: - Usage Overview Widget (Small + Medium + Large)

struct UsageOverviewWidget: Widget {
    let kind = "UsageOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CLIPulseTimelineProvider()) { entry in
            UsageOverviewWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(L10n.widget.overviewTitle)
        .description(L10n.widget.overviewDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget View

struct UsageOverviewWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CLIPulseEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }

    // MARK: - Small: Total usage ring

    private var smallView: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                    .frame(width: 60, height: 60)

                let topProvider = entry.data.providers.first
                let percent = topProvider?.usagePercent ?? 0

                Circle()
                    .trim(from: 0, to: min(percent, 1.0))
                    .stroke(
                        WidgetTheme.providerGradient(topProvider?.name ?? ""),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int(percent * 100))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.data.providers.first?.name ?? L10n.widget.noData)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            Text(formatUsage(entry.data.totalUsageToday))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium: 3 provider bars

    private var mediumView: some View {
        HStack(spacing: 12) {
            // Left: summary
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetTheme.accent)
                    Text(L10n.auth.title)
                        .font(.caption.weight(.bold))
                }

                Text(formatUsage(entry.data.totalUsageToday))
                    .font(.title2.weight(.bold).monospacedDigit())

                Text(formatCost(entry.data.totalCostToday))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.green)

                Spacer()

                HStack(spacing: 8) {
                    WidgetMiniStat(icon: "terminal", value: "\(entry.data.activeSessions)", color: .blue)
                    if entry.data.unresolvedAlerts > 0 {
                        WidgetMiniStat(icon: "bell.badge", value: "\(entry.data.unresolvedAlerts)", color: .red)
                    }
                }
            }

            Divider()

            // Right: provider bars
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.data.providers.prefix(3))) { provider in
                    WidgetProviderBar(provider: provider)
                }

                if entry.data.providers.isEmpty {
                    Text(L10n.widget.noProviderData)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Large: Full dashboard

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WidgetTheme.accent)
                    Text(L10n.auth.title)
                        .font(.caption.weight(.bold))
                }
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Stats row
            HStack(spacing: 0) {
                WidgetMetricBox(title: L10n.widget.usageTitle, value: formatUsage(entry.data.totalUsageToday))
                WidgetMetricBox(title: L10n.dashboard.costToday, value: formatCost(entry.data.totalCostToday), color: .green)
                WidgetMetricBox(title: L10n.tab.sessions, value: "\(entry.data.activeSessions)")
                WidgetMetricBox(title: L10n.tab.alerts, value: "\(entry.data.unresolvedAlerts)", color: entry.data.unresolvedAlerts > 0 ? .red : .primary)
            }

            Divider()

            // Provider list
            Text(L10n.tab.providers)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(entry.data.providers.prefix(5))) { provider in
                WidgetProviderRow(provider: provider)
            }

            if entry.data.providers.isEmpty {
                Text(L10n.widget.noProviderData)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatUsage(_ usage: Int) -> String {
        if usage >= 1_000_000 {
            return String(format: "%.1fM", Double(usage) / 1_000_000)
        } else if usage >= 1_000 {
            return String(format: "%.0fK", Double(usage) / 1_000)
        }
        return "\(usage)"
    }

    private func formatCost(_ cost: Double) -> String {
        String(format: "$%.2f", cost)
    }
}

// MARK: - Subviews

struct WidgetMiniStat: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.weight(.bold).monospacedDigit())
        }
    }
}

struct WidgetProviderBar: View {
    let provider: WidgetProviderData

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.providerColor(provider.name))
                Text(provider.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(provider.usagePercent * 100))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(provider.usagePercent > 0.8 ? .red : .primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(WidgetTheme.providerGradient(provider.name))
                        .frame(width: max(2, geo.size.width * min(provider.usagePercent, 1.0)))
                }
            }
            .frame(height: 4)
        }
    }
}

struct WidgetProviderRow: View {
    let provider: WidgetProviderData

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: provider.iconName)
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.providerColor(provider.name))
                .frame(width: 16)

            Text(provider.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Spacer()

            Text(provider.formattedUsage)
                .font(.caption.weight(.bold).monospacedDigit())

            // Mini usage bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 4)
                Capsule()
                    .fill(WidgetTheme.providerColor(provider.name))
                    .frame(width: max(2, 40 * min(provider.usagePercent, 1.0)), height: 4)
            }

            Text(provider.formattedCost)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.green)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

struct WidgetMetricBox: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    UsageOverviewWidget()
} timeline: {
    CLIPulseEntry(date: .now, data: .preview)
}

#Preview(as: .systemMedium) {
    UsageOverviewWidget()
} timeline: {
    CLIPulseEntry(date: .now, data: .preview)
}

#Preview(as: .systemLarge) {
    UsageOverviewWidget()
} timeline: {
    CLIPulseEntry(date: .now, data: .preview)
}
