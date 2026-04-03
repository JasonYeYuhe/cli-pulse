package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind

data class CollectorResult(
    val provider: ProviderKind,
    val remaining: Int? = null,
    val quota: Int? = null,
    val planType: String? = null,
    val resetTime: String? = null,
    val tiers: List<CollectorTier> = emptyList(),
    val credits: Double? = null,
    val statusText: String = "Operational",
    val confidence: String = "high",
)

data class CollectorTier(
    val name: String,
    val quota: Int,
    val remaining: Int,
    val resetTime: String? = null,
)

interface ProviderCollector {
    val kind: ProviderKind
    fun isAvailable(apiKey: String?): Boolean
    suspend fun collect(apiKey: String): CollectorResult
}
