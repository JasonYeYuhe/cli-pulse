package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class MiniMaxCollector : ProviderCollector {
    override val kind = ProviderKind.MiniMax

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("https://platform.minimax.io/v1/api/openplatform/coding_plan/remains")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("MiniMax API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val data = json.optJSONObject("data") ?: json
            val remaining = data.optInt("remaining", 0)
            val quota = data.optInt("quota", 100)

            CollectorResult(
                provider = ProviderKind.MiniMax,
                remaining = remaining,
                quota = quota,
                confidence = "medium",
            )
        }
    }
}
