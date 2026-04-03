package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class AlibabaCollector : ProviderCollector {
    override val kind = ProviderKind.Alibaba

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        // Try international endpoint first, fallback to China
        val baseUrl = if (apiKey.startsWith("cn-")) {
            "https://dashscope.aliyuncs.com"
        } else {
            "https://dashscope-intl.aliyuncs.com"
        }

        val req = Request.Builder()
            .url("$baseUrl/api/v1/usage")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Alibaba API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val remaining = json.optInt("remaining", 0)
            val quota = json.optInt("quota", 0)

            CollectorResult(
                provider = ProviderKind.Alibaba,
                remaining = remaining,
                quota = quota,
                confidence = "medium",
            )
        }
    }
}
