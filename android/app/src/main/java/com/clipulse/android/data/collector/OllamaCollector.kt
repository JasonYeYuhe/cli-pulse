package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Checks an Ollama server for installed/running models.
 *
 * Endpoints: GET {host}/api/tags   (list all models)
 *            GET {host}/api/ps     (running models)
 * Auth:      None — the "apiKey" field is the host URL (e.g. "http://192.168.1.5:11434").
 *
 * Status-only collector: Ollama has no quota model.
 */
class OllamaCollector : ProviderCollector {
    override val kind = ProviderKind.Ollama

    override fun isAvailable(apiKey: String?): Boolean =
        !apiKey.isNullOrBlank() && apiKey.startsWith("http")

    override suspend fun collect(apiKey: String): CollectorResult {
        val host = apiKey.trimEnd('/')
        val client = OkHttpClient.Builder()
            .connectTimeout(3, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .build()

        // Fetch model list
        val tagsReq = Request.Builder().url("$host/api/tags").get().build()
        val tagsResp = client.newCall(tagsReq).execute()
        val models = tagsResp.use { r ->
            if (!r.isSuccessful) throw Exception("Ollama API error: ${r.code}")
            val json = JSONObject(r.body?.string() ?: "{}")
            val arr = json.optJSONArray("models") ?: return@use emptyList()
            (0 until arr.length()).mapNotNull { i ->
                arr.getJSONObject(i).optString("name").takeIf { it.isNotBlank() }
            }
        }

        // Fetch running models (non-fatal)
        val running = try {
            val psReq = Request.Builder().url("$host/api/ps").get().build()
            val psResp = client.newCall(psReq).execute()
            psResp.use { r ->
                if (!r.isSuccessful) return@use emptyList()
                val json = JSONObject(r.body?.string() ?: "{}")
                val arr = json.optJSONArray("models") ?: return@use emptyList()
                (0 until arr.length()).mapNotNull { i ->
                    arr.getJSONObject(i).optString("name").takeIf { it.isNotBlank() }
                }
            }
        } catch (_: Exception) {
            emptyList()
        }

        val statusText = if (running.isEmpty()) {
            "${models.size} models installed"
        } else {
            "${running.size} running, ${models.size} installed"
        }

        CollectorResult(
            provider = kind,
            remaining = null,
            quota = null,
            planType = "Local",
            resetTime = null,
            tiers = emptyList(),
            statusText = statusText,
            confidence = "low",
        )
    }
}
