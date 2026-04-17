import SwiftUI
import CLIPulseCore

/// Compact card shown on the Overview tab. Displays per-provider Cost-to-Code
/// Yield Score over the user-selected window (7d / 30d / 90d).
///
/// Empty/disabled states:
/// - Helper not installed → "Install macOS helper to track yield score"
/// - Tracking opt-in not enabled → "Enable in Settings"
/// - No commits attributed → "0 commits — try writing some code in a tracked repo"
struct YieldScoreCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if !trackingEnabled {
                disabledView
            } else if state.yieldScoreSummaries.isEmpty {
                emptyView
            } else {
                summaryList
                detailLink
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .center) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(.purple)
            Text("Yield Score")
                .font(.system(size: 13, weight: .semibold))
            Text("· Estimated")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .help("Cost is estimated from token usage when an exact API price isn't available.")
            Spacer()
            Picker("Range", selection: $state.yieldScoreRange) {
                ForEach(YieldScoreRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 140)
        }
    }

    private var trackingEnabled: Bool {
        state.gitTrackingEnabled
    }

    private var disabledView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Track AI cost per commit to see your yield score.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Enable in Settings → Privacy → Track git activity.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var emptyView: some View {
        Text("0 commits attributed in this window. Try writing some code in a tracked repo.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    private var summaryList: some View {
        VStack(spacing: 6) {
            ForEach(rankedSummaries) { summary in
                row(for: summary)
            }
        }
    }

    private var detailLink: some View {
        NavigationLink(destination: YieldScoreDetailView()) {
            HStack {
                Spacer()
                Text("View detail")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.purple)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)
            }
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row

    private func row(for summary: YieldScoreSummary) -> some View {
        HStack(alignment: .center, spacing: 8) {
            providerBadge(summary)
            Text(summary.provider)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(costLine(summary))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(yieldLine(summary))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(yieldColor(summary))
                    .monospacedDigit()
            }
        }
    }

    private func providerBadge(_ summary: YieldScoreSummary) -> some View {
        Group {
            if let kind = summary.providerKind {
                Image(systemName: kind.iconName)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.purple)
            } else {
                Circle()
                    .fill(.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func costLine(_ s: YieldScoreSummary) -> String {
        let cost = String(format: "$%.2f", s.totalCost)
        let commits: String
        if s.weightedCommits > 0 && abs(s.weightedCommits - Double(s.rawCommits)) < 0.01 {
            commits = "\(s.rawCommits) commits"
        } else if s.weightedCommits > 0 {
            commits = String(format: "%.1f commits", s.weightedCommits)
        } else {
            commits = "0 commits"
        }
        return "\(cost) → \(commits)"
    }

    private func yieldLine(_ s: YieldScoreSummary) -> String {
        guard let cpc = s.costPerCommit else { return "—" }
        return String(format: "$%.2f / commit", cpc)
    }

    /// Star the best yield (lowest cost/commit), warn at >2× the median.
    private func yieldColor(_ s: YieldScoreSummary) -> Color {
        guard let cpc = s.costPerCommit else { return .secondary }
        let medians = rankedSummaries.compactMap(\.costPerCommit).sorted()
        guard !medians.isEmpty else { return .primary }
        let median = medians[medians.count / 2]
        if cpc <= medians.first! + 0.001 { return .green }    // best
        if cpc > median * 2 { return .orange }                // poor ROI
        return .primary
    }

    private var rankedSummaries: [YieldScoreSummary] {
        state.yieldScoreSummaries
    }
}

// MARK: - Detail View

/// Full screen view (push from the card) that lists per-day yield contribution
/// and breaks down ambiguous attributions. Light shell for v2.0; can be
/// expanded with charts/per-commit detail in v2.1+.
struct YieldScoreDetailView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Yield Score Detail")
                    .font(.title2.bold())
                Text("\(state.yieldScoreRange.label) · ranked by cost per commit (lower is better)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(state.yieldScoreSummaries) { summary in
                    summaryCard(summary)
                }

                Text("Cost is estimated from token usage when an exact API price isn't available. Merge commits are excluded from attribution.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }
            .padding(16)
        }
        .frame(minWidth: 480)
    }

    private func summaryCard(_ s: YieldScoreSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.provider).font(.headline)
                Spacer()
                if let cpc = s.costPerCommit {
                    Text(String(format: "$%.3f / commit", cpc))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.purple)
                } else {
                    Text("no commits")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Label(String(format: "$%.2f", s.totalCost), systemImage: "dollarsign.circle")
                Label("\(s.rawCommits) commits", systemImage: "checkmark.circle")
                if s.ambiguousCommits > 0 {
                    Label("\(s.ambiguousCommits) ambiguous", systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
