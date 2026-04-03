package com.clipulse.android.data.model

data class ProviderUsage(
    val provider: String,
    val todayUsage: Int = 0,
    val weekUsage: Int = 0,
    val estimatedCostToday: Double = 0.0,
    val estimatedCostWeek: Double = 0.0,
    val costStatusToday: String = "Estimated",
    val costStatusWeek: String = "Estimated",
    val quota: Int? = null,
    val remaining: Int? = null,
    val planType: String? = null,
    val resetTime: String? = null,
    val tiers: List<TierDTO> = emptyList(),
    val statusText: String = "Operational",
    val trend: List<UsagePoint> = emptyList(),
    val recentSessions: List<String> = emptyList(),
    val recentErrors: List<String> = emptyList(),
    val metadata: ProviderMetadata? = null,
) {
    val providerKind: ProviderKind? get() = ProviderKind.fromString(provider)

    val usagePercent: Double
        get() {
            val q = quota ?: return 0.0
            if (q <= 0) return 0.0
            val used = q - (remaining ?: 0)
            return (used.toDouble() / q).coerceIn(0.0, 1.0)
        }
}

data class TierDTO(
    val name: String,
    val quota: Int,
    val remaining: Int,
    val resetTime: String? = null,
)

data class ProviderMetadata(
    val displayName: String,
    val category: String,
    val supportsExactCost: Boolean = false,
    val supportsQuota: Boolean = true,
    val defaultQuota: Int? = null,
)
