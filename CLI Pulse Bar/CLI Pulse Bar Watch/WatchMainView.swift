import SwiftUI
import CLIPulseCore

struct WatchMainView: View {
    @EnvironmentObject var state: WatchAppState

    var body: some View {
        if !state.isAuthenticated {
            WatchLoginView()
                .environmentObject(state)
        } else {
            NavigationStack {
                List {
                    // Quick glance
                    if let dash = state.dashboard {
                        Section {
                            WatchQuickGlance(dashboard: dash, showCost: state.showCost)
                        }
                    }

                    // Navigation
                    Section {
                        NavigationLink {
                            WatchOverviewView()
                                .environmentObject(state)
                        } label: {
                            Label(L10n.tab.overview, systemImage: "gauge.with.dots.needle.33percent")
                        }

                        NavigationLink {
                            WatchProvidersView()
                                .environmentObject(state)
                        } label: {
                            Label(L10n.tab.providers, systemImage: "cpu")
                        }

                        NavigationLink {
                            WatchSessionsView()
                                .environmentObject(state)
                        } label: {
                            Label(L10n.tab.sessions, systemImage: "terminal")
                        }

                        NavigationLink {
                            WatchAlertsView()
                                .environmentObject(state)
                        } label: {
                            HStack {
                                Label(L10n.tab.alerts, systemImage: "bell.badge")
                                Spacer()
                                let unresolved = state.alerts.filter { !$0.is_resolved }.count
                                if unresolved > 0 {
                                    Text("\(unresolved)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(.red))
                                }
                            }
                        }
                    }
                }
                .navigationTitle(L10n.auth.title)
            }
            .task {
                await state.refreshAll()
                state.startRefreshLoop()
            }
        }
    }
}

// MARK: - Quick Glance

struct WatchQuickGlance: View {
    let dashboard: DashboardSummary
    let showCost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.dashboard.today)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(CostFormatter.formatUsage(dashboard.total_usage_today))
                    .font(.headline.monospacedDigit())
            }

            if showCost {
                HStack {
                    Text(L10n.dashboard.costToday)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(CostFormatter.format(dashboard.total_estimated_cost_today))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 12) {
                WatchMiniMetric(
                    icon: "terminal",
                    value: "\(dashboard.active_sessions)",
                    color: .blue
                )
                WatchMiniMetric(
                    icon: "desktopcomputer",
                    value: "\(dashboard.online_devices)",
                    color: .cyan
                )
                if dashboard.unresolved_alerts > 0 {
                    WatchMiniMetric(
                        icon: "bell.badge",
                        value: "\(dashboard.unresolved_alerts)",
                        color: .red
                    )
                }
            }
        }
    }
}

struct WatchMiniMetric: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
        }
    }
}
