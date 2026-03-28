import SwiftUI
import CLIPulseCore

struct iOSProvidersTab: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showDisabled = false

    private var isIPad: Bool { horizontalSizeClass == .regular }

    private var visibleDetails: [ProviderDetail] {
        state.providerDetails.filter { showDisabled || $0.config.isEnabled }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Cost bar
                    if state.showCost {
                        costBar
                            .padding(.horizontal)
                    }

                    if visibleDetails.isEmpty && state.providers.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.providers.noProviders, systemImage: "cpu")
                        } description: {
                            Text(L10n.providers.emptyHint)
                        }
                        .padding(.vertical, 40)
                    } else if isIPad {
                        // iPad: two-column grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ], spacing: 12) {
                            ForEach(visibleDetails) { detail in
                                iOSEnhancedProviderCard(detail: detail, showCost: state.showCost) {
                                    state.toggleProvider(detail.config.kind)
                                }
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // iPhone: single column
                        ForEach(visibleDetails) { detail in
                            iOSEnhancedProviderCard(detail: detail, showCost: state.showCost) {
                                state.toggleProvider(detail.config.kind)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.tab.providers)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showDisabled.toggle()
                        } label: {
                            Label(showDisabled ? L10n.providers.hideDisabled : L10n.providers.showAll, systemImage: showDisabled ? "eye.slash" : "eye")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Text("\(state.providers.count) \(L10n.providers.tracked)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .refreshable {
                await state.refreshAll()
            }
        }
    }

    private var costBar: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.dashboard.today)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(CostFormatter.format(state.costSummary.todayTotal))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.dashboard.thirtyDayEst)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(CostFormatter.format(state.costSummary.thirtyDayTotal))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
            }
            Spacer()
        }
        .padding()
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Enhanced Provider Card for iOS

struct iOSEnhancedProviderCard: View {
    let detail: ProviderDetail
    let showCost: Bool
    let onToggle: () -> Void

    private var provider: ProviderUsage { detail.provider }
    private var config: ProviderConfig { detail.config }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: config.kind.iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(providerColor)
                    .frame(width: 36, height: 36)
                    .background(providerColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(provider.provider)
                            .font(.headline)
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        if let meta = provider.metadata {
                            CategoryBadge(category: meta.category)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(provider.status_text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if showCost {
                            CostStatusBadge(status: provider.cost_status_today)
                        }
                    }
                }
                Spacer()

                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
            }

            if config.isEnabled {
                // Usage stats
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.dashboard.today)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(CostFormatter.formatUsage(provider.today_usage))
                            .font(.title3.weight(.bold).monospacedDigit())
                        if showCost {
                            Text(CostFormatter.format(provider.estimated_cost_today))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.providers.thisWeek)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(CostFormatter.formatUsage(provider.week_usage))
                            .font(.title3.weight(.bold).monospacedDigit())
                        if showCost {
                            Text(CostFormatter.format(provider.estimated_cost_week))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    }
                    Spacer()
                    quotaBadge
                }

                // Quota bar
                if let quota = provider.quota, quota > 0 {
                    UsageBar(
                        label: "Quota",
                        value: provider.usagePercent,
                        color: usageColor,
                        detail: remainingText
                    )
                }
            }
        }
        .padding()
        .background(PulseTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(providerColor.opacity(config.isEnabled ? 0.2 : 0.05), lineWidth: 1)
        )
        .opacity(config.isEnabled ? 1.0 : 0.6)
    }

    private var providerColor: Color { PulseTheme.providerColor(provider.provider) }

    private var statusColor: Color {
        switch detail.operationalStatus {
        case .operational: return .green
        case .degraded: return .orange
        case .down: return .red
        }
    }

    private var usageColor: Color {
        if provider.usagePercent > 0.9 { return .red }
        if provider.usagePercent > 0.7 { return .orange }
        return providerColor
    }

    private var remainingText: String? {
        guard let remaining = provider.remaining else { return nil }
        return "\(CostFormatter.formatUsage(remaining)) remaining"
    }

    private var quotaBadge: some View {
        Group {
            if provider.usagePercent > 0.9 {
                StatusBadge(text: "LOW", color: .red)
            } else if provider.usagePercent > 0.7 {
                StatusBadge(text: "MODERATE", color: .orange)
            } else {
                StatusBadge(text: "OK", color: .green)
            }
        }
    }
}
