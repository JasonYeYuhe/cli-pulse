package com.clipulse.android.data.model

data class DeviceRecord(
    val id: String,
    val name: String,
    val type: String,
    val system: String,
    val status: String,
    val lastSyncAt: String? = null,
    val helperVersion: String,
    val currentSessionCount: Int,
    val cpuUsage: Int? = null,
    val memoryUsage: Int? = null,
) {
    val deviceStatus: DeviceStatus? get() = DeviceStatus.fromString(status)
}
