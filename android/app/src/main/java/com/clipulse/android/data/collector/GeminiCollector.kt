package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class GeminiCollector : ProviderCollector {
    override val kind = ProviderKind.Gemini

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val jsonMedia = "application/json".toMediaType()
        val tiers = mutableListOf<CollectorTier>()
        var planType: String? = null

        // Step 1: Get tier info
        try {
            val tierReq = Request.Builder()
                .url("https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")
                .post("{}".toRequestBody(jsonMedia))
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .build()

            val tierResp = client.newCall(tierReq).execute()
            tierResp.use { r ->
                if (r.isSuccessful) {
                    val json = JSONObject(r.body?.string() ?: "{}")
                    planType = json.optString("subscriptionPlanType").takeIf { it.isNotBlank() }
                }
            }
        } catch (_: Exception) { }

        // Step 2: Get quota usage
        val quotaReq = Request.Builder()
            .url("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")
            .post("{}".toRequestBody(jsonMedia))
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Content-Type", "application/json")
            .build()

        val quotaResp = client.newCall(quotaReq).execute()
        quotaResp.use { r ->
            if (!r.isSuccessful) throw Exception("Gemini quota API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val buckets = json.optJSONArray("quotaBuckets")

            if (buckets != null) {
                for (i in 0 until buckets.length()) {
                    val b = buckets.getJSONObject(i)
                    val name = b.optString("quotaBucketName", "Quota")
                    val remaining = b.optDouble("remainingFraction", 1.0)
                    val resetTime = b.optString("resetTime").takeIf { it.isNotBlank() }
                    val quotaVal = 100
                    val remainingVal = (remaining * 100).toInt()
                    tiers.add(CollectorTier(name, quotaVal, remainingVal, resetTime))
                }
            }
        }

        val overall = tiers.firstOrNull()
        return CollectorResult(
            provider = kind,
            remaining = overall?.remaining,
            quota = overall?.quota,
            planType = planType,
            resetTime = overall?.resetTime,
            tiers = tiers,
            confidence = "high",
        )
    }
}
