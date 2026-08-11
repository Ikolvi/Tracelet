package com.ikolvi.tracelet.flutter.db

import uniffi.tracelet_core.DatabaseManager
import uniffi.tracelet_core.Coordinate
import org.junit.After
import org.junit.Before
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import java.io.File

class TraceletDatabaseGeofenceTest {

    private lateinit var db: DatabaseManager
    private lateinit var tempFile: File

    @Before
    fun setUp() {
        tempFile = File.createTempFile("test_geo", ".sqlite")
        db = DatabaseManager(tempFile.absolutePath)
    }

    @After
    fun tearDown() {
        db.close()
        tempFile.delete()
    }

    @Test
    fun insertCircularGeofence_roundTripsCorrectly() {
        db.insertGeofence(
            identifier = "circle-1",
            lat = 37.7749,
            lng = -122.4194,
            radius = 200.0,
            vertices = null,
            extras = null,
            notifyOnEntry = true,
            notifyOnExit = true,
            notifyOnDwell = true,
            loiteringDelay = 30000,
        )

        val result = db.getGeofences().find { it.identifier == "circle-1" }
        assertNotNull(result)
        assertEquals("circle-1", result.identifier)
        assertEquals(37.7749, result.latitude)
        assertEquals(-122.4194, result.longitude)
        assertEquals(200.0, result.radius)
        assertTrue(result.vertices.isNullOrEmpty())
        // #355: the notify_* flags and loitering delay must round-trip, or a
        // fence rebuilt from the DB after a reboot silently loses DWELL.
        assertTrue(result.notifyOnEntry)
        assertTrue(result.notifyOnExit)
        assertTrue(result.notifyOnDwell)
        assertEquals(30000, result.loiteringDelay)
    }

    @Test
    fun insertPolygonGeofence_verticesPersistAndRoundTrip() {
        val vertices = listOf(
            Coordinate(37.78, -122.42),
            Coordinate(37.77, -122.41),
            Coordinate(37.76, -122.43),
            Coordinate(37.78, -122.42)
        )
        db.insertGeofence(
            identifier = "polygon-1",
            lat = 37.77,
            lng = -122.42,
            radius = 0.0,
            vertices = vertices,
            extras = null,
            notifyOnEntry = true,
            notifyOnExit = true,
            notifyOnDwell = false,
            loiteringDelay = 0,
        )

        val result = db.getGeofences().find { it.identifier == "polygon-1" }
        assertNotNull(result)
        assertEquals("polygon-1", result.identifier)

        val resultVertices = result.vertices
        assertNotNull(resultVertices)
        assertEquals(4, resultVertices.size)
        assertEquals(37.78, resultVertices[0].lat)
        assertEquals(-122.42, resultVertices[0].lng)
        assertEquals(37.76, resultVertices[2].lat)
        assertEquals(-122.43, resultVertices[2].lng)
    }

    @Test
    fun deleteGeofence_removesGeofence() {
        db.insertGeofence("to-delete", 37.0, -122.0, 100.0, null, null, true, true, false, 0)
        assertTrue(db.getGeofences().any { it.identifier == "to-delete" })
        
        db.deleteGeofence("to-delete")
        assertNull(db.getGeofences().find { it.identifier == "to-delete" })
    }
}
