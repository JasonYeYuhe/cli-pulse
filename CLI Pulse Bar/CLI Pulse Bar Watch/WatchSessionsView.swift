import SwiftUI
import CLIPulseCore

struct WatchSessionsView: View {
    @EnvironmentObject var state: WatchAppState

    private var runningSessions: [SessionRecord] {
        state.sessions.filter { $0.status.caseInsensitiveCompare("running") == .orderedSame }
    }

    private var otherSessions: [SessionRecord] {
        state.sessions.filter { $0.status.caseInsensitiveCompare("running") != .orderedSame }
    }

    var body: some View {
        List {
            if state.sessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text(L10n.sessions.noSessions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                // Running sessions featured
                if !runningSessions.isEmpty {
                    Section {
                        ForEach(runningSessions) { session in
                            NavigationLink {
                                WatchSessionDetailView(session: session, showCost: state.showCost)
                            } label: {
                                WatchRunningSessionRow(session: session, showCost: state.showCost)
                            }
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("\(runningSessions.count) \(L10n.sessions.running)")
                        }
                    }
                }

                // Other sessions
                if !otherSessions.isEmpty {
                    Section("Other") {
                        ForEach(otherSessions) { session in
                            NavigationLink {
                                WatchSessionDetailView(session: session, showCost: state.showCost)
                            } label: {
                                WatchSessionRow(session: session, showCost: state.showCost)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tab.sessions)
        .refreshable {
            await state.refreshAll()
        }
    }
}

// MARK: - Running Session Row (featured)

struct WatchRunningSessionRow: View {
    let session: SessionRecord
    let showCost: Bool

    private var providerColor: Color {
        PulseTheme.providerColor(session.provider)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Provider icon with live indicator
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: session.providerKind?.iconName ?? "terminal")
                    .font(.caption)
                    .foregroundStyle(providerColor)
                    .frame(width: 24, height: 24)
                    .background(providerColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().stroke(Color.black, lineWidth: 1.5)
                    )
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.project)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(session.provider)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(sessionDuration)
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(providerColor)
                }

                HStack(spacing: 4) {
                    Text(CostFormatter.formatUsage(session.total_usage))
                        .font(.caption2.weight(.bold).monospacedDigit())
                    if showCost && session.estimated_cost > 0 {
                        Text(CostFormatter.format(session.estimated_cost))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var sessionDuration: String {
        RelativeTime.format(session.started_at)
    }
}

// MARK: - Session Row (compact)

struct WatchSessionRow: View {
    let session: SessionRecord
    let showCost: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.providerKind?.iconName ?? "terminal")
                .font(.caption2)
                .foregroundStyle(PulseTheme.providerColor(session.provider))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.project)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    StatusBadge(
                        text: session.status,
                        color: PulseTheme.statusColor(session.status)
                    )
                    .scaleEffect(0.8, anchor: .leading)
                    Text(CostFormatter.formatUsage(session.total_usage))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
    }
}

// MARK: - Session Detail

struct WatchSessionDetailView: View {
    let session: SessionRecord
    let showCost: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: session.providerKind?.iconName ?? "terminal")
                        .foregroundStyle(PulseTheme.providerColor(session.provider))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.caption.weight(.bold))
                            .lineLimit(2)
                        StatusBadge(
                            text: session.status,
                            color: PulseTheme.statusColor(session.status)
                        )
                        .scaleEffect(0.85)
                    }
                }
            }

            Section(L10n.sessions.details) {
                WatchMetricRow(label: L10n.tab.providers, value: session.provider, icon: "cpu")
                WatchMetricRow(label: L10n.dashboard.topProjects, value: session.project, icon: "folder")
                WatchMetricRow(label: L10n.dashboard.onlineDevices, value: session.device_name, icon: "desktopcomputer")
                WatchMetricRow(label: L10n.alerts.created, value: RelativeTime.format(session.started_at), icon: "clock")
            }

            Section(L10n.dashboard.quickStats) {
                WatchMetricRow(
                    label: L10n.widget.usageTitle,
                    value: CostFormatter.formatUsage(session.total_usage),
                    icon: "chart.bar.fill"
                )
                if showCost {
                    WatchMetricRow(
                        label: L10n.dashboard.costToday,
                        value: CostFormatter.format(session.estimated_cost),
                        icon: "dollarsign.circle",
                        valueColor: .green
                    )
                }
                WatchMetricRow(
                    label: L10n.dashboard.requests,
                    value: "\(session.requests)",
                    icon: "arrow.up.arrow.down"
                )
                if session.error_count > 0 {
                    WatchMetricRow(
                        label: "Errors",
                        value: "\(session.error_count)",
                        icon: "exclamationmark.triangle",
                        valueColor: .red
                    )
                }
            }
        }
        .navigationTitle(session.name)
    }
}
