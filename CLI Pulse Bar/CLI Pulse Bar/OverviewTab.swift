import SwiftUI
import CLIPulseCore

struct OverviewTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.dashboard.title)
                            .font(.system(size: 14, weight: .bold))
                        if let lastRefresh = state.lastRefresh {
                            Text(L10n.dashboard.updated(RelativeTime.format(ISO8601DateFormatter().string(from: lastRefresh))))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    serverStatus
                    refreshButton
                }

                // Metric Grid
                if let dash = state.dashboard {
                    metricsGrid(dash)

                    // Activity timeline sparkline
                    if !dash.trend.isEmpty {
                        activityTimeline(dash.trend)
                    }

                    // Cost summary
                    if state.showCost {
                        costSection
                    }

                    providerBreakdown(dash)
                    topProjects(dash)
                    riskSignals(dash)
                } else if state.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                } else {
                    EmptyStateView(
                        icon: "chart.bar.xaxis",
                        title: L10n.dashboard.noData,
                        subtitle: L10n.dashboard.connectHelper
                    )
                }
            }
            .padding(12)
        }
    }

    // MARK: - Server Status

    private var serverStatus: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state.serverOnline ? .green : .red)
                .frame(width: 6, height: 6)
            Text(state.serverOnline ? L10n.common.online : L10n.common.offline)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await state.refreshAll() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .disabled(state.isLoading)
    }

    // MARK: - Metrics Grid

    private func metricsGrid(_ dash: DashboardSummary) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ], spacing: 6) {
            MetricCard(
                title: L10n.dashboard.usageToday,
                value: CostFormatter.formatUsage(dash.total_usage_today),
                icon: "chart.bar.fill",
                color: PulseTheme.accent
            )
            MetricCard(
                title: L10n.dashboard.estCost,
                value: CostFormatter.format(dash.total_estimated_cost_today),
                subtitle: dash.cost_status,
                icon: "dollarsign.circle",
                color: .green
            )
            MetricCard(
                title: L10n.dashboard.requests,
                value: "\(dash.total_requests_today)",
                icon: "arrow.up.arrow.down",
                color: .purple
            )
            MetricCard(
                title: L10n.tab.sessions,
                value: "\(dash.active_sessions)",
                icon: "terminal",
                color: .cyan
            )
            MetricCard(
                title: L10n.dashboard.onlineDevices,
                value: "\(dash.online_devices)",
                icon: "desktopcomputer",
                color: .blue
            )
            MetricCard(
                title: L10n.dashboard.unresolvedAlerts,
                value: "\(dash.unresolved_alerts)",
                icon: "bell.badge",
                color: dash.unresolved_alerts > 0 ? .orange : .gray
            )
        }
    }

    // MARK: - Cost Section

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.dashboard.costSummary, icon: "dollarsign.circle")

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.dashboard.today)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(CostFormatter.format(state.costSummary.todayTotal))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.dashboard.thirtyDayEst)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(CostFormatter.format(state.costSummary.thirtyDayTotal))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
                Spacer()
            }

            // Per-provider breakdown
            if !state.costSummary.todayByProvider.isEmpty {
                ForEach(state.costSummary.todayByProvider.sorted(by: { $0.cost > $1.cost }).prefix(5), id: \.provider) { item in
                    HStack {
                        Circle()
                            .fill(PulseTheme.providerColor(item.provider))
                            .frame(width: 6, height: 6)
                        Text(item.provider)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CostFormatter.format(item.cost))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(10)
        .background(PulseTheme.cardBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Provider Breakdown

    private func providerBreakdown(_ dash: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.dashboard.providerUsage, icon: "cpu")

            let enabledProviders = dash.provider_breakdown.filter { p in
                state.enabledProviderNames.contains(p.provider)
            }

            ForEach(enabledProviders) { provider in
                let maxUsage = enabledProviders.map(\.usage).max() ?? 1
                let fraction = maxUsage > 0 ? Double(provider.usage) / Double(maxUsage) : 0

                UsageBar(
                    label: provider.provider,
                    value: fraction,
                    color: PulseTheme.providerColor(provider.provider),
                    detail: "\(CostFormatter.formatUsage(provider.usage)) · \(CostFormatter.format(provider.estimated_cost))"
                )
            }

            if enabledProviders.isEmpty {
                Text("No enabled providers with data")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(PulseTheme.cardBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Top Projects

    private func topProjects(_ dash: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: L10n.dashboard.topProjects, icon: "folder")

            if dash.top_projects.isEmpty {
                Text(L10n.dashboard.noProjects)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(dash.top_projects) { project in
                    HStack {
                        Text(project.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(CostFormatter.formatUsage(project.usage))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(CostFormatter.format(project.estimated_cost))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 2)
                    if project.id != dash.top_projects.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(10)
        .background(PulseTheme.cardBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Activity Timeline

    private func activityTimeline(_ trend: [UsagePoint]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: L10n.dashboard.activity, icon: "chart.bar.fill")

            let maxValue = trend.map(\.value).max() ?? 1
            let barCount = trend.count

            GeometryReader { geometry in
                let spacing: CGFloat = 1
                let totalSpacing = spacing * CGFloat(max(barCount - 1, 0))
                let barWidth = barCount > 0 ? (geometry.size.width - totalSpacing) / CGFloat(barCount) : 0

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(trend.enumerated()), id: \.element.id) { _, point in
                        let fraction = maxValue > 0 ? CGFloat(point.value) / CGFloat(maxValue) : 0
                        RoundedRectangle(cornerRadius: 1)
                            .fill(PulseTheme.accent.opacity(0.4 + 0.6 * fraction))
                            .frame(width: max(barWidth, 1), height: max(fraction * geometry.size.height, 1))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 40)

            // Hour labels
            if trend.count >= 2 {
                HStack {
                    Text(hourLabel(trend.first?.timestamp ?? ""))
                        .font(.system(size: 7))
                        .foregroundStyle(.quaternary)
                    Spacer()
                    if trend.count > 2 {
                        Text(hourLabel(trend[trend.count / 2].timestamp))
                            .font(.system(size: 7))
                            .foregroundStyle(.quaternary)
                        Spacer()
                    }
                    Text(hourLabel(trend.last?.timestamp ?? ""))
                        .font(.system(size: 7))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(10)
        .background(PulseTheme.cardBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func hourLabel(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            let hf = DateFormatter()
            hf.dateFormat = "ha"
            return hf.string(from: date).lowercased()
        }
        // Fallback: try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            let hf = DateFormatter()
            hf.dateFormat = "ha"
            return hf.string(from: date).lowercased()
        }
        // Last resort: try to extract hour from the timestamp string
        if timestamp.count >= 13 {
            let hourStart = timestamp.index(timestamp.startIndex, offsetBy: 11)
            let hourEnd = timestamp.index(hourStart, offsetBy: 2)
            return String(timestamp[hourStart..<hourEnd]) + "h"
        }
        return timestamp
    }

    // MARK: - Risk Signals

    @ViewBuilder
    private func riskSignals(_ dash: DashboardSummary) -> some View {
        if !dash.risk_signals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: L10n.dashboard.riskSignals, icon: "exclamationmark.shield")

                ForEach(dash.risk_signals, id: \.self) { signal in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text(signal)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
