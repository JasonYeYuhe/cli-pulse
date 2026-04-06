import SwiftUI
import CLIPulseCore

struct WatchProvidersView: View {
    @EnvironmentObject var state: WatchAppState

    private var visibleProviders: [ProviderUsage] {
        state.providers.filter { state.enabledProviderNames.contains($0.provider) }
    }

    var body: some View {
        List {
            if visibleProviders.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text(L10n.providers.noData)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(visibleProviders) { provider in
                    NavigationLink {
                        WatchProviderDetailView(provider: provider, showCost: state.showCost)
                    } label: {
                        WatchProviderCard(provider: provider, showCost: state.showCost)
                    }
                }
            }
        }
        .navigationTitle(L10n.tab.providers)
        .refreshable {
            await state.refreshAll()
        }
    }
}

// MARK: - Provider Card with Progress Ring

struct WatchProviderCard: View {
    let provider: ProviderUsage
    let showCost: Bool

    private var providerColor: Color {
        PulseTheme.providerColor(provider.provider)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(providerColor.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: provider.usagePercent)
                    .stroke(
                        ringGradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: provider.providerKind?.iconName ?? "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(providerColor)
            }
            .frame(width: 36, height: 36)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.provider)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(CostFormatter.formatUsage(provider.today_usage))
                        .font(.caption2.weight(.bold).monospacedDigit())
                    if let quota = provider.quota {
                        Text("/ \(CostFormatter.formatUsage(quota))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    if provider.usagePercent > 0 {
                        Text("\(Int(provider.usagePercent * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(percentColor)
                    }
                    if showCost && provider.estimated_cost_today > 0 {
                        Text(CostFormatter.format(provider.estimated_cost_today))
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var percentColor: Color {
        if provider.usagePercent > 0.9 { return .red }
        if provider.usagePercent > 0.7 { return .orange }
        return providerColor
    }

    private var ringGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [providerColor, ringEndColor]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * provider.usagePercent)
        )
    }

    private var ringEndColor: Color {
        if provider.usagePercent > 0.9 { return .red }
        if provider.usagePercent > 0.7 { return .orange }
        return providerColor
    }
}

// MARK: - Provider Detail

struct WatchProviderDetailView: View {
    let provider: ProviderUsage
    let showCost: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: provider.providerKind?.iconName ?? "cpu")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PulseTheme.providerColor(provider.provider))
                    Text(provider.provider)
                        .font(.headline)
                }
            }

            // Gauge section
            if provider.quota != nil {
                Section(L10n.providers.quota) {
                    Gauge(value: provider.usagePercent) {
                        Text(provider.provider)
                    } currentValueLabel: {
                        Text("\(Int(provider.usagePercent * 100))%")
                            .font(.caption.weight(.bold))
                    } minimumValueLabel: {
                        Text("0")
                            .font(.system(size: 8))
                    } maximumValueLabel: {
                        Text("100")
                            .font(.system(size: 8))
                    }
                    .gaugeStyle(.linearCapacity)
                    .tint(provider.usagePercent > 0.9 ? .red : provider.usagePercent > 0.7 ? .orange : PulseTheme.providerColor(provider.provider))
                }
            }

            Section(L10n.dashboard.today) {
                WatchMetricRow(
                    label: L10n.widget.usageTitle,
                    value: CostFormatter.formatUsage(provider.today_usage),
                    icon: "chart.bar.fill"
                )
                if showCost {
                    WatchMetricRow(
                        label: L10n.dashboard.costToday,
                        value: CostFormatter.format(provider.estimated_cost_today),
                        icon: "dollarsign.circle",
                        valueColor: .green
                    )
                }
                if let quota = provider.quota {
                    WatchMetricRow(
                        label: L10n.providers.quota,
                        value: CostFormatter.formatUsage(quota),
                        icon: "gauge.with.needle"
                    )
                }
                if let remaining = provider.remaining {
                    WatchMetricRow(
                        label: "Remaining",
                        value: CostFormatter.formatUsage(remaining),
                        icon: "hourglass",
                        valueColor: remaining < (provider.quota ?? Int.max) / 5 ? .red : .primary
                    )
                }
            }

            Section(L10n.providers.thisWeek) {
                WatchMetricRow(
                    label: L10n.widget.usageTitle,
                    value: CostFormatter.formatUsage(provider.week_usage),
                    icon: "calendar"
                )
                if showCost {
                    WatchMetricRow(
                        label: L10n.dashboard.costToday,
                        value: CostFormatter.format(provider.estimated_cost_week),
                        icon: "dollarsign.circle",
                        valueColor: .green
                    )
                }
            }

            Section(L10n.dashboard.activity) {
                WatchMetricRow(
                    label: L10n.tab.sessions,
                    value: "\(provider.recent_sessions.count)",
                    icon: "terminal"
                )
                if !provider.recent_errors.isEmpty {
                    WatchMetricRow(
                        label: "Errors",
                        value: "\(provider.recent_errors.count)",
                        icon: "exclamationmark.triangle",
                        valueColor: .red
                    )
                }
                if !provider.status_text.isEmpty {
                    HStack {
                        Text(L10n.providers.status)
                            .font(.caption)
                        Spacer()
                        Text(provider.status_text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(provider.provider)
    }
}
