import SwiftUI
import CLIPulseCore

struct AlertsTab: View {
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
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Text(L10n.alerts.title)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    alertSummary
                }

                // Filter + Resolve All
                HStack {
                    Picker("", selection: $filter) {
                        ForEach(AlertFilter.allCases, id: \.self) { f in
                            Text(f.label)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    if filter == .open && !filteredAlerts.isEmpty {
                        Button {
                            Task {
                                for alert in filteredAlerts where !alert.is_resolved {
                                    await state.resolveAlert(alert)
                                }
                            }
                        } label: {
                            Text("Resolve All")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.1))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Alert List
                if filteredAlerts.isEmpty {
                    EmptyStateView(
                        icon: filter == .open ? "checkmark.shield" : "bell.slash",
                        title: filter == .open ? L10n.alerts.allClear : L10n.alerts.noAlerts,
                        subtitle: filter == .open ? L10n.alerts.noUnresolved : L10n.alerts.noMatching
                    )
                } else {
                    ForEach(filteredAlerts) { alert in
                        AlertRow(alert: alert) {
                            await state.acknowledgeAlert(alert)
                        } onResolve: {
                            await state.resolveAlert(alert)
                        } onSnooze: { minutes in
                            await state.snoozeAlert(alert, minutes: minutes)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var alertSummary: some View {
        let open = state.alerts.filter { !$0.is_resolved }
        let critical = open.filter { $0.severity == "Critical" }.count
        let warning = open.filter { $0.severity == "Warning" }.count

        HStack(spacing: 6) {
            if critical > 0 {
                StatusBadge(text: "\(critical) \(L10n.alerts.severityCritical)", color: .red)
            }
            if warning > 0 {
                StatusBadge(text: "\(warning) \(L10n.alerts.severityWarning)", color: .orange)
            }
        }
    }
}

// MARK: - Alert Row

struct AlertRow: View {
    let alert: AlertRecord
    let onAcknowledge: () async -> Void
    let onResolve: () async -> Void
    let onSnooze: (Int) async -> Void

    @State private var showSnooze = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                SeverityDot(severity: alert.severity)
                Text(alert.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Text(RelativeTime.format(alert.created_at))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            // Message
            Text(alert.message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // Related entity chips
            HStack(spacing: 4) {
                if let provider = alert.related_provider {
                    chipView(icon: "cpu", text: provider)
                }
                if let project = alert.related_project_name {
                    chipView(icon: "folder", text: project)
                }
                if let session = alert.related_session_name {
                    chipView(icon: "terminal", text: session)
                }
                if let device = alert.related_device_name {
                    chipView(icon: "desktopcomputer", text: device)
                }
            }

            // Actions
            if !alert.is_resolved {
                HStack(spacing: 6) {
                    if !alert.is_read {
                        Button(L10n.alerts.ack) {
                            Task { await onAcknowledge() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }

                    Button(L10n.alerts.resolve) {
                        Task { await onResolve() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())

                    Button(showSnooze ? L10n.common.cancel : L10n.alerts.snooze) {
                        showSnooze.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.1))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())

                    Spacer()
                }

                if showSnooze {
                    HStack(spacing: 6) {
                        ForEach([15, 30, 60, 120], id: \.self) { min in
                            Button("\(min)m") {
                                Task {
                                    await onSnooze(min)
                                    showSnooze = false
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    Text(L10n.alerts.resolved)
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(8)
        .background(severityBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(PulseTheme.severityColor(alert.severity).opacity(0.2), lineWidth: 1)
        )
    }

    private var severityBackground: Color {
        PulseTheme.severityColor(alert.severity).opacity(alert.is_resolved ? 0.02 : 0.05)
    }

    private func chipView(icon: String, text: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 8))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.08))
        .clipShape(Capsule())
    }
}
