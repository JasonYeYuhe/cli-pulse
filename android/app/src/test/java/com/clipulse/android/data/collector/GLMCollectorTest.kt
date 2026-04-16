package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class GLMCollectorTest {

    private lateinit var server: MockWebServer
    private lateinit var collector: GLMCollector

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        collector = GLMCollector(baseUrl = server.url("/").toString().trimEnd('/'))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `kind is GLM`() {
        assertEquals(ProviderKind.GLM, collector.kind)
    }

    @Test
    fun `isAvailable returns false for null or blank`() {
        assertFalse(collector.isAvailable(null))
        assertFalse(collector.isAvailable(""))
        assertFalse(collector.isAvailable("   "))
    }

    @Test
    fun `collect parses balance response`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {
                "data": {
                    "balance": 156.78,
                    "currency": "CNY"
                }
            }
        """))

        val result = collector.collect("glm-test-key")

        assertEquals(ProviderKind.GLM, result.provider)
        assertEquals(156.78, result.credits!!, 0.01)
        assertEquals("high", result.confidence)
        assertTrue(result.statusText.contains("156.78"))
        assertTrue(result.statusText.contains("CNY"))
    }

    @Test
    fun `collect falls back to models list probe`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {
                "data": [
                    {"id": "glm-4"},
                    {"id": "glm-4-flash"},
                    {"id": "glm-3-turbo"}
                ]
            }
        """))

        val result = collector.collect("glm-test-key")

        assertEquals(ProviderKind.GLM, result.provider)
        assertNull(result.credits)
        assertEquals("medium", result.confidence)
        assertTrue(result.statusText.contains("3 models"))
    }

    @Test
    fun `collect handles empty models list`() = runTest {
        server.enqueue(MockResponse().setBody("""{"data": []}"""))

        val result = collector.collect("glm-test-key")
        assertEquals("Connected", result.statusText)
    }

    @Test
    fun `collect defaults currency to CNY`() = runTest {
        server.enqueue(MockResponse().setBody("""
            {"data": {"balance": 10.0}}
        """))

        val result = collector.collect("glm-test-key")
        assertTrue(result.statusText.contains("CNY"))
    }

    @Test(expected = Exception::class)
    fun `collect throws on HTTP error`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401))
        collector.collect("bad-key")
    }

    @Test
    fun `collect sends correct authorization header`() = runTest {
        server.enqueue(MockResponse().setBody("""{"data":[]}"""))
        collector.collect("my-glm-key")

        val request = server.takeRequest()
        assertEquals("Bearer my-glm-key", request.getHeader("Authorization"))
        assertEquals("/api/paas/v4/models", request.path)
    }
}
