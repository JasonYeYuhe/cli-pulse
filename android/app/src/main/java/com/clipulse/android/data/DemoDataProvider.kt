package com.clipulse.android.data

import com.clipulse.android.data.model.*
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Generates demo data for Android, mirroring iOS DemoDataProvider.swift.
 * 3 providers, 4 sessions, 3 devices, 5 alerts, dashboard summary.
 */
object DemoDataProvider {

    private fun ts(offsetMinutes: Long = 0): String {
        return Instant.now().plus(offsetMinutes, ChronoUnit.MINUTES).toString()
    }

    fun providers(): List<ProviderUsage> = listOf(
        ProviderUsage(
            provider = "Codex", todayUsage = 85900, weekUsage = 462000,
            estimatedCostWeek = 5.54,
            quota = 500000, remaining = 38000, planType = "Pro",
            resetTime = null, tiers = listOf(
                TierDTO("5h Window", 100, 8, null),
                TierDTO("Weekly", 100, 22, null),
            ),
        ),
        ProviderUsage(
            provider = "Gemini", todayUsage = 43400, weekUsage = 214000,
            estimatedCostWeek = 1.71,
            quota = 300000, remaining = 86000, planType = "Pro",
            resetTime = null, tiers = emptyList(),
        ),
        ProviderUsage(
            provider = "Claude", todayUsage = 24800, weekUsage = 132000,
            estimatedCostWeek = 1.98,
            quota = 250000, remaining = 118000, planType = "Pro",
            resetTime = null, tiers = emptyList(),
        ),
    )

    fun sessions(): List<SessionRecord> = listOf(
        SessionRecord(
            id = "s1", name = "Dashboard metrics pass", provider = "Codex",
            project = "cli-pulse-ios", deviceName = "MacBook Pro",
            startedAt = ts(-120), lastActiveAt = ts(),
            status = "Running", totalUsage = 24500, estimatedCost = 0.29,
            costStatus = "Estimated", requests = 142, errorCount = 0,
            collectionConfidence = "high",
        ),
        SessionRecord(
            id = "s2", name = "Helper heartbeat monitor", provider = "Gemini",
            project = "cli-pulse-helper", deviceName = "lab-server-01",
            startedAt = ts(-60), lastActiveAt = ts(),
            status = "Syncing", totalUsage = 12800, estimatedCost = 0.10,
            costStatus = "Estimated", requests = 87, errorCount = 0,
            collectionConfidence = "medium",
        ),
        SessionRecord(
            id = "s3", name = "Session error triage", provider = "Codex",
            project = "backend-api", deviceName = "build-box",
            startedAt = ts(-120), lastActiveAt = ts(-60),
            status = "Failed", totalUsage = 8400, estimatedCost = 0.10,
            costStatus = "Estimated", requests = 56, errorCount = 3,
            collectionConfidence = "high",
        ),
        SessionRecord(
            id = "s4", name = "Provider adapter review", provider = "Claude",
            project = "provider-layer", deviceName = "MacBook Pro",
            startedAt = ts(-60), lastActiveAt = ts(),
            status = "Running", totalUsage = 6200, estimatedCost = 0.09,
            costStatus = "Estimated", requests = 38, errorCount = 0,
            collectionConfidence = "low",
        ),
    )

    fun devices(): List<DeviceRecord> = listOf(
        DeviceRecord(
            id = "d1", name = "MacBook Pro", type = "laptop", system = "macOS 15.4",
            status = "Online", lastSyncAt = ts(), helperVersion = "0.2.0",
            currentSessionCount = 2, cpuUsage = 42.0, memoryUsage = 68.0,
        ),
        DeviceRecord(
            id = "d2", name = "lab-server-01", type = "server", system = "Ubuntu 24.04",
            status = "Online", lastSyncAt = ts(), helperVersion = "0.2.0",
            currentSessionCount = 1, cpuUsage = 23.0, memoryUsage = 45.0,
        ),
        DeviceRecord(
            id = "d3", name = "build-box", type = "server", system = "macOS 14.7",
            status = "Offline", lastSyncAt = ts(-60), helperVersion = "0.1.9",
            currentSessionCount = 0, cpuUsage = null, memoryUsage = null,
        ),
    )

    fun alerts(): List<AlertRecord> = listOf(
        AlertRecord(
            id = "a1", type = "Quota Critical", severity = "Critical",
            title = "Codex quota critically low",
            message = "Only 7.6% remaining (38,000 of 500,000 tokens)",
            createdAt = ts(), isRead = false, isResolved = false,
            relatedProvider = "Codex",
            sourceKind = "provider", sourceId = "Codex",
            groupingKey = "quota-critical:Codex",
        ),
        AlertRecord(
            id = "a2", type = "Session Failed", severity = "Warning",
            title = "Session failed: error triage",
            message = "Session 'Session error triage' encountered 3 errors on build-box",
            createdAt = ts(-60), isRead = false, isResolved = false,
            relatedProvider = "Codex", relatedDeviceName = "build-box",
            sourceKind = "session", sourceId = "s3",
            groupingKey = "session-failed:s3",
        ),
        AlertRecord(
            id = "a3", type = "Helper Offline", severity = "Warning",
            title = "Device offline: build-box",
            message = "build-box has not synced for over 60 minutes",
            createdAt = ts(-60), isRead = true, isResolved = false,
            relatedDeviceName = "build-box",
            sourceKind = "device", sourceId = "d3",
            groupingKey = "device-offline:build-box",
        ),
        AlertRecord(
            id = "a4", type = "Cost Spike", severity = "Warning",
            title = "Cost spike: Codex",
            message = "Codex estimated cost today reached \$1.03, exceeding threshold \$0.80",
            createdAt = ts(-120), isRead = true, isResolved = false,
            relatedProvider = "Codex",
            sourceKind = "provider", sourceId = "Codex",
            groupingKey = "cost-spike:Codex",
        ),
        AlertRecord(
            id = "a5", type = "Error Rate Spike", severity = "Info",
            title = "Error rate spike: Codex",
            message = "Codex error rate spiked: 3 errors across 4 sessions",
            createdAt = ts(-120), isRead = true, isResolved = false,
            relatedProvider = "Codex",
            sourceKind = "provider", sourceId = "Codex",
            groupingKey = "error-rate:Codex",
        ),
    )

    fun dashboard(): DashboardSummary {
        val provs = providers()
        return DashboardSummary(
            totalUsageToday = provs.sumOf { it.todayUsage },
            totalEstimatedCostToday = 1.75,
            costStatus = "Estimated",
            totalRequestsToday = 323,
            activeSessions = 3,
            onlineDevices = 2,
            unresolvedAlerts = 5,
            alertSummary = AlertSummaryDTO(critical = 1, warning = 3, info = 1),
        )
    }
}
