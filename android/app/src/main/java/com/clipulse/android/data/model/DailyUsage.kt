package com.clipulse.android.data.model

data class DailyUsage(
    val date: String,
    val provider: String,
    val model: String,
    val inputTokens: Int = 0,
    val cachedTokens: Int = 0,
    val outputTokens: Int = 0,
    val cost: Double = 0.0,
) {
    val totalTokens: Int get() = inputTokens + outputTokens
    val providerKind: ProviderKind? get() = ProviderKind.fromString(provider)
}
