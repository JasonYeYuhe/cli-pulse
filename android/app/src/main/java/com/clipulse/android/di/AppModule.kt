package com.clipulse.android.di

import android.content.Context
import com.clipulse.android.billing.BillingManager
import com.clipulse.android.data.collector.CollectorManager
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
    fun provideDashboardRepository(supabase: SupabaseClient): DashboardRepository =
        DashboardRepository(supabase)

    @Provides
    @Singleton
    fun provideBillingManager(@ApplicationContext context: Context): BillingManager =
        BillingManager(context)
}
