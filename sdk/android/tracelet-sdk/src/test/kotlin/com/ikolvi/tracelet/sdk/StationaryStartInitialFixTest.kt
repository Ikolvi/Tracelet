package com.ikolvi.tracelet.sdk

import android.Manifest
import android.app.Application
import android.content.Context
import android.location.Location
import android.os.Build
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationToken
import com.ikolvi.tracelet.sdk.wrapper.TraceletEventExtractor
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationCallback
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationPriority
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.atLeastOnce
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Regression for #385 — a session that *starts* stationary must still acquire
 * one location.
 *
 * `motion.isMoving` defaults to false, so this is what an app that configures
 * nothing gets. `start()` then takes its stationary branch, which runs no
 * continuous stream by design (#319), and nothing else acquires either: the
 * SMART coordinator is synced to STATIONARY_PERIODIC and *then* told both of
 * its inputs are stationary, so `evaluate_state` sees no mode change, returns
 * `None`, and never arms the periodic worker. The one-shot that does exist
 * ([LocationEngine.requestImmediateFix]) is fired from `changePace(true)` — a
 * stationary → moving *transition* a session that begins stationary never
 * takes.
 *
 * The field report: `start()`, phone on a desk, and `onLocation` silent
 * forever. The advice being handed out was `motion.isMoving: true`, which buys
 * a first fix with a full-rate GPS stream nobody asked for.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.R])
class StationaryStartInitialFixTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk
    private lateinit var events: TraceletEventSender

    private companion object {
        /**
         * Class-scoped because the engine is: `initialize()` is guarded by
         * `initStarted` and builds exactly one [LocationEngine], which resolves
         * its client from [TraceletServices] at construction. A fresh client per
         * test would be handed to nobody after the first one.
         */
        val client = InitialFixLocationClient()

        /**
         * Drops the process-wide [TraceletSdk] so this class gets an engine
         * built from *its* provider.
         *
         * Robolectric caches one sandbox per SDK level and shares it across
         * every test class configured for it, so the singleton — and the single
         * [LocationEngine] `initialize()` builds, which resolves its client at
         * construction — outlives the class that first asked for it. Without
         * this, the counters below belong to whichever class Gradle happened to
         * schedule first, and the suite passes or fails on test *order*.
         */
        fun resetSdkSingleton() {
            try {
                TraceletSdk::class.java.getDeclaredField("instance").apply {
                    isAccessible = true
                    set(null, null)
                }
            } catch (_: Exception) {
                // Field renamed: the tests below still run, they just inherit
                // whatever engine exists — which is the pre-existing behaviour.
            }
        }
    }

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            Manifest.permission.ACTIVITY_RECOGNITION,
        )

        // start()/stop() cancel PeriodicLocationWorker — stand up the in-memory
        // scheduler so those calls don't throw.
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )

        TraceletServices.setProvider(InitialFixServicesProvider(client))
        client.reset()

        resetSdkSingleton()
        events = mock()
        sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(events)
        sdk.initialize()
    }

    @After
    fun tearDown() {
        try { sdk.stop() } catch (_: Exception) {}
        idle()
        TraceletServices.setProvider(null)
        ConfigManager.resetInstance()
        // Hand the next class a clean slate rather than an SDK wired to this
        // one's client and mock event sender — the same courtesy this class
        // needs from whoever runs before it.
        resetSdkSingleton()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    /** ready() with a committed pace of [isMoving], plus any [extra] config. */
    private fun ready(isMoving: Boolean, extra: Map<String, Any?> = emptyMap()) {
        var done = false
        sdk.ready(
            mapOf(
                "foregroundService" to false,
                "stopOnStationary" to false,
                "isMoving" to isMoving,
            ) + extra,
        ) { done = true }
        idle()
        check(done) { "ready() did not complete" }

        // The motion subsystems are process-scoped and outlive stop(), so a
        // leftover moving input from whichever test ran before this one would
        // wake the session for reasons this test is not about. Park them the
        // way a previous session settling to stationary does in the field —
        // then discard anything that recorded, so the counts below belong to
        // start() alone.
        sdk.changePace(false)
        idle()
        client.reset()
    }

    @Test
    fun `a fresh stationary start acquires one initial fix`() {
        ready(isMoving = false)

        sdk.start()
        idle()

        assertEquals(
            "precondition: the stationary branch runs no continuous stream — " +
                "the one-shot is the only thing that can produce a location here",
            false,
            sdk.locationEngine.isTracking,
        )
        assertEquals(
            "start() must acquire the position the session begins at, rather " +
                "than leaving the app with nothing until the device moves",
            1,
            client.getCurrentLocationCalls,
        )
    }

    @Test
    fun `the initial fix is delivered through the normal location pipeline`() {
        ready(isMoving = false)
        sdk.start()
        idle()

        // What the provider returns for that one-shot.
        client.deliverCurrentLocation(
            Location("gps").apply {
                latitude = 10.787929
                longitude = 76.684183
                accuracy = 8.0f
                time = System.currentTimeMillis()
                elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
            },
        )
        idle()

        // Requesting a fix is not the point — handing it to the app is. Routing
        // through onLocationReceived() is what makes it a location like any
        // other: filtered, odometer-counted, persisted under the configured
        // persistMode, and dispatched.
        verify(events, atLeastOnce()).sendLocation(any())
        assertEquals(
            "the anchor must also become lastLocation, or the heartbeat and " +
                "the motionchange enrichment stay empty for the whole session",
            10.787929,
            sdk.locationEngine.getLastLocation()?.latitude ?: 0.0,
            1e-6,
        )
    }

    @Test
    fun `the initial fix cannot overturn the pace start() just committed`() {
        // SPEED mode, because that is where the speed machine is wired to the
        // location stream at all.
        ready(isMoving = false, extra = mapOf("motionDetectionMode" to 1))

        // Session one ends somewhere. Neither stop() nor the Rust processor
        // clears its last fix, so it stays as the reference both of them derive
        // speed against.
        sdk.start()
        idle()
        client.deliverCurrentLocation(fix(lat = 10.787929, ageSeconds = 600))
        idle()
        sdk.stop()
        idle()

        // The device is carried 5 km with tracking off, and session two starts
        // stationary. 5 km over 10 minutes derives ~8.3 m/s — comfortably under
        // maxImpliedSpeed (80 m/s), so nothing discards it, and well over
        // speedMovingThreshold (1.5 m/s), so the speed machine would wake on it.
        sdk.start()
        idle()
        client.deliverCurrentLocation(fix(lat = 10.832929, ageSeconds = 0))
        idle()

        assertEquals(
            "the anchor is a position, not a motion sample — a speed derived " +
                "against the previous session's last fix must not promote a " +
                "session the app asked to begin stationary",
            false,
            sdk.stateManager.isMoving,
        )
    }

    /** A fix [ageSeconds] in the past, carrying no platform speed. */
    private fun fix(lat: Double, ageSeconds: Long) = Location("gps").apply {
        latitude = lat
        longitude = 76.684183
        accuracy = 8.0f
        time = System.currentTimeMillis() - ageSeconds * 1000L
        elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
    }

    @Test
    fun `a resume does not acquire an initial fix`() {
        ready(isMoving = false)

        // The killed-state / relaunch path. It runs on every process restart
        // and restores its pace rather than committing one; #385 is about the
        // fresh start the app asked for.
        sdk.start(isResume = true)
        idle()

        assertEquals(
            "a resume must be exactly as cheap as it was before #385",
            0,
            client.getCurrentLocationCalls,
        )
    }

    @Test
    fun `a moving start still acquires through the stream, not a one-shot`() {
        ready(isMoving = true)

        sdk.start()
        idle()

        assertTrue(
            "precondition: a moving start runs the continuous stream",
            sdk.locationEngine.isTracking,
        )
        assertEquals(
            "the stream is already acquiring — #385 must not add a second, " +
                "redundant request to the moving path",
            0,
            client.getCurrentLocationCalls,
        )
    }

    @Test
    fun `the initial fix is floored off passive so it can actually return`() {
        // PRIORITY_PASSIVE only yields a fix while *another* app is actively
        // requesting one, so a passive tracking profile would reproduce the
        // exact silence this fix exists to remove.
        ready(isMoving = false, extra = mapOf("desiredAccuracy" to 4))

        sdk.start()
        idle()

        assertEquals(
            "a passive desiredAccuracy must not leave the startup fix unable " +
                "to acquire — getCurrentPosition() floors it for the same reason",
            TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY,
            client.lastCurrentLocationPriority,
        )
    }
}

/** Records the one-shot requests [LocationEngine] makes of the provider. */
private class InitialFixLocationClient : TraceletLocationClient {
    var getCurrentLocationCalls = 0
    var lastCurrentLocationPriority = -1
    private var pendingOnSuccess: ((Location?) -> Unit)? = null

    fun reset() {
        getCurrentLocationCalls = 0
        lastCurrentLocationPriority = -1
        pendingOnSuccess = null
    }

    /** Completes the in-flight one-shot with [location]. */
    fun deliverCurrentLocation(location: Location) {
        pendingOnSuccess?.invoke(location)
    }

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) = Unit

    override fun removeLocationUpdates(callback: TraceletLocationCallback) = Unit

    override fun getCurrentLocation(
        priority: Int,
        cancellationToken: TraceletCancellationToken?,
        onSuccess: (Location?) -> Unit,
    ) {
        getCurrentLocationCalls++
        lastCurrentLocationPriority = priority
        // Held rather than answered: the engine cancels and supersedes in-flight
        // one-shots, and a synchronous answer would hide that.
        pendingOnSuccess = onSuccess
    }

    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) =
        onSuccess(null)
}

private class InitialFixServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) = mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
