import WidgetKit
import SwiftUI

// MARK: - watchOS Complication Widget

/// WidgetKit complication for watchOS showing remaining quota % or unresolved alert count.
/// Uses the same WidgetStorage app group data as iOS widgets.
@available(watchOSApplicationExtension 10.0, *)
struct WatchComplicationWidget: Widget {
    let kind = "WatchComplicationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CLIPulseTimelineProvider()) { entry in
            WatchComplicationView(entry: entry)
        }
        .configurationDisplayName("CLI Pulse")
        .description("Quota & alerts at a glance")
        #if os(watchOS)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline,
        ])
        #endif
    }
}

// MARK: - Complication Views

@available(watchOSApplicationExtension 10.0, *)
struct WatchComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: CLIPulseEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    // MARK: - Circular: Gauge with quota %

    private var circularView: some View {
        let topProvider = entry.data.providers.first
        let percent = topProvider?.usagePercent ?? 0
        let remaining = max(0, 1.0 - percent)

        return ZStack {
            AccessoryWidgetBackground()

            if entry.data.providers.isEmpty {
                // Unauthenticated / no data: lock icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
            } else if entry.data.unresolvedAlerts > 0 {
                // Show alert count
                Gauge(value: min(percent, 1.0)) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 9))
                } currentValueLabel: {
                    Text("\(entry.data.unresolvedAlerts)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                // Show remaining %
                Gauge(value: remaining) {
                    Image(systemName: topProvider?.iconName ?? "waveform.path.ecg")
                        .font(.system(size: 9))
                } currentValueLabel: {
                    Text("\(Int(remaining * 100))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
            }
        }
    }

    // MARK: - Rectangular: Provider + remaining + alerts

    private var rectangularView: some View {
        let providers = Array(entry.data.providers.prefix(2))

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 8))
                Text("CLI Pulse")
                    .font(.caption2.weight(.bold))
                Spacer()
                if entry.data.unresolvedAlerts > 0 {
                    Text("\(entry.data.unresolvedAlerts)")
                        .font(.caption2.weight(.bold))
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 8))
                }
            }

            if providers.isEmpty {
                Text("Sign in to view usage")
                    .font(.caption2)
            } else {
                ForEach(providers) { p in
                    HStack(spacing: 4) {
                        Text(p.name)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        let remaining = max(0, 1.0 - p.usagePercent)
                        Text("\(Int(remaining * 100))%")
                            .font(.caption2.weight(.bold).monospacedDigit())

                        Gauge(value: remaining) {
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryLinear)
                        .frame(width: 36)
                    }
                }
            }
        }
    }

    // MARK: - Corner: Arc gauge with remaining %

    private var cornerView: some View {
        let topProvider = entry.data.providers.first
        let remaining = topProvider.map { max(0, 1.0 - $0.usagePercent) } ?? 1.0

        return Text("\(Int(remaining * 100))%")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .widgetLabel {
                Gauge(value: remaining) {
                    Text(topProvider?.name ?? "Quota")
                }
                .gaugeStyle(.accessoryLinear)
            }
    }

    // MARK: - Inline: Text summary

    private var inlineView: some View {
        let alerts = entry.data.unresolvedAlerts
        if alerts > 0 {
            return Text("\(alerts) alert\(alerts == 1 ? "" : "s") • CLI Pulse")
        }
        let topProvider = entry.data.providers.first
        let remaining = topProvider.map { Int(max(0, 1.0 - $0.usagePercent) * 100) } ?? 100
        let name = topProvider?.name ?? "Quota"
        return Text("\(name) \(remaining)% left")
    }
}
