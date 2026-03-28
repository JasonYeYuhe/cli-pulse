import WidgetKit
import SwiftUI
import CLIPulseCore

// MARK: - Single Provider Widget (Small circular gauge)

struct ProviderUsageWidget: Widget {
    let kind = "ProviderUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SingleProviderTimelineProvider()) { entry in
            ProviderUsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(L10n.widget.usageTitle)
        .description(L10n.widget.usageDescription)
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - View

struct ProviderUsageWidgetView: View {
    let entry: SingleProviderEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                    .frame(width: 72, height: 72)

                // Usage ring
                Circle()
                    .trim(from: 0, to: min(entry.provider.usagePercent, 1.0))
                    .stroke(
                        WidgetTheme.providerGradient(entry.provider.name),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))

                // Warning ring overlay
                if entry.provider.usagePercent > 0.9 {
                    Circle()
                        .trim(from: 0, to: min(entry.provider.usagePercent, 1.0))
                        .stroke(
                            Color.red.opacity(0.6),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                }

                // Center content
                VStack(spacing: 0) {
                    Image(systemName: entry.provider.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WidgetTheme.providerColor(entry.provider.name))
                    Text("\(Int(entry.provider.usagePercent * 100))%")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }

            Text(entry.provider.name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(entry.provider.formattedUsage)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                if entry.provider.quota != nil {
                    Text(L10n.widget.used)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    ProviderUsageWidget()
} timeline: {
    SingleProviderEntry(date: .now, provider: WidgetData.preview.providers[0])
}
