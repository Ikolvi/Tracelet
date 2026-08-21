package com.ikolvi.tracelet.sdk.algorithm

import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * #402: the trip identity a [TripManager] mints and the trip-start edge it now
 * reports.
 */
class TripManagerIdentityTest {

    private lateinit var tripManager: TripManager
    private var lastTripStart: Map<String, Any?>? = null
    private var lastTripEnd: Map<String, Any?>? = null

    @Before
    fun setUp() {
        tripManager = TripManager()
        lastTripStart = null
        lastTripEnd = null
        tripManager.onTripStart = { data -> lastTripStart = data }
        tripManager.onTripEnd = { data -> lastTripEnd = data }
    }

    @Test
    fun `trip start is reported with a freshly minted id`() {
        // Before #402 a trip only became observable once it was over.
        assertNull(tripManager.currentTripId)

        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)

        val start = assertNotNull(lastTripStart, "onTripStart did not fire")
        val tripId = assertNotNull(start["tripId"] as? String)
        assertTrue(tripId.isNotBlank())
        assertEquals(tripId, tripManager.currentTripId)
        assertNull(lastTripEnd, "the trip has not ended yet")
    }

    @Test
    fun `the summary carries the id minted at start`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 37.42, longitude = -122.08)
        val startedId = tripManager.currentTripId

        tripManager.onMotionStateChanged(isMoving = false, latitude = 37.43, longitude = -122.09)

        val end = assertNotNull(lastTripEnd, "onTripEnd did not fire")
        assertEquals(startedId, end["tripId"], "summary must be joinable to the trip's records")
        assertNotNull(end["startedAt"], "absolute bounds accompany the summary")
        assertNotNull(end["endedAt"])
    }

    @Test
    fun `the id is cleared at trip end and a second trip gets a new one`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 1.0, longitude = 1.0)
        val first = tripManager.currentTripId
        tripManager.onMotionStateChanged(isMoving = false, latitude = 1.1, longitude = 1.1)
        assertNull(tripManager.currentTripId, "the id must not survive trip end")

        tripManager.onMotionStateChanged(isMoving = true, latitude = 2.0, longitude = 2.0)
        val second = tripManager.currentTripId

        assertNotNull(first)
        assertNotNull(second)
        assertNotEquals(first, second, "a second journey was handed the first journey's id")
    }

    @Test
    fun `a motion change that crosses no boundary reports nothing`() {
        tripManager.onMotionStateChanged(isMoving = false, latitude = 1.0, longitude = 1.0)
        assertNull(lastTripStart)
        assertNull(lastTripEnd)

        tripManager.onMotionStateChanged(isMoving = true, latitude = 1.0, longitude = 1.0)
        lastTripStart = null
        tripManager.onMotionStateChanged(isMoving = true, latitude = 1.0, longitude = 1.0)
        assertNull(lastTripStart, "moving while already moving is not a boundary")
    }

    @Test
    fun `reset discards the active trip id`() {
        tripManager.onMotionStateChanged(isMoving = true, latitude = 1.0, longitude = 1.0)
        assertNotNull(tripManager.currentTripId)

        tripManager.reset()

        assertNull(tripManager.currentTripId)
        assertNull(lastTripEnd, "a reset trip produces no summary")
    }
}
