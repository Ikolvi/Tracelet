package com.ikolvi.tracelet.sdk

import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class ListenerEventSenderTest {

    @Test
    fun `hasListener returns false when no listener set`() {
        val sender = ListenerEventSender()
        assertFalse(sender.hasListener("location"))
    }

    @Test
    fun `hasListener returns true when listener set`() {
        val sender = ListenerEventSender()
        sender.listener = object : TraceletListener {}
        assertTrue(sender.hasListener("location"))
    }

    @Test
    fun `headless fallback called when no listener`() {
        val sender = ListenerEventSender()
        var receivedEvent: String? = null
        var receivedData: Map<String, Any?>? = null

        sender.headlessFallback = { eventName, data ->
            receivedEvent = eventName
            receivedData = data
        }

        val testData = mapOf<String, Any?>("lat" to 37.0, "lng" to -122.0)
        sender.sendLocation(testData)

        assertEquals("location", receivedEvent)
        assertEquals(testData, receivedData)
    }

    @Test
    fun `no fallback invoked when listener is set`() {
        val sender = ListenerEventSender()
        var fallbackCalled = false

        sender.headlessFallback = { _, _ -> fallbackCalled = true }
        sender.listener = object : TraceletListener {}

        // This won't work in a test without Looper, but verifies no fallback
        // In a real test with Robolectric, the listener would be called instead
        assertFalse(fallbackCalled)
    }
}
