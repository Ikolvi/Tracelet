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
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Robolectric tests for [TraceletDatabase] geofence CRUD — focusing on
 * the `vertices` column for polygon geofences.
 *
 * Uses Robolectric to provide an in-memory SQLite context so the full
 * SQLiteOpenHelper lifecycle (onCreate, onUpgrade) is exercised.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
internal class TraceletDatabaseGeofenceTest {

    private lateinit var db: TraceletDatabase

    @Before
    fun setUp() {
        // Reset singleton so each test gets a fresh database
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

    // =========================================================================
    // Circular geofence (no vertices)
    // =========================================================================

    @Test
    fun insertCircularGeofence_roundTripsCorrectly() {
        val geofence = mapOf<String, Any?>(
            "identifier" to "circle-1",
            "latitude" to 37.7749,
            "longitude" to -122.4194,
            "radius" to 200.0,
            "notifyOnEntry" to true,
            "notifyOnExit" to true,
            "notifyOnDwell" to false,
            "loiteringDelay" to 0,
        )
        assertTrue(db.insertGeofence(geofence))

        val result = db.getGeofence("circle-1")
        assertNotNull(result)
        assertEquals("circle-1", result["identifier"])
        assertEquals(37.7749, result["latitude"])
        assertEquals(-122.4194, result["longitude"])
        assertEquals(200.0, result["radius"])
        // Circular geofence: vertices key should NOT be present
        assertTrue(!result.containsKey("vertices"), "Circular geofence should not have 'vertices' key")
    }

    // =========================================================================
    // Polygon geofence (vertices)
    // =========================================================================

    @Test
    fun insertPolygonGeofence_verticesPersistAndRoundTrip() {
        val vertices = listOf(
            listOf(37.78, -122.42),
            listOf(37.77, -122.41),
            listOf(37.76, -122.43),
            listOf(37.78, -122.42),  // closed ring
        )
        val geofence = mapOf<String, Any?>(
            "identifier" to "polygon-1",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 0.0,
            "vertices" to vertices,
        )
        assertTrue(db.insertGeofence(geofence))

        val result = db.getGeofence("polygon-1")
        assertNotNull(result)
        assertEquals("polygon-1", result["identifier"])

        @Suppress("UNCHECKED_CAST")
        val resultVertices = result["vertices"] as? List<List<Double>>
        assertNotNull(resultVertices, "Polygon geofence should have 'vertices'")
        assertEquals(4, resultVertices.size)
        assertEquals(37.78, resultVertices[0][0], 0.0001)
        assertEquals(-122.42, resultVertices[0][1], 0.0001)
        assertEquals(37.76, resultVertices[2][0], 0.0001)
        assertEquals(-122.43, resultVertices[2][1], 0.0001)
    }

    @Test
    fun insertPolygonGeofence_withFewerThan3Vertices_storesNull() {
        val vertices = listOf(
            listOf(37.78, -122.42),
            listOf(37.77, -122.41),
        )
        val geofence = mapOf<String, Any?>(
            "identifier" to "polygon-2-vert",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 100.0,
            "vertices" to vertices,
        )
        assertTrue(db.insertGeofence(geofence))

        val result = db.getGeofence("polygon-2-vert")
        assertNotNull(result)
        // Fewer than 3 vertices → treated as circular, no vertices key
        assertTrue(!result.containsKey("vertices"), "Geofence with <3 vertices should not have 'vertices' key")
    }

    @Test
    fun insertPolygonGeofence_withEmptyVertices_storesNull() {
        val geofence = mapOf<String, Any?>(
            "identifier" to "polygon-empty",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 100.0,
            "vertices" to emptyList<List<Double>>(),
        )
        assertTrue(db.insertGeofence(geofence))

        val result = db.getGeofence("polygon-empty")
        assertNotNull(result)
        assertTrue(!result.containsKey("vertices"))
    }

    @Test
    fun insertPolygonGeofence_withNullVertices_storesNull() {
        val geofence = mapOf<String, Any?>(
            "identifier" to "polygon-null",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 100.0,
            "vertices" to null,
        )
        assertTrue(db.insertGeofence(geofence))

        val result = db.getGeofence("polygon-null")
        assertNotNull(result)
        assertTrue(!result.containsKey("vertices"))
    }

    @Test
    fun insertPolygonGeofence_skipsInvalidVertexEntries() {
        // Mix of valid and invalid vertex entries
        val vertices = listOf(
            listOf(37.78, -122.42),   // valid
            "not a list",             // invalid
            listOf(37.77, -122.41),   // valid
            listOf(37.76),            // invalid (too few elements)
            listOf(37.75, -122.44),   // valid
        )
        val geofence = mapOf<String, Any?>(
            "identifier" to "polygon-mixed",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 0.0,
            "vertices" to vertices,
        )
        assertTrue(db.insertGeofence(geofence))

        val result = db.getGeofence("polygon-mixed")
        assertNotNull(result)

        @Suppress("UNCHECKED_CAST")
        val resultVertices = result["vertices"] as? List<List<Double>>
        assertNotNull(resultVertices, "Should have 3 valid vertices")
        assertEquals(3, resultVertices.size)
    }

    @Test
    fun insertPolygonGeofence_invalidVerticesBelowMinimum_storesNull() {
        // All invalid except 2 valid → fewer than 3 → null
        val vertices = listOf(
            listOf(37.78, -122.42),
            "invalid",
            listOf(37.77, -122.41),
        )
        val geofence = mapOf<String, Any?>(
            "identifier" to "polygon-too-few-valid",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 100.0,
            "vertices" to vertices,
        )
        assertTrue(db.insertGeofence(geofence))

        val result = db.getGeofence("polygon-too-few-valid")
        assertNotNull(result)
        assertTrue(!result.containsKey("vertices"))
    }

    // =========================================================================
    // Update (replace) preserves vertices
    // =========================================================================

    @Test
    fun insertOrReplace_updatesVertices() {
        // First insert: circular
        val circular = mapOf<String, Any?>(
            "identifier" to "geo-upgrade",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 100.0,
        )
        assertTrue(db.insertGeofence(circular))
        val result1 = db.getGeofence("geo-upgrade")
        assertNotNull(result1)
        assertTrue(!result1.containsKey("vertices"))

        // Second insert: upgrade to polygon
        val polygon = mapOf<String, Any?>(
            "identifier" to "geo-upgrade",
            "latitude" to 37.77,
            "longitude" to -122.42,
            "radius" to 0.0,
            "vertices" to listOf(
                listOf(37.78, -122.42),
                listOf(37.77, -122.41),
                listOf(37.76, -122.43),
            ),
        )
        assertTrue(db.insertGeofence(polygon))
        val result2 = db.getGeofence("geo-upgrade")
        assertNotNull(result2)

        @Suppress("UNCHECKED_CAST")
        val v = result2["vertices"] as? List<List<Double>>
        assertNotNull(v)
        assertEquals(3, v.size)
    }

    // =========================================================================
    // getGeofences (list all) includes vertices
    // =========================================================================

    @Test
    fun getGeofences_returnsPolygonAndCircular() {
        db.insertGeofence(mapOf<String, Any?>(
            "identifier" to "c1",
            "latitude" to 37.0,
            "longitude" to -122.0,
            "radius" to 100.0,
        ))
        db.insertGeofence(mapOf<String, Any?>(
            "identifier" to "p1",
            "latitude" to 38.0,
            "longitude" to -121.0,
            "radius" to 0.0,
            "vertices" to listOf(
                listOf(38.01, -121.01),
                listOf(38.02, -121.02),
                listOf(38.03, -121.03),
            ),
        ))

        val all = db.getGeofences()
        assertEquals(2, all.size)

        val circular = all.find { it["identifier"] == "c1" }
        assertNotNull(circular)
        assertTrue(!circular.containsKey("vertices"))

        val polygon = all.find { it["identifier"] == "p1" }
        assertNotNull(polygon)

        @Suppress("UNCHECKED_CAST")
        val v = polygon["vertices"] as? List<List<Double>>
        assertNotNull(v)
        assertEquals(3, v.size)
    }

    // =========================================================================
    // Delete geofence cleans up vertices
    // =========================================================================

    @Test
    fun deleteGeofence_removesPolygon() {
        db.insertGeofence(mapOf<String, Any?>(
            "identifier" to "to-delete",
            "latitude" to 37.0,
            "longitude" to -122.0,
            "radius" to 0.0,
            "vertices" to listOf(
                listOf(37.01, -122.01),
                listOf(37.02, -122.02),
                listOf(37.03, -122.03),
            ),
        ))
        assertTrue(db.geofenceExists("to-delete"))
        assertTrue(db.deleteGeofence("to-delete"))
        assertNull(db.getGeofence("to-delete"))
    }

    // =========================================================================
    // Database version
    // =========================================================================

    @Test
    fun databaseVersion_isFive() {
        assertEquals(5, db.readableDatabase.version)
    }
}
