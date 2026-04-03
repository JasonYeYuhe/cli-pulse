package com.clipulse.android.worker

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.*
import com.clipulse.android.data.collector.CollectorManager
import com.clipulse.android.data.remote.SupabaseClient
import com.clipulse.android.data.remote.TokenStore
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.concurrent.TimeUnit

@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val supabase: SupabaseClient,
    private val tokenStore: TokenStore,
    private val collectorManager: CollectorManager,
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "SyncWorker"
        private const val WORK_NAME = "cli_pulse_sync"

        fun enqueue(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(
                    WORK_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    request,
                )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }

    override suspend fun doWork(): Result {
        if (!tokenStore.isLoggedIn) return Result.success()

        return try {
            // 1. Only run collectors if any provider keys are configured
            val available = collectorManager.availableCollectors()
            if (available.isNotEmpty()) {
                val results = collectorManager.collectAll()
                Log.d(TAG, "Collected ${results.size} provider results")
                // TODO: sync results to Supabase once this device is registered
                //       as a helper via helper_sync RPC
            } else {
                Log.d(TAG, "No provider keys configured, skipping collection")
            }

            // 2. Prefetch dashboard data to keep cache warm
            try {
                supabase.dashboard()
                Log.d(TAG, "Dashboard prefetch successful")
            } catch (e: Exception) {
                Log.w(TAG, "Dashboard prefetch failed (non-fatal)", e)
            }

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }
}
