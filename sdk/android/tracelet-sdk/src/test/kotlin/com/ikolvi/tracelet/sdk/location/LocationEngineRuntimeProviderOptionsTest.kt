package com.ikolvi.tracelet.sdk.location

import android.Manifest
import android.app.Application
import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.model.MotionDetectionMode
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationToken
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationCallback
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationPriority
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Android mirror of the iOS LocationEngineRuntimeProviderOptionsTests: the
 * live provider override must swap the fused request in place — same tracking
 * callback, no removeLocationUpdates — restore configured values when cleared,
 * reject invalid filters, and be cleared by stop().
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
class LocationEngineRuntimeProviderOptionsTest {

    private lateinit var context: Context
    private lateinit var configManager: ConfigManager
    private lateinit var engine: LocationEngine
    private lateinit var client: RecordingLocationClient

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application)
            .grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        shadowOf(lm).setProviderEnabled(LocationManager.GPS_PROVIDER, true)

        client = RecordingLocationClient()
        TraceletServices.setProvider(RecordingServicesProvider(client))

        configManager = mock()
        whenever(configManager.getDesiredAccuracy()).thenReturn(0)
        whenever(configManager.getDistanceFilter()).thenReturn(10.0)
        whenever(configManager.getDeferTime()).thenReturn(0)
        whenever(configManager.getLocationUpdateInterval()).thenReturn(1000L)
        whenever(configManager.getFastestLocationUpdateInterval()).thenReturn(500L)
        whenever(configManager.getMotionDetectionMode())
            .thenReturn(MotionDetectionMode.ACCELEROMETER)
        whenever(configManager.getEnableDeadReckoning()).thenReturn(false)

        engine = LocationEngine(context, configManager, mock<StateManager>(), mock<TraceletEventSender>())
    }

    @After
    fun tearDown() {
        engine.stop()
        TraceletServices.setProvider(null)
    }

    @Test
    fun appliesLiveProviderOptionsWithoutDroppingCallback() {
        engine.start()
        assertEquals(1, client.requests.size)
        assertEquals(TraceletLocationPriority.PRIORITY_HIGH_ACCURACY, client.requests[0].priority)
        assertEquals(10f, client.requests[0].minUpdateDistanceMeters)

        assertTrue(engine.updateLocationProviderOptions(1, 25.0))

        assertEquals(2, client.requests.size)
        assertEquals(TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY, client.requests[1].priority)
        assertEquals(25f, client.requests[1].minUpdateDistanceMeters)
        assertSame(client.callbacks[0], client.callbacks[1])
        assertEquals(0, client.removeCount)
    }

    @Test
    fun nullOptionsRestoreConfiguredProviderValues() {
        engine.start()
        assertTrue(engine.updateLocationProviderOptions(1, 25.0))

        assertTrue(engine.updateLocationProviderOptions(null, null))

        val restored = client.requests.last()
        assertEquals(TraceletLocationPriority.PRIORITY_HIGH_ACCURACY, restored.priority)
        assertEquals(10f, restored.minUpdateDistanceMeters)
        assertEquals(0, client.removeCount)
    }

    @Test
    fun stopClearsRuntimeProviderOverride() {
        engine.start()
        assertTrue(engine.updateLocationProviderOptions(1, 25.0))

        engine.stop()
        engine.start()

        val fresh = client.requests.last()
        assertEquals(TraceletLocationPriority.PRIORITY_HIGH_ACCURACY, fresh.priority)
        assertEquals(10f, fresh.minUpdateDistanceMeters)
    }

    @Test
    fun rejectsInvalidFilterAndInactiveTracking() {
        assertFalse(engine.updateLocationProviderOptions(1, 25.0))
        assertEquals(0, client.requests.size)

        engine.start()
        assertFalse(engine.updateLocationProviderOptions(1, Double.NaN))
        assertFalse(engine.updateLocationProviderOptions(1, -5.0))
        assertEquals(1, client.requests.size)
    }
}

private class RecordingLocationClient : TraceletLocationClient {
    val requests = mutableListOf<TraceletLocationRequest>()
    val callbacks = mutableListOf<TraceletLocationCallback>()
    var removeCount = 0

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) {
        requests += request
        callbacks += callback
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {
        removeCount++
    }

    override fun getCurrentLocation(
        priority: Int,
        cancellationToken: TraceletCancellationToken?,
        onSuccess: (Location?) -> Unit,
    ) = onSuccess(null)

    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) =
        onSuccess(null)
}

private class RecordingServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) = mock<com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<com.ikolvi.tracelet.sdk.wrapper.TraceletEventExtractor>()
}
