package com.ikolvi.tracelet.sdk.service

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletSdk
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mockStatic
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class LocationServiceSmartBootTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var serviceController: org.robolectric.android.controller.ServiceController<LocationService>

    @Before
    fun setUp() {
        org.robolectric.shadows.ShadowLog.stream = System.out
        context = ApplicationProvider.getApplicationContext()
        config = ConfigManager.getInstance(context)
        state = StateManager(context)
        
        // Grant permissions for LocationService to bootstrap
        val shadowApp = org.robolectric.Shadows.shadowOf(context as android.app.Application)
        shadowApp.grantPermissions(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        
        // Configure to start in SMART motion mode and CONTINUOUS tracking mode 
        // so that bootLocationEngine and bootMotionDetector are instantiated.
        config.setConfig(mapOf(
            "trackingMode" to 0, // CONTINUOUS
            "motionDetectionMode" to 2, // SMART
            "foregroundChannelId" to "test_channel",
            "bootStrategy" to true
        ))
        
        // Set state to stationary so that an initial state change triggers logic.
        // Tracking must be enabled — startBootTracking() refuses to bootstrap
        // when the user explicitly stopped tracking.
        state.enabled = true
        state.isMoving = false
        state.trackingMode = com.ikolvi.tracelet.sdk.model.TrackingMode.CONTINUOUS
        
        serviceController = Robolectric.buildService(LocationService::class.java)
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
        LocationService.bootLocationEngine?.destroy()
        LocationService.bootLocationEngine = null
        LocationService.bootMotionDetector = null
        try {
            serviceController.destroy()
        } catch (e: Exception) {}
    }

    @Test
    fun `boot start with tracking disabled does not bootstrap native tracking`() {
        state.enabled = false

        val intent = android.content.Intent(context, LocationService::class.java)
        intent.action = LocationService.ACTION_START
        intent.putExtra("boot_start", true)
        serviceController.create().withIntent(intent).startCommand(0, 1)

        assertTrue(
            LocationService.bootLocationEngine == null,
            "bootLocationEngine must not be created when tracking was explicitly stopped",
        )
        assertTrue(
            LocationService.bootMotionDetector == null,
            "bootMotionDetector must not be created when tracking was explicitly stopped",
        )
    }

    @Test
    fun `when killed state detects motion without cached location, forcePersistNextFilteredLocation is set`() {
        val intent = android.content.Intent(context, LocationService::class.java)
        intent.action = LocationService.ACTION_START
        intent.putExtra("boot_start", true)
        serviceController.create().withIntent(intent).startCommand(0, 1)
        
        val engine = LocationService.bootLocationEngine
        assertNotNull(engine, "bootLocationEngine should be initialized in background tracking mode")
        
        val detector = LocationService.bootMotionDetector
        assertNotNull(detector, "bootMotionDetector should be initialized in SMART motion mode")
        
        // Assert no cached location initially
        assertTrue(engine.getLastLocation() == null, "Expected no cached location initially")
        
        // Simulate motion (shake or activity recognition)
        val callback = detector.onMotionStateChanged
        assertNotNull(callback, "Motion state callback should be set")
        
        println("TEST: engine.getLastLocation() = ${engine.getLastLocation()}")
        println("TEST: locMap coords = ${engine.getLastLocation()?.let { engine.enrichLocation(it, "motionchange").containsKey("coords") }}")
        
        callback.invoke(true)
        
        println("TEST: force flag is ${engine.forcePersistNextFilteredLocation}")
        
        // Assert the flag is set to force sync the next GPS fix (bypassing Rust processor distance filter)
        assertTrue(engine.forcePersistNextFilteredLocation, "forcePersistNextFilteredLocation should be true when no coords are cached")
    }

    @Test
    fun `boot start in high-accuracy geofence mode wires the proximity location stream (issue 185)`() {
        // Regression: geofenceModeHighAccuracy suppresses OS-level geofence
        // transitions and relies ENTIRELY on per-location proximity evaluation
        // (-> evaluateHighAccuracyProximity). The boot/task-removal path used to
        // re-register geofences but never wire that callback, so after a reboot
        // NO enter/exit events ever fired even though the foreground service and
        // engine were running.
        //
        // The stream it must be wired to is now the RAW one
        // (onRawGeofenceLocation) rather than the persistence-filtered
        // onLocationUpdate (#352). This boot path never received the #297 fix, so
        // both crossings and proximity scope were gated by the tracking filter —
        // which 3.8.0's auto-tune (#299) tightens to maxImpliedSpeed=3 m/s for a
        // committed `still` mode, rejecting every fix once the device moves.
        config.setConfig(mapOf(
            "trackingMode" to 1, // GEOFENCES
            "motionDetectionMode" to 2, // SMART
            "geofenceModeHighAccuracy" to true,
            "foregroundChannelId" to "test_channel",
            "bootStrategy" to true,
        ))
        state.enabled = true
        state.trackingMode = com.ikolvi.tracelet.sdk.model.TrackingMode.GEOFENCES

        val intent = android.content.Intent(context, LocationService::class.java)
        intent.action = LocationService.ACTION_START
        intent.putExtra("boot_start", true)
        serviceController.create().withIntent(intent).startCommand(0, 1)

        val engine = LocationService.bootLocationEngine
        assertNotNull(engine, "bootLocationEngine should be initialized in geofence boot mode")
        assertNotNull(
            engine.onRawGeofenceLocation,
            "the raw geofence stream must be wired after boot so high-accuracy " +
                "transitions can fire without the persistence filter gating them",
        )
        assertTrue(
            engine.geofenceHighAccuracyMode,
            "high-accuracy mode must be propagated to the boot engine so it " +
                "requests time-based delivery",
        )
    }

    @Test
    fun `when killed state detects motion WITH cached location, sync is called immediately`() {
        val intent = android.content.Intent(context, LocationService::class.java)
        intent.action = LocationService.ACTION_START
        intent.putExtra("boot_start", true)
        serviceController.create().withIntent(intent).startCommand(0, 1)
        
        val engine = LocationService.bootLocationEngine
        assertNotNull(engine)
        
        val detector = LocationService.bootMotionDetector
        assertNotNull(detector)
        
        // Inject a cached location manually
        val fallback = android.location.Location("test").apply {
            latitude = 12.0
            longitude = 34.0
            accuracy = 10f
            time = System.currentTimeMillis()
            elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
        }
        val lastLocationField = com.ikolvi.tracelet.sdk.location.LocationEngine::class.java.getDeclaredField("lastLocation")
        lastLocationField.isAccessible = true
        lastLocationField.set(engine, fallback)
        
        // Simulate motion
        val callback = detector.onMotionStateChanged
        assertNotNull(callback)
        callback.invoke(true)
        
        // Assert force flag is NOT set because we had cached coords to construct a payload
        assertFalse(engine.forcePersistNextFilteredLocation, "forcePersistNextFilteredLocation should be false when coords are cached")
    }
}
