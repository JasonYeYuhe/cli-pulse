package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class ZaiCollector : ProviderCollector {
    override val kind = ProviderKind.Zai

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("https://api.z.ai/api/monitor/usage/quota/limit")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("z.ai API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val data = json.optJSONObject("data") ?: json
            val remaining = data.optInt("remaining", 0)
            val quota = data.optInt("quota", 100)

            CollectorResult(
                provider = ProviderKind.Zai,
                remaining = remaining,
                quota = quota,
                confidence = "high",
            )
        }
    }
}
