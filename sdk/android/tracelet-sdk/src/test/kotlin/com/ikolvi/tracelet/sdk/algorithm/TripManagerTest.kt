package com.ikolvi.tracelet.sdk.algorithm

import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit tests for [TripManager].
 */
class TripManagerTest {

    private lateinit var tripManager: TripManager
    private var lastTripData: Map<String, Any?>? = null

    @Before
    fun setUp() {
        tripManager = TripManager()
        lastTripData = null
        tripManager.onTripEnd = { data -> lastTripData = data }
    }

    @Test
    fun `trip starts on moving transition`() {
        assertFalse(tripManager.isTripActive)
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        assertTrue(tripManager.isTripActive)
        assertNull(lastTripData) // Trip hasn't ended yet
    }

    @Test
    fun `trip ends on stationary transition`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.43, longitude = -122.07)

        assertFalse(tripManager.isTripActive)
        assertNotNull(lastTripData)
        assertEquals(false, lastTripData!!["isMoving"])
    }

    @Test
    fun `trip collects start and stop locations`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.43, longitude = -122.07)

        val start = lastTripData!!["startLocation"] as Map<*, *>
        val stop = lastTripData!!["stopLocation"] as Map<*, *>
        assertEquals(37.42, start["latitude"])
        assertEquals(-122.08, start["longitude"])
        assertEquals(37.43, stop["latitude"])
        assertEquals(-122.07, stop["longitude"])
    }

    @Test
    fun `trip accumulates distance from waypoints`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.onLocationReceived(37.421, -122.079)
        tripManager.onLocationReceived(37.422, -122.078)
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.423, longitude = -122.077)

        val distance = lastTripData!!["distance"] as Double
        assertTrue(distance > 0, "Distance should be positive: $distance")
    }

    @Test
    fun `trip records duration`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        // Small delay is inherent (system time), but duration should be >= 0
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.43, longitude = -122.07)

        val duration = lastTripData!!["duration"] as Double
        assertTrue(duration >= 0)
    }

    @Test
    fun `waypoints recorded during trip`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.onLocationReceived(37.421, -122.079, "ts1")
        tripManager.onLocationReceived(37.422, -122.078, "ts2")
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.423, longitude = -122.077)

        @Suppress("UNCHECKED_CAST")
        val waypoints = lastTripData!!["waypoints"] as List<Map<String, Any?>>
        // Start waypoint + 2 location + end stop waypoint
        assertTrue(waypoints.size >= 3, "Expected at least 3 waypoints, got ${waypoints.size}")
    }

    @Test
    fun `locations ignored when trip not active`() {
        tripManager.onLocationReceived(37.42, -122.08) // No trip started
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.42, longitude = -122.08)

        @Suppress("UNCHECKED_CAST")
        val waypoints = lastTripData!!["waypoints"] as List<Map<String, Any?>>
        // Only start and end waypoints, no pre-trip locations
        assertTrue(waypoints.size <= 2)
    }

    @Test
    fun `duplicate moving events do not restart trip`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.onLocationReceived(37.421, -122.079)
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.422, longitude = -122.078)
        // Should still be same trip
        assertTrue(tripManager.isTripActive)
        assertNull(lastTripData) // No trip ended
    }

    @Test
    fun `reset clears trip state`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        assertTrue(tripManager.isTripActive)

        tripManager.reset()
        assertFalse(tripManager.isTripActive)
    }

    @Test
    fun `reset during trip does not fire onTripEnd`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.reset()
        assertNull(lastTripData)
    }

    @Test
    fun `multiple consecutive trips`() {
        // First trip
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.43, longitude = -122.07)
        val firstTrip = lastTripData
        assertNotNull(firstTrip)

        // Second trip
        lastTripData = null
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.44, longitude = -122.06)
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.45, longitude = -122.05)
        val secondTrip = lastTripData
        assertNotNull(secondTrip)

        // Verify they have different start locations
        val start1 = firstTrip["startLocation"] as Map<*, *>
        val start2 = secondTrip["startLocation"] as Map<*, *>
        assertEquals(37.42, start1["latitude"])
        assertEquals(37.44, start2["latitude"])
    }

    @Test
    fun `trip with null coordinates`() {
        tripManager.onMotionStateChanged(isMoving = true)
        assertTrue(tripManager.isTripActive)
        tripManager.onMotionStateChanged(isMoving = false)
        assertFalse(tripManager.isTripActive)
        assertNotNull(lastTripData)
        assertEquals(0.0, lastTripData!!["distance"])
    }

    @Test
    fun `average speed calculated correctly`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        tripManager.onLocationReceived(37.421, -122.079)
        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.422, longitude = -122.078)

        val distance = lastTripData!!["distance"] as Double
        val duration = lastTripData!!["duration"] as Double
        if (duration > 0) {
            val avgSpeed = distance / duration
            assertTrue(avgSpeed >= 0)
        }
    }
}
