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

    // Providers
    @Query("SELECT * FROM cached_providers")
    suspend fun getProviders(): List<CachedProvider>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveProviders(providers: List<CachedProvider>)

    @Query("DELETE FROM cached_providers")
    suspend fun clearProviders()

    @Transaction
    suspend fun replaceProviders(providers: List<CachedProvider>) {
        clearProviders()
        saveProviders(providers)
    }

    // Sessions
    @Query("SELECT * FROM cached_sessions")
    suspend fun getSessions(): List<CachedSession>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveSessions(sessions: List<CachedSession>)

    @Query("DELETE FROM cached_sessions")
    suspend fun clearSessions()

    @Transaction
    suspend fun replaceSessions(sessions: List<CachedSession>) {
        clearSessions()
        saveSessions(sessions)
    }

    // Alerts
    @Query("SELECT * FROM cached_alerts")
    suspend fun getAlerts(): List<CachedAlert>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveAlerts(alerts: List<CachedAlert>)

    @Query("DELETE FROM cached_alerts")
    suspend fun clearAlerts()

    @Transaction
    suspend fun replaceAlerts(alerts: List<CachedAlert>) {
        clearAlerts()
        saveAlerts(alerts)
    }

    // Devices
    @Query("SELECT * FROM cached_devices")
    suspend fun getDevices(): List<CachedDevice>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun saveDevices(devices: List<CachedDevice>)

    @Query("DELETE FROM cached_devices")
    suspend fun clearDevices()

    @Transaction
    suspend fun replaceDevices(devices: List<CachedDevice>) {
        clearDevices()
        saveDevices(devices)
    }

    // Clear all
    @Query("DELETE FROM cached_dashboard")
    suspend fun clearDashboard()

    suspend fun clearAll() {
        clearDashboard()
        clearProviders()
        clearSessions()
        clearAlerts()
        clearDevices()
    }
}
