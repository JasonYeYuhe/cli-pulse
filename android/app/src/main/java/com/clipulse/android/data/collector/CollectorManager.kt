package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import com.clipulse.android.data.remote.TokenStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.withContext

class CollectorManager(
    private val tokenStore: TokenStore,
) {
    private val collectors: Map<ProviderKind, ProviderCollector> = mapOf(
        ProviderKind.OpenRouter to OpenRouterCollector(),
        ProviderKind.Zai to ZaiCollector(),
        ProviderKind.KimiK2 to KimiK2Collector(),
        ProviderKind.Warp to WarpCollector(),
        ProviderKind.Kilo to KiloCollector(),
        ProviderKind.MiniMax to MiniMaxCollector(),
        ProviderKind.Copilot to CopilotCollector(),
        ProviderKind.Alibaba to AlibabaCollector(),
        ProviderKind.VolcanoEngine to VolcanoEngineCollector(),
        ProviderKind.Kimi to KimiCollector(),
        ProviderKind.Claude to ClaudeCollector(),
        ProviderKind.Gemini to GeminiCollector(),
        ProviderKind.Codex to CodexCollector(),
        ProviderKind.Cursor to CursorCollector(),
        ProviderKind.Ollama to OllamaCollector(),
        ProviderKind.Augment to AugmentCollector(),
    )

    fun availableCollectors(): List<ProviderKind> =
        collectors.keys.filter { kind ->
            val key = tokenStore.loadProviderKey(kind.displayValue)
            collectors[kind]?.isAvailable(key) == true
        }

    suspend fun collectAll(): List<CollectorResult> = withContext(Dispatchers.IO) {
        collectors.entries
            .filter { (kind, collector) ->
                val key = tokenStore.loadProviderKey(kind.displayValue)
                collector.isAvailable(key)
            }
            .map { (kind, collector) ->
                async {
                    try {
                        val key = tokenStore.loadProviderKey(kind.displayValue) ?: return@async null
                        collector.collect(key)
                    } catch (e: Exception) {
                        // Return a degraded result instead of failing
                        CollectorResult(
                            provider = kind,
                            statusText = "Error: ${e.message?.take(50)}",
                            confidence = "low",
                        )
                    }
                }
            }
            .awaitAll()
            .filterNotNull()
    }

    suspend fun collect(kind: ProviderKind): CollectorResult? {
        val collector = collectors[kind] ?: return null
        val key = tokenStore.loadProviderKey(kind.displayValue) ?: return null
        if (!collector.isAvailable(key)) return null
        return withContext(Dispatchers.IO) {
            collector.collect(key)
        }
    }
}
