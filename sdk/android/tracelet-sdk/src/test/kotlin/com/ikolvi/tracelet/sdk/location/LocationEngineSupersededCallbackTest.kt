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
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
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

/**
 * #432: a continuous callback the engine no longer holds must neither feed the
 * pipeline nor stay registered. Without the guard, a registration that outlived
 * `stop()` delivered fixes until process death, and `changePace(false)` could
 * not reach it because the engine already reported not tracking.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
class LocationEngineSupersededCallbackTest {

    private lateinit var context: Context
    private lateinit var engine: LocationEngine
    private lateinit var client: RegistrationRecordingClient
    private lateinit var events: TraceletEventSender

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application)
            .grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        shadowOf(lm).setProviderEnabled(LocationManager.GPS_PROVIDER, true)

        client = RegistrationRecordingClient()
        TraceletServices.setProvider(SingleClientProvider(client))

        val configManager = mock<ConfigManager>()
        whenever(configManager.getDesiredAccuracy()).thenReturn(0)
        whenever(configManager.getDistanceFilter()).thenReturn(0.0)
        whenever(configManager.getDeferTime()).thenReturn(0)
        whenever(configManager.getLocationUpdateInterval()).thenReturn(5000L)
        whenever(configManager.getFastestLocationUpdateInterval()).thenReturn(2500L)
        whenever(configManager.getMotionDetectionMode())
            .thenReturn(MotionDetectionMode.ACCELEROMETER)
        whenever(configManager.getEnableDeadReckoning()).thenReturn(false)

        events = mock()
        engine = LocationEngine(context, configManager, mock<StateManager>(), events)
    }

    @After
    fun tearDown() {
        engine.stop()
        TraceletServices.setProvider(null)
    }

    private fun fix() = Location("fused").apply {
        latitude = 52.0
        longitude = 4.0
        accuracy = 5f
        time = System.currentTimeMillis()
    }

    @Test
    fun deliveryAfterStopIsDroppedAndUnregistersTheCallback() {
        engine.start()
        val callback = client.registered.single()
        engine.stop()
        assertFalse(engine.isTracking)
        assertEquals(listOf(callback), client.removed)

        callback.onLocationResult(listOf(fix()))

        assertEquals(
            "the stray callback removes itself so it cannot deliver until process death",
            listOf(callback, callback), client.removed,
        )
        verify(events, never()).sendLocation(any())
    }

    @Test
    fun restartLeavesOnlyTheNewCallbackLive() {
        engine.start()
        val first = client.registered[0]
        engine.start()
        val second = client.registered[1]
        assertNotSame(first, second)

        first.onLocationResult(listOf(fix()))
        first.onLocationAvailability(false)

        // `first` was removed by the restart's stop() and again by its own guard;
        // `second` was never touched.
        assertEquals(listOf(first, first, first), client.removed)
        verify(events, never()).sendLocation(any())
        verify(events, never()).sendProviderChange(any())
    }
}

private class RegistrationRecordingClient : TraceletLocationClient {
    val registered = mutableListOf<TraceletLocationCallback>()
    val removed = mutableListOf<TraceletLocationCallback>()

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) {
        if (registered.none { it === callback }) registered += callback
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {
        removed += callback
    }

    override fun getCurrentLocation(
        priority: Int,
        cancellationToken: TraceletCancellationToken?,
        onSuccess: (Location?) -> Unit,
    ) = onSuccess(null)

    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) =
        onSuccess(null)
}

private class SingleClientProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) = mock<com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<com.ikolvi.tracelet.sdk.wrapper.TraceletEventExtractor>()
}
