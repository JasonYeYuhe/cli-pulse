package com.clipulse.android.data.model

data class SessionRecord(
    val id: String,
    val name: String,
    val provider: String,
    val project: String,
    val deviceName: String,
    val startedAt: String,
    val lastActiveAt: String,
    val status: String,
    val totalUsage: Int,
    val estimatedCost: Double,
    val costStatus: String,
    val requests: Int,
    val errorCount: Int,
    val collectionConfidence: String? = null,
) {
    val providerKind: ProviderKind? get() = ProviderKind.fromString(provider)
    val sessionStatus: SessionStatus? get() = SessionStatus.fromString(status)
}
