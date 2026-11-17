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
import com.ikolvi.tracelet.sdk.model.StationaryTrackingMode
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationToken
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationCallback
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationPriority
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import java.util.concurrent.TimeUnit
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
    private lateinit var state: StateManager
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

        state = mock()
        engine = LocationEngine(context, configManager, state, mock<TraceletEventSender>())
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
    fun stationaryContinuousReplacesOnlyPriorityAndRestoresItOnMovement() {
        enableStationaryContinuous()
        engine.applyContinuousPace(stationary = false)
        assertTrue(engine.updateLocationProviderOptions(null, 25.0))
        val moving = client.requests.last()
        val movingCallback = client.callbacks.last()
        client.deferNextRegistration = true

        engine.applyContinuousPace(stationary = true)

        assertEquals(
            moving.copy(priority = TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY),
            client.requests.last(),
        )
        val stationaryCallback = client.callbacks.last()
        assertFalse(engine.isStationaryContinuous)
        assertEquals(0, client.removeCount)

        client.finishRegistration()
        assertTrue(engine.isStationaryContinuous)
        assertEquals(listOf(movingCallback), client.removedCallbacks)

        engine.applyContinuousPace(stationary = false)

        assertEquals(moving, client.requests.last())
        assertFalse(engine.isStationaryContinuous)
        assertEquals(listOf(movingCallback, stationaryCallback), client.removedCallbacks)
    }

    @Test
    fun stationaryContinuousAppliesTheStationaryIntervalAndRestoresTheMovingInterval() {
        enableStationaryContinuous()
        whenever(configManager.getStationaryLocationUpdateInterval()).thenReturn(10_000L)

        engine.applyContinuousPace(stationary = false)
        val moving = client.requests.last()
        engine.applyContinuousPace(stationary = true)
        assertEquals(10_000L, client.requests.last().intervalMillis)
        assertEquals(10_000L, client.requests.last().minUpdateIntervalMillis)

        engine.applyContinuousPace(stationary = false)
        assertEquals(moving, client.requests.last())
    }

    @Test
    fun stationaryContinuousStartsAtStationaryAccuracyWithoutIncreasingPrecision() {
        enableStationaryContinuous()
        whenever(configManager.getDesiredAccuracy()).thenReturn(2)

        engine.applyContinuousPace(stationary = true)

        assertEquals(TraceletLocationPriority.PRIORITY_LOW_POWER, client.requests.single().priority)
        assertTrue(engine.isStationaryContinuous)
    }

    @Test
    fun failedMovingRegistrationKeepsTheOldSubscriptionAndRetries() {
        enableStationaryContinuous()
        engine.applyContinuousPace(stationary = true)
        val stationaryCallback = client.callbacks.single()
        client.registrationError = SecurityException("Temporary registration failure")

        engine.applyContinuousPace(stationary = false)

        assertTrue(engine.isStationaryContinuous)
        assertFalse(stationaryCallback in client.removedCallbacks)
        shadowOf(Looper.getMainLooper()).idleFor(30, TimeUnit.SECONDS)

        assertFalse(engine.isStationaryContinuous)
        assertEquals(3, client.requests.size)
        assertEquals(TraceletLocationPriority.PRIORITY_HIGH_ACCURACY, client.requests.last().priority)
        assertTrue(stationaryCallback in client.removedCallbacks)
    }

    @Test
    fun stationaryStartUsesMovingAccuracyUntilStationaryRegistrationSucceeds() {
        enableStationaryContinuous()
        client.registrationError = IllegalStateException("No stationary provider available")

        engine.applyContinuousPace(stationary = true)

        assertTrue(engine.isTracking)
        assertFalse(engine.isStationaryContinuous)
        assertEquals(TraceletLocationPriority.PRIORITY_HIGH_ACCURACY, client.requests.last().priority)

        shadowOf(Looper.getMainLooper()).idleFor(30, TimeUnit.SECONDS)

        assertTrue(engine.isStationaryContinuous)
        assertEquals(TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY, client.requests.last().priority)
    }

    @Test
    fun stoppedSessionRejectsLatePaceChangesAndRegistrationResults() {
        enableStationaryContinuous()
        engine.applyContinuousPace(stationary = false)
        client.deferNextRegistration = true
        engine.applyContinuousPace(stationary = true)

        whenever(state.enabled).thenReturn(false)
        engine.stop()
        client.finishRegistration()
        engine.applyContinuousPace(stationary = true)
        shadowOf(Looper.getMainLooper()).idleFor(30, TimeUnit.SECONDS)

        assertFalse(engine.isTracking)
        assertFalse(engine.isStationaryContinuous)
        assertEquals(2, client.requests.size)
        assertEquals(client.callbacks.toSet(), client.removedCallbacks.toSet())
    }

    @Test
    fun stoppedSessionCancelsTheScheduledPaceRetry() {
        enableStationaryContinuous()
        engine.applyContinuousPace(stationary = true)
        client.registrationError = SecurityException("Temporary registration failure")
        engine.applyContinuousPace(stationary = false)

        engine.stop()
        shadowOf(Looper.getMainLooper()).idleFor(30, TimeUnit.SECONDS)

        assertFalse(engine.isTracking)
        assertEquals(2, client.requests.size)
    }

    private fun enableStationaryContinuous() {
        whenever(configManager.getStationaryTrackingMode()).thenReturn(StationaryTrackingMode.CONTINUOUS)
        whenever(configManager.getMotionDetectionMode()).thenReturn(MotionDetectionMode.SMART)
        whenever(configManager.getStationaryPeriodicAccuracy()).thenReturn(1)
        whenever(state.sessionTrackingMode).thenReturn(TrackingMode.CONTINUOUS)
        whenever(state.enabled).thenReturn(true)
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
    val removedCallbacks = mutableListOf<TraceletLocationCallback>()
    val removeCount get() = removedCallbacks.size
    var registrationError: Exception? = null
    var deferNextRegistration = false
    private var pendingRegistration: ((Result<Unit>) -> Unit)? = null

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) {
        requests += request
        callbacks += callback
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {
        removedCallbacks += callback
    }

    override fun requestLocationUpdatesWithResult(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
        onResult: (Result<Unit>) -> Unit,
    ) {
        requestLocationUpdates(request, callback, looper)
        if (deferNextRegistration) {
            deferNextRegistration = false
            pendingRegistration = onResult
        } else {
            val error = registrationError
            registrationError = null
            onResult(if (error == null) Result.success(Unit) else Result.failure(error))
        }
    }

    fun finishRegistration() {
        val completion = checkNotNull(pendingRegistration)
        pendingRegistration = null
        completion(Result.success(Unit))
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
