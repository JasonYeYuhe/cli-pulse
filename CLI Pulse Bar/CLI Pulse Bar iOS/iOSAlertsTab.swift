import SwiftUI
import CLIPulseCore

struct iOSAlertsTab: View {
    @EnvironmentObject var state: AppState
    @State private var filter: AlertFilter = .open

    enum AlertFilter: String, CaseIterable {
        case open = "Open"
        case resolved = "Resolved"
        case all = "All"

        var label: String {
            switch self {
            case .open: return L10n.alerts.open
            case .resolved: return L10n.alerts.resolved
            case .all: return L10n.alerts.all
            }
        }
    }

    private var filteredAlerts: [AlertRecord] {
        switch filter {
        case .open: return state.alerts.filter { !$0.is_resolved }
        case .resolved: return state.alerts.filter { $0.is_resolved }
        case .all: return state.alerts
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Summary badges
                    alertSummary
                        .padding(.horizontal)

                    // Filter
                    Picker(L10n.alerts.filter, selection: $filter) {
                        ForEach(AlertFilter.allCases, id: \.self) { f in
                            Text(f.label)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Alert List
                    if filteredAlerts.isEmpty {
                        ContentUnavailableView {
                            Label(
                                filter == .open ? L10n.alerts.allClear : L10n.alerts.noAlerts,
                                systemImage: filter == .open ? "checkmark.shield" : "bell.slash"
                            )
                        } description: {
                            Text(filter == .open ? L10n.alerts.noUnresolved : L10n.alerts.noMatching)
                        }
                        .padding(.vertical, 40)
                    } else {
                        ForEach(filteredAlerts) { alert in
                            iOSAlertRow(alert: alert) {
                                await state.acknowledgeAlert(alert)
                            } onResolve: {
                                await state.resolveAlert(alert)
                            } onSnooze: { minutes in
                                await state.snoozeAlert(alert, minutes: minutes)
                            } onNavigate: { tab in
                                state.selectedTab = tab
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.tab.alerts)
            .refreshable {
                await state.refreshAll()
            }
        }
    }

    @ViewBuilder
    private var alertSummary: some View {
        let open = state.alerts.filter { !$0.is_resolved }
        let critical = open.filter { $0.severity == "Critical" }.count
        let warning = open.filter { $0.severity == "Warning" }.count

        if critical > 0 || warning > 0 {
            HStack(spacing: 8) {
                if critical > 0 {
                    StatusBadge(text: "\(critical) \(L10n.alerts.severityCritical)", color: .red)
                }
                if warning > 0 {
                    StatusBadge(text: "\(warning) \(L10n.alerts.severityWarning)", color: .orange)
                }
                Spacer()
            }
        }
    }
}

struct iOSAlertRow: View {
    let alert: AlertRecord
    let onAcknowledge: () async -> Void
    let onResolve: () async -> Void
    let onSnooze: (Int) async -> Void
    var onNavigate: ((AppState.Tab) -> Void)? = nil

    @State private var showSnooze = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                SeverityDot(severity: alert.severity)
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Text(RelativeTime.format(alert.created_at))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Message
            Text(alert.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // Related entity chips (tappable for deep link navigation)
            FlowLayout(spacing: 4) {
                if let provider = alert.related_provider {
                    Button { onNavigate?(.providers) } label: {
                        chipView(icon: "cpu", text: provider, tappable: onNavigate != nil)
                    }
                    .buttonStyle(.plain)
                }
                if let project = alert.related_project_name {
                    chipView(icon: "folder", text: project)
                }
                if let session = alert.related_session_name {
                    Button { onNavigate?(.sessions) } label: {
                        chipView(icon: "terminal", text: session, tappable: onNavigate != nil)
                    }
                    .buttonStyle(.plain)
                }
                if let device = alert.related_device_name {
                    chipView(icon: "desktopcomputer", text: device)
                }

                // Source kind chip from deep link metadata
                if let sourceKind = alert.source_kind {
                    chipView(icon: sourceKindIcon(sourceKind), text: sourceKind)
                }
            }

            // Actions
            if !alert.is_resolved {
                HStack(spacing: 8) {
                    if !alert.is_read {
                        Button(L10n.alerts.ack) {
                            Task { await onAcknowledge() }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }

                    Button(L10n.alerts.resolve) {
                        Task { await onResolve() }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())

                    Button(showSnooze ? L10n.common.cancel : L10n.alerts.snooze) {
                        withAnimation { showSnooze.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())

                    Spacer()
                }

                if showSnooze {
                    HStack(spacing: 8) {
                        ForEach([15, 30, 60, 120], id: \.self) { min in
                            Button("\(min)m") {
                                Task {
                                    await onSnooze(min)
                                    showSnooze = false
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(L10n.alerts.resolved)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(12)
        .background(PulseTheme.severityColor(alert.severity).opacity(alert.is_resolved ? 0.02 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PulseTheme.severityColor(alert.severity).opacity(0.2), lineWidth: 1)
        )
    }

    private func chipView(icon: String, text: String, tappable: Bool = false) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(tappable ? .blue : .tertiary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background((tappable ? Color.blue : Color.gray).opacity(0.08))
        .clipShape(Capsule())
    }

    private func sourceKindIcon(_ kind: String) -> String {
        switch kind {
        case "provider": return "cpu"
        case "session": return "terminal"
        case "project": return "folder"
        case "device": return "desktopcomputer"
        default: return "link"
        }
    }
}

// Simple flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
