package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Fetches credit usage from Augment code assistant.
 *
 * Endpoints: GET https://app.augmentcode.com/api/credits
 *            GET https://app.augmentcode.com/api/subscription
 * Auth:      Cookie header (session cookies from browser, stored as provider key).
 *
 * NOTE: Cookie-based, unofficial endpoint — treat as experimental.
 */
class AugmentCollector : ProviderCollector {
    override val kind = ProviderKind.Augment

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        // Fetch credits
        val creditsReq = Request.Builder()
            .url("https://app.augmentcode.com/api/credits")
            .get()
            .addHeader("Cookie", apiKey)
            .addHeader("Accept", "application/json")
            .build()

        val creditsResp = client.newCall(creditsReq).execute()
        val credits = creditsResp.use { r ->
            if (!r.isSuccessful) throw Exception("Augment credits API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            Triple(
                json.optInt("usageUnitsRemaining", 0),
                json.optInt("usageUnitsConsumedThisBillingCycle", 0),
                json.optInt("usageUnitsAvailable", 0),
            )
        }

        val remaining = credits.first
        val consumed = credits.second
        val total = remaining + consumed

        // Fetch subscription (non-fatal)
        val sub = try {
            val subReq = Request.Builder()
                .url("https://app.augmentcode.com/api/subscription")
                .get()
                .addHeader("Cookie", apiKey)
                .addHeader("Accept", "application/json")
                .build()
            val subResp = client.newCall(subReq).execute()
            subResp.use { r ->
                if (!r.isSuccessful) return@use null
                val json = JSONObject(r.body?.string() ?: "{}")
                Pair(
                    json.optString("planName").takeIf { it.isNotBlank() },
                    json.optString("billingPeriodEnd").takeIf { it.isNotBlank() },
                )
            }
        } catch (_: Exception) {
            null
        }

        val tiers = mutableListOf<CollectorTier>()
        if (total > 0) {
            tiers.add(CollectorTier("Credits", total, remaining, sub?.second))
        }

        return CollectorResult(
            provider = kind,
            remaining = remaining,
            quota = if (total > 0) total else null,
            planType = sub?.first,
            resetTime = sub?.second,
            tiers = tiers,
            statusText = if (total > 0) "$consumed/$total used" else "Operational",
            confidence = "high",
        )
    }
}
