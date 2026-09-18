package com.ikolvi.tracelet.sdk.location

import android.Manifest
import android.app.Application
import android.location.Location
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.wrapper.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.kotlin.any
import org.mockito.kotlin.anyOrNull
import org.mockito.kotlin.doAnswer
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.times
import org.mockito.kotlin.verify
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
    private lateinit var engine: LocationEngine
    private lateinit var mockLocationClient: TraceletLocationClient

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        // Grant location permission so hasPermission() returns true
        val shadowApp = shadowOf(context)
        shadowApp.grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)

        config = ConfigManager.getInstance(context)
        state = StateManager(context)

        mockLocationClient = mock()
        
        // Inject mock provider before creating engine
        val mockProvider = object : TraceletServicesProvider {
            override fun getLocationClient(context: android.content.Context) = mockLocationClient
            override fun getGeofencingClient(context: android.content.Context) = mock<TraceletGeofencingClient>()
            override fun getActivityRecognitionClient(context: android.content.Context) = mock<TraceletActivityRecognitionClient>()
            override fun getEventExtractor() = mock<TraceletEventExtractor>()
        }
        TraceletServices.setProvider(mockProvider)

        engine = LocationEngine(context, config, state, ListenerEventSender())
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
        // Reset provider to default
        try {
            val field = TraceletServices::class.java.getDeclaredField("provider")
            field.isAccessible = true
            field.set(null, null)
        } catch (_: Exception) {}
    }

    // =====================================================================
    // Single-sample fallback
    // =====================================================================

    @Test
    fun `getCurrentPosition returns lastLocation when single sample returns null`() {
        // Arrange: fusedClient.getCurrentLocation invokes onSuccess with null (emulator)
        doAnswer { invocation ->
            val onSuccess = invocation.getArgument<(Location?) -> Unit>(2)
            onSuccess(null)
            null
        }.`when`(mockLocationClient).getCurrentLocation(anyInt(), anyOrNull(), any())

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
        // Arrange: fusedClient invokes onSuccess with null
        doAnswer { invocation ->
            val onSuccess = invocation.getArgument<(Location?) -> Unit>(2)
            onSuccess(null)
            null
        }.`when`(mockLocationClient).getCurrentLocation(anyInt(), anyOrNull(), any())

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
        // Arrange: fusedClient.getCurrentLocation always invokes onSuccess with null
        doAnswer { invocation ->
            val onSuccess = invocation.getArgument<(Location?) -> Unit>(2)
            onSuccess(null)
            null
        }.`when`(mockLocationClient).getCurrentLocation(anyInt(), anyOrNull(), any())

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

    // =====================================================================
    // skipCache
    // =====================================================================

    @Test
    fun `getLastKnownLocation with skipCache ignores lastLocation cache`() {
        // Arrange
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

        doAnswer { invocation ->
            val onSuccess = invocation.getArgument<(Location?) -> Unit>(0)
            val mockLoc = Location("test").apply { 
                latitude = 1.0
                longitude = 1.0 
                time = System.currentTimeMillis()
                elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
            }
            onSuccess(mockLoc)
            null
        }.`when`(mockLocationClient).getLastLocation(any(), any())

        // Act
        var result: Map<String, Any?>? = null
        engine.getLastKnownLocation(mapOf("skipCache" to true)) { loc ->
            result = loc
        }

        // Assert
        assertNotNull(result)
        val coords = result!!["coords"] as Map<*, *>
        assertEquals(1.0, coords["latitude"])
    }

    // =====================================================================
    // #416 — a fresh fix comes from a continuous request, and every exit
    // unregisters it
    // =====================================================================

    private fun fix(lat: Double, lon: Double, acc: Float, provider: String = "gps"): Location =
        Location(provider).apply {
            latitude = lat
            longitude = lon
            accuracy = acc
            time = System.currentTimeMillis()
            elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
        }

    /** Stubs the one-shot to answer [location] on every call — null is the reported device. */
    private fun oneShotAlwaysReturns(location: Location?) {
        doAnswer { invocation ->
            invocation.getArgument<(Location?) -> Unit>(2)(location)
            null
        }.`when`(mockLocationClient).getCurrentLocation(anyInt(), anyOrNull(), any())
    }

    /** Stubs the continuous request to deliver [locations] as soon as it is registered. */
    private fun streamDeliversOnRegistration(vararg locations: Location) {
        doAnswer { invocation ->
            val cb = invocation.getArgument<TraceletLocationCallback>(1)
            if (locations.isNotEmpty()) cb.onLocationResult(locations.toList())
            null
        }.`when`(mockLocationClient).requestLocationUpdates(any(), any(), any())
    }

    private fun runGetCurrentPosition(options: Map<String, Any?>, idleSeconds: Long): Map<String, Any?>? {
        val latch = CountDownLatch(1)
        var result: Map<String, Any?>? = null
        engine.getCurrentPosition(options) { loc ->
            result = loc
            latch.countDown()
        }
        shadowOf(android.os.Looper.getMainLooper()).idleFor(idleSeconds, TimeUnit.SECONDS)
        latch.await(2, TimeUnit.SECONDS)
        return result
    }

    /**
     * The reported scenario: the one-shot answers null on every retry, so
     * before #416 the request spun for the whole timeout and fell back. A
     * continuous request delivers the fresh fix, and it is the answer.
     */
    @Test
    fun `a fix from the continuous request answers when the one-shot returns nothing`() {
        oneShotAlwaysReturns(null)
        streamDeliversOnRegistration(fix(51.5074, -0.1278, 8f))

        val result = runGetCurrentPosition(mapOf("timeout" to 5L, "persist" to false), idleSeconds = 1)

        assertNotNull(result, "the continuous request's fix should have answered")
        val coords = result!!["coords"] as Map<*, *>
        assertEquals(51.5074, coords["latitude"])
        verify(mockLocationClient, times(1)).removeLocationUpdates(any())
    }

    /**
     * The other device: the continuous request is throttled and delivers
     * nothing, and the one-shot is what answers — the reason it stayed.
     */
    @Test
    fun `a fix from the one-shot answers when the continuous request delivers nothing`() {
        oneShotAlwaysReturns(fix(35.6762, 139.6503, 12f))
        streamDeliversOnRegistration(/* nothing */)

        val result = runGetCurrentPosition(mapOf("timeout" to 5L, "persist" to false), idleSeconds = 1)

        assertNotNull(result)
        val coords = result!!["coords"] as Map<*, *>
        assertEquals(35.6762, coords["latitude"])
        verify(mockLocationClient, times(1)).removeLocationUpdates(any())
    }

    /** A one-shot operation must not leave the provider running on timeout either. */
    @Test
    fun `timing out with no fix unregisters the continuous request`() {
        oneShotAlwaysReturns(null)
        streamDeliversOnRegistration(/* nothing */)

        val result = runGetCurrentPosition(mapOf("timeout" to 2L, "persist" to false), idleSeconds = 3)

        assertNull(result)
        verify(mockLocationClient, times(1)).removeLocationUpdates(any())
    }

    /**
     * Both sources can hand over the same fix. `samples` means distinct fixes,
     * so the request must keep waiting for a second one rather than finishing
     * on a duplicate.
     */
    @Test
    fun `the same fix from both sources counts once toward samples`() {
        val shared = fix(40.7128, -74.0060, 10f)
        oneShotAlwaysReturns(shared)
        streamDeliversOnRegistration(shared)

        var result: Map<String, Any?>? = null
        var completions = 0
        engine.getCurrentPosition(
            mapOf("timeout" to 2L, "samples" to 2, "persist" to false)
        ) { loc ->
            result = loc
            completions++
        }
        val looper = shadowOf(android.os.Looper.getMainLooper())

        // One distinct fix, delivered by both sources and re-delivered by the
        // one-shot every 800 ms: without the dedupe this completes right here.
        looper.idleFor(1, TimeUnit.SECONDS)
        assertEquals(0, completions, "a duplicate fix must not satisfy samples=2")

        looper.idleFor(2, TimeUnit.SECONDS)
        assertEquals(1, completions, "the timeout completes it, once")
        assertNotNull(result)
        verify(mockLocationClient, times(1)).removeLocationUpdates(any())
    }

    /** The continuous request is registered at all — this is the whole fix. */
    @Test
    fun `getCurrentPosition registers a continuous request`() {
        oneShotAlwaysReturns(null)
        streamDeliversOnRegistration(/* nothing */)

        runGetCurrentPosition(mapOf("timeout" to 1L, "persist" to false), idleSeconds = 2)

        verify(mockLocationClient, times(1)).requestLocationUpdates(any(), any(), any())
        verify(mockLocationClient, never()).getLastLocation(any(), any())
    }
}
