package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Fetches rate-limit / credit data from Codex (OpenAI ChatGPT).
 *
 * Endpoint: GET https://chatgpt.com/backend-api/wham/usage
 * Auth:     Bearer token (OAuth access token from ~/.codex/auth.json on desktop,
 *           stored as provider key on Android).
 *
 * NOTE: This uses an unofficial endpoint — treat as experimental.
 */
class CodexCollector : ProviderCollector {
    override val kind = ProviderKind.Codex

    override fun isAvailable(apiKey: String?): Boolean = !apiKey.isNullOrBlank()

    override suspend fun collect(apiKey: String): CollectorResult {
        val client = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder()
            .url("https://chatgpt.com/backend-api/wham/usage")
            .get()
            .addHeader("Authorization", "Bearer $apiKey")
            .addHeader("Accept", "application/json")
            .addHeader("User-Agent", "CLIPulse-Android")
            .build()

        val resp = client.newCall(req).execute()
        return resp.use { r ->
            if (!r.isSuccessful) throw Exception("Codex API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")

            val planType = json.optString("plan_type").takeIf { it.isNotBlank() }
            val tiers = mutableListOf<CollectorTier>()

            // Parse rate limit windows
            val rateLimit = json.optJSONObject("rate_limit")
            parseLimitWindow(rateLimit?.optJSONObject("primary_window"), "5h Window")?.let { tiers.add(it) }
            parseLimitWindow(rateLimit?.optJSONObject("secondary_window"), "Weekly")?.let { tiers.add(it) }

            // Parse credits
            val credits = json.optJSONObject("credits")
            var creditBalance: Double? = null
            if (credits != null && credits.optBoolean("has_credits", false) && !credits.optBoolean("unlimited", false)) {
                val balance = credits.optDouble("balance", 0.0)
                creditBalance = balance
                val balanceUnits = (balance * 100_000).toInt()
                tiers.add(CollectorTier("Credits", balanceUnits, balanceUnits, null))
            }

            val primary = tiers.firstOrNull()
            CollectorResult(
                provider = kind,
                remaining = primary?.remaining,
                quota = primary?.quota,
                planType = planType?.replaceFirstChar { it.uppercase() },
                resetTime = primary?.resetTime,
                tiers = tiers,
                credits = creditBalance,
                statusText = primary?.let { "${((it.quota - it.remaining) * 100) / it.quota.coerceAtLeast(1)}% used" } ?: "Operational",
                confidence = "high",
            )
        }
    }

    private fun parseLimitWindow(window: JSONObject?, name: String): CollectorTier? {
        if (window == null) return null
        val usedPercent = window.optInt("used_percent", 0)
        val resetAt = window.optString("reset_at").takeIf { it.isNotBlank() }
        // Percentage-based: quota=100, remaining=100-used
        return CollectorTier(name, 100, (100 - usedPercent).coerceAtLeast(0), resetAt)
    }
}
