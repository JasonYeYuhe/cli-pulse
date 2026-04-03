package com.clipulse.android.data.model

data class DashboardSummary(
    val totalUsageToday: Int = 0,
    val totalEstimatedCostToday: Double = 0.0,
    val costStatus: String = "Estimated",
    val totalRequestsToday: Int = 0,
    val activeSessions: Int = 0,
    val onlineDevices: Int = 0,
    val unresolvedAlerts: Int = 0,
    val providerBreakdown: List<ProviderBreakdown> = emptyList(),
    val topProjects: List<TopProject> = emptyList(),
    val trend: List<UsagePoint> = emptyList(),
    val recentActivity: List<ActivityItem> = emptyList(),
    val riskSignals: List<String> = emptyList(),
    val alertSummary: AlertSummaryDTO = AlertSummaryDTO(),
)

data class ProviderBreakdown(
    val provider: String,
    val usage: Int,
    val estimatedCost: Double,
    val costStatus: String,
    val remaining: Int? = null,
) {
    val providerKind: ProviderKind? get() = ProviderKind.fromString(provider)
}

data class TopProject(
    val id: String,
    val name: String,
    val usage: Int,
    val estimatedCost: Double,
    val costStatus: String,
)

data class UsagePoint(
    val timestamp: String,
    val value: Int,
)

data class ActivityItem(
    val id: String,
    val title: String,
    val subtitle: String,
    val timestamp: String,
)

data class AlertSummaryDTO(
    val critical: Int = 0,
    val warning: Int = 0,
    val info: Int = 0,
)
