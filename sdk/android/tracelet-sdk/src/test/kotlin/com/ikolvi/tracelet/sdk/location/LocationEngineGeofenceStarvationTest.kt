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
 * Regression for the high-accuracy geofence **starvation** bug (missing
 * ENTER/EXIT, intermittent): a stationary device on a stable provider emits no
 * fixes that survive the tracking distance filter, so the in-app crossing
 * evaluator is never fed and transitions are silently dropped.
 *
 * The fix decouples geofence crossing evaluation from persistence:
 *  1. the provider is requested with a time-based cadence
 *     (`minUpdateDistanceMeters = 0`) so a stationary device still receives
 *     fixes, and
 *  2. crossings are evaluated on the **raw** fix stream — before the Rust
 *     `LocationProcessor` distance filter — so a fix the filter drops for
 *     *persistence* is still evaluated for a *crossing*.
 *
 * Persistence volume is unchanged: the processor keeps its distance filter, so
 * `onLocationUpdate` (the persistence-side geofence-proximity callback) still
 * only fires on accepted fixes.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.R])
class LocationEngineGeofenceStarvationTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var events: TraceletEventSender
    private lateinit var engine: LocationEngine
    private lateinit var client: CapturingLocationClient

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application)
            .grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)

        client = CapturingLocationClient()
        TraceletServices.setProvider(StarvationServicesProvider(client))

        config = ConfigManager.getInstance(context)
        config.setConfig(
            mapOf(
                "distanceFilter" to 10.0,
                // persistMode 3 = none → dispatch skips DB/sink writes so the
                // test needs no native persistence wiring.
                "persistMode" to 3,
                "resolveAddress" to false,
                "rejectMockLocations" to false,
                "locationUpdateInterval" to 1000L,
                "fastestLocationUpdateInterval" to 500L,
            ),
        )

        state = StateManager(context)
        // These drive fixes through the engine as a *running* session does.
        // `onLocationReceived` drops a fix when the session is not enabled,
        // because after `stop()` a straggling delivery is not ours to record
        // (#412) — and an engine streaming into a disabled session is a state
        // production never reaches: `start()` sets this before it starts the
        // engine or asks for the startup fix.
        state.enabled = true
        events = mock()
        engine = LocationEngine(context, config, state, events)
    }

    @After
    fun tearDown() {
        engine.stop()
        TraceletServices.setProvider(null)
        ConfigManager.resetInstance()
    }

    private fun fixAt(lat: Double, lng: Double, timeMs: Long): Location =
        Location("fused").apply {
            latitude = lat
            longitude = lng
            accuracy = 5f
            time = timeMs
            elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
        }

    @Test
    fun `high-accuracy geofence mode requests time-based updates (no distance gate)`() {
        engine.geofenceHighAccuracyMode = true
        engine.start()

        assertEquals(
            "high-accuracy geofence mode must request time-based delivery so a " +
                "stationary device isn't starved of fixes",
            0f,
            client.lastRequest!!.minUpdateDistanceMeters,
        )
    }

    @Test
    fun `without geofence mode the configured distance filter still gates the request`() {
        engine.geofenceHighAccuracyMode = false
        engine.start()

        assertEquals(
            "normal tracking must keep its distance filter to limit fix volume",
            10f,
            client.lastRequest!!.minUpdateDistanceMeters,
        )
    }

    /**
     * Regression for #357 — the fence set is mutable after `start()`.
     *
     * `start()` then `addGeofence(radius = 10f)` is the ordinary order, and the
     * flag was only ever computed at start: the request kept
     * `minUpdateDistanceMeters` at the configured filter for the whole session,
     * so the evaluator saw one fix per that many metres travelled. A device can
     * cross a 10 m fence's exit band and be back inside between two deliveries,
     * and EXIT needs two *consecutive* fixes beyond it.
     */
    @Test
    fun `a fence added after start drops the distance gate live`() {
        engine.start()
        assertEquals(
            "precondition: no fences, so the configured filter gates the request",
            10f,
            client.lastRequest!!.minUpdateDistanceMeters,
        )

        engine.geofenceHighAccuracyMode = true

        assertEquals(
            "a fence the evaluator owns, added mid-session, must drop the distance " +
                "gate without waiting for a restart",
            0f,
            client.lastRequest!!.minUpdateDistanceMeters,
        )
        assertEquals(
            "the live update must replace the request in place, not tear tracking down",
            true,
            engine.isTracking,
        )
    }

    @Test
    fun `removing the last evaluator-owned fence restores the configured gate`() {
        engine.geofenceHighAccuracyMode = true
        engine.start()
        assertEquals(0f, client.lastRequest!!.minUpdateDistanceMeters)

        engine.geofenceHighAccuracyMode = false

        assertEquals(
            "with no evaluator-owned fence left, the configured filter must come " +
                "back rather than leaking time-based delivery for the whole session",
            10f,
            client.lastRequest!!.minUpdateDistanceMeters,
        )
    }

    /**
     * Regression for #357 — the stationary state must not take the stream away
     * from a fence that is decided from it.
     *
     * #319 stops the engine when the committed state goes stationary, on the
     * premise that nothing needs the continuous stream while the device is
     * still. A sub-100 m fence breaks that premise. A device trace showed a 10 m
     * fence registered, the cadence correctly re-aligned, and not one fix in the
     * following minute — the session had started stationary, so `start()` went
     * through `changePace(false)` and the engine was never running at all.
     */
    @Test
    fun `a stationary pace change keeps the stream for an in-app evaluated fence`() {
        engine.geofenceHighAccuracyMode = true
        engine.start()
        assertEquals("precondition: tracking", true, engine.isTracking)

        engine.changePace(false)

        assertEquals(
            "the fence is evaluated from this stream — going stationary must not " +
                "leave the evaluator with nothing to judge",
            true,
            engine.isTracking,
        )
    }

    @Test
    fun `a stationary pace change still stops the stream when no fence needs it`() {
        engine.geofenceHighAccuracyMode = false
        engine.start()
        assertEquals("precondition: tracking", true, engine.isTracking)

        engine.changePace(false)

        assertEquals(
            "with nothing depending on the stream, stationary still means stop — " +
                "#319's battery saving is unchanged",
            false,
            engine.isTracking,
        )
    }

    @Test
    fun `setting the same cadence twice does not re-issue the request`() {
        engine.geofenceHighAccuracyMode = true
        engine.start()
        val requestsAfterStart = client.requestCount

        engine.geofenceHighAccuracyMode = true

        assertEquals(
            "an unchanged fence set must not churn the fused subscription",
            requestsAfterStart,
            client.requestCount,
        )
    }

    @Test
    fun `crossings evaluate on every raw fix even when persistence rejects the duplicate`() {
        var rawEvaluations = 0
        var persistedUpdates = 0
        engine.geofenceHighAccuracyMode = true
        engine.onRawGeofenceLocation = { _, _, _ -> rawEvaluations++ }
        engine.onLocationUpdate = { _, _, _ -> persistedUpdates++ }
        engine.start()

        val callback = client.lastCallback!!
        // Two fixes from a stationary device: identical position, later time.
        // The processor accepts the first and rejects the second (distance 0 <
        // 10 m filter) for persistence.
        callback.onLocationResult(listOf(fixAt(10.787929, 76.684183, 1_000L)))
        callback.onLocationResult(listOf(fixAt(10.787929, 76.684183, 2_000L)))
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "both raw fixes must reach the geofence evaluator — a stationary " +
                "duplicate the persistence filter drops must NOT starve crossings",
            2,
            rawEvaluations,
        )
        assertEquals(
            "persistence stays filtered: the stationary duplicate is dropped, so " +
                "the persistence-side geofence callback fires only for the accepted fix",
            1,
            persistedUpdates,
        )
    }

    /**
     * Regression for #352 — geofence **proximity scope** must survive a fix the
     * processor rejects for a reason unrelated to movement.
     *
     * `updateProximity()` is what registers fences with Play Services, so in
     * standard (OS) geofence mode it *is* the feature. It used to ride the
     * persistence-filtered `onLocationUpdate`, which meant the tracking filter
     * silently decided whether geofencing worked at all.
     *
     * 3.8.0's transport-mode auto-tune (#299) made that fatal: a committed
     * `still` mode retunes `maxImpliedSpeed` to 3 m/s, so the moment the device
     * starts moving every fix is rejected — registration froze and ENTER/EXIT
     * never fired again. This models that exact rejection.
     */
    @Test
    fun `proximity scope still updates when the implied-speed filter rejects the fix`() {
        // Mirrors TransportMode::Still from the auto-tune table: 3 m/s.
        config.setConfig(mapOf("maxImpliedSpeed" to 3))

        var rawEvaluations = 0
        var persistedUpdates = 0
        // Standard (OS) geofence mode — high accuracy OFF, which is the
        // configuration in the field report.
        engine.geofenceHighAccuracyMode = false
        engine.onRawGeofenceLocation = { _, _, _ -> rawEvaluations++ }
        engine.onLocationUpdate = { _, _, _ -> persistedUpdates++ }
        engine.start()

        val callback = client.lastCallback!!
        // First fix anchors the processor. The second is ~110 m away one second
        // later — an implied ~110 m/s, far above the 3 m/s auto-tuned gate, so
        // the processor rejects it for persistence.
        callback.onLocationResult(listOf(fixAt(10.787929, 76.684183, 1_000L)))
        callback.onLocationResult(listOf(fixAt(10.788929, 76.684183, 2_000L)))
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "both fixes must reach geofence proximity — a fix rejected by the " +
                "implied-speed filter must NOT freeze Play Services registration (#352)",
            2,
            rawEvaluations,
        )
        assertEquals(
            "persistence stays filtered: the implausible-speed fix is still " +
                "rejected for persistence, so only the first fix is dispatched",
            1,
            persistedUpdates,
        )
    }
    /**
     * #412: `removeLocationUpdates` is asynchronous, so a fix already in the
     * fused client's delivery pipeline still arrives after `stop()` returns —
     * and the whole pipeline ran for it: enrich, geocode, odometer, persist,
     * appending a row to a database the user had just stopped filling.
     *
     * A field trace shows one landing a second after `session: stop`, on a
     * device whose health check then read `Tracking enabled: false` with the
     * pending-location count still climbing.
     */
    @Test
    fun `a fix delivered after the session stopped is dropped`() {
        var rawEvaluations = 0
        engine.geofenceHighAccuracyMode = true
        engine.onRawGeofenceLocation = { _, _, _ -> rawEvaluations++ }
        engine.start()

        val callback = client.lastCallback!!
        callback.onLocationResult(listOf(fixAt(10.787929, 76.684183, 1_000L)))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(
            "precondition: a fix during an enabled session is processed",
            1,
            rawEvaluations,
        )

        // What TraceletSdk.stop() does, in its order: clear the session flag,
        // then tear the engine down.
        state.enabled = false
        engine.stop()

        // Already in flight when removeLocationUpdates() was called.
        callback.onLocationResult(listOf(fixAt(10.787939, 76.684193, 2_000L)))
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(
            "a fix that arrives after the session stopped must not be processed",
            1,
            rawEvaluations,
        )
    }
}

private class CapturingLocationClient : TraceletLocationClient {
    var lastRequest: TraceletLocationRequest? = null
    var lastCallback: TraceletLocationCallback? = null
    var requestCount = 0

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) {
        lastRequest = request
        lastCallback = callback
        requestCount++
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {}

    override fun getCurrentLocation(
        priority: Int,
        cancellationToken: TraceletCancellationToken?,
        onSuccess: (Location?) -> Unit,
    ) = onSuccess(null)

    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) =
        onSuccess(null)
}

private class StarvationServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) = mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
