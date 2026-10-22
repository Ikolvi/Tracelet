package com.ikolvi.tracelet.sdk

import android.Manifest
import android.app.Application
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.service.LocationService
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse

/**
 * #428 / #436: the killed-state engine writes PERIODIC into
 * `StateManager.trackingMode` when it parks a stationary device
 * (`LocationService.switchToStationaryPeriodic`, #319). That is a *pace*. The
 * session's *strategy* — what the app started — must survive it, because every
 * resume decision reads the strategy:
 *
 * - `ready()` on reopen resumed `startPeriodic()`, which stopped the foreground
 *   service and the motion detector of a continuous session (#428);
 * - a START_STICKY restart after process death was declined as "periodic
 *   without a foreground service", leaving a cached process with nothing to
 *   wake it (#436).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class StationaryPaceResumeTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        )
        // The singleton outlives the test (one Robolectric sandbox per SDK level)
        // and would carry another test's state and engines into this one.
        resetSdkSingleton()
        StateManager(context).reset()
        sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(ListenerEventSender())
        sdk.initialize()
    }

    @After
    fun tearDown() {
        try { sdk.stop() } catch (_: Exception) {}
        shadowOf(Looper.getMainLooper()).idle()
        StateManager(context).reset()
        ConfigManager.resetInstance()
        resetSdkSingleton()
    }

    private fun resetSdkSingleton() {
        TraceletSdk::class.java.getDeclaredField("instance").apply {
            isAccessible = true
            set(null, null)
        }
    }

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun drainStartedServiceActions(): List<String?> {
        val app = shadowOf(context as Application)
        val actions = mutableListOf<String?>()
        var intent: Intent? = app.nextStartedService
        while (intent != null) {
            if (intent.component?.className == LocationService::class.java.name) {
                actions.add(intent.action)
            }
            intent = app.nextStartedService
        }
        return actions
    }

    private val config = mapOf<String, Any?>(
        "fg_enabled" to true,
        "stopOnTerminate" to false,
        "periodicLocationInterval" to 60,
    )

    /** What `switchToStationaryPeriodic` persists when the killed-state engine parks. */
    private fun killedStateEngineParks(state: StateManager) {
        state.isMoving = false
        state.trackingMode = TrackingMode.PERIODIC
    }

    @Test
    fun `a stationary pace does not overwrite the started strategy`() {
        val state = StateManager(context)
        state.trackingMode = TrackingMode.CONTINUOUS
        state.sessionTrackingMode = TrackingMode.CONTINUOUS

        killedStateEngineParks(state)

        assertEquals(TrackingMode.PERIODIC, state.trackingMode)
        assertEquals(TrackingMode.CONTINUOUS, state.sessionTrackingMode)
    }

    @Test
    fun `a session from before the field existed falls back to trackingMode`() {
        val state = StateManager(context)
        state.reset()
        state.trackingMode = TrackingMode.GEOFENCES
        assertEquals(TrackingMode.GEOFENCES, state.sessionTrackingMode)
    }

    @Test
    fun `ready after a killed-state stationary park resumes continuous, not periodic`() {
        sdk.ready(config) {}
        idle()
        sdk.start()
        idle()
        assertEquals(TrackingMode.CONTINUOUS, sdk.stateManager.sessionTrackingMode)

        killedStateEngineParks(sdk.stateManager)
        drainStartedServiceActions()

        // The app is reopened and calls ready() again.
        sdk.ready(config) {}
        idle()

        assertEquals(
            TrackingMode.CONTINUOUS, sdk.stateManager.trackingMode,
            "ready() must resume the strategy start() chose, not the parked pace (#428)",
        )
        val actions = drainStartedServiceActions()
        assertFalse(
            actions.contains(LocationService.ACTION_STOP),
            "resuming a continuous session must not stop the foreground service (#428); got $actions",
        )
    }

    @Test
    fun `an explicitly periodic session still resumes periodic`() {
        sdk.ready(config) {}
        idle()
        sdk.startPeriodic()
        idle()

        sdk.ready(config) {}
        idle()

        assertEquals(TrackingMode.PERIODIC, sdk.stateManager.trackingMode)
        assertEquals(TrackingMode.PERIODIC, sdk.stateManager.sessionTrackingMode)
    }

    @Test
    fun `sticky restart of a parked continuous session is not declined`() {
        ConfigManager.getInstance(context).setConfig(config)
        val state = StateManager(context)
        state.enabled = true
        state.sessionTrackingMode = TrackingMode.CONTINUOUS
        killedStateEngineParks(state)

        val controller = Robolectric.buildService(LocationService::class.java)
        try {
            val result = controller.create().get().onStartCommand(null, 0, 1)
            assertEquals(
                Service.START_STICKY, result,
                "a parked continuous session must come back after process death (#436)",
            )
        } finally {
            try { controller.destroy() } catch (_: Throwable) {}
            LocationService.stopBootTracking()
        }
    }

    @Test
    fun `sticky restart of a periodic session without a service is still declined`() {
        ConfigManager.getInstance(context).setConfig(config)
        val state = StateManager(context)
        state.enabled = true
        state.trackingMode = TrackingMode.PERIODIC
        state.sessionTrackingMode = TrackingMode.PERIODIC

        val controller = Robolectric.buildService(LocationService::class.java)
        try {
            val result = controller.create().get().onStartCommand(null, 0, 1)
            assertEquals(Service.START_NOT_STICKY, result)
        } finally {
            try { controller.destroy() } catch (_: Throwable) {}
        }
    }
}
