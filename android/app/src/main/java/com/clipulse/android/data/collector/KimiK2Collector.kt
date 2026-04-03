package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class KimiK2Collector : ProviderCollector {
    override val kind = ProviderKind.KimiK2

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("https://kimi-k2.ai/api/user/credits")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Kimi K2 API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val balance = json.optDouble("balance", 0.0)
            val total = json.optDouble("total", 100.0)

            CollectorResult(
                provider = ProviderKind.KimiK2,
                remaining = (balance * 100).toInt(),
                quota = (total * 100).toInt(),
                credits = balance,
                planType = "Credits",
                confidence = "high",
            )
        }
    }
}
