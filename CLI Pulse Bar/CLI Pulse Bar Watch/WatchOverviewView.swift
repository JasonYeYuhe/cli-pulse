import SwiftUI
import CLIPulseCore

struct WatchOverviewView: View {
    @EnvironmentObject var state: WatchAppState

    var body: some View {
        List {
            if let dash = state.dashboard {
                // Server status
                Section {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.serverOnline ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(state.serverOnline ? L10n.dashboard.serverOnline : L10n.dashboard.serverOffline)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(state.serverOnline ? .green : .red)
                        Spacer()
                        if let last = state.lastRefresh {
                            Text(last, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Key metrics row
                Section(L10n.dashboard.today) {
                    HStack(spacing: 0) {
                        WatchCompactMetric(
                            icon: "chart.bar.fill",
                            value: CostFormatter.formatUsage(dash.total_usage_today),
                            label: L10n.widget.usageTitle,
                            color: PulseTheme.accent
                        )
                        Spacer()
                        WatchCompactMetric(
                            icon: "terminal",
                            value: "\(dash.active_sessions)",
                            label: L10n.tab.sessions,
                            color: .blue
                        )
                        Spacer()
                        WatchCompactMetric(
                            icon: "desktopcomputer",
                            value: "\(dash.online_devices)",
                            label: L10n.dashboard.onlineDevices,
                            color: .cyan
                        )
                    }

                    if state.showCost {
                        HStack {
                            Image(systemName: "dollarsign.circle")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(L10n.dashboard.costToday)
                                .font(.caption)
                            Spacer()
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(CostFormatter.format(dash.total_estimated_cost_today))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.green)
                                if state.costSummary.todayTokens > 0 {
                                    Text("· \(TokenFormatter.format(state.costSummary.todayTokens))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }

                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(L10n.dashboard.requests)
                            .font(.caption)
                        Spacer()
                        Text("\(dash.total_requests_today)")
                            .font(.caption.weight(.bold).monospacedDigit())
                    }

                    if dash.unresolved_alerts > 0 {
                        HStack {
                            Image(systemName: "bell.badge")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text(L10n.tab.alerts)
                                .font(.caption)
                            Spacer()
                            Text("\(dash.unresolved_alerts)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Provider gauges
                let topProviders = dash.provider_breakdown
                    .filter { state.enabledProviderNames.contains($0.provider) }
                    .prefix(4)

                if !topProviders.isEmpty {
                    Section(L10n.providers.quota) {
                        ForEach(Array(topProviders), id: \.provider) { p in
                            WatchProviderGauge(breakdown: p, showCost: state.showCost)
                        }
                    }
                }

                // Top projects
                if !dash.top_projects.isEmpty {
                    Section(L10n.dashboard.topProjects) {
                        ForEach(Array(dash.top_projects.prefix(3))) { proj in
                            HStack {
                                Image(systemName: "folder")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(proj.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(CostFormatter.formatUsage(proj.usage))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                            }
                        }
                    }
                }

                // Risk signals
                if !dash.risk_signals.isEmpty {
                    Section(L10n.dashboard.riskSignals) {
                        ForEach(dash.risk_signals, id: \.self) { signal in
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(signal)
                                    .font(.caption2)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } else if state.isLoading {
                ProgressView("Loading...")
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Pull to refresh")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .navigationTitle(L10n.tab.overview)
        .refreshable {
            await state.refreshAll()
        }
    }
}

// MARK: - Compact Metric

struct WatchCompactMetric: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Provider Gauge

struct WatchProviderGauge: View {
    let breakdown: ProviderBreakdown
    let showCost: Bool

    private var usagePercent: Double {
        guard let remaining = breakdown.remaining else { return 0 }
        let total = breakdown.usage + remaining
        guard total > 0 else { return 0 }
        return min(1.0, Double(breakdown.usage) / Double(total))
    }

    private var hasQuota: Bool {
        breakdown.remaining != nil
    }

    private var gaugeColor: Color {
        PulseTheme.providerColor(breakdown.provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: ProviderKind(rawValue: breakdown.provider)?.iconName ?? "cpu")
                    .font(.caption2)
                    .foregroundStyle(gaugeColor)
                    .frame(width: 14)
                Text(breakdown.provider)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if showCost && breakdown.estimated_cost > 0 {
                    Text(CostFormatter.format(breakdown.estimated_cost))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }

            if hasQuota {
                Gauge(value: usagePercent) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(usagePercent * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.linearCapacity)
                .tint(gaugeGradient)
            }

            HStack {
                Text(CostFormatter.formatUsage(breakdown.usage))
                    .font(.caption2.weight(.bold).monospacedDigit())
                if let remaining = breakdown.remaining {
                    Text("/ \(CostFormatter.formatUsage(breakdown.usage + remaining))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var gaugeGradient: Gradient {
        if usagePercent > 0.9 {
            return Gradient(colors: [.red, .red])
        } else if usagePercent > 0.7 {
            return Gradient(colors: [gaugeColor, .orange])
        } else {
            return Gradient(colors: [gaugeColor, gaugeColor])
        }
    }
}

// MARK: - Metric Row

struct WatchMetricRow: View {
    let label: String
    let value: String
    let icon: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(valueColor)
        }
    }
}
