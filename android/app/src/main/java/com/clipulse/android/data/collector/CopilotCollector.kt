package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class CopilotCollector : ProviderCollector {
    override val kind = ProviderKind.Copilot

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("https://api.github.com/copilot_internal/user")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Accept", "application/json")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Copilot API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val plan = json.optString("copilot_plan", "free")

            CollectorResult(
                provider = ProviderKind.Copilot,
                planType = plan,
                statusText = "Operational",
                confidence = "high",
            )
        }
    }
}
