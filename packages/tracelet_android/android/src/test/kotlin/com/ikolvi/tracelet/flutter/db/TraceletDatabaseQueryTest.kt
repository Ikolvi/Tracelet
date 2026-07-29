package com.ikolvi.tracelet.flutter.db

import com.ikolvi.tracelet.sdk.location.LocationMapper
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

    // #280: end-to-end proof that locationSource / reducedAccuracy survive the
    // real Rust DB round-trip when persisted as route_context keys (the shape
    // TraceletSdk.insertLocation writes) and are promoted to top level by
    // LocationMapper on read — where Location.fromMap reads them.
    @Test
    fun routeContext_locationSourceAndReducedAccuracy_surviveDbRoundTrip() {
        db.insertLocation(
            uuid = "issue-280",
            lat = 37.0,
            lng = -122.0,
            acc = 8.0,
            speed = 0.0,
            heading = 0.0,
            altitude = 0.0,
            isMock = false,
            isMoving = false,
            activity = "still",
            activityConfidence = -1,
            routeContext = """{"locationSource":"gps","reducedAccuracy":true}""",
            timestampOverride = java.time.Instant.ofEpochMilli(1000L).toString(),
            eventType = null,
            eventPayload = null,
            address = null,
        )

        val record = db.getLocationsBatch(null).single()
        val map = LocationMapper.buildLocationMap(
            id = record.id,
            uuid = record.uuid,
            timestamp = record.timestamp,
            latitude = record.latitude,
            longitude = record.longitude,
            altitude = record.altitude,
            speed = record.speed,
            heading = record.heading,
            accuracy = record.accuracy,
            isMock = record.isMock,
            activity = record.activity,
            activityConfidence = record.activityConfidence,
            routeContext = record.routeContext,
            isMoving = record.isMoving,
            odometer = 0.0,
            eventType = record.eventType,
            eventPayload = record.eventPayload,
            address = record.address,
        )

        assertEquals("gps", map["locationSource"])
        assertEquals(true, map["reducedAccuracy"])
    }
}
