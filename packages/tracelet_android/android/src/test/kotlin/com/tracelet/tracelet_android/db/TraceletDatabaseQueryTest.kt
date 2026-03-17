package com.tracelet.tracelet_android.db

import androidx.test.core.app.ApplicationProvider
import com.tracelet.core.db.TraceletDatabase
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Robolectric tests for [TraceletDatabase] location query filtering —
 * verifying that getLocations() and getLocationCount() correctly apply
 * start/end timestamp WHERE clauses.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
internal class TraceletDatabaseQueryTest {

    private lateinit var db: TraceletDatabase

    @Before
    fun setUp() {
        val field = TraceletDatabase::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
        db = TraceletDatabase.getInstance(ApplicationProvider.getApplicationContext())
    }

    @After
    fun tearDown() {
        db.close()
        val field = TraceletDatabase::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }

    /** Helper to insert a location with a specific timestamp. */
    private fun insertAt(timestamp: Long, lat: Double = 37.0, lng: Double = -122.0): String {
        return db.insertLocation(mapOf(
            "latitude" to lat,
            "longitude" to lng,
            "timestamp" to timestamp,
        ))
    }

    // =========================================================================
    // getLocations — timestamp filtering
    // =========================================================================

    @Test
    fun getLocations_noFilters_returnsAll() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        val results = db.getLocations()
        assertEquals(3, results.size)
    }

    @Test
    fun getLocations_withStartTime_filtersOlderLocations() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        val results = db.getLocations(startTime = 2000L)
        assertEquals(2, results.size)
        // All returned timestamps should be >= 2000
        results.forEach { loc ->
            val ts = (loc["timestamp"] as Number).toLong()
            assertTrue(ts >= 2000L, "Expected timestamp >= 2000, got $ts")
        }
    }

    @Test
    fun getLocations_withEndTime_filtersNewerLocations() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        val results = db.getLocations(endTime = 2000L)
        assertEquals(2, results.size)
        results.forEach { loc ->
            val ts = (loc["timestamp"] as Number).toLong()
            assertTrue(ts <= 2000L, "Expected timestamp <= 2000, got $ts")
        }
    }

    @Test
    fun getLocations_withStartAndEnd_filtersToRange() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        insertAt(4000L)
        val results = db.getLocations(startTime = 2000L, endTime = 3000L)
        assertEquals(2, results.size)
        results.forEach { loc ->
            val ts = (loc["timestamp"] as Number).toLong()
            assertTrue(ts in 2000L..3000L, "Expected timestamp in [2000,3000], got $ts")
        }
    }

    @Test
    fun getLocations_startAndEnd_areInclusive() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        // Exact boundary match should be included
        val results = db.getLocations(startTime = 1000L, endTime = 3000L)
        assertEquals(3, results.size)
    }

    @Test
    fun getLocations_noMatchingRange_returnsEmpty() {
        insertAt(1000L)
        insertAt(2000L)
        val results = db.getLocations(startTime = 5000L, endTime = 6000L)
        assertEquals(0, results.size)
    }

    @Test
    fun getLocations_withLimitAndTimeRange() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        insertAt(4000L)
        // Time range matches 3 rows (2000-4000), but limit to 2
        val results = db.getLocations(limit = 2, startTime = 2000L, endTime = 4000L)
        assertEquals(2, results.size)
    }

    @Test
    fun getLocations_withOrderAndTimeRange() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        val resultsAsc = db.getLocations(startTime = 1000L, endTime = 3000L, orderAsc = true)
        val resultsDesc = db.getLocations(startTime = 1000L, endTime = 3000L, orderAsc = false)
        assertEquals(3, resultsAsc.size)
        assertEquals(3, resultsDesc.size)
        // ASC: first timestamp should be smallest
        val firstAsc = (resultsAsc.first()["timestamp"] as Number).toLong()
        val lastAsc = (resultsAsc.last()["timestamp"] as Number).toLong()
        assertTrue(firstAsc <= lastAsc, "ASC order: first ($firstAsc) should be <= last ($lastAsc)")
        // DESC: first timestamp should be largest
        val firstDesc = (resultsDesc.first()["timestamp"] as Number).toLong()
        val lastDesc = (resultsDesc.last()["timestamp"] as Number).toLong()
        assertTrue(firstDesc >= lastDesc, "DESC order: first ($firstDesc) should be >= last ($lastDesc)")
    }

    @Test
    fun getLocations_nullTimestamps_returnAll() {
        insertAt(1000L)
        insertAt(2000L)
        // Explicitly passing null for both should be the same as no filter
        val results = db.getLocations(startTime = null, endTime = null)
        assertEquals(2, results.size)
    }

    // =========================================================================
    // getLocationCount — timestamp filtering
    // =========================================================================

    @Test
    fun getLocationCount_noFilters_countsAll() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        assertEquals(3, db.getLocationCount())
    }

    @Test
    fun getLocationCount_withStartTime() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        assertEquals(2, db.getLocationCount(startTime = 2000L))
    }

    @Test
    fun getLocationCount_withEndTime() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        assertEquals(2, db.getLocationCount(endTime = 2000L))
    }

    @Test
    fun getLocationCount_withStartAndEnd() {
        insertAt(1000L)
        insertAt(2000L)
        insertAt(3000L)
        insertAt(4000L)
        assertEquals(2, db.getLocationCount(startTime = 2000L, endTime = 3000L))
    }

    @Test
    fun getLocationCount_noMatchingRange_returnsZero() {
        insertAt(1000L)
        insertAt(2000L)
        assertEquals(0, db.getLocationCount(startTime = 5000L, endTime = 6000L))
    }

    @Test
    fun getLocationCount_emptyDatabase_returnsZero() {
        assertEquals(0, db.getLocationCount())
        assertEquals(0, db.getLocationCount(startTime = 1000L, endTime = 2000L))
    }
}
