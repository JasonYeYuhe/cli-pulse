package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class OpenRouterCollector(
    internal val baseUrl: String = "https://openrouter.ai",
) : ProviderCollector {
    override val kind = ProviderKind.OpenRouter

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("$baseUrl/api/v1/credits")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("OpenRouter API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val data = json.optJSONObject("data") ?: json
            val totalCredits = data.optDouble("total_credits", 0.0)
            val usedCredits = data.optDouble("total_usage", 0.0)
            val remaining = ((totalCredits - usedCredits) * 100).toInt() // as percentage
            val quota = (totalCredits * 100).toInt()

            CollectorResult(
                provider = ProviderKind.OpenRouter,
                remaining = remaining,
                quota = quota,
                credits = totalCredits - usedCredits,
                planType = "Credits",
                confidence = "high",
            )
        }
    }
}
