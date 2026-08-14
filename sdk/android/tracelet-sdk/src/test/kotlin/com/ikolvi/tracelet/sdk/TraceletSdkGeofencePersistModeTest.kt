package com.ikolvi.tracelet.sdk

import android.Manifest
import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import uniffi.tracelet_core.DatabaseManager
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * #383: guard that `persistMode` gates geofence ENTER/EXIT rows, not just
 * ordinary location rows.
 *
 * Geofence transitions were wired straight from `GeofenceManager.onGeofenceEvent`
 * to [TraceletSdk.insertLocation], bypassing the only persist-mode check on the
 * platform (`LocationEngine.persistLocationIfAllowed`). `location` and `none`
 * therefore persisted — and HTTP-synced — every crossing, contradicting their
 * documented meaning.
 *
 * The test fires the **production** callback (`geofenceManager.onGeofenceEvent`,
 * installed during SDK setup) rather than calling the gate directly, so it covers
 * the wiring as well as the mode arithmetic. That callback is the single funnel
 * both transition sources — OS-delivered `handleGeofenceEvent` and
 * software-evaluated `evaluateHighAccuracyProximity` — pass through.
 *
 * The SDK is a process-wide singleton shared by every Robolectric suite in the
 * JVM, and `initialize()` latches on `initStarted`, so the callback under test
 * survives only until some other suite clears it (`GeofenceStartIdempotencyTest`
 * nulls it in teardown). This suite therefore drops the singleton before and
 * after each test, so every case re-runs the real setup and asserts against
 * freshly installed production wiring instead of whatever the previous class
 * left behind. It reads the SDK's own DB rather than injecting one, so it never
 * leaves `rustDatabase` null for a later suite.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class TraceletSdkGeofencePersistModeTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk
    private lateinit var db: DatabaseManager

    /** Drops the process-wide SDK singleton so the next `getInstance` rebuilds it. */
    private fun resetSdkSingleton() {
        val field = TraceletSdk::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )

        resetSdkSingleton()
        sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(ListenerEventSender())
        // Wires geofenceManager and installs the production onGeofenceEvent
        // callback — the code path under test. initialize() hands the wiring to
        // the background "tracelet-init" thread, so block on awaitInit() before
        // touching the lateinit managers.
        sdk.initialize()
        assertTrue(sdk.awaitInit(), "test precondition: SDK init must complete")

        db = assertNotNull(sdk.rustDatabase, "test precondition: the Rust DB must be open")
        db.destroyLocations()

        sdk.configManager.reset(null)
        assertNotNull(
            sdk.geofenceManager.onGeofenceEvent,
            "test precondition: the production geofence callback must be wired",
        )
        assertEquals(0, db.getLocationsCount(), "test precondition: DB starts empty")
    }

    @After
    fun tearDown() {
        try { db.destroyLocations() } catch (_: Exception) {}
        sdk.configManager.reset(null)
        ConfigManager.resetInstance()
        // Hand the next suite a clean singleton rather than this suite's SDK.
        resetSdkSingleton()
    }

    /**
     * Fires one geofence transition through the production callback, using the
     * same payload shape `GeofenceManager` builds.
     */
    private fun fireTransition(identifier: String, action: String = "ENTER") {
        sdk.geofenceManager.onGeofenceEvent?.invoke(
            mapOf(
                "uuid" to java.util.UUID.randomUUID().toString(),
                "event" to "geofence",
                "timestamp" to Instant.now().toString(),
                "coords" to mapOf(
                    "latitude" to 10.787929,
                    "longitude" to 76.684183,
                    "accuracy" to 8.0,
                ),
                "geofence" to mapOf(
                    "identifier" to identifier,
                    "action" to action,
                    "extras" to null,
                ),
            ),
        )
    }

    private fun setPersistMode(mode: Int) {
        sdk.configManager.setConfig(mapOf("persistence" to mapOf("persistMode" to mode)))
        assertEquals(mode, sdk.configManager.getPersistMode(), "config precondition")
    }

    /** Mode 0 = all: geofence rows are persisted, as documented. */
    @Test
    fun geofenceTransition_persistsUnderModeAll() {
        setPersistMode(0)
        fireTransition("fence-all")
        assertEquals(1, db.getLocationsCount(), "mode `all` must persist geofence rows")
    }

    /**
     * Mode 1 = location only. The regression: documented as "persist only
     * location records", it persisted geofence records too.
     */
    @Test
    fun geofenceTransition_isSkippedUnderModeLocation() {
        setPersistMode(1)
        fireTransition("fence-location")
        assertEquals(0, db.getLocationsCount(), "mode `location` must not persist geofence rows")
    }

    /** Mode 2 = geofence only: the one mode that exists to keep these rows. */
    @Test
    fun geofenceTransition_persistsUnderModeGeofence() {
        setPersistMode(2)
        fireTransition("fence-geofence")
        assertEquals(1, db.getLocationsCount(), "mode `geofence` must persist geofence rows")
    }

    /**
     * Mode 3 = none. The privacy-relevant half of #383: an app asking for no
     * persistence still accumulated a history of every fence it crossed, and
     * handed it to the sync provider for the next HTTP batch.
     */
    @Test
    fun geofenceTransition_isSkippedUnderModeNone() {
        setPersistMode(3)
        repeat(5) { fireTransition("fence-none-$it", if (it % 2 == 0) "ENTER" else "EXIT") }
        assertEquals(0, db.getLocationsCount(), "mode `none` must not persist geofence rows")
    }

    /**
     * The gate reads config live, so a mode change mid-session takes effect on
     * the next transition — it is not latched at setup time.
     */
    @Test
    fun geofenceTransition_honoursModeChangedAfterSetup() {
        setPersistMode(0)
        fireTransition("fence-before")
        assertEquals(1, db.getLocationsCount(), "baseline insert under `all`")

        setPersistMode(3)
        fireTransition("fence-after")
        assertEquals(1, db.getLocationsCount(), "switching to `none` must stop new geofence rows")
    }
}
