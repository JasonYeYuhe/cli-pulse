import SwiftUI
import CLIPulseCore

struct SessionsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.sessions.title)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    let running = state.sessions.filter { $0.status.caseInsensitiveCompare("running") == .orderedSame }.count
                    if running > 0 {
                        StatusBadge(text: "\(running) \(L10n.sessions.running)", color: .green)
                    }
                }

                if state.sessions.isEmpty {
                    EmptyStateView(
                        icon: "terminal",
                        title: L10n.sessions.noSessions,
                        subtitle: L10n.sessions.emptyHint
                    )
                } else {
                    ForEach(state.sessions) { session in
                        SessionRow(session: session, showCost: state.showCost)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: SessionRecord
    let showCost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: session.providerKind?.iconName ?? "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(PulseTheme.providerColor(session.provider))

                Text(session.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                StatusBadge(
                    text: session.status,
                    color: PulseTheme.statusColor(session.status)
                )
            }

            // Details
            HStack(spacing: 12) {
                Label(session.provider, systemImage: "cpu")
                Label(session.project, systemImage: "folder")
                Label(session.device_name, systemImage: "desktopcomputer")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            // Metrics
            HStack(spacing: 16) {
                metricItem(label: "Usage", value: CostFormatter.formatUsage(session.total_usage))
                if showCost {
                    metricItem(label: "Cost", value: CostFormatter.format(session.estimated_cost), color: .green)
                }
                metricItem(label: "Requests", value: "\(session.requests)")
                if session.error_count > 0 {
                    metricItem(label: "Errors", value: "\(session.error_count)", color: .red)
                }
                Spacer()
                Text(RelativeTime.format(session.started_at))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(PulseTheme.cardBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    session.status.caseInsensitiveCompare("failed") == .orderedSame ? Color.red.opacity(0.3) :
                    PulseTheme.providerColor(session.provider).opacity(0.15),
                    lineWidth: 1
                )
        )
    }

    private func metricItem(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
