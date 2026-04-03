package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class WarpCollector : ProviderCollector {
    override val kind = ProviderKind.Warp

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val graphqlQuery = """{"query":"{ currentUser { aiCreditsRemaining aiCreditsTotal } }"}"""
        val req = Request.Builder()
            .url("https://app.warp.dev/graphql/v2")
            .post(graphqlQuery.toRequestBody("application/json".toMediaType()))
            .addHeader("Authorization", "Bearer $apiKey")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Warp API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val user = json.optJSONObject("data")?.optJSONObject("currentUser") ?: JSONObject()
            val remaining = user.optInt("aiCreditsRemaining", 0)
            val total = user.optInt("aiCreditsTotal", 0)

            CollectorResult(
                provider = ProviderKind.Warp,
                remaining = remaining,
                quota = total,
                planType = "Monthly",
                confidence = "high",
            )
        }
    }
}
