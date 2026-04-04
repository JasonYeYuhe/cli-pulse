package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class VolcanoEngineCollector : ProviderCollector {
    override val kind = ProviderKind.VolcanoEngine

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("https://ark.cn-beijing.volces.com/api/v3/models")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Accept", "application/json")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Volcano Engine API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")

            // Direct quota fields
            val total = json.optInt("total", 0)
            if (total > 0) {
                val remaining = json.optInt("remaining", 0)
                val resetTime = json.optString("reset_time").takeIf { it.isNotBlank() }
                    ?: json.optString("end_time").takeIf { it.isNotBlank() }
                return@use CollectorResult(
                    provider = kind,
                    remaining = remaining,
                    quota = total,
                    resetTime = resetTime,
                    tiers = listOf(CollectorTier("Ark Plan", total, remaining, resetTime)),
                    confidence = "high",
                )
            }

            // Models list — connectivity probe
            val models = json.optJSONArray("data")
            val modelCount = models?.length() ?: 0
            CollectorResult(
                provider = kind,
                statusText = if (modelCount > 0) "$modelCount models available" else "Connected",
                confidence = "medium",
            )
        }
    }
}
