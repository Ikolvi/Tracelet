package com.ikolvi.tracelet.flutter.db

import uniffi.tracelet_core.DatabaseManager
import uniffi.tracelet_core.LocationQuery
import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import java.io.File

class TraceletDatabaseQueryTest {

    private lateinit var db: DatabaseManager
    private lateinit var tempFile: File

    @Before
    fun setUp() {
        tempFile = File.createTempFile("test_db", ".sqlite")
        db = DatabaseManager(tempFile.absolutePath)
    }

    @After
    fun tearDown() {
        db.close()
        tempFile.delete()
    }

    private fun insertAt(timestamp: Long, lat: Double = 37.0, lng: Double = -122.0) {
        db.insertLocation(
            uuid = null,
            lat = lat,
            lng = lng,
            acc = 10.0,
            speed = 0.0,
            heading = 0.0,
            altitude = 0.0,
            isMock = false,
            isMoving = false,
            activity = "still",
            activityConfidence = -1,
            routeContext = null,
            timestampOverride = java.time.Instant.ofEpochMilli(timestamp).toString(),
            eventType = null,
            eventPayload = null,
            address = null
        )
    }

    @Test
    fun getLocations_noFilters_returnsAll() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        val results = db.getLocationsBatch(null)
        assertEquals(3, results.size)
    }

    @Test
    fun getLocations_withStartTime_filtersOlderLocations() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        val query = LocationQuery(startTimeMs = 2000L, endTimeMs = null, limit = null, offset = null, orderDescending = null)
        val results = db.getLocationsBatch(query)
        assertEquals(2, results.size)
    }

    @Test
    fun getLocations_withStartAndEnd_filtersToRange() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        insertAt(4000L)
        val query = LocationQuery(startTimeMs = 2000L, endTimeMs = 3000L, limit = null, offset = null, orderDescending = null)
        val results = db.getLocationsBatch(query)
        assertEquals(2, results.size)
    }

    @Test
    fun getLocationCount_noFilters_countsAll() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        assertEquals(3, db.getLocationsCount())
    }
}
