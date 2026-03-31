import SwiftUI
import CLIPulseCore

struct iOSSessionsTab: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSession: SessionRecord?

    private var isIPad: Bool { horizontalSizeClass == .regular }

    var body: some View {
        if isIPad {
            iPadSessionsView
        } else {
            iPhoneSessionsView
        }
    }

    // MARK: - iPad: Master-Detail

    private var iPadSessionsView: some View {
        NavigationSplitView {
            sessionList
                .navigationTitle(L10n.tab.sessions)
        } detail: {
            if let session = selectedSession {
                SessionDetailView(session: session, showCost: state.showCost)
            } else {
                ContentUnavailableView {
                    Label(L10n.sessions.select, systemImage: "terminal")
                } description: {
                    Text(L10n.sessions.selectHint)
                }
            }
        }
        .refreshable {
            await state.refreshAll()
        }
    }

    // MARK: - iPhone: List

    private var iPhoneSessionsView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if state.sessions.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.sessions.noSessions, systemImage: "terminal")
                        } description: {
                            Text(L10n.sessions.emptyHint)
                        }
                        .padding(.vertical, 40)
                    } else {
                        ForEach(state.sessions) { session in
                            NavigationLink(value: session) {
                                iOSSessionRow(session: session, showCost: state.showCost)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.tab.sessions)
            .navigationDestination(for: SessionRecord.self) { session in
                SessionDetailView(session: session, showCost: state.showCost)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    let running = state.sessions.filter { $0.status.caseInsensitiveCompare("running") == .orderedSame }.count
                    if running > 0 {
                        StatusBadge(text: L10n.sessions.countRunning(running), color: .green)
                    }
                }
            }
            .refreshable {
                await state.refreshAll()
            }
        }
    }

    private var sessionList: some View {
        List(state.sessions, selection: $selectedSession) { session in
            HStack(spacing: 10) {
                Image(systemName: session.providerKind?.iconName ?? "terminal")
                    .foregroundStyle(PulseTheme.providerColor(session.provider))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(session.provider)
                            .font(.caption2)
                        Text(session.project)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(
                    text: L10n.status.localized(session.status),
                    color: PulseTheme.statusColor(session.status)
                )
            }
            .padding(.vertical, 2)
            .tag(session)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let running = state.sessions.filter { $0.status.caseInsensitiveCompare("running") == .orderedSame }.count
                if running > 0 {
                    StatusBadge(text: L10n.sessions.countRunning(running), color: .green)
                }
            }
        }
    }
}

// MARK: - Session Detail View (iPad)

struct SessionDetailView: View {
    let session: SessionRecord
    let showCost: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: session.providerKind?.iconName ?? "terminal")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PulseTheme.providerColor(session.provider))
                        .frame(width: 48, height: 48)
                        .background(PulseTheme.providerColor(session.provider).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name)
                            .font(.title3.weight(.bold))
                        HStack(spacing: 6) {
                            StatusBadge(
                                text: session.status,
                                color: PulseTheme.statusColor(session.status)
                            )
                            if let conf = session.collection_confidence {
                                ConfidenceBadge(confidence: conf)
                            }
                            CostStatusBadge(status: session.cost_status)
                        }
                    }
                    Spacer()
                }

                // Info grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 16) {
                    detailItem(label: L10n.detail.provider, value: session.provider, icon: "cpu")
                    detailItem(label: L10n.detail.project, value: session.project, icon: "folder")
                    detailItem(label: L10n.detail.device, value: session.device_name, icon: "desktopcomputer")
                    detailItem(label: L10n.detail.started, value: RelativeTime.format(session.started_at), icon: "clock")
                }

                Divider()

                // Metrics
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 16) {
                    metricBox(title: L10n.detail.usage, value: CostFormatter.formatUsage(session.total_usage))
                    if showCost {
                        metricBox(title: L10n.detail.cost, value: CostFormatter.format(session.estimated_cost), color: .green)
                    }
                    metricBox(title: L10n.detail.requests, value: "\(session.requests)")
                    if session.error_count > 0 {
                        metricBox(title: L10n.detail.errors, value: "\(session.error_count)", color: .red)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
    }

    private func metricBox(title: String, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Session Row (iPhone)

struct iOSSessionRow: View {
    let session: SessionRecord
    let showCost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: session.providerKind?.iconName ?? "terminal")
                    .foregroundStyle(PulseTheme.providerColor(session.provider))

                Text(session.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                StatusBadge(
                    text: L10n.status.localized(session.status),
                    color: PulseTheme.statusColor(session.status)
                )
            }

            HStack(spacing: 14) {
                Label(session.provider, systemImage: "cpu")
                Label(session.project, systemImage: "folder")
                if let conf = session.collection_confidence {
                    ConfidenceBadge(confidence: conf)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 18) {
                metricItem(label: L10n.detail.usage, value: CostFormatter.formatUsage(session.total_usage))
                if showCost {
                    metricItem(label: L10n.detail.cost, value: CostFormatter.format(session.estimated_cost), color: .green)
                }
                metricItem(label: L10n.detail.requests, value: "\(session.requests)")
                if session.error_count > 0 {
                    metricItem(label: L10n.detail.errors, value: "\(session.error_count)", color: .red)
                }
                Spacer()
                Text(RelativeTime.format(session.started_at))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    session.status.caseInsensitiveCompare("failed") == .orderedSame ? Color.red.opacity(0.3) :
                    PulseTheme.providerColor(session.provider).opacity(0.15),
                    lineWidth: 1
                )
        )
    }

    private func metricItem(label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
