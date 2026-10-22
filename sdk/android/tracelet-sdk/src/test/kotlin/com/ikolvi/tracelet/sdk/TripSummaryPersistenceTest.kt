package com.ikolvi.tracelet.sdk

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import org.json.JSONArray
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * #401: a completed trip produces exactly one summary row, carrying the id
 * stamped on its locations; it rides the next flush as a root `trips` array and
 * is marked synced only once that request succeeded.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class TripSummaryPersistenceTest {

    private lateinit var context: Context
    private lateinit var sdk: TraceletSdk

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        resetSdkSingleton()
        androidx.work.testing.WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            androidx.work.Configuration.Builder()
                .setExecutor(androidx.work.testing.SynchronousExecutor())
                .build(),
        )
        sdk = TraceletSdk.getInstance(context)
        sdk.setEventSender(ListenerEventSender())
        sdk.initialize()
        sdk.ready(mapOf("url" to "http://127.0.0.1:9/locations")) {}
        shadowOf(Looper.getMainLooper()).idle()
        sdk.rustDatabase?.getTrips(1000)?.let { existing ->
            if (existing.isNotEmpty()) sdk.rustDatabase?.markTripsSynced(Long.MAX_VALUE)
        }
    }

    @After
    fun tearDown() {
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

    private fun driveOneTrip(): String {
        sdk.tripManager.onMotionStateChanged(isMoving = true, latitude = 24.81, longitude = 67.05)
        val tripId = assertNotNull(sdk.tripManager.currentTripId)
        sdk.tripManager.onLocationReceived(24.83, 67.03)
        sdk.tripManager.onMotionStateChanged(isMoving = false, latitude = 24.8607, longitude = 67.0011)
        return tripId
    }

    private fun db() = assertNotNull(sdk.rustDatabase)

    @Test
    fun `a completed trip is stored once, under the id its locations carry`() {
        val before = db().getUnsyncedTrips(1000).size
        val tripId = driveOneTrip()

        val pending = db().getUnsyncedTrips(1000)
        assertEquals(before + 1, pending.size)
        val row = pending.last()
        assertEquals(tripId, row.tripId)
        assertEquals(24.81, row.startLatitude)
        assertEquals(67.0011, row.stopLongitude)
        assertTrue(row.distance > 0.0)
        assertFalse(row.synced)
    }

    @Test
    fun `pending trips ride the flush and are settled only after success`() {
        val tripId = driveOneTrip()
        val http = assertNotNull(sdk.rustEngineState).getConfig().http

        val withTrips = sdk.withPendingTrips(http)
        assertTrue(sdk.hasTripsInFlight)
        val sent = JSONArray(assertNotNull(withTrips.extras?.get("__trips")))
        val ids = (0 until sent.length()).map { sent.getJSONObject(it).getString("trip_id") }
        assertTrue(tripId in ids, "the flush carries the trip that just ended")

        // A failed request settles nothing: the next flush offers it again.
        sdk.withPendingTrips(http)
        assertTrue(db().getUnsyncedTrips(1000).any { it.tripId == tripId })

        sdk.settleTripsInFlight()
        assertFalse(sdk.hasTripsInFlight)
        assertTrue(db().getUnsyncedTrips(1000).none { it.tripId == tripId })
        assertTrue(db().getTrips(1000).any { it.tripId == tripId && it.synced }, "marked, not deleted")
    }

    @Test
    fun `a custom builder receives trips in the default payload's shape`() {
        val tripId = driveOneTrip()

        val exposed = sdk.getTripsForCustomBuilder()
        val trip = exposed.single { it["trip_id"] == tripId }
        assertNotNull(trip["started_at"])
        assertEquals(24.81, (trip["start_location"] as Map<*, *>)["latitude"])
        assertTrue(sdk.hasTripsInFlight, "exposed trips are settled on the next success")
    }
}
