package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class ClaudeCollectorTest {

    private lateinit var server: MockWebServer
    private lateinit var collector: ClaudeCollector

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        collector = ClaudeCollector(baseUrl = server.url("/").toString().trimEnd('/'))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `kind is Claude`() {
        assertEquals(ProviderKind.Claude, collector.kind)
    }

    @Test
    fun `isAvailable returns false for null key`() {
        assertFalse(collector.isAvailable(null))
    }

    @Test
    fun `isAvailable returns false for blank key`() {
        assertFalse(collector.isAvailable("  "))
    }

    @Test
    fun `isAvailable returns true for valid key`() {
        assertTrue(collector.isAvailable("sk-ant-test"))
    }

    @Test
    fun `collect parses usage windows correctly`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {
                "plan_type": "pro",
                "usage_windows": [
                    {"window_name": "5h Window", "limit": 100, "used": 35, "reset_time": "2026-04-16T12:00:00Z"},
                    {"window_name": "Weekly", "limit": 500, "used": 120, "reset_time": "2026-04-20T00:00:00Z"}
                ]
            }
        """))

        val result = collector.collect("sk-test")

        assertEquals(ProviderKind.Claude, result.provider)
        assertEquals("pro", result.planType)
        assertEquals(100, result.quota)
        assertEquals(65, result.remaining)
        assertEquals("high", result.confidence)
        assertEquals(2, result.tiers.size)
        assertEquals("5h Window", result.tiers[0].name)
        assertEquals(65, result.tiers[0].remaining)
        assertEquals("Weekly", result.tiers[1].name)
        assertEquals(380, result.tiers[1].remaining)
    }

    @Test
    fun `collect handles empty usage windows`() = runTest {
        server.enqueue(MockResponse().setBody("""{"plan_type": "free"}"""))

        val result = collector.collect("sk-test")

        assertEquals("free", result.planType)
        assertNull(result.remaining)
        assertNull(result.quota)
        assertTrue(result.tiers.isEmpty())
    }

    @Test
    fun `collect clamps negative remaining to zero`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {
                "usage_windows": [
                    {"window_name": "5h Window", "limit": 100, "used": 150}
                ]
            }
        """))

        val result = collector.collect("sk-test")
        assertEquals(0, result.tiers[0].remaining)
    }

    @Test(expected = Exception::class)
    fun `collect throws on HTTP error`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401))
        collector.collect("bad-key")
    }

    @Test
    fun `collect sends authorization header`() = runTest {
        server.enqueue(MockResponse().setBody("{}"))
        collector.collect("my-token")

        val request = server.takeRequest()
        assertEquals("Bearer my-token", request.getHeader("Authorization"))
    }
}
