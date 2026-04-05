#if os(macOS)
import Foundation

/// Generates alerts from device metrics and session data.
/// Ports the 3 alert rules from Python's `collect_alerts()`.
public enum AlertGenerator {

    /// Generate alerts based on device snapshot and active sessions.
    ///
    /// - `device`: device-level CPU/memory snapshot
    /// - `sessions`: active sessions from LocalScanner
    /// - `sessionCPU`: optional per-session CPU usage (session.id → cpu%), from raw ps output
    ///
    /// Returns at most 6 alerts per cycle (matching Python behavior).
    public static func generate(
        device: DeviceMetrics.Snapshot,
        sessions: [SessionRecord],
        sessionCPU: [String: Double] = [:]
    ) -> [[String: Any]] {
        var alerts: [[String: Any]] = []
        let now = sharedISO8601Formatter.string(from: Date())

        // Rule 1: Device CPU >= 85%
        if device.cpuUsage >= 85 {
            alerts.append([
                "id": "cpu-spike-\(Int(Date().timeIntervalSince1970))",
                "type": "Usage Spike",
                "severity": "Warning",
                "title": "Device CPU usage is elevated",
                "message": "helper sampled CPU usage at \(device.cpuUsage)%.",
                "created_at": now,
                "source_kind": "device",
                "grouping_key": "Usage Spike:system",
                "suppression_key": "Usage Spike:global",
            ])
        }

        for session in sessions {
            // Rule 2: Session CPU >= 80%
            if let cpu = sessionCPU[session.id], cpu >= 80 {
                alerts.append([
                    "id": "session-spike-\(session.id)",
                    "type": "Usage Spike",
                    "severity": "Warning",
                    "title": "\(session.name) is consuming high CPU",
                    "message": "Process CPU is \(String(format: "%.1f", cpu))% for \(session.provider).",
                    "created_at": now,
                    "related_session_id": session.id,
                    "related_session_name": session.name,
                    "related_provider": session.provider,
                    "related_project_name": session.project,
                    "source_kind": "session",
                    "grouping_key": "Usage Spike:\(session.provider)",
                    "suppression_key": "Usage Spike:\(session.id)",
                ])
            }

            // Rule 3: Session requests >= 400 (long-running)
            if session.requests >= 400 {
                alerts.append([
                    "id": "session-long-\(session.id)",
                    "type": "Session Too Long",
                    "severity": "Info",
                    "title": "\(session.name) has been running for a long time",
                    "message": "Long-running local agent session detected by helper.",
                    "created_at": now,
                    "related_session_id": session.id,
                    "related_session_name": session.name,
                    "related_provider": session.provider,
                    "related_project_name": session.project,
                    "source_kind": "session",
                    "grouping_key": "Session Too Long:\(session.provider)",
                    "suppression_key": "Session Too Long:\(session.id)",
                ])
            }
        }

        return Array(alerts.prefix(6))
    }

    /// Generate budget and cost spike alerts from provider usage data.
    /// Called during both cloud and local refresh cycles.
    public static func evaluateBudgetAlerts(
        providers: [ProviderUsage],
        budgetThreshold: Double,
        yesterdayCost: Double? = nil
    ) -> [[String: Any]] {
        guard budgetThreshold > 0 else { return [] }
        var alerts: [[String: Any]] = []
        let now = sharedISO8601Formatter.string(from: Date())
        let weekLabel = {
            let cal = Calendar(identifier: .iso8601)
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
        }()

        // Per-provider budget check
        let totalWeekCost = providers.reduce(0.0) { $0 + $1.estimated_cost_week }
        if totalWeekCost > budgetThreshold {
            let key = "budget:total:\(weekLabel)"
            alerts.append([
                "id": "budget-total-\(weekLabel)",
                "type": "Project Budget Exceeded",
                "severity": "Warning",
                "title": "Weekly cost exceeds budget",
                "message": String(format: "Total cost this week ($%.2f) exceeds your budget ($%.2f)", totalWeekCost, budgetThreshold),
                "created_at": now,
                "suppression_key": key,
                "grouping_key": "budget:total",
            ])
        }

        // Cost spike: today's total > 2x yesterday
        if let yesterday = yesterdayCost, yesterday > 0 {
            let todayCost = providers.reduce(0.0) { $0 + Double($1.today_usage) * 0.001 } // rough estimate
            if todayCost > yesterday * 2 {
                let spikeKey = "costspike:\(sharedISO8601Formatter.string(from: Date()).prefix(10))"
                alerts.append([
                    "id": "costspike-\(spikeKey)",
                    "type": "Cost Spike",
                    "severity": "Warning",
                    "title": "Unusual cost spike detected",
                    "message": String(format: "Today's estimated cost is significantly higher than yesterday ($%.2f)", yesterday),
                    "created_at": now,
                    "suppression_key": spikeKey,
                    "grouping_key": "costspike:daily",
                ])
            }
        }

        return alerts
    }
}
#endif
