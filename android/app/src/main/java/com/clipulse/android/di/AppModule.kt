package com.clipulse.android.di

import android.content.Context
import android.util.Log
import androidx.room.Room
import com.clipulse.android.BuildConfig
import com.clipulse.android.billing.BillingManager
import com.clipulse.android.data.collector.CollectorManager
import com.clipulse.android.data.local.AppDatabase
import com.clipulse.android.data.local.CacheDao
import com.clipulse.android.data.remote.SupabaseClient
import com.clipulse.android.data.remote.TokenStore
import com.clipulse.android.data.repository.DashboardRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideTokenStore(@ApplicationContext context: Context): TokenStore =
        TokenStore(context)

    @Provides
    @Singleton
    fun provideSupabaseClient(tokenStore: TokenStore): SupabaseClient =
        SupabaseClient(tokenStore)

    @Provides
    @Singleton
    fun provideCollectorManager(tokenStore: TokenStore): CollectorManager =
        CollectorManager(tokenStore)

    @Provides
    @Singleton
    fun provideAppDatabase(@ApplicationContext context: Context): AppDatabase {
        val builder = Room.databaseBuilder(context, AppDatabase::class.java, "cli_pulse_cache")
        if (BuildConfig.DEBUG) {
            // Debug only: silently recreate DB on schema changes for convenience.
            builder.fallbackToDestructiveMigration(true)
        } else {
            // Release: no destructive fallback — forces us to add explicit
            // Migration objects before bumping AppDatabase.version.
            // If we forget, Room will throw IllegalStateException on upgrade
            // instead of silently wiping user caches.
            // Add migrations here: builder.addMigrations(MIGRATION_1_2, ...)
            builder.addCallback(object : androidx.room.RoomDatabase.Callback() {
                    override fun onDestructiveMigration(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                        Log.w("AppDatabase", "Destructive migration triggered — cache cleared")
                    }
                })
        }
        return builder.build()
    }

    @Provides
    @Singleton
    fun provideCacheDao(db: AppDatabase): CacheDao =
        db.cacheDao()

    @Provides
    @Singleton
    fun provideDashboardRepository(supabase: SupabaseClient, cacheDao: CacheDao): DashboardRepository =
        DashboardRepository(supabase, cacheDao)

    @Provides
    @Singleton
    fun provideBillingManager(
        @ApplicationContext context: Context,
        supabase: SupabaseClient,
    ): BillingManager =
        BillingManager(context, supabase)
}
