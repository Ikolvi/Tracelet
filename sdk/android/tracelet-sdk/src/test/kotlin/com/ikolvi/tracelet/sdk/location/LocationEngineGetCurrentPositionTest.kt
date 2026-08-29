package com.ikolvi.tracelet.sdk.location

import android.Manifest
import android.app.Application
import android.location.Location
import android.os.Looper
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
import org.mockito.kotlin.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
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

    @Test
    fun `accuracy target keeps provider warm until quality arrives`() {
        lateinit var updateCallback: TraceletLocationCallback
        doAnswer { invocation ->
            updateCallback = invocation.getArgument(1)
            null
        }.`when`(mockLocationClient).requestLocationUpdates(any(), any(), any())

        var result: Map<String, Any?>? = null
        engine.getCurrentPosition(
            mapOf(
                "timeout" to 30L,
                "samples" to 1,
                "accuracyTarget" to 100.0,
                "requestId" to "quality",
                "persist" to false,
            ),
        ) { result = it }

        updateCallback.onLocationResult(listOf(location(accuracy = 1500f)))
        shadowOf(Looper.getMainLooper()).idle()
        assertNull(result)

        updateCallback.onLocationResult(listOf(location(accuracy = 20f)))
        shadowOf(Looper.getMainLooper()).idle()

        val coords = result?.get("coords") as? Map<*, *>
        assertNotNull(coords)
        assertEquals(20.0, coords["accuracy"])
        verify(mockLocationClient).removeLocationUpdates(updateCallback)
    }

    @Test
    fun `coarse cached fix remains candidate until accuracy target`() {
        lateinit var updateCallback: TraceletLocationCallback
        doAnswer { invocation ->
            updateCallback = invocation.getArgument(1)
            null
        }.`when`(mockLocationClient).requestLocationUpdates(any(), any(), any())
        val cached = location(accuracy = 800f)
        val lastLocationField = LocationEngine::class.java.getDeclaredField("lastLocation")
        lastLocationField.isAccessible = true
        lastLocationField.set(engine, cached)

        var result: Map<String, Any?>? = null
        engine.getCurrentPosition(
            mapOf(
                "maximumAge" to 60_000L,
                "accuracyTarget" to 100.0,
                "requestId" to "quality",
                "persist" to false,
            ),
        ) { result = it }

        assertNull(result)
        updateCallback.onLocationResult(listOf(location(accuracy = 25f)))
        shadowOf(Looper.getMainLooper()).idle()

        val coords = result?.get("coords") as? Map<*, *>
        assertNotNull(coords)
        assertEquals(25.0, coords["accuracy"])
    }

    @Test
    fun `accuracy target timeout returns best coarse candidate`() {
        lateinit var updateCallback: TraceletLocationCallback
        doAnswer { invocation ->
            updateCallback = invocation.getArgument(1)
            null
        }.`when`(mockLocationClient).requestLocationUpdates(any(), any(), any())

        var result: Map<String, Any?>? = null
        engine.getCurrentPosition(
            mapOf(
                "timeout" to 3L,
                "accuracyTarget" to 100.0,
                "requestId" to "quality",
                "persist" to false,
            ),
        ) { result = it }

        updateCallback.onLocationResult(listOf(location(accuracy = 1500f)))
        shadowOf(Looper.getMainLooper()).idleFor(4, TimeUnit.SECONDS)

        val coords = result?.get("coords") as? Map<*, *>
        assertNotNull(coords)
        assertEquals(1500.0, coords["accuracy"])
    }

    @Test
    fun `cancelling quality request stops updates and suppresses late result`() {
        lateinit var updateCallback: TraceletLocationCallback
        doAnswer { invocation ->
            updateCallback = invocation.getArgument(1)
            null
        }.`when`(mockLocationClient).requestLocationUpdates(any(), any(), any())

        var callbackInvoked = false
        engine.getCurrentPosition(
            mapOf(
                "timeout" to 30L,
                "accuracyTarget" to 100.0,
                "requestId" to "quality",
                "persist" to false,
            ),
        ) { callbackInvoked = true }

        assertTrue(engine.cancelCurrentPosition("quality"))
        updateCallback.onLocationResult(listOf(location(accuracy = 5f)))
        shadowOf(Looper.getMainLooper()).idle()

        assertTrue(callbackInvoked)
        verify(mockLocationClient).removeLocationUpdates(updateCallback)
    }

    private fun location(accuracy: Float) = Location("test").apply {
        latitude = 45.0
        longitude = -122.0
        this.accuracy = accuracy
        time = System.currentTimeMillis()
    }
}
