import SwiftUI
import CLIPulseCore
#if os(watchOS)
import WatchKit
#endif

struct WatchAlertsView: View {
    @EnvironmentObject var state: WatchAppState

    private var openAlerts: [AlertRecord] {
        state.alerts.filter { !$0.is_resolved }
    }

    private var unreadCount: Int {
        openAlerts.filter { !$0.is_read }.count
    }

    private var resolvedAlerts: [AlertRecord] {
        state.alerts.filter { $0.is_resolved }
    }

    var body: some View {
        List {
            if openAlerts.isEmpty && resolvedAlerts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text(L10n.alerts.allClear)
                        .font(.caption.weight(.semibold))
                    Text(L10n.alerts.noAlerts)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            if !openAlerts.isEmpty {
                Section {
                    ForEach(openAlerts) { alert in
                        NavigationLink {
                            WatchAlertDetailView(alert: alert)
                                .environmentObject(state)
                        } label: {
                            WatchAlertRow(alert: alert)
                        }
                    }
                } header: {
                    HStack {
                        Text(L10n.alerts.open)
                        Spacer()
                        if unreadCount > 0 {
                            Text("\(unreadCount) unread")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.red))
                        }
                    }
                }
            }

            if !resolvedAlerts.isEmpty {
                Section(L10n.alerts.resolved) {
                    ForEach(Array(resolvedAlerts.prefix(5))) { alert in
                        WatchAlertRow(alert: alert)
                    }
                }
            }
        }
        .navigationTitle(L10n.tab.alerts)
        .refreshable {
            await state.refreshAll()
        }
        .task {
            triggerHapticForCritical()
        }
    }

    private func triggerHapticForCritical() {
        let critical = openAlerts.filter { $0.severity == "Critical" }
        if !critical.isEmpty {
            #if os(watchOS)
            WKInterfaceDevice.current().play(.failure)
            #endif
        }
    }
}

// MARK: - Alert Row

struct WatchAlertRow: View {
    let alert: AlertRecord

    private var severityColor: Color {
        PulseTheme.severityColor(alert.severity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Severity indicator bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(severityColor)
                    .frame(width: 3, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if !alert.is_read && !alert.is_resolved {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                        }
                        Text(alert.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                    }
                    Text(alert.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 6) {
                // Severity badge
                Text(alert.severity)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(severityColor.opacity(0.2))
                    .foregroundStyle(severityColor)
                    .clipShape(Capsule())

                if alert.is_resolved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }

                Spacer()

                Text(RelativeTime.format(alert.created_at))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Alert Detail

struct WatchAlertDetailView: View {
    let alert: AlertRecord
    @EnvironmentObject var state: WatchAppState

    private var severityColor: Color {
        PulseTheme.severityColor(alert.severity)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(severityColor)
                            .frame(width: 3, height: 20)
                        Text(alert.severity)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(severityColor)
                    }
                    Text(alert.title)
                        .font(.caption.weight(.semibold))
                    Text(alert.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if alert.related_provider != nil || alert.related_project_name != nil || alert.related_device_name != nil {
                Section(L10n.alerts.related) {
                    if let provider = alert.related_provider {
                        HStack {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text(provider)
                                .font(.caption)
                        }
                    }
                    if let project = alert.related_project_name {
                        HStack {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text(project)
                                .font(.caption)
                        }
                    }
                    if let device = alert.related_device_name {
                        HStack {
                            Image(systemName: "desktopcomputer")
                                .font(.caption2)
                            Text(device)
                                .font(.caption)
                        }
                    }
                }
            }

            if !alert.is_resolved {
                Section(L10n.alerts.actions) {
                    if !alert.is_read {
                        Button {
                            Task { await state.acknowledgeAlert(alert) }
                        } label: {
                            HStack {
                                Image(systemName: "eye")
                                    .font(.caption)
                                Text(L10n.alerts.acknowledge)
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.blue)
                    }

                    Button {
                        Task { await state.resolveAlert(alert) }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                            Text(L10n.alerts.resolve)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.green)

                    NavigationLink {
                        List {
                            Button("15 minutes") {
                                Task { await state.snoozeAlert(alert, minutes: 15) }
                            }
                            Button("30 minutes") {
                                Task { await state.snoozeAlert(alert, minutes: 30) }
                            }
                            Button("1 hour") {
                                Task { await state.snoozeAlert(alert, minutes: 60) }
                            }
                        }
                        .navigationTitle(L10n.alerts.snooze)
                    } label: {
                        HStack {
                            Image(systemName: "moon.zzz")
                                .font(.caption)
                            Text(L10n.alerts.snooze)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.orange)
                }
            }

            Section {
                HStack {
                    Text(L10n.alerts.created)
                        .font(.caption)
                    Spacer()
                    Text(RelativeTime.format(alert.created_at))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L10n.tab.alerts)
    }
}
