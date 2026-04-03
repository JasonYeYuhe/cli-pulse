package com.clipulse.android.data.model

data class SettingsSnapshot(
    val notificationsEnabled: Boolean = true,
    val pushPolicy: String = "Warnings + Critical",
    val digestEnabled: Boolean = true,
    val digestIntervalHours: Int = 0,
    val usageSpikeThreshold: Int = 500,
    val projectBudgetThresholdUsd: Double = 0.25,
    val sessionTooLongThresholdMinutes: Int = 180,
    val offlineGracePeriodMinutes: Int = 5,
    val repeatedFailureThreshold: Int = 3,
    val alertCooldownMinutes: Int = 30,
    val dataRetentionDays: Int = 7,
)
