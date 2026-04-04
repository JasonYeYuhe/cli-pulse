package com.clipulse.android.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [
        CachedDashboard::class,
        CachedProvider::class,
        CachedSession::class,
        CachedAlert::class,
        CachedDevice::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun cacheDao(): CacheDao
}
