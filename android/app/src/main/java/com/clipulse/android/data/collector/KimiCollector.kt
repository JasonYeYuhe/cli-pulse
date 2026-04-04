package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class KimiCollector : ProviderCollector {
    override val kind = ProviderKind.Kimi

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val body = JSONObject().apply {
            put("scope", JSONArray().put("FEATURE_CODING"))
        }

        val req = Request.Builder()
            .url("https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Cookie", "kimi-auth=$apiKey")
            .addHeader("Origin", "https://www.kimi.com")
            .addHeader("Referer", "https://www.kimi.com/code/console")
            .addHeader("connect-protocol-version", "1")
            .addHeader("x-language", "en-US")
            .addHeader("x-msh-platform", "web")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Kimi API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val usages = json.optJSONArray("usages")
            val first = usages?.optJSONObject(0) ?: throw Exception("Kimi: no usages data")

            val detail = first.optJSONObject("detail")
            val weeklyLimit = detail?.optString("limit")?.toIntOrNull()
            val weeklyUsed = detail?.optString("used")?.toIntOrNull()
            val weeklyRemaining = detail?.optString("remaining")?.toIntOrNull()
            val weeklyReset = detail?.optString("resetTime")?.takeIf { it.isNotBlank() }

            val tiers = mutableListOf<CollectorTier>()
            if (weeklyLimit != null && weeklyLimit > 0) {
                tiers.add(CollectorTier(
                    "Weekly",
                    weeklyLimit,
                    weeklyRemaining ?: (weeklyLimit - (weeklyUsed ?: 0)).coerceAtLeast(0),
                    weeklyReset,
                ))
            }

            // Rate limit tier
            val limits = first.optJSONArray("limits")
            val firstLimit = limits?.optJSONObject(0)
            if (firstLimit != null) {
                val ld = firstLimit.optJSONObject("detail")
                val rlTotal = ld?.optString("limit")?.toIntOrNull()
                val rlUsed = ld?.optString("used")?.toIntOrNull()
                val rlReset = ld?.optString("resetTime")?.takeIf { it.isNotBlank() }
                if (rlTotal != null && rlTotal > 0) {
                    tiers.add(CollectorTier(
                        "5h Rate Limit",
                        rlTotal,
                        (rlTotal - (rlUsed ?: 0)).coerceAtLeast(0),
                        rlReset,
                    ))
                }
            }

            CollectorResult(
                provider = kind,
                remaining = weeklyRemaining,
                quota = weeklyLimit,
                resetTime = weeklyReset,
                tiers = tiers,
                confidence = "high",
            )
        }
    }
}
