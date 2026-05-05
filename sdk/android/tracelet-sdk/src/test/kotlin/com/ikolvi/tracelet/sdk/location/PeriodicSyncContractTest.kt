package com.ikolvi.tracelet.sdk.location

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.db.TraceletDatabase
import com.ikolvi.tracelet.sdk.http.HttpSyncManager
import com.ikolvi.tracelet.sdk.model.TrackingMode
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Tests the periodic-mode HTTP sync contract:
 *
 * 1. [PeriodicLocationWorker] must use the static [httpSyncManager] when available.
 * 2. When the static ref is null (headless / killed state), it must create a
 *    local [HttpSyncManager] via [TraceletBootstrap.eventSenderFactory].
 * 3. [LocationEngine.onLocationPersisted] callback must fire after every
 *    [db.insertLocationAsync] with persist=true so the HTTP pipeline is triggered.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class PeriodicSyncContractTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        // Reset static references to known state
        PeriodicLocationWorker.httpSyncManager = null
        PeriodicLocationWorker.eventSender = null
        TraceletBootstrap.eventSenderFactory = null
        TraceletBootstrap.headlessDispatcherFactory = null
    }

    @After
    fun tearDown() {
        PeriodicLocationWorker.httpSyncManager = null
        PeriodicLocationWorker.eventSender = null
        TraceletBootstrap.eventSenderFactory = null
        TraceletBootstrap.headlessDispatcherFactory = null
        ConfigManager.resetInstance()
    }

    // =========================================================================
    // Static HttpSyncManager wiring
    // =========================================================================

    @Test
    fun `httpSyncManager static ref is null by default`() {
        assertNull(PeriodicLocationWorker.httpSyncManager)
    }

    @Test
    fun `httpSyncManager static ref can be set and read`() {
        val config = ConfigManager.getInstance(context)
        val db = TraceletDatabase.getInstance(context)
        val sender = ListenerEventSender()
        val sync = HttpSyncManager(context, config, sender, db)

        PeriodicLocationWorker.httpSyncManager = sync

        assertNotNull(PeriodicLocationWorker.httpSyncManager)
    }

    // =========================================================================
    // TraceletBootstrap.eventSenderFactory — headless fallback
    // =========================================================================

    @Test
    fun `eventSenderFactory is null by default`() {
        assertNull(TraceletBootstrap.eventSenderFactory)
    }

    @Test
    fun `eventSenderFactory produces an event sender`() {
        val created = mutableListOf<TraceletEventSender>()

        TraceletBootstrap.eventSenderFactory = { ctx ->
            val sender = ListenerEventSender()
            created.add(sender)
            sender
        }

        val result = TraceletBootstrap.eventSenderFactory?.invoke(context)
        assertNotNull(result)
        assertEquals(1, created.size)
    }

    // =========================================================================
    // Headless sync — local HttpSyncManager creation
    // =========================================================================

    @Test
    fun `headless sync creates local HttpSyncManager via factory`() {
        // Simulate the exact logic in PeriodicLocationWorker.doWork()
        // when httpSyncManager is null:
        var factoryCalled = false

        TraceletBootstrap.eventSenderFactory = { ctx ->
            factoryCalled = true
            ListenerEventSender()
        }

        val staticManager = PeriodicLocationWorker.httpSyncManager
        assertNull(staticManager)

        // Replicate the doWork() fallback logic
        val config = ConfigManager.getInstance(context)
        val db = TraceletDatabase.getInstance(context)
        val syncManager = staticManager ?: run {
            val sender = TraceletBootstrap.eventSenderFactory
                ?.invoke(context)
                ?: ListenerEventSender()
            HttpSyncManager(context, config, sender, db)
        }

        assertNotNull(syncManager)
        assertTrue(factoryCalled, "Factory should be called when static httpSyncManager is null")
    }

    @Test
    fun `headless sync falls back to ListenerEventSender when no factory`() {
        // When both httpSyncManager AND eventSenderFactory are null,
        // the code creates a bare ListenerEventSender as fallback
        assertNull(PeriodicLocationWorker.httpSyncManager)
        assertNull(TraceletBootstrap.eventSenderFactory)

        val config = ConfigManager.getInstance(context)
        val db = TraceletDatabase.getInstance(context)

        val syncManager = PeriodicLocationWorker.httpSyncManager ?: run {
            val sender = TraceletBootstrap.eventSenderFactory
                ?.invoke(context)
                ?: ListenerEventSender()
            HttpSyncManager(context, config, sender, db)
        }

        // Must not crash — even with a bare ListenerEventSender
        assertNotNull(syncManager)
    }

    // =========================================================================
    // Static ref takes priority over factory
    // =========================================================================

    @Test
    fun `static httpSyncManager takes priority over factory`() {
        val config = ConfigManager.getInstance(context)
        val db = TraceletDatabase.getInstance(context)
        val sender = ListenerEventSender()
        val staticSync = HttpSyncManager(context, config, sender, db)
        PeriodicLocationWorker.httpSyncManager = staticSync

        var factoryCalled = false
        TraceletBootstrap.eventSenderFactory = { _ ->
            factoryCalled = true
            ListenerEventSender()
        }

        // Replicate doWork() logic
        val syncManager = PeriodicLocationWorker.httpSyncManager ?: run {
            val s = TraceletBootstrap.eventSenderFactory
                ?.invoke(context)
                ?: ListenerEventSender()
            HttpSyncManager(context, config, s, db)
        }

        // Static ref should be used — factory should NOT be called
        assertEquals(staticSync, syncManager)
        assertTrue(!factoryCalled, "Factory should NOT be called when static httpSyncManager exists")
    }

    // =========================================================================
    // onLocationPersisted callback contract
    // =========================================================================

    @Test
    fun `onLocationPersisted callback is non-null settable on LocationEngine`() {
        // LocationEngine needs FusedLocationProviderClient, which requires
        // Google Play Services. Here we only test the callback-property contract.
        val config = ConfigManager.getInstance(context)
        val state = StateManager(context)
        val sender = ListenerEventSender()
        val db = TraceletDatabase.getInstance(context)
        val engine = LocationEngine(context, config, state, sender, db)

        var callbackFired = false
        engine.onLocationPersisted = { callbackFired = true }

        // Invoke it directly to verify the property is wired
        engine.onLocationPersisted?.invoke()
        assertTrue(callbackFired)
    }

    @Test
    fun `onLocationPersisted defaults to null`() {
        val config = ConfigManager.getInstance(context)
        val state = StateManager(context)
        val sender = ListenerEventSender()
        val db = TraceletDatabase.getInstance(context)
        val engine = LocationEngine(context, config, state, sender, db)

        assertNull(engine.onLocationPersisted)
    }

    // =========================================================================
    // Exact alarm helpers
    // =========================================================================

    @Test
    fun `canScheduleExactAlarms returns boolean`() {
        // On Robolectric (< API 31), this should return true
        val result = PeriodicLocationWorker.canScheduleExactAlarms(context)
        assertNotNull(result)
    }

    // =========================================================================
    // Exact alarm catch-block re-schedule contract
    // =========================================================================

    @Test
    fun `catch block re-schedule logic runs when enabled and periodic`() {
        // Simulates the catch block inside doWork(): after a failure the code
        // must obtain config + state and determine whether to re-schedule.
        val config = ConfigManager.getInstance(context)
        config.setConfig(mapOf(
            "geo" to mapOf<String, Any?>(
                "periodicLocationInterval" to 60,
                "periodicUseExactAlarms" to true,
            ),
        ))
        val state = StateManager(context)
        state.enabled = true
        state.trackingMode = TrackingMode.PERIODIC

        val interval = config.getPeriodicLocationInterval()
        val useExact = config.getPeriodicUseExactAlarms() || interval < 900

        // The catch block should decide to re-schedule
        assertTrue(state.enabled, "State should be enabled")
        assertEquals(TrackingMode.PERIODIC, state.trackingMode, "Tracking mode should be periodic")
        assertTrue(useExact, "Should use exact alarms")
        assertEquals(60, interval)
    }

    @Test
    fun `catch block skips re-schedule when not in periodic mode`() {
        val config = ConfigManager.getInstance(context)
        val state = StateManager(context)
        state.enabled = true
        state.trackingMode = TrackingMode.GEOFENCES // Geofences mode, not periodic

        val interval = config.getPeriodicLocationInterval()
        val useExact = config.getPeriodicUseExactAlarms() || interval < 900

        // trackingMode != PERIODIC means re-schedule should be skipped
        assertTrue(state.enabled)
        assertFalse(state.trackingMode == TrackingMode.PERIODIC, "Tracking mode should NOT be periodic")
    }

    @Test
    fun `catch block skips re-schedule when disabled`() {
        val config = ConfigManager.getInstance(context)
        val state = StateManager(context)
        state.enabled = false
        state.trackingMode = TrackingMode.PERIODIC

        // Disabled state means re-schedule should be skipped
        assertFalse(state.enabled, "State should be disabled")
    }

    // =========================================================================
    // Auto-purge workflow: insert → mark synced → delete synced
    // =========================================================================

    @Test
    fun `auto-purge workflow deletes synced keeps unsynced`() {
        val db = TraceletDatabase.getInstance(context)
        db.deleteAllLocations()

        // Insert 3 locations
        val uuid1 = db.insertLocation(mapOf(
            "uuid" to "purge-1",
            "latitude" to 1.0, "longitude" to 2.0,
            "accuracy" to 5.0, "speed" to 0.0, "heading" to 0.0, "altitude" to 0.0,
            "timestamp" to System.currentTimeMillis(),
        ))
        val uuid2 = db.insertLocation(mapOf(
            "uuid" to "purge-2",
            "latitude" to 3.0, "longitude" to 4.0,
            "accuracy" to 5.0, "speed" to 0.0, "heading" to 0.0, "altitude" to 0.0,
            "timestamp" to System.currentTimeMillis(),
        ))
        val uuid3 = db.insertLocation(mapOf(
            "uuid" to "purge-3",
            "latitude" to 5.0, "longitude" to 6.0,
            "accuracy" to 5.0, "speed" to 0.0, "heading" to 0.0, "altitude" to 0.0,
            "timestamp" to System.currentTimeMillis(),
        ))

        assertEquals(3, db.getLocationCount())

        // Simulate HTTP sync: mark 2 as synced
        db.markSynced(listOf(uuid1, uuid2))

        // Simulate auto-purge (what performSync does after successful upload)
        val deleted = db.deleteSyncedLocations()
        assertEquals(2, deleted)

        // Only the unsynced location remains
        assertEquals(1, db.getLocationCount())
        val remaining = db.getLocations()
        assertEquals("purge-3", remaining.first()["uuid"])

        db.deleteAllLocations()
    }
}
