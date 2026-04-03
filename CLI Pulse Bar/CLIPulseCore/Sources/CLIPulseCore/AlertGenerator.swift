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
        let now = ISO8601DateFormatter().string(from: Date())

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
}
#endif
