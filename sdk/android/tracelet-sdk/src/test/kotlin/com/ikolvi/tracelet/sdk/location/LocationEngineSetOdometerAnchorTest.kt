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
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationToken
import com.ikolvi.tracelet.sdk.wrapper.TraceletEventExtractor
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationCallback
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Regression for #387 — `setOdometer()` must move the anchor, not just the total.
 *
 * Distance is accumulated in the Rust `LocationProcessor`, which keeps its own
 * odometer anchor and advances it on every fix that passes the accuracy gate.
 * `setOdometer` wrote `state.odometer` and nothing else, so the next accepted
 * fix added the whole span since the previous one and the value the caller had
 * just set survived exactly one fix.
 *
 * The visible form is the common "reset to zero, then start tracking": the
 * phantom leg is however far the device was carried while untracked, and it is
 * booked against the new trip.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.R])
class LocationEngineSetOdometerAnchorTest {

    private lateinit var context: Context
    private lateinit var engine: LocationEngine
    private lateinit var state: StateManager
    private val client = RecordingOdometerClient()

    /** Metres per degree of latitude — lets the fixes below be spaced in metres. */
    private val metresPerDegree = 111_320.0
    private val baseLat = 10.787929
    private val baseLng = 76.684183

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )

        TraceletServices.setProvider(OdometerServicesProvider(client))

        val config = ConfigManager.getInstance(context)
        config.reset(null)
        state = StateManager(context)
        state.odometer = 0.0

        engine = LocationEngine(context, config, state, mock<TraceletEventSender>())
        engine.start()
        idle()
        checkNotNull(client.callback) { "start() did not subscribe a location callback" }
    }

    @After
    fun tearDown() {
        engine.stop()
        TraceletServices.setProvider(null)
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    /** Delivers a fix [metresNorth] of the base point, [secondsIn] into the run. */
    private fun deliver(metresNorth: Double, secondsIn: Long) {
        client.callback!!.onLocationResult(
            listOf(
                Location("gps").apply {
                    latitude = baseLat + metresNorth / metresPerDegree
                    longitude = baseLng
                    accuracy = 5.0f
                    time = START_MS + secondsIn * 1000L
                    elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
                },
            ),
        )
        idle()
    }

    @Test
    fun `the fix after setOdometer contributes no distance`() {
        deliver(metresNorth = 0.0, secondsIn = 0)
        deliver(metresNorth = 100.0, secondsIn = 20)
        assertEquals(
            "precondition: ordinary accumulation works",
            100.0,
            state.odometer,
            2.0,
        )

        // "This trip starts now, at zero."
        engine.setOdometer(0.0)
        assertEquals(0.0, state.odometer, 0.001)

        // The next fix is 100 m on. Before #387 the processor still measured
        // from the fix before the reset and booked the whole span, so the trip
        // began at 100 m — the untracked distance the caller had just disowned.
        deliver(metresNorth = 200.0, secondsIn = 40)
        assertEquals(
            "the first fix after a reset has nothing to measure from, exactly " +
                "as the first fix of a session has",
            0.0,
            state.odometer,
            0.001,
        )

        // The anchor is re-established, so accumulation resumes from there.
        deliver(metresNorth = 300.0, secondsIn = 60)
        assertEquals(
            "distance travelled since the reset must still be counted",
            100.0,
            state.odometer,
            2.0,
        )
    }

    @Test
    fun `setOdometer does not change which fixes are recorded`() {
        deliver(metresNorth = 0.0, secondsIn = 0)
        deliver(metresNorth = 100.0, secondsIn = 20)

        engine.setOdometer(0.0)

        // A 1 m step is under the default 10 m distance filter. Only the
        // odometer anchor was cleared, so the tracking anchor still rejects it
        // — clearing that one too would waive the filter and silently change
        // which locations the app receives.
        deliver(metresNorth = 101.0, secondsIn = 40)
        assertEquals(
            "a filtered fix contributes nothing either way",
            0.0,
            state.odometer,
            0.001,
        )
        assertEquals(
            "and it is still filtered — setting a counter must not start " +
                "recording locations that were being dropped",
            100.0,
            engine.getLastLocation()!!.latitude.minus(baseLat).times(metresPerDegree),
            2.0,
        )
    }

    private companion object {
        /** Fixed epoch base so the fixes below have a stable, monotonic clock. */
        const val START_MS = 1_760_000_000_000L
    }
}

/** Captures the tracking callback so fixes can be driven through the pipeline. */
private class RecordingOdometerClient : TraceletLocationClient {
    var callback: TraceletLocationCallback? = null

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) {
        this.callback = callback
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {
        this.callback = null
    }

    override fun getCurrentLocation(
        priority: Int,
        cancellationToken: TraceletCancellationToken?,
        onSuccess: (Location?) -> Unit,
    ) = onSuccess(null)

    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) =
        onSuccess(null)
}

private class OdometerServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) = mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
