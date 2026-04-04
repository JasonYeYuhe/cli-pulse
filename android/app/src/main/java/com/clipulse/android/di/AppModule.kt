package com.clipulse.android.di

import android.content.Context
import androidx.room.Room
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
    fun provideAppDatabase(@ApplicationContext context: Context): AppDatabase =
        Room.databaseBuilder(context, AppDatabase::class.java, "cli_pulse_cache")
            .fallbackToDestructiveMigration(true)
            .build()

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
