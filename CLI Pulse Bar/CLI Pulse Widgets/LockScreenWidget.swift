import WidgetKit
import SwiftUI
import CLIPulseCore

// MARK: - Lock Screen Widget (iOS 17+)

@available(iOSApplicationExtension 17.0, *)
struct UsageLockScreenWidget: Widget {
    let kind = "UsageLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CLIPulseTimelineProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.widget.usageTitle)
        .description(L10n.widget.usageDescription)
        #if os(iOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

// MARK: - Lock Screen Views

@available(iOSApplicationExtension 17.0, *)
struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CLIPulseEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    // MARK: - Circular: Usage gauge

    private var circularView: some View {
        let topProvider = entry.data.providers.first
        let percent = topProvider?.usagePercent ?? 0

        return ZStack {
            AccessoryWidgetBackground()

            Gauge(value: min(percent, 1.0)) {
                Image(systemName: topProvider?.iconName ?? "waveform.path.ecg")
                    .font(.system(size: 10))
            } currentValueLabel: {
                Text("\(Int(percent * 100))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    // MARK: - Rectangular: Provider summary

    private var rectangularView: some View {
        let providers = Array(entry.data.providers.prefix(2))

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 8))
                Text(L10n.auth.title)
                    .font(.caption2.weight(.bold))
            }

            if providers.isEmpty {
                Text(L10n.widget.noData)
                    .font(.caption2)
            } else {
                ForEach(providers) { p in
                    HStack(spacing: 4) {
                        Text(p.name)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(p.usagePercent * 100))%")
                            .font(.caption2.weight(.bold).monospacedDigit())

                        Gauge(value: min(p.usagePercent, 1.0)) {
                            EmptyView()
                        }
                        .gaugeStyle(.accessoryLinear)
                        .frame(width: 40)
                    }
                }
            }
        }
    }

    // MARK: - Inline: Text summary

    private var inlineView: some View {
        let topProvider = entry.data.providers.first
        let percent = topProvider.map { Int($0.usagePercent * 100) } ?? 0
        let name = topProvider?.name ?? L10n.auth.title

        return Text("\(name) \(percent)% • \(entry.data.activeSessions) sessions")
    }
}

// MARK: - Preview

#if os(iOS)
@available(iOSApplicationExtension 17.0, *)
#Preview(as: .accessoryCircular) {
    UsageLockScreenWidget()
} timeline: {
    CLIPulseEntry(date: .now, data: .preview)
}

@available(iOSApplicationExtension 17.0, *)
#Preview(as: .accessoryRectangular) {
    UsageLockScreenWidget()
} timeline: {
    CLIPulseEntry(date: .now, data: .preview)
}
#endif
