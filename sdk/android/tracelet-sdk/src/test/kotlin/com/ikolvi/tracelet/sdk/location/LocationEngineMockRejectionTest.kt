package com.ikolvi.tracelet.sdk.location

import android.Manifest
import android.app.Application
import android.content.Context
import android.location.Location
import android.os.Build
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationToken
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletEventExtractor
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationCallback
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.TimeUnit

/**
 * `rejectMockLocations` must guard every delivery path, not just continuous
 * tracking's onLocationReceived(): one-shot getCurrentPosition() samples,
 * watchPosition() fixes, and (via the shared top-level isLocationMock) the
 * periodic worker.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.R])
class LocationEngineMockRejectionTest {

    private lateinit var context: Context
    private lateinit var configManager: ConfigManager
    private lateinit var events: TraceletEventSender
    private lateinit var engine: LocationEngine
    private lateinit var client: MockableLocationClient

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application)
            .grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)

        client = MockableLocationClient()
        TraceletServices.setProvider(FakeServicesProvider(client))

        configManager = mock()
        whenever(configManager.getRejectMockLocations()).thenReturn(true)
        whenever(configManager.getMockDetectionLevel()).thenReturn(1)
        whenever(configManager.getDeferTime()).thenReturn(0)
        whenever(configManager.getDesiredAccuracy()).thenReturn(0)

        events = mock()
        engine = LocationEngine(context, configManager, mock<StateManager>(), events)
    }

    @After
    fun tearDown() {
        TraceletServices.setProvider(null)
    }

    private fun mockLocation(): Location {
        val location = Location("gps").apply {
            latitude = 12.34
            longitude = 56.78
            accuracy = 5f
            time = System.currentTimeMillis()
            elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
        }
        Location::class.java
            .getMethod("setIsFromMockProvider", Boolean::class.javaPrimitiveType)
            .invoke(location, true)
        return location
    }

    @Test
    fun sharedDetectorFlagsPlatformMockFlag() {
        val location = mockLocation()
        assertTrue(isLocationMock(location, level = 1, deferTimeMs = 0, context = context))
        // Level 0 disables detection entirely.
        assertFalse(isLocationMock(location, level = 0, deferTimeMs = 0, context = context))
    }

    @Test
    fun watchPositionDropsMockFixes() {
        val watchId = engine.watchPosition(
            mapOf("interval" to 1000L, "distanceFilter" to 0f, "desiredAccuracy" to 0)
        )
        assertTrue(watchId >= 0)

        client.lastCallback!!.onLocationResult(listOf(mockLocation()))

        verify(events, never()).sendWatchPosition(any())
    }

    @Test
    fun getCurrentPositionRejectsMockSamples() {
        client.currentLocationResult = mockLocation()

        var delivered: Map<String, Any?>? = mapOf("sentinel" to true)
        engine.getCurrentPosition(mapOf("timeout" to 1L, "persist" to false)) {
            delivered = it
        }

        // Drive the retry loop (800ms between samples) past the 1s timeout.
        shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS)

        // Every sample was a rejected mock and there is no vetted lastLocation
        // fallback — the request must resolve to null, not a spoofed fix.
        assertNull(delivered)
    }
}

private class MockableLocationClient : TraceletLocationClient {
    var currentLocationResult: Location? = null
    var lastCallback: TraceletLocationCallback? = null

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) {
        lastCallback = callback
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {}

    override fun getCurrentLocation(
        priority: Int,
        cancellationToken: TraceletCancellationToken?,
        onSuccess: (Location?) -> Unit,
    ) = onSuccess(currentLocationResult)

    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) =
        onSuccess(null)
}

private class FakeServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) = mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
