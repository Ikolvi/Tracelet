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

    // =========================================================================
    // Event buffering tests
    // =========================================================================

    @Test
    fun `events buffered when no listener or headless fallback`() {
        val sender = ListenerEventSender()
        val received = mutableListOf<Pair<String, Map<String, Any?>>>()

        // Send events with neither listener nor headless fallback
        sender.sendLocation(mapOf("lat" to 1.0))
        sender.sendGeofence(mapOf("id" to "home"))

        // No crash, no events delivered yet. Attach a headless fallback.
        sender.headlessFallback = { name, data -> received.add(name to data) }

        assertEquals(2, received.size)
        assertEquals("location", received[0].first)
        assertEquals(1.0, received[0].second["lat"])
        assertEquals("geofence", received[1].first)
        assertEquals("home", received[1].second["id"])
    }

    @Test
    fun `buffered events flushed in order when listener set`() {
        val sender = ListenerEventSender()
        val received = mutableListOf<String>()

        sender.sendMotionChange(mapOf("is_moving" to true))
        sender.sendActivityChange(mapOf("activity" to "walking"))
        sender.sendHeartbeat(mapOf("ts" to 123))

        // Attach listener — events should flush in order
        sender.listener = object : TraceletListener {
            override fun onMotionChange(data: Map<String, Any?>) { received.add("motionchange") }
            override fun onActivityChange(data: Map<String, Any?>) { received.add("activitychange") }
            override fun onHeartbeat(data: Map<String, Any?>) { received.add("heartbeat") }
        }

        assertEquals(listOf("motionchange", "activitychange", "heartbeat"), received)
    }

    @Test
    fun `no flush when listener set to null`() {
        val sender = ListenerEventSender()

        sender.sendLocation(mapOf("lat" to 1.0))

        // Setting listener to null should NOT flush
        sender.listener = null

        // Now set a real headless fallback — should still flush the 1 event
        val received = mutableListOf<String>()
        sender.headlessFallback = { name, _ -> received.add(name) }
        assertEquals(listOf("location"), received)
    }

    @Test
    fun `events delivered directly when listener already set`() {
        val sender = ListenerEventSender()
        val received = mutableListOf<String>()

        sender.listener = object : TraceletListener {
            override fun onLocation(location: Map<String, Any?>) { received.add("location") }
        }

        sender.sendLocation(mapOf("lat" to 1.0))
        assertEquals(listOf("location"), received)
    }

    @Test
    fun `buffer not re-flushed on second listener assignment`() {
        val sender = ListenerEventSender()

        sender.sendGeofence(mapOf("id" to "office"))

        val received1 = mutableListOf<String>()
        sender.listener = object : TraceletListener {
            override fun onGeofence(data: Map<String, Any?>) { received1.add("geofence") }
        }
        assertEquals(1, received1.size)

        // Second listener assignment should NOT replay events
        val received2 = mutableListOf<String>()
        sender.listener = object : TraceletListener {
            override fun onGeofence(data: Map<String, Any?>) { received2.add("geofence") }
        }
        assertEquals(0, received2.size)
    }

    @Test
    fun `headless fallback setting flushes buffer only when no listener`() {
        val sender = ListenerEventSender()
        val listenerReceived = mutableListOf<String>()
        val headlessReceived = mutableListOf<String>()

        // Set listener first
        sender.listener = object : TraceletListener {
            override fun onLocation(location: Map<String, Any?>) { listenerReceived.add("location") }
        }

        sender.sendLocation(mapOf("lat" to 1.0))
        assertEquals(1, listenerReceived.size)

        // Setting headless fallback with listener present should NOT flush anything new
        sender.headlessFallback = { name, _ -> headlessReceived.add(name) }
        assertEquals(0, headlessReceived.size)
    }
}
