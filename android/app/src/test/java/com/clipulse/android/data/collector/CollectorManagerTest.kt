package com.clipulse.android.data.collector

import com.clipulse.android.MainDispatcherRule
import com.clipulse.android.data.model.ProviderKind
import com.clipulse.android.data.remote.TokenStore
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CollectorManagerTest {

    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val tokenStore = mockk<TokenStore>(relaxed = true)

    @Before
    fun setUp() {
        every { tokenStore.loadProviderKey(any()) } returns null
    }

    @Test
    fun `availableCollectors returns only providers with keys`() {
        every { tokenStore.loadProviderKey("Claude") } returns "sk-test"
        every { tokenStore.loadProviderKey("Codex") } returns "tok-test"

        val manager = CollectorManager(tokenStore)
        val available = manager.availableCollectors()

        assertTrue(available.contains(ProviderKind.Claude))
        assertTrue(available.contains(ProviderKind.Codex))
        assertFalse(available.contains(ProviderKind.Gemini))
    }

    @Test
    fun `availableCollectors returns empty when no keys`() {
        val manager = CollectorManager(tokenStore)
        val available = manager.availableCollectors()

        assertTrue(available.isEmpty())
    }

    @Test
    fun `collect returns null for unknown provider`() = runTest {
        val manager = CollectorManager(tokenStore)
        val result = manager.collect(ProviderKind.Synthetic)

        assertNull(result)
    }

    @Test
    fun `collect returns null when no key available`() = runTest {
        val manager = CollectorManager(tokenStore)
        val result = manager.collect(ProviderKind.Claude)

        assertNull(result)
    }

    @Test
    fun `collectAll returns empty when no providers available`() = runTest {
        val manager = CollectorManager(tokenStore)
        val results = manager.collectAll()

        assertTrue(results.isEmpty())
    }

    @Test
    fun `collectAll returns degraded result on collector exception`() = runTest {
        every { tokenStore.loadProviderKey("OpenRouter") } returns "sk-test"

        val manager = CollectorManager(tokenStore)
        // OpenRouter collector will fail because there's no real server
        // CollectorManager catches the exception and returns a degraded result
        val results = manager.collectAll()

        assertEquals(1, results.size)
        assertEquals(ProviderKind.OpenRouter, results[0].provider)
        assertEquals("low", results[0].confidence)
        assertTrue(results[0].statusText.startsWith("Error:"))
    }

    @Test
    fun `blank api key means provider not available`() {
        every { tokenStore.loadProviderKey("Claude") } returns "  "

        val manager = CollectorManager(tokenStore)
        assertFalse(manager.availableCollectors().contains(ProviderKind.Claude))
    }
}
