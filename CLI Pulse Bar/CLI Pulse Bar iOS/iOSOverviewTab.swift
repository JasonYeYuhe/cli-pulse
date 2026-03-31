import SwiftUI
import CLIPulseCore

struct iOSOverviewTab: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Server status
                    HStack {
                        Circle()
                            .fill(state.serverOnline ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(state.serverOnline ? L10n.dashboard.serverOnline : L10n.dashboard.serverOffline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let lastRefresh = state.lastRefresh {
                            Text(L10n.dashboard.updated(RelativeTime.format(ISO8601DateFormatter().string(from: lastRefresh))))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal)

                    if let dash = state.dashboard {
                        metricsGrid(dash)

                        // Activity timeline sparkline
                        if !dash.trend.isEmpty {
                            activityTimeline(dash.trend)
                        }

                        if state.showCost {
                            costSection
                        }

                        providerBreakdown(dash)
                        topProjects(dash)
                        riskSignals(dash)
                    } else if state.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        ContentUnavailableView {
                            Label(L10n.dashboard.noData, systemImage: "chart.bar.xaxis")
                        } description: {
                            Text(L10n.dashboard.connectHelper)
                        }
                        .padding(.vertical, 40)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.dashboard.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await state.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(state.isLoading)
                }
            }
            .refreshable {
                await state.refreshAll()
            }
        }
    }

    // MARK: - Metrics Grid

    private func metricsGrid(_ dash: DashboardSummary) -> some View {
        let columns = isIPad ? [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ] : [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            iOSMetricCard(title: L10n.dashboard.usageToday, value: CostFormatter.formatUsage(dash.total_usage_today), icon: "chart.bar.fill", color: PulseTheme.accent)
            iOSMetricCard(title: L10n.dashboard.estCost, value: CostFormatter.format(dash.total_estimated_cost_today), icon: "dollarsign.circle", color: .green, badge: dash.cost_status)
            iOSMetricCard(title: L10n.dashboard.requests, value: "\(dash.total_requests_today)", icon: "arrow.up.arrow.down", color: .purple)
            iOSMetricCard(title: L10n.tab.sessions, value: "\(dash.active_sessions)", icon: "terminal", color: .cyan)
            iOSMetricCard(title: L10n.dashboard.onlineDevices, value: "\(dash.online_devices)", icon: "desktopcomputer", color: .blue)
            iOSMetricCard(title: L10n.tab.alerts, value: "\(dash.unresolved_alerts)", icon: "bell.badge", color: dash.unresolved_alerts > 0 ? .orange : .gray)
        }
        .padding(.horizontal)
    }

    // MARK: - Cost Section

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Text(L10n.dashboard.costSummary)
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.dashboard.today)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(CostFormatter.format(state.costSummary.todayTotal))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.dashboard.thirtyDayEst)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(CostFormatter.format(state.costSummary.thirtyDayTotal))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.green)
                }
                Spacer()
            }

            ForEach(state.costSummary.todayByProvider.sorted(by: { $0.cost > $1.cost }).prefix(5), id: \.provider) { item in
                HStack {
                    Circle()
                        .fill(PulseTheme.providerColor(item.provider))
                        .frame(width: 8, height: 8)
                    Text(item.provider)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(CostFormatter.format(item.cost))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Provider Breakdown

    private func providerBreakdown(_ dash: DashboardSummary) -> some View {
        let enabledProviders = dash.provider_breakdown.filter { p in
            state.enabledProviderNames.contains(p.provider)
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PulseTheme.accent)
                Text(L10n.dashboard.providerUsage)
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(enabledProviders) { provider in
                let maxUsage = enabledProviders.map(\.usage).max() ?? 1
                let fraction = maxUsage > 0 ? Double(provider.usage) / Double(maxUsage) : 0

                UsageBar(
                    label: provider.provider,
                    value: fraction,
                    color: PulseTheme.providerColor(provider.provider),
                    detail: "\(CostFormatter.formatUsage(provider.usage)) \u{00B7} \(CostFormatter.format(provider.estimated_cost))"
                )
            }
        }
        .padding()
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Top Projects

    private func topProjects(_ dash: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PulseTheme.accent)
                Text(L10n.dashboard.topProjects)
                    .font(.subheadline.weight(.semibold))
            }

            if dash.top_projects.isEmpty {
                Text(L10n.dashboard.noProjects)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(dash.top_projects) { project in
                    HStack {
                        Text(project.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(CostFormatter.formatUsage(project.usage))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(CostFormatter.format(project.estimated_cost))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 2)
                    if project.id != dash.top_projects.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Risk Signals

    @ViewBuilder
    private func riskSignals(_ dash: DashboardSummary) -> some View {
        if !dash.risk_signals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(L10n.dashboard.riskSignals)
                        .font(.subheadline.weight(.semibold))
                }

                ForEach(dash.risk_signals, id: \.self) { signal in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(signal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.orange.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    // MARK: - Activity Timeline

    private func activityTimeline(_ trend: [UsagePoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PulseTheme.accent)
                Text(L10n.dashboard.activity)
                    .font(.subheadline.weight(.semibold))
            }

            let maxValue = trend.map(\.value).max() ?? 1
            let barCount = trend.count

            GeometryReader { geometry in
                let spacing: CGFloat = 2
                let totalSpacing = spacing * CGFloat(max(barCount - 1, 0))
                let barWidth = barCount > 0 ? (geometry.size.width - totalSpacing) / CGFloat(barCount) : 0

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(trend.enumerated()), id: \.element.id) { _, point in
                        let fraction = maxValue > 0 ? CGFloat(point.value) / CGFloat(maxValue) : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PulseTheme.accent.opacity(0.4 + 0.6 * fraction))
                            .frame(width: max(barWidth, 1), height: max(fraction * geometry.size.height, 2))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 60)

            // Hour labels
            if trend.count >= 2 {
                HStack {
                    Text(hourLabel(trend.first?.timestamp ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Spacer()
                    if trend.count > 2 {
                        Text(hourLabel(trend[trend.count / 2].timestamp))
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Spacer()
                    }
                    Text(hourLabel(trend.last?.timestamp ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding()
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func hourLabel(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            let hf = DateFormatter()
            hf.dateFormat = "ha"
            return hf.string(from: date).lowercased()
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            let hf = DateFormatter()
            hf.dateFormat = "ha"
            return hf.string(from: date).lowercased()
        }
        if timestamp.count >= 13 {
            let hourStart = timestamp.index(timestamp.startIndex, offsetBy: 11)
            let hourEnd = timestamp.index(hourStart, offsetBy: 2)
            return String(timestamp[hourStart..<hourEnd]) + "h"
        }
        return timestamp
    }
}

// MARK: - iOS Metric Card

struct iOSMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                if let badge {
                    CostStatusBadge(status: badge)
                }
            }
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
