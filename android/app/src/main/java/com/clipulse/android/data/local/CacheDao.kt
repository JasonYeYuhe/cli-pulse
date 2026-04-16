package com.clipulse.android.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction

@Dao
interface CacheDao {

    // Dashboard
    @Query("SELECT * FROM cached_dashboard WHERE id = 'singleton'")
    suspend fun getDashboard(): CachedDashboard?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveDashboard(dashboard: CachedDashboard)

    @Query("DELETE FROM cached_dashboard")
    suspend fun clearDashboard()

    // Providers
    @Query("SELECT * FROM cached_providers")
    suspend fun getProviders(): List<CachedProvider>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveProviders(providers: List<CachedProvider>)

    @Query("DELETE FROM cached_providers")
    suspend fun clearProviders()

    // Sessions
    @Query("SELECT * FROM cached_sessions")
    suspend fun getSessions(): List<CachedSession>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveSessions(sessions: List<CachedSession>)

    @Query("DELETE FROM cached_sessions")
    suspend fun clearSessions()

    // Alerts
    @Query("SELECT * FROM cached_alerts")
    suspend fun getAlerts(): List<CachedAlert>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveAlerts(alerts: List<CachedAlert>)

    @Query("DELETE FROM cached_alerts")
    suspend fun clearAlerts()

    // Devices
    @Query("SELECT * FROM cached_devices")
    suspend fun getDevices(): List<CachedDevice>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveDevices(devices: List<CachedDevice>)

    @Query("DELETE FROM cached_devices")
    suspend fun clearDevices()

    // Transactional replace operations (atomic clear + insert)
    @Transaction
    suspend fun replaceProviders(providers: List<CachedProvider>) {
        clearProviders()
        saveProviders(providers)
    }

    @Transaction
    suspend fun replaceSessions(sessions: List<CachedSession>) {
        clearSessions()
        saveSessions(sessions)
    }

    @Transaction
    suspend fun replaceAlerts(alerts: List<CachedAlert>) {
        clearAlerts()
        saveAlerts(alerts)
    }

    @Transaction
    suspend fun replaceDevices(devices: List<CachedDevice>) {
        clearDevices()
        saveDevices(devices)
    }

    // Daily Usage
    @Query("SELECT * FROM cached_daily_usage")
    suspend fun getDailyUsage(): List<CachedDailyUsage>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveDailyUsage(items: List<CachedDailyUsage>)

    @Query("DELETE FROM cached_daily_usage")
    suspend fun clearDailyUsage()

    @Transaction
    suspend fun replaceDailyUsage(items: List<CachedDailyUsage>) {
        clearDailyUsage()
        saveDailyUsage(items)
    }
}
