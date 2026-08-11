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
 * Regression for #357 — a fence the OS cannot resolve must have a location
 * stream to be decided from, even when the session is stationary.
 *
 * `start()` runs no stream when the committed motion state is stationary: that
 * is the whole point of its `changePace(false)` branch, and #319 stops the
 * engine on every moving → stationary transition for the same reason. A
 * sub-100 m fence breaks the premise — since #355 it is evaluated *from* that
 * stream — and the killed-state reconcile already refuses the throttle on those
 * grounds while the alive app did not.
 *
 * The device trace this pins down: `session: start — isMoving=false`, a 10 m
 * fence registered seconds later, `[geofence] fence set changed — in-app
 * evaluation required` logged correctly, and then not one location fix in the
 * following minute, because the engine had never been started at all.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.R])
class GeofenceStationaryStreamTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk
    private lateinit var client: RecordingLocationClient

    private val lat = 10.787929
    private val lng = 76.684183

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )

        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )

        client = RecordingLocationClient()
        TraceletServices.setProvider(StationaryStreamServicesProvider(client))

        sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(mock())
        sdk.initialize()
        var ready = false
        // The default config: geofenceModeHighAccuracy off, so the fence is
        // evaluator-owned purely because its radius is under 100 m.
        sdk.ready(mapOf("distanceFilter" to 10.0, "foregroundService" to mapOf("enabled" to false))) {
            ready = true
        }
        idle()
        check(ready) { "ready() did not complete" }
        // The state under test: a device that is not moving.
        sdk.stateManager.isMoving = false
    }

    @After
    fun tearDown() {
        try { sdk.removeGeofences() } catch (_: Exception) {}
        try { sdk.stop() } catch (_: Exception) {}
        idle()
        TraceletServices.setProvider(null)
        ConfigManager.resetInstance()
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun addSmallFence(identifier: String) {
        sdk.addGeofence(
            mapOf(
                "identifier" to identifier,
                "latitude" to lat,
                "longitude" to lng,
                "radius" to 10.0,
            ),
        )
        idle()
    }

    @Test
    fun `a fence added while the session is stationary starts the stream`() {
        sdk.start()
        idle()
        assertEquals(
            "precondition: a stationary session runs no stream",
            false,
            sdk.locationEngine.isTracking,
        )

        addSmallFence("issue-357-added-later")

        assertEquals(
            "the fence is decided from the location stream, so registering one " +
                "has to start it — otherwise it is evaluated against nothing",
            true,
            sdk.locationEngine.isTracking,
        )
        // What that stream is *shaped* like is pinned by
        // LocationEngineGeofenceStarvationTest; this test is only about whether
        // one is running at all.
    }

    @Test
    fun `a fence stored before a stationary start still gets a stream`() {
        // The common real case: the fence outlives the session that created it,
        // so no ownership change fires during start() to correct the posture.
        addSmallFence("issue-357-stored-first")
        sdk.stop()
        idle()
        sdk.stateManager.isMoving = false

        sdk.start()
        idle()

        assertEquals(
            "a fence that was already stored must not wait for the device to " +
                "move before it is given the stream it is decided from",
            true,
            sdk.locationEngine.isTracking,
        )
    }

    @Test
    fun `a stationary start with no evaluator-owned fence still runs no stream`() {
        // The control: #319's battery saving is untouched for fences the OS can
        // resolve on its own.
        sdk.addGeofence(
            mapOf(
                "identifier" to "issue-357-os-serviceable",
                "latitude" to lat,
                "longitude" to lng,
                "radius" to 400.0,
            ),
        )
        idle()

        sdk.start()
        idle()

        assertEquals(
            "a 400 m fence is region-monitored by the OS and needs no stream",
            false,
            sdk.locationEngine.isTracking,
        )
    }
}

private class RecordingLocationClient : TraceletLocationClient {
    var lastRequest: TraceletLocationRequest? = null
    var lastCallback: TraceletLocationCallback? = null

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) {
        lastRequest = request
        lastCallback = callback
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

private class StationaryStreamServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) = mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
