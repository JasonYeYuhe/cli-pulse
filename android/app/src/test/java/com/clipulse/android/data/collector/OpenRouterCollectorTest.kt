package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class OpenRouterCollectorTest {

    private lateinit var server: MockWebServer
    private lateinit var collector: OpenRouterCollector

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        collector = OpenRouterCollector(baseUrl = server.url("/").toString().trimEnd('/'))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `kind is OpenRouter`() {
        assertEquals(ProviderKind.OpenRouter, collector.kind)
    }

    @Test
    fun `collect parses credits response`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {
                "data": {
                    "total_credits": 50.0,
                    "total_usage": 12.5
                }
            }
        """))

        val result = collector.collect("sk-or-test")

        assertEquals(ProviderKind.OpenRouter, result.provider)
        assertEquals(37.5, result.credits!!, 0.01)
        assertEquals("Credits", result.planType)
        assertEquals("high", result.confidence)
        assertEquals(5000, result.quota)
        assertEquals(3750, result.remaining)
    }

    @Test
    fun `collect handles zero credits`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {"data": {"total_credits": 0.0, "total_usage": 0.0}}
        """))

        val result = collector.collect("sk-or-test")
        assertEquals(0.0, result.credits!!, 0.01)
    }

    @Test
    fun `collect handles top-level response without data wrapper`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {"total_credits": 100.0, "total_usage": 25.0}
        """))

        val result = collector.collect("sk-or-test")
        assertEquals(75.0, result.credits!!, 0.01)
    }

    @Test(expected = Exception::class)
    fun `collect throws on HTTP error`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401))
        collector.collect("bad-key")
    }

    @Test
    fun `collect sends bearer token`() = runTest {
        server.enqueue(MockResponse().setBody("""{"data":{"total_credits":1,"total_usage":0}}"""))
        collector.collect("my-key")

        val request = server.takeRequest()
        assertEquals("Bearer my-key", request.getHeader("Authorization"))
    }
}
