package com.ikolvi.tracelet.sdk.location

import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit tests for [LocationMapper] — the single source of truth that maps a
 * persisted location record into the nested schema emitted by onLocation and
 * getLocations (Issue #126). These pin the contract that DB-sourced locations
 * use the SAME nested shape as live locations, so the sync interceptor
 * (setSyncBodyBuilder) and getLocations no longer leak a flat representation.
 */
class LocationMapperTest {

    private fun sampleMap(
        routeContext: String? = null,
        isMoving: Boolean = true,
        odometer: Double = 1234.5,
    ): Map<String, Any?> = LocationMapper.buildLocationMap(
        id = 42L,
        uuid = "uuid-1",
        timestamp = "2026-06-08T10:00:00Z",
        latitude = 48.8566,
        longitude = 2.3522,
        altitude = 35.0,
        speed = 1.2,
        heading = 90.0,
        accuracy = 5.0,
        isMock = false,
        activity = "walking",
        activityConfidence = 75,
        routeContext = routeContext,
        isMoving = isMoving,
        odometer = odometer,
    )

    @Test
    fun coords_areNested_notFlat() {
        val map = sampleMap()
        assertFalse(map.containsKey("latitude"), "must NOT be flat — no top-level latitude")
        @Suppress("UNCHECKED_CAST")
        val coords = map["coords"] as Map<String, Any?>
        assertEquals(48.8566, coords["latitude"])
        assertEquals(2.3522, coords["longitude"])
        assertEquals(35.0, coords["altitude"])
        assertEquals(1.2, coords["speed"])
        assertEquals(90.0, coords["heading"])
        assertEquals(5.0, coords["accuracy"])
    }

    @Test
    fun activity_isNestedMap_notRawString() {
        val map = sampleMap()
        assertTrue(map["activity"] is Map<*, *>, "activity must be a nested map, not a String")
        @Suppress("UNCHECKED_CAST")
        val activity = map["activity"] as Map<String, Any?>
        assertEquals("walking", activity["type"])
        // #245: the record's persisted confidence, no longer hardcoded 100.
        assertEquals(75, activity["confidence"])
    }

    @Test
    fun battery_isNestedMap() {
        @Suppress("UNCHECKED_CAST")
        val battery = sampleMap()["battery"] as Map<String, Any?>
        assertEquals(-1.0, battery["level"])
        assertEquals(false, battery["isCharging"])
    }

    @Test
    fun passesThrough_isMoving_odometer_andMeta() {
        val map = sampleMap(isMoving = true, odometer = 999.0)
        assertEquals(true, map["is_moving"])
        assertEquals(999.0, map["odometer"])
        assertEquals("location", map["event"])
        assertEquals(false, map["mock"])
        assertEquals("uuid-1", map["uuid"])
    }

    @Test
    fun uuid_fallsBackToId_whenNull() {
        val map = LocationMapper.buildLocationMap(
            id = 7L, uuid = null, timestamp = "t", latitude = 0.0, longitude = 0.0,
            altitude = 0.0, speed = 0.0, heading = 0.0, accuracy = 0.0, isMock = false,
            activity = "still", routeContext = null, isMoving = false, odometer = 0.0,
        )
        assertEquals("7", map["uuid"])
    }

    @Test
    fun routeContext_null_producesNoExtras() {
        val map = sampleMap(routeContext = null)
        assertFalse(map.containsKey("extras"))
        assertFalse(map.containsKey("audit_hash"))
    }

    @Test
    fun routeContext_customFields_goIntoExtrasRouteContext() {
        val map = sampleMap(routeContext = """{"taskId":"task-101","driverId":"john"}""")
        @Suppress("UNCHECKED_CAST")
        val extras = map["extras"] as Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val rc = extras["route_context"] as Map<String, Any?>
        assertEquals("task-101", rc["taskId"])
        assertEquals("john", rc["driverId"])
    }

    @Test
    fun routeContext_auditFields_goTopLevel_notIntoExtras() {
        val map = sampleMap(
            routeContext = """{"taskId":"task-101","audit_hash":"h1","audit_previous_hash":"h0","audit_chain_index":7}""",
        )
        assertEquals("h1", map["audit_hash"])
        assertEquals("h0", map["audit_previous_hash"])
        assertEquals(7, map["audit_chain_index"])

        @Suppress("UNCHECKED_CAST")
        val rc = (map["extras"] as Map<String, Any?>)["route_context"] as Map<String, Any?>
        assertEquals("task-101", rc["taskId"])
        assertFalse(rc.containsKey("audit_hash"), "audit fields must not leak into extras.route_context")
        assertNull(rc["audit_chain_index"])
    }

    @Test
    fun routeContext_invalidJson_isIgnoredGracefully() {
        val map = sampleMap(routeContext = "not-json")
        assertFalse(map.containsKey("extras"))
    }

    // #280: locationSource/reducedAccuracy persisted as first-class route_context
    // keys must be promoted to top level (where Location.fromMap reads them) and
    // must NOT leak into extras.route_context.
    @Test
    fun routeContext_locationSourceAndReducedAccuracy_goTopLevel_notIntoExtras() {
        val map = sampleMap(
            routeContext = """{"taskId":"task-1","locationSource":"gps","reducedAccuracy":true}""",
        )
        assertEquals("gps", map["locationSource"])
        assertEquals(true, map["reducedAccuracy"])

        @Suppress("UNCHECKED_CAST")
        val rc = (map["extras"] as Map<String, Any?>)["route_context"] as Map<String, Any?>
        assertEquals("task-1", rc["taskId"])
        assertFalse(rc.containsKey("locationSource"), "must not leak into extras.route_context")
        assertFalse(rc.containsKey("reducedAccuracy"), "must not leak into extras.route_context")
    }

    @Test
    fun routeContext_withoutLocationSource_leavesKeysAbsent() {
        val map = sampleMap(routeContext = """{"taskId":"task-1"}""")
        assertFalse(map.containsKey("locationSource"))
        assertFalse(map.containsKey("reducedAccuracy"))
    }
}
