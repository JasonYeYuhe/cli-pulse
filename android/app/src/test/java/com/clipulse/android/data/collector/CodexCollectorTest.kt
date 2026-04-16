package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class CodexCollectorTest {

    private lateinit var server: MockWebServer
    private lateinit var collector: CodexCollector

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        collector = CodexCollector(baseUrl = server.url("/").toString().trimEnd('/'))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `kind is Codex`() {
        assertEquals(ProviderKind.Codex, collector.kind)
    }

    @Test
    fun `isAvailable returns false for null or blank`() {
        assertFalse(collector.isAvailable(null))
        assertFalse(collector.isAvailable(""))
    }

    @Test
    fun `collect parses rate limit windows`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {
                "plan_type": "plus",
                "rate_limit": {
                    "primary_window": {"used_percent": 40, "reset_at": "2026-04-16T15:00:00Z"},
                    "secondary_window": {"used_percent": 10, "reset_at": "2026-04-20T00:00:00Z"}
                }
            }
        """))

        val result = collector.collect("tok-test")

        assertEquals(ProviderKind.Codex, result.provider)
        assertEquals("Plus", result.planType)
        assertEquals(100, result.quota)
        assertEquals(60, result.remaining)
        assertEquals("high", result.confidence)
        assertEquals(2, result.tiers.size)
        assertEquals("5h Window", result.tiers[0].name)
        assertEquals(60, result.tiers[0].remaining)
        assertEquals("Weekly", result.tiers[1].name)
        assertEquals(90, result.tiers[1].remaining)
    }

    @Test
    fun `collect parses credits`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {
                "rate_limit": {},
                "credits": {
                    "has_credits": true,
                    "unlimited": false,
                    "balance": 12.50
                }
            }
        """))

        val result = collector.collect("tok-test")

        assertEquals(12.50, result.credits!!, 0.01)
        assertTrue(result.tiers.any { it.name == "Credits" })
    }

    @Test
    fun `collect skips unlimited credits`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {
                "credits": {"has_credits": true, "unlimited": true, "balance": 0}
            }
        """))

        val result = collector.collect("tok-test")
        assertNull(result.credits)
    }

    @Test(expected = Exception::class)
    fun `collect throws on HTTP error`() = runTest {
        server.enqueue(MockResponse().setResponseCode(403))
        collector.collect("bad-token")
    }
}
