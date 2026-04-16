package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class ClaudeCollector(
    internal val baseUrl: String = "https://api.anthropic.com",
) : ProviderCollector {
    override val kind = ProviderKind.Claude

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("$baseUrl/api/oauth/usage")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("anthropic-beta", "oauth-2025-04-20")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Claude API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")

            val tiers = mutableListOf<CollectorTier>()

            // Parse usage windows
            val windows = json.optJSONArray("usage_windows")
            if (windows != null) {
                for (i in 0 until windows.length()) {
                    val w = windows.getJSONObject(i)
                    val name = w.optString("window_name", "Window")
                    val limit = w.optInt("limit", 0)
                    val used = w.optInt("used", 0)
                    val resetTime = w.optString("reset_time").takeIf { it.isNotBlank() }
                    if (limit > 0) {
                        tiers.add(CollectorTier(name, limit, (limit - used).coerceAtLeast(0), resetTime))
                    }
                }
            }

            // Overall from the primary window (typically "5h Window")
            val primaryQuota = tiers.firstOrNull()?.quota
            val primaryRemaining = tiers.firstOrNull()?.remaining
            val planType = json.optString("plan_type").takeIf { it.isNotBlank() }

            CollectorResult(
                provider = kind,
                remaining = primaryRemaining,
                quota = primaryQuota,
                planType = planType,
                resetTime = tiers.firstOrNull()?.resetTime,
                tiers = tiers,
                confidence = "high",
            )
        }
    }
}
