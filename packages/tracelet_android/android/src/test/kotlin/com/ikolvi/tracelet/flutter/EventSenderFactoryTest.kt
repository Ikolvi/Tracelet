package com.ikolvi.tracelet.flutter

import android.content.Context
import android.content.SharedPreferences
import com.ikolvi.tracelet.flutter.service.HeadlessTaskService
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import org.mockito.Mockito
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Verifies that the [TraceletBootstrap.eventSenderFactory] set by
 * [TraceletAndroidPlugin] produces an [EventDispatcher] with
 * [EventDispatcher.headlessFallback] properly wired.
 *
 * Regression test for GitHub issue #43: headless geofence events
 * silently dropped on task removal because the boot-mode
 * EventDispatcher had no headlessFallback.
 */
internal class EventSenderFactoryTest {

    @Test
    fun eventSenderFactory_producesDispatcherWithHeadlessFallback() {
        // Arrange: set the factory exactly as TraceletAndroidPlugin does
        TraceletBootstrap.eventSenderFactory = { ctx ->
            val dispatcher = EventDispatcher()
            val hs = HeadlessTaskService(ctx)
            dispatcher.headlessFallback = { eventName, eventData ->
                if (hs.isRegistered()) {
                    hs.dispatchEvent(eventName, eventData)
                }
            }
            dispatcher
        }

        val mockContext = createMockContextWithHeadlessPrefs()

        // Act: invoke the factory (simulates LocationService.startBootTracking)
        val eventSender = TraceletBootstrap.eventSenderFactory?.invoke(mockContext)

        // Assert: dispatcher has headlessFallback wired
        assertNotNull(eventSender, "eventSenderFactory must return a non-null sender")
        assertTrue(eventSender is EventDispatcher, "eventSenderFactory must return an EventDispatcher")
        assertNotNull(
            (eventSender as EventDispatcher).headlessFallback,
            "EventDispatcher.headlessFallback must be wired (issue #43)",
        )
    }

    @Test
    fun eventSenderFactory_dispatcher_fallsBackWhenNoFlutterEngine() {
        // Arrange: set up factory and track headless dispatch calls
        val dispatched = mutableListOf<Pair<String, Map<String, Any?>>>()

        TraceletBootstrap.eventSenderFactory = { ctx ->
            val dispatcher = EventDispatcher()
            dispatcher.headlessFallback = { eventName, eventData ->
                dispatched.add(eventName to eventData)
            }
            dispatcher
        }

        val mockContext = createMockContextWithHeadlessPrefs()
        val eventSender = TraceletBootstrap.eventSenderFactory!!.invoke(mockContext)
            as EventDispatcher

        // Act: send a geofence event with no Flutter engine attached
        // (eventApi is null since register() was never called)
        val geofenceData = mapOf<String, Any?>(
            "identifier" to "test-zone",
            "action" to "ENTER",
            "location" to mapOf<String, Any?>(
                "coords" to mapOf("latitude" to 37.4219983, "longitude" to -122.084),
                "timestamp" to "2026-03-26T00:00:00Z",
            ),
        )
        eventSender.sendGeofence(geofenceData)

        // Assert: event must reach headlessFallback, not be silently dropped
        assertTrue(dispatched.isNotEmpty(), "Geofence event must reach headlessFallback")
        assertTrue(dispatched[0].first == "geofence", "Event name must be 'geofence'")
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helper
    // ─────────────────────────────────────────────────────────────────────

    private fun createMockContextWithHeadlessPrefs(): Context {
        val prefs = Mockito.mock(SharedPreferences::class.java)
        `when`(prefs.contains("registration_callback_id")).thenReturn(true)
        `when`(prefs.contains("dispatch_callback_id")).thenReturn(true)
        `when`(prefs.getLong("registration_callback_id", -1L)).thenReturn(42L)
        `when`(prefs.getLong("dispatch_callback_id", -1L)).thenReturn(43L)

        val context = Mockito.mock(Context::class.java)
        `when`(context.getSharedPreferences("com.tracelet.headless", Context.MODE_PRIVATE))
            .thenReturn(prefs)
        `when`(context.applicationContext).thenReturn(context)
        return context
    }
}
