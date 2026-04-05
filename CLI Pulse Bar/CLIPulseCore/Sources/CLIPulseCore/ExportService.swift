import Foundation

/// Generates CSV export files from CLI Pulse data.
/// Used by iOS, macOS, and watchOS for data export.
public enum ExportService {

    // MARK: - Sessions CSV

    /// Export sessions to a CSV file. Returns the temporary file URL.
    public static func exportSessionsCSV(sessions: [SessionRecord]) -> URL? {
        var csv = "ID,Name,Provider,Project,Status,Usage,Cost,Requests,Errors,Started,Last Active\n"
        for s in sessions {
            csv += "\(esc(s.id)),\(esc(s.name)),\(esc(s.provider)),\(esc(s.project)),"
            csv += "\(esc(s.status)),\(s.total_usage),\(s.estimated_cost),"
            csv += "\(s.requests),\(s.error_count),\(esc(s.started_at)),\(esc(s.last_active_at))\n"
        }
        return writeTemp(csv, name: "cli-pulse-sessions.csv")
    }

    // MARK: - Provider Summary CSV

    /// Export provider usage summary to a CSV file.
    public static func exportProviderSummaryCSV(providers: [ProviderUsage]) -> URL? {
        var csv = "Provider,Today Usage,Week Usage,Est. Cost (Week),Remaining,Quota,Plan Type,Reset Time\n"
        for p in providers {
            csv += "\(esc(p.provider)),\(p.today_usage),\(p.total_usage),"
            csv += "\(p.estimated_cost_week),"
            csv += "\(p.remaining.map(String.init) ?? "N/A"),"
            csv += "\(p.quota.map(String.init) ?? "N/A"),"
            csv += "\(esc(p.plan_type ?? "")),\(esc(p.reset_time ?? ""))\n"
        }
        return writeTemp(csv, name: "cli-pulse-providers.csv")
    }

    // MARK: - Alerts CSV

    /// Export alerts to a CSV file.
    public static func exportAlertsCSV(alerts: [AlertRecord]) -> URL? {
        var csv = "ID,Type,Severity,Title,Message,Provider,Project,Created,Read,Resolved\n"
        for a in alerts {
            csv += "\(esc(a.id)),\(esc(a.type)),\(esc(a.severity)),\(esc(a.title)),"
            csv += "\(esc(a.message)),\(esc(a.related_provider ?? "")),"
            csv += "\(esc(a.related_project_name ?? "")),\(esc(a.created_at)),"
            csv += "\(a.is_read),\(a.is_resolved)\n"
        }
        return writeTemp(csv, name: "cli-pulse-alerts.csv")
    }

    // MARK: - Cost Report CSV

    /// Export a combined cost report with dashboard + provider breakdown.
    public static func exportCostReportCSV(
        dashboard: DashboardSummary?,
        providers: [ProviderUsage],
        sessions: [SessionRecord]
    ) -> URL? {
        var csv = "CLI Pulse Cost Report\n"
        csv += "Generated,\(sharedISO8601Formatter.string(from: Date()))\n\n"

        if let d = dashboard {
            csv += "Summary\n"
            csv += "Today Usage,\(d.total_usage_today)\n"
            csv += "Today Cost,$\(d.total_estimated_cost_today)\n"
            csv += "Active Sessions,\(d.active_sessions)\n"
            csv += "Online Devices,\(d.online_devices)\n"
            csv += "Unresolved Alerts,\(d.unresolved_alerts)\n\n"
        }

        csv += "Provider Breakdown\n"
        csv += "Provider,Week Usage,Est. Cost,Remaining,Quota\n"
        for p in providers {
            csv += "\(esc(p.provider)),\(p.total_usage),\(p.estimated_cost_week),"
            csv += "\(p.remaining.map(String.init) ?? "N/A"),\(p.quota.map(String.init) ?? "N/A")\n"
        }

        csv += "\nTop Sessions by Cost\n"
        csv += "Provider,Project,Cost,Usage,Status\n"
        let topSessions = sessions.sorted { $0.estimated_cost > $1.estimated_cost }.prefix(20)
        for s in topSessions {
            csv += "\(esc(s.provider)),\(esc(s.project)),\(s.estimated_cost),\(s.total_usage),\(esc(s.status))\n"
        }

        return writeTemp(csv, name: "cli-pulse-cost-report.csv")
    }

    // MARK: - Helpers

    private static func esc(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func writeTemp(_ content: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
