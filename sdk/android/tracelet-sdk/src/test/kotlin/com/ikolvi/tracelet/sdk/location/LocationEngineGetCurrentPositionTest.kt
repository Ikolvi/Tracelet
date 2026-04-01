package com.ikolvi.tracelet.sdk.location

import android.Manifest
import android.app.Application
import android.location.Location
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.tasks.Tasks
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.db.TraceletDatabase
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.Mockito.doReturn
import org.mockito.kotlin.anyOrNull
import org.mockito.kotlin.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * Tests [LocationEngine.getCurrentPosition] fallback behavior when
 * FusedLocationProviderClient.getCurrentLocation() returns null (e.g. emulator).
 *
 * Issue: https://github.com/Ikolvi/Tracelet/issues/46
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class LocationEngineGetCurrentPositionTest {

    private lateinit var context: Application
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var db: TraceletDatabase
    private lateinit var engine: LocationEngine
    private lateinit var mockFusedClient: FusedLocationProviderClient

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        // Grant location permission so hasPermission() returns true
        val shadowApp = shadowOf(context)
        shadowApp.grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)

        config = ConfigManager.getInstance(context)
        state = StateManager(context)
        db = TraceletDatabase.getInstance(context)
        engine = LocationEngine(context, config, state, ListenerEventSender(), db)

        // Replace the private fusedClient with a mock
        mockFusedClient = mock()
        val field = LocationEngine::class.java.getDeclaredField("fusedClient")
        field.isAccessible = true
        field.set(engine, mockFusedClient)
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
    }

    // =====================================================================
    // Single-sample fallback
    // =====================================================================

    @Test
    fun `getCurrentPosition returns lastLocation when single sample returns null`() {
        // Arrange: fusedClient.getCurrentLocation returns null (emulator)
        doReturn(Tasks.forResult<Location>(null))
            .`when`(mockFusedClient).getCurrentLocation(anyInt(), anyOrNull())

        // Seed a lastLocation via reflection
        val fallback = Location("test").apply {
            latitude = 48.8566
            longitude = 2.3522
            accuracy = 25f
            time = System.currentTimeMillis()
            elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
        }
        val lastLocationField = LocationEngine::class.java.getDeclaredField("lastLocation")
        lastLocationField.isAccessible = true
        lastLocationField.set(engine, fallback)

        // Act
        val latch = CountDownLatch(1)
        var result: Map<String, Any?>? = null
        engine.getCurrentPosition(mapOf("timeout" to 5L, "persist" to false)) { loc ->
            result = loc
            latch.countDown()
        }

        // Advance the looper through the full collectSamples timeout.
        // Since 1.8.6, samples==1 routes through collectSamples which uses
        // postDelayed for retry (800ms) and timeout (5s). We must advance
        // far enough for the timeout + retry attempts to complete.
        val shadow = shadowOf(android.os.Looper.getMainLooper())
        shadow.idleFor(6, TimeUnit.SECONDS)
        latch.await(2, TimeUnit.SECONDS)

        // Assert: should get a location, not null
        assertNotNull(result, "Expected fallback to lastLocation but got null (LOCATION_UNAVAILABLE)")
        val coords = result!!["coords"] as Map<*, *>
        assertEquals(48.8566, coords["latitude"])
        assertEquals(2.3522, coords["longitude"])
    }

    @Test
    fun `getCurrentPosition returns null when no lastLocation and single sample returns null`() {
        // Arrange: fusedClient returns null, no lastLocation seeded
        doReturn(Tasks.forResult<Location>(null))
            .`when`(mockFusedClient).getCurrentLocation(anyInt(), anyOrNull())

        // Act
        val latch = CountDownLatch(1)
        var result: Map<String, Any?>? = null
        var callbackInvoked = false
        engine.getCurrentPosition(mapOf("timeout" to 5L, "persist" to false)) { loc ->
            result = loc
            callbackInvoked = true
            latch.countDown()
        }

        // Advance the looper through the full collectSamples timeout.
        val shadow = shadowOf(android.os.Looper.getMainLooper())
        shadow.idleFor(6, TimeUnit.SECONDS)
        latch.await(2, TimeUnit.SECONDS)

        // Assert: null is expected when there's truly no location available
        assert(callbackInvoked) { "Callback was never invoked" }
        assertNull(result)
    }

    // =====================================================================
    // Multi-sample (collectSamples) fallback
    // =====================================================================

    @Test
    fun `getCurrentPosition with samples falls back to lastLocation when all samples return null`() {
        // Arrange: fusedClient.getCurrentLocation always returns null
        doReturn(Tasks.forResult<Location>(null))
            .`when`(mockFusedClient).getCurrentLocation(anyInt(), anyOrNull())

        // Seed lastLocation
        val fallback = Location("test").apply {
            latitude = 41.9028
            longitude = 12.4964
            accuracy = 30f
            time = System.currentTimeMillis()
            elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
        }
        val lastLocationField = LocationEngine::class.java.getDeclaredField("lastLocation")
        lastLocationField.isAccessible = true
        lastLocationField.set(engine, fallback)

        // Act: request 3 samples with short timeout
        val latch = CountDownLatch(1)
        var result: Map<String, Any?>? = null
        engine.getCurrentPosition(
            mapOf("timeout" to 3L, "samples" to 3, "persist" to false)
        ) { loc ->
            result = loc
            latch.countDown()
        }

        // Advance the looper enough for timeout + retries
        val shadow = shadowOf(android.os.Looper.getMainLooper())
        shadow.idleFor(4, TimeUnit.SECONDS)
        latch.await(2, TimeUnit.SECONDS)

        // Assert: should fallback to lastLocation, not null
        assertNotNull(result, "Expected fallback to lastLocation but got null (LOCATION_UNAVAILABLE)")
        val coords = result!!["coords"] as Map<*, *>
        assertEquals(41.9028, coords["latitude"])
        assertEquals(12.4964, coords["longitude"])
    }
}
