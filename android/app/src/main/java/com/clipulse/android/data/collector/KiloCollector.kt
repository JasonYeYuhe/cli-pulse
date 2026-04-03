package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class KiloCollector : ProviderCollector {
    override val kind = ProviderKind.Kilo

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        // tRPC batch call
        val batchBody = JSONObject().apply {
            put("0", JSONObject().apply {
                put("json", JSONObject())
            })
        }
        val req = Request.Builder()
            .url("https://app.kilo.ai/api/trpc/user.getQuota?batch=1&input=${batchBody}")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Kilo API error: ${r.code}")
            val text = r.body?.string() ?: "[]"
            val arr = JSONArray(text)
            val result = arr.optJSONObject(0)?.optJSONObject("result")?.optJSONObject("data")?.optJSONObject("json")
                ?: JSONObject()
            val remaining = result.optInt("remaining", 0)
            val quota = result.optInt("quota", 0)

            CollectorResult(
                provider = ProviderKind.Kilo,
                remaining = remaining,
                quota = quota,
                confidence = "high",
            )
        }
    }
}
