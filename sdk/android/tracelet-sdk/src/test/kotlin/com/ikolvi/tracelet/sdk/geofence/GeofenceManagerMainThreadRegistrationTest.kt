package com.ikolvi.tracelet.sdk.geofence

import android.Manifest
import android.app.Application
import android.app.PendingIntent
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingRequest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import uniffi.tracelet_core.DatabaseManager
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Regression for #265 — `addGeofence()` must not return `false` for a geofence
 * that was actually registered.
 *
 * When no device location is known yet, `addGeofence()` persists the record and
 * calls `registerGeofence()`, whose Play Services `GeofencingClient.addGeofences()`
 * is asynchronous. The Flutter host invokes this on the Android main thread,
 * where the SDK must NOT block on the callback (Play Services delivers it on the
 * same main looper). Previously it returned the still-`false` `success` before
 * the callback ran, so callers saw a bogus failure for a geofence that was in
 * fact created and listed by `getGeofences()`.
 *
 * The fix: on the main thread, return `true` once the registration request has
 * been scheduled without a synchronous error; off the main thread, keep awaiting
 * the callback and return its real result.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GeofenceManagerMainThreadRegistrationTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var db: DatabaseManager

    private val dbName = "test_geofence_265.db"

    /** A geofencing client whose callback is never fired — simulates a Play
     *  Services registration that is still in flight when the main-thread call
     *  returns. */
    private class PendingClient : TraceletGeofencingClient {
        override fun addGeofences(
            request: TraceletGeofencingRequest,
            pendingIntent: PendingIntent,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) {
            // Intentionally do nothing: registration accepted, callback pending.
        }

        override fun removeGeofences(
            pendingIntent: PendingIntent,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) { onSuccess() }

        override fun removeGeofences(
            requestIds: List<String>,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) { onSuccess() }
    }

    /** Fires the requested callback synchronously to model a resolved async
     *  registration for the off-main-thread path. */
    private class ImmediateClient(private val succeed: Boolean) : TraceletGeofencingClient {
        override fun addGeofences(
            request: TraceletGeofencingRequest,
            pendingIntent: PendingIntent,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) {
            if (succeed) onSuccess() else onFailure(RuntimeException("registration failed"))
        }

        override fun removeGeofences(
            pendingIntent: PendingIntent,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) { onSuccess() }

        override fun removeGeofences(
            requestIds: List<String>,
            onSuccess: () -> Unit,
            onFailure: (Exception) -> Unit,
        ) { onSuccess() }
    }

    @Before
    fun setUp() {
        org.robolectric.shadows.ShadowLog.stream = System.out
        context = ApplicationProvider.getApplicationContext()
        // registerGeofence() short-circuits to false without location permission.
        Shadows.shadowOf(context as Application)
            .grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION)
        config = ConfigManager.getInstance(context)

        val dbPath = context.filesDir.resolve(dbName).absolutePath
        db = DatabaseManager(dbPath)
        db.setEncryptionKey("")
        db.clearGeofences()
    }

    @After
    fun tearDown() {
        ConfigManager.resetInstance()
        context.filesDir.resolve(dbName).delete()
    }

    private fun manager(client: TraceletGeofencingClient) =
        GeofenceManager(context, config, ListenerEventSender(), db, client)

    private fun geofence(id: String) = mapOf<String, Any?>(
        "identifier" to id,
        "latitude" to 6.5244,
        "longitude" to 3.3792,
        "radius" to 100.0,
    )

    @Test
    fun `addGeofence on main thread returns true while registration is still pending`() {
        // Robolectric runs the test body on the main looper, so this exercises
        // the exact main-thread path the Flutter host uses. The PendingClient
        // never fires its callback — pre-fix this returned the initial false.
        val geoManager = manager(PendingClient())

        val added = geoManager.addGeofence(geofence("issue-265-office"))

        assertTrue(
            added,
            "addGeofence() must return true on the main thread once registration " +
                "is scheduled, even though the async Play Services callback has " +
                "not fired yet (#265)",
        )
        // And it must actually be persisted — the whole point of the report.
        assertTrue(
            db.getGeofences().any { it.identifier == "issue-265-office" },
            "geofence should be persisted to the Rust DB",
        )
    }

    @Test
    fun `off the main thread addGeofence returns the real registration result`() {
        // Off the main thread the SDK still awaits the callback, so a genuine
        // Play Services failure must surface as false (and a success as true).
        val executor = Executors.newSingleThreadExecutor()
        try {
            val succeeded = executor.submit<Boolean> {
                manager(ImmediateClient(succeed = true)).addGeofence(geofence("ok"))
            }.get(10, TimeUnit.SECONDS)
            assertTrue(succeeded, "off-main success callback should yield true")

            val failed = executor.submit<Boolean> {
                manager(ImmediateClient(succeed = false)).addGeofence(geofence("bad"))
            }.get(10, TimeUnit.SECONDS)
            assertFalse(
                failed,
                "off-main a genuine registration failure must still return false",
            )
        } finally {
            executor.shutdownNow()
        }
    }
}
