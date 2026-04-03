package com.ikolvi.tracelet.sdk.db

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Tests that the database round-trip (insert → read) produces maps conforming
 * to the canonical Location Map Format contract (`help/LOCATION-MAP-FORMAT.md`).
 *
 * These tests specifically verify the HTTP Sync payload consistency between
 * Android and iOS — see GitHub issue #48.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class LocationMapRoundTripTest {

    private lateinit var db: TraceletDatabase

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        db = TraceletDatabase.getInstance(context)
    }

    @After
    fun tearDown() {
        db.deleteAllLocations()
    }

    private fun makeCanonicalLocation(
        uuid: String = "test-uuid-001",
        timestampMillis: Long = 1718438400000L, // 2024-06-15T12:00:00.000Z
        isMoving: Boolean = true,
    ): Map<String, Any?> = mapOf(
        "uuid" to uuid,
        "timestamp" to timestampMillis,
        "is_moving" to isMoving,
        "odometer" to 1500.5,
        "event" to "location",
        "coords" to mapOf(
            "latitude" to 37.7749,
            "longitude" to -122.4194,
            "altitude" to 50.0,
            "speed" to 5.0,
            "heading" to 180.0,
            "accuracy" to 10.0,
            "speedAccuracy" to 1.5,
            "headingAccuracy" to 5.0,
            "altitudeAccuracy" to 3.0,
        ),
        "battery" to mapOf(
            "level" to 0.75,
            "is_charging" to true,
        ),
        "activity" to mapOf(
            "type" to "walking",
            "confidence" to 85,
        ),
    )

    // =========================================================================
    // is_moving key format (issue #48)
    // =========================================================================

    @Test
    fun `cursorToLocation uses is_moving not isMoving`() {
        val location = makeCanonicalLocation(isMoving = true)
        db.insertLocation(location)
        val rows = db.getLocations(limit = 1)
        assertTrue(rows.isNotEmpty(), "Should have at least one location")
        val row = rows.first()

        assertTrue(row.containsKey("is_moving"), "Must have 'is_moving' key (snake_case)")
        assertFalse(row.containsKey("isMoving"), "Must NOT have 'isMoving' key (camelCase)")
        assertEquals(true, row["is_moving"])
    }

    @Test
    fun `cursorToLocation preserves is_moving false`() {
        val location = makeCanonicalLocation(isMoving = false)
        db.insertLocation(location)
        val rows = db.getLocations(limit = 1)
        val row = rows.first()

        assertEquals(false, row["is_moving"])
    }

    // =========================================================================
    // insertLocation accepts is_moving (canonical format)
    // =========================================================================

    @Test
    fun `insertLocation reads is_moving from canonical format`() {
        val location = makeCanonicalLocation(isMoving = true)
        db.insertLocation(location)
        val rows = db.getLocations(limit = 1)
        val row = rows.first()

        assertEquals(true, row["is_moving"], "is_moving=true must survive round-trip")
    }

    // =========================================================================
    // timestamp format (issue #48)
    // =========================================================================

    @Test
    fun `cursorToLocation returns timestamp as ISO 8601 string`() {
        val location = makeCanonicalLocation(timestampMillis = 1718438400000L)
        db.insertLocation(location)
        val rows = db.getLocations(limit = 1)
        val row = rows.first()

        val timestamp = row["timestamp"]
        assertTrue(timestamp is String, "timestamp must be String, was ${timestamp?.javaClass?.simpleName}")
        assertTrue(
            (timestamp as String).contains("2024-06-15"),
            "ISO timestamp must contain date component, was: $timestamp"
        )
        assertTrue(
            timestamp.endsWith("Z") || timestamp.contains("+"),
            "ISO timestamp must have timezone, was: $timestamp"
        )
    }

    // =========================================================================
    // Nested structure consistency
    // =========================================================================

    @Test
    fun `cursorToLocation has all required nested maps`() {
        db.insertLocation(makeCanonicalLocation())
        val row = db.getLocations(limit = 1).first()

        assertTrue(row.containsKey("coords"), "Must have 'coords'")
        assertTrue(row.containsKey("battery"), "Must have 'battery'")
        assertTrue(row.containsKey("activity"), "Must have 'activity'")
        assertTrue(row["coords"] is Map<*, *>, "coords must be a Map")
        assertTrue(row["battery"] is Map<*, *>, "battery must be a Map")
        assertTrue(row["activity"] is Map<*, *>, "activity must be a Map")
    }

    @Test
    fun `cursorToLocation battery uses is_charging not isCharging`() {
        db.insertLocation(makeCanonicalLocation())
        val row = db.getLocations(limit = 1).first()

        @Suppress("UNCHECKED_CAST")
        val battery = row["battery"] as Map<String, Any?>
        assertTrue(battery.containsKey("is_charging"), "Battery must have 'is_charging'")
        assertFalse(battery.containsKey("isCharging"), "Battery must NOT have 'isCharging'")
    }
}
