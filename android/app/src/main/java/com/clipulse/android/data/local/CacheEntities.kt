package com.clipulse.android.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Room entities for offline caching. Each entity stores a JSON-serialized
 * snapshot of the corresponding API response, keyed by a stable identifier.
 * This avoids duplicating all model fields as columns while still providing
 * fast local reads when offline.
 */

@Entity(tableName = "cached_dashboard")
data class CachedDashboard(
    @PrimaryKey val id: String = "singleton",
    val json: String,
    val updatedAt: Long = System.currentTimeMillis(),
)

@Entity(tableName = "cached_providers")
data class CachedProvider(
    @PrimaryKey val provider: String,
    val json: String,
    val updatedAt: Long = System.currentTimeMillis(),
)

@Entity(tableName = "cached_sessions")
data class CachedSession(
    @PrimaryKey val id: String,
    val json: String,
    val updatedAt: Long = System.currentTimeMillis(),
)

@Entity(tableName = "cached_alerts")
data class CachedAlert(
    @PrimaryKey val id: String,
    val json: String,
    val updatedAt: Long = System.currentTimeMillis(),
)

@Entity(tableName = "cached_devices")
data class CachedDevice(
    @PrimaryKey val id: String,
    val json: String,
    val updatedAt: Long = System.currentTimeMillis(),
)

@Entity(tableName = "cached_daily_usage")
data class CachedDailyUsage(
    @PrimaryKey val id: String,
    val json: String,
    val updatedAt: Long = System.currentTimeMillis(),
)
