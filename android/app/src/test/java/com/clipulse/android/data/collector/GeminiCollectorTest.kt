package com.clipulse.android.data.collector

import com.clipulse.android.data.model.ProviderKind
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class GeminiCollectorTest {

    private lateinit var server: MockWebServer
    private lateinit var collector: GeminiCollector

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        collector = GeminiCollector(baseUrl = server.url("/").toString().trimEnd('/'))
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `kind is Gemini`() {
        assertEquals(ProviderKind.Gemini, collector.kind)
    }

    @Test
    fun `collect parses tier and quota response`() = runTest {
        // Tier info response
        server.enqueue(MockResponse().setBody("""
            {"subscriptionPlanType": "PREMIUM"}
        """))
        // Quota response
        server.enqueue(MockResponse().setBody("""
            {
                "quotaBuckets": [
                    {"quotaBucketName": "Daily", "remainingFraction": 0.75, "resetTime": "2026-04-17T00:00:00Z"},
                    {"quotaBucketName": "Monthly", "remainingFraction": 0.90, "resetTime": "2026-05-01T00:00:00Z"}
                ]
            }
        """))

        val result = collector.collect("ya29.test")

        assertEquals(ProviderKind.Gemini, result.provider)
        assertEquals("PREMIUM", result.planType)
        assertEquals(100, result.quota)
        assertEquals(75, result.remaining)
        assertEquals("high", result.confidence)
        assertEquals(2, result.tiers.size)
        assertEquals("Daily", result.tiers[0].name)
        assertEquals(75, result.tiers[0].remaining)
        assertEquals("Monthly", result.tiers[1].name)
        assertEquals(90, result.tiers[1].remaining)
    }

    @Test
    fun `collect handles tier request failure gracefully`() = runTest {
        // Tier info fails
        server.enqueue(MockResponse().setResponseCode(500))
        // Quota succeeds
        server.enqueue(MockResponse().setBody("""
            {"quotaBuckets": [{"quotaBucketName": "Daily", "remainingFraction": 0.5}]}
        """))

        val result = collector.collect("ya29.test")

        assertNull(result.planType)
        assertEquals(1, result.tiers.size)
        assertEquals(50, result.tiers[0].remaining)
    }

    @Test(expected = Exception::class)
    fun `collect throws when quota request fails`() = runTest {
        // Tier OK
        server.enqueue(MockResponse().setBody("{}"))
        // Quota fails
        server.enqueue(MockResponse().setResponseCode(403))

        collector.collect("ya29.test")
    }

    @Test
    fun `collect handles empty quota buckets`() = runTest {
        server.enqueue(MockResponse().setBody("{}"))
        server.enqueue(MockResponse().setBody("""{"quotaBuckets": []}"""))

        val result = collector.collect("ya29.test")

        assertTrue(result.tiers.isEmpty())
        assertNull(result.remaining)
    }
}
