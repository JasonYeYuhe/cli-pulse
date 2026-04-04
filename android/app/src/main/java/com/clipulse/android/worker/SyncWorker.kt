package com.clipulse.android.worker

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.*
import com.clipulse.android.data.collector.CollectorManager
import com.clipulse.android.data.remote.SupabaseClient
import com.clipulse.android.data.remote.TokenStore
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import org.json.JSONArray
import org.json.JSONObject
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
                .setRequiresBatteryNotLow(true)
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
            // 1. Ensure device is registered
            ensureDeviceRegistered()

            // 2. Run collectors if any provider keys are configured
            val available = collectorManager.availableCollectors()
            if (available.isNotEmpty()) {
                val results = collectorManager.collectAll()
                Log.d(TAG, "Collected ${results.size} provider results")

                // 3. Upload collected quota data to Supabase
                val payloads = results.mapNotNull { r ->
                    val remaining = r.remaining ?: return@mapNotNull null
                    val quota = r.quota ?: return@mapNotNull null
                    val tiersJson = JSONArray().apply {
                        for (tier in r.tiers) {
                            put(JSONObject().apply {
                                put("name", tier.name)
                                put("quota", tier.quota)
                                put("remaining", tier.remaining)
                                if (tier.resetTime != null) put("reset_time", tier.resetTime)
                            })
                        }
                    }.toString()

                    SupabaseClient.ProviderQuotaPayload(
                        provider = r.provider.displayValue,
                        remaining = remaining,
                        quota = quota,
                        planType = r.planType,
                        resetTime = r.resetTime,
                        tiersJson = tiersJson,
                    )
                }
                supabase.syncProviderQuotas(payloads)
                Log.d(TAG, "Synced ${payloads.size} provider quotas to Supabase")
            } else {
                Log.d(TAG, "No provider keys configured, skipping collection")
            }

            // 4. Prefetch dashboard data to keep cache warm
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

    private suspend fun ensureDeviceRegistered() {
        if (tokenStore.deviceId != null) return
        try {
            val deviceName = "${Build.MANUFACTURER} ${Build.MODEL}"
            val system = "Android ${Build.VERSION.RELEASE}"
            val deviceId = supabase.registerDevice(
                name = deviceName,
                type = "Android",
                system = system,
            )
            tokenStore.deviceId = deviceId
            Log.d(TAG, "Registered Android device: $deviceId")
        } catch (e: Exception) {
            Log.w(TAG, "Device registration failed (non-fatal)", e)
        }
    }
}
