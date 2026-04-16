package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class GLMCollector(
    internal val baseUrl: String = "https://open.bigmodel.cn",
) : ProviderCollector {
    override val kind = ProviderKind.GLM

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("$baseUrl/api/paas/v4/models")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Accept", "application/json")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("GLM API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")

            // Balance/credits response
            val dataObj = json.optJSONObject("data")
            if (dataObj != null && dataObj.has("balance")) {
                val balance = dataObj.optDouble("balance", 0.0)
                val currency = dataObj.optString("currency", "CNY")
                return@use CollectorResult(
                    provider = kind,
                    credits = balance,
                    statusText = String.format("%.2f %s remaining", balance, currency),
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
