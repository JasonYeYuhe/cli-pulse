package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Fetches usage summary from Cursor IDE via cookie-based session auth.
 *
 * Endpoint: GET https://cursor.com/api/usage-summary
 * Auth:     Cookie header (session cookies from browser, stored as provider key).
 *
 * NOTE: Cookie-based, unofficial endpoint — treat as experimental.
 */
class CursorCollector : ProviderCollector {
    override val kind = ProviderKind.Cursor

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("https://cursor.com/api/usage-summary")
            .get()
            .addHeader("Cookie", apiKey)
            .addHeader("Accept", "application/json")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Cursor API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")

            val membership = json.optString("membershipType").takeIf { it.isNotBlank() }
            val cycleEnd = json.optString("billingCycleEnd").takeIf { it.isNotBlank() }

            val indiv = json.optJSONObject("individualUsage") ?: JSONObject()
            val plan = indiv.optJSONObject("plan") ?: JSONObject()
            val onDemand = indiv.optJSONObject("onDemand") ?: JSONObject()

            val planUsed = plan.optInt("used", 0)
            val planLimit = plan.optInt("limit", 0)
            val planRemaining = plan.optInt("remaining", planLimit - planUsed)
            val odUsed = onDemand.optInt("used", 0)
            val odLimit = if (onDemand.has("limit")) onDemand.optInt("limit") else null
            val totalPct = if (plan.has("totalPercentUsed")) plan.optDouble("totalPercentUsed") else null

            val tiers = mutableListOf<CollectorTier>()
            if (planLimit > 0) {
                tiers.add(CollectorTier("Plan", planLimit, planRemaining, cycleEnd))
            }
            if (odLimit != null && odLimit > 0) {
                tiers.add(CollectorTier("On-Demand", odLimit, (odLimit - odUsed).coerceAtLeast(0), cycleEnd))
            }

            val pctUsed = totalPct ?: if (planLimit > 0) planUsed.toDouble() / planLimit * 100.0 else 0.0

            CollectorResult(
                provider = kind,
                remaining = planRemaining,
                quota = if (planLimit > 0) planLimit else null,
                planType = membership?.replaceFirstChar { it.uppercase() },
                resetTime = cycleEnd,
                tiers = tiers,
                credits = if (odUsed > 0) odUsed.toDouble() / 100.0 else null,
                statusText = String.format("%.0f%% used", pctUsed),
                confidence = "high",
            )
        }
    }
}
