import SwiftUI
import CLIPulseCore

struct ProvidersTab: View {
    @EnvironmentObject var state: AppState
    @State private var showDisabled = false

    private var sortedDetails: [ProviderDetail] {
        state.providerDetails.filter { showDisabled || $0.config.isEnabled }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Text(L10n.providers.title)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Button {
                        showDisabled.toggle()
                    } label: {
                        Text(showDisabled ? L10n.providers.hideDisabled : L10n.providers.showAll)
                            .font(.system(size: 9))
                            .foregroundStyle(PulseTheme.accent)
                    }
                    .buttonStyle(.plain)
                    Text("\(state.providers.count) \(L10n.providers.tracked)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // Cost summary bar
                if state.showCost {
                    costSummaryBar
                }

                if sortedDetails.isEmpty && state.providers.isEmpty {
                    EmptyStateView(
                        icon: "cpu",
                        title: L10n.providers.noProviders,
                        subtitle: L10n.providers.emptyHint
                    )
                } else if sortedDetails.isEmpty {
                    EmptyStateView(
                        icon: "eye.slash",
                        title: L10n.providers.allHidden,
                        subtitle: L10n.providers.showAllHint
                    )
                } else {
                    ForEach(sortedDetails) { detail in
                        EnhancedProviderCard(detail: detail, showCost: state.showCost) {
                            state.toggleProvider(detail.config.kind)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var costSummaryBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.dashboard.today)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(CostFormatter.format(state.costSummary.todayTotal))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }
            Divider().frame(height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.dashboard.thirtyDayEst)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(CostFormatter.format(state.costSummary.thirtyDayTotal))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }
            Spacer()
        }
        .padding(8)
        .background(PulseTheme.cardBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Enhanced Provider Card

struct EnhancedProviderCard: View {
    let detail: ProviderDetail
    let showCost: Bool
    let onToggle: () -> Void

    private var provider: ProviderUsage { detail.provider }
    private var config: ProviderConfig { detail.config }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                providerIcon
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(provider.provider)
                            .font(.system(size: 12, weight: .bold))
                        if !config.isEnabled {
                            Text("DISABLED")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 4) {
                        // Status indicator
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        Text(statusText)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        if let src = detail.version {
                            Text("v\(src)")
                                .font(.system(size: 8))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                Spacer()

                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if config.isEnabled {
                // Source + Plan row
                HStack(spacing: 8) {
                    if let email = detail.accountEmail {
                        Label(email, systemImage: "envelope")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if let plan = detail.planType {
                        StatusBadge(text: plan, color: plan == "Paid" ? .green : .orange)
                    }
                    Text("Source: \(detail.sourceType.rawValue)")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                    Spacer()
                    quotaBadge
                }

                // Usage stats
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(CostFormatter.formatUsage(provider.today_usage))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        if showCost {
                            Text(CostFormatter.format(provider.estimated_cost_today))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.providers.thisWeek)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(CostFormatter.formatUsage(provider.week_usage))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        if showCost {
                            Text(CostFormatter.format(provider.estimated_cost_week))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }
                    Spacer()
                }

                // Usage tiers
                if !detail.tiers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(detail.tiers) { tier in
                            UsageBar(
                                label: tier.name,
                                value: tier.usagePercent,
                                color: tierColor(tier),
                                detail: tierDetail(tier)
                            )
                        }
                    }
                } else if let quota = provider.quota, quota > 0 {
                    UsageBar(
                        label: "Quota",
                        value: provider.usagePercent,
                        color: usageColor,
                        detail: remainingText
                    )
                }

                // Recent sessions
                if !provider.recent_sessions.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(provider.recent_sessions.prefix(3).joined(separator: ", "))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(PulseTheme.cardBackground.opacity(config.isEnabled ? 0.5 : 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(providerColor.opacity(config.isEnabled ? 0.2 : 0.05), lineWidth: 1)
        )
        .opacity(config.isEnabled ? 1.0 : 0.6)
    }

    private var providerColor: Color {
        PulseTheme.providerColor(provider.provider)
    }

    private var statusColor: Color {
        switch detail.operationalStatus {
        case .operational: return .green
        case .degraded: return .orange
        case .down: return .red
        }
    }

    private var statusText: String {
        if !config.isEnabled { return "Disabled" }
        switch detail.operationalStatus {
        case .operational: return "Operational"
        case .degraded: return "Degraded"
        case .down: return "Down"
        }
    }

    private var providerIcon: some View {
        Image(systemName: config.kind.iconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(providerColor)
            .frame(width: 28, height: 28)
            .background(providerColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var usageColor: Color {
        if provider.usagePercent > 0.9 { return .red }
        if provider.usagePercent > 0.7 { return .orange }
        return providerColor
    }

    private func tierColor(_ tier: UsageTier) -> Color {
        if tier.usagePercent > 0.9 { return .red }
        if tier.usagePercent > 0.7 { return .orange }
        return providerColor
    }

    private func tierDetail(_ tier: UsageTier) -> String? {
        guard let remaining = tier.remaining, let quota = tier.quota, quota > 0 else { return nil }
        let pctLeft = Int(100.0 * Double(remaining) / Double(quota))
        var result = "\(pctLeft)% left"
        if let reset = tier.resetTime {
            result += " · Resets \(RelativeTime.format(reset))"
        }
        return result
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
