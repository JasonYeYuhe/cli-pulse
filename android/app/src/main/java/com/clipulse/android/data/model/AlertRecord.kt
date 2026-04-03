package com.clipulse.android.data.model

data class AlertRecord(
    val id: String,
    val type: String,
    val severity: String,
    val title: String,
    val message: String,
    val createdAt: String,
    val isRead: Boolean,
    val isResolved: Boolean,
    val acknowledgedAt: String? = null,
    val snoozedUntil: String? = null,
    val relatedProjectId: String? = null,
    val relatedProjectName: String? = null,
    val relatedSessionId: String? = null,
    val relatedSessionName: String? = null,
    val relatedProvider: String? = null,
    val relatedDeviceName: String? = null,
    val sourceKind: String? = null,
    val sourceId: String? = null,
    val groupingKey: String? = null,
    val suppressionKey: String? = null,
) {
    val alertSeverity: AlertSeverity? get() = AlertSeverity.fromString(severity)
    val alertType: AlertType? get() = AlertType.fromString(type)
}
