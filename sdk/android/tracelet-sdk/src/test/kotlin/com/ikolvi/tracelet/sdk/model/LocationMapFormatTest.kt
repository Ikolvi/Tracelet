package com.ikolvi.tracelet.sdk.model

import com.ikolvi.tracelet.sdk.util.BatteryUtils
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Tests that location map formats produced by SDK model classes and utilities
 * match the structure expected by the Flutter EventDispatcher's `mapToTlLocation()`.
 *
 * EventDispatcher expects:
 * - `data["coords"]`    → nested map with: latitude, longitude, accuracy, speed,
 *                         heading, altitude, altitudeAccuracy, speedAccuracy, headingAccuracy
 * - `data["battery"]`   → nested map with: level, is_charging
 * - `data["timestamp"]` → string
 * - `data["uuid"]`      → string
 * - `data["is_moving"]` or `data["isMoving"]` → boolean
 * - `data["odometer"]`  → double
 * - `data["event"]`     → string
 * - `data["activity"]`  → map with: type, confidence
 * - `data["extras"]`    → map (optional)
 * - `data["mock"]`      → boolean (pass-through)
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class LocationMapFormatTest {

    // =========================================================================
    // BatteryUtils format
    // =========================================================================

    @Test
    fun `BatteryUtils getBatteryInfo uses is_charging key`() {
        val context = RuntimeEnvironment.getApplication()
        val info = BatteryUtils.getBatteryInfo(context)

        assertTrue(info.containsKey("level"), "Battery map must contain 'level'")
        assertTrue(info.containsKey("is_charging"), "Battery map must contain 'is_charging'")
        assertFalse(
            info.containsKey("isCharging"),
            "Battery map must NOT contain camelCase 'isCharging'"
        )
    }

    @Test
    fun `BatteryUtils getBatteryInfo level is between -1 and 1`() {
        val context = RuntimeEnvironment.getApplication()
        val info = BatteryUtils.getBatteryInfo(context)
        val level = info["level"] as Double
        assertTrue(level >= -1.0 && level <= 1.0, "Level=$level out of range [-1, 1]")
    }

    @Test
    fun `BatteryUtils getBatteryInfo is_charging is boolean`() {
        val context = RuntimeEnvironment.getApplication()
        val info = BatteryUtils.getBatteryInfo(context)
        assertTrue(info["is_charging"] is Boolean, "is_charging must be Boolean")
    }

    // =========================================================================
    // TraceletBattery model
    // =========================================================================

    @Test
    fun `TraceletBattery toMap uses is_charging key`() {
        val battery = TraceletBattery(isCharging = true, level = 0.85)
        val map = battery.toMap()
        assertTrue(map.containsKey("is_charging"), "Must contain 'is_charging'")
        assertFalse(map.containsKey("isCharging"), "Must not contain 'isCharging'")
        assertEquals(true, map["is_charging"])
        assertEquals(0.85, map["level"])
    }

    @Test
    fun `TraceletBattery fromMap reads is_charging key`() {
        val map = mapOf<String, Any?>("is_charging" to true, "level" to 0.5)
        val battery = TraceletBattery.fromMap(map)
        assertTrue(battery.isCharging)
        assertEquals(0.5, battery.level)
    }

    @Test
    fun `TraceletBattery round-trip preserves values`() {
        val original = TraceletBattery(isCharging = true, level = 0.72)
        val roundTripped = TraceletBattery.fromMap(original.toMap())
        assertEquals(original.isCharging, roundTripped.isCharging)
        assertEquals(original.level, roundTripped.level)
    }

    // =========================================================================
    // TraceletCoords model
    // =========================================================================

    @Test
    fun `TraceletCoords toMap uses camelCase keys`() {
        val coords = TraceletCoords(
            latitude = 37.7749,
            longitude = -122.4194,
            altitude = 50.0,
            speed = 5.0,
            heading = 180.0,
            accuracy = 10.0,
            speedAccuracy = 1.5,
            headingAccuracy = 5.0,
            altitudeAccuracy = 3.0,
        )
        val map = coords.toMap()

        // Verify camelCase keys (EventDispatcher expects these)
        assertTrue(map.containsKey("altitudeAccuracy"), "Must use 'altitudeAccuracy' (camelCase)")
        assertTrue(map.containsKey("speedAccuracy"), "Must use 'speedAccuracy' (camelCase)")
        assertTrue(map.containsKey("headingAccuracy"), "Must use 'headingAccuracy' (camelCase)")

        // Verify NO snake_case keys
        assertFalse(map.containsKey("altitude_accuracy"), "Must NOT use 'altitude_accuracy'")
        assertFalse(map.containsKey("speed_accuracy"), "Must NOT use 'speed_accuracy'")
        assertFalse(map.containsKey("heading_accuracy"), "Must NOT use 'heading_accuracy'")

        // Verify all values
        assertEquals(37.7749, map["latitude"])
        assertEquals(-122.4194, map["longitude"])
        assertEquals(50.0, map["altitude"])
        assertEquals(5.0, map["speed"])
        assertEquals(180.0, map["heading"])
        assertEquals(10.0, map["accuracy"])
        assertEquals(1.5, map["speedAccuracy"])
        assertEquals(5.0, map["headingAccuracy"])
        assertEquals(3.0, map["altitudeAccuracy"])
    }

    @Test
    fun `TraceletCoords round-trip preserves all fields`() {
        val original = TraceletCoords(
            latitude = 51.5074,
            longitude = -0.1278,
            altitude = 11.2,
            speed = 3.5,
            heading = 90.0,
            accuracy = 8.0,
            speedAccuracy = 0.5,
            headingAccuracy = 2.0,
            altitudeAccuracy = 1.5,
        )
        val roundTripped = TraceletCoords.fromMap(original.toMap())
        assertEquals(original.latitude, roundTripped.latitude)
        assertEquals(original.longitude, roundTripped.longitude)
        assertEquals(original.altitude, roundTripped.altitude)
        assertEquals(original.speed, roundTripped.speed)
        assertEquals(original.heading, roundTripped.heading)
        assertEquals(original.accuracy, roundTripped.accuracy)
        assertEquals(original.speedAccuracy, roundTripped.speedAccuracy)
        assertEquals(original.headingAccuracy, roundTripped.headingAccuracy)
        assertEquals(original.altitudeAccuracy, roundTripped.altitudeAccuracy)
    }

    // =========================================================================
    // TraceletActivity model
    // =========================================================================

    @Test
    fun `TraceletActivity toMap produces type and confidence`() {
        val activity = TraceletActivity(type = "walking", confidence = 92)
        val map = activity.toMap()
        assertEquals("walking", map["type"])
        assertEquals(92, map["confidence"])
    }

    @Test
    fun `TraceletActivity defaults to unknown and -1`() {
        val activity = TraceletActivity()
        val map = activity.toMap()
        assertEquals("unknown", map["type"])
        assertEquals(-1, map["confidence"])
    }

    @Test
    fun `TraceletActivity round-trip preserves values`() {
        val original = TraceletActivity(type = "in_vehicle", confidence = 80)
        val roundTripped = TraceletActivity.fromMap(original.toMap())
        assertEquals(original.type, roundTripped.type)
        assertEquals(original.confidence, roundTripped.confidence)
    }

    // =========================================================================
    // TraceletLocation model — full map format compliance
    // =========================================================================

    @Test
    fun `TraceletLocation toMap has nested coords`() {
        val location = makeTestLocation()
        val map = location.toMap()
        assertTrue(map.containsKey("coords"), "Must have nested 'coords' map")
        @Suppress("UNCHECKED_CAST")
        val coords = map["coords"] as Map<String, Any?>
        assertEquals(37.7749, coords["latitude"])
        assertEquals(-122.4194, coords["longitude"])
    }

    @Test
    fun `TraceletLocation toMap does not have flat coordinate keys`() {
        val location = makeTestLocation()
        val map = location.toMap()
        assertFalse(map.containsKey("latitude"), "Must NOT have flat 'latitude'")
        assertFalse(map.containsKey("longitude"), "Must NOT have flat 'longitude'")
        assertFalse(map.containsKey("accuracy"), "Must NOT have flat 'accuracy'")
        assertFalse(map.containsKey("speed"), "Must NOT have flat 'speed'")
        assertFalse(map.containsKey("heading"), "Must NOT have flat 'heading'")
        assertFalse(map.containsKey("altitude"), "Must NOT have flat 'altitude'")
    }

    @Test
    fun `TraceletLocation toMap has nested battery with is_charging`() {
        val location = makeTestLocation()
        val map = location.toMap()
        assertTrue(map.containsKey("battery"), "Must have nested 'battery' map")
        @Suppress("UNCHECKED_CAST")
        val battery = map["battery"] as Map<String, Any?>
        assertTrue(battery.containsKey("is_charging"), "Battery must have 'is_charging'")
        assertTrue(battery.containsKey("level"), "Battery must have 'level'")
        assertFalse(battery.containsKey("isCharging"), "Battery must NOT have 'isCharging'")
    }

    @Test
    fun `TraceletLocation toMap has nested activity with type and confidence`() {
        val location = makeTestLocation()
        val map = location.toMap()
        assertTrue(map.containsKey("activity"), "Must have 'activity' map")
        @Suppress("UNCHECKED_CAST")
        val activity = map["activity"] as Map<String, Any?>
        assertEquals("walking", activity["type"])
        assertEquals(85, activity["confidence"])
    }

    @Test
    fun `TraceletLocation toMap uses is_moving key`() {
        val location = makeTestLocation()
        val map = location.toMap()
        assertTrue(map.containsKey("is_moving"), "Must have 'is_moving' key")
        // EventDispatcher checks both is_moving and isMoving, but the model
        // should consistently use is_moving.
        assertEquals(true, map["is_moving"])
    }

    @Test
    fun `TraceletLocation toMap has required string fields`() {
        val location = makeTestLocation()
        val map = location.toMap()
        assertEquals("test-uuid-123", map["uuid"])
        assertEquals("2024-06-15T12:00:00.000Z", map["timestamp"])
        assertEquals("location", map["event"])
    }

    @Test
    fun `TraceletLocation toMap has odometer as double`() {
        val location = makeTestLocation()
        val map = location.toMap()
        assertEquals(1500.5, map["odometer"])
    }

    @Test
    fun `TraceletLocation toMap uses mock key not isMock`() {
        val location = makeTestLocation(isMock = true)
        val map = location.toMap()
        assertTrue(map.containsKey("mock"), "Must use 'mock' key")
        assertFalse(map.containsKey("isMock"), "Must NOT use 'isMock' key")
        assertEquals(true, map["mock"])
    }

    @Test
    fun `TraceletLocation toMap coords use camelCase accuracy keys`() {
        val location = makeTestLocation()
        val map = location.toMap()
        @Suppress("UNCHECKED_CAST")
        val coords = map["coords"] as Map<String, Any?>
        assertTrue(coords.containsKey("altitudeAccuracy"), "Coords must have 'altitudeAccuracy'")
        assertTrue(coords.containsKey("speedAccuracy"), "Coords must have 'speedAccuracy'")
        assertTrue(coords.containsKey("headingAccuracy"), "Coords must have 'headingAccuracy'")
        assertFalse(coords.containsKey("altitude_accuracy"), "Must NOT use snake_case")
        assertFalse(coords.containsKey("speed_accuracy"), "Must NOT use snake_case")
        assertFalse(coords.containsKey("heading_accuracy"), "Must NOT use snake_case")
    }

    @Test
    fun `TraceletLocation toMap includes extras when non-empty`() {
        val location = makeTestLocation(extras = mapOf("route" to "A"))
        val map = location.toMap()
        @Suppress("UNCHECKED_CAST")
        val extras = map["extras"] as? Map<String, Any?>
        assertNotNull(extras)
        assertEquals("A", extras["route"])
    }

    @Test
    fun `TraceletLocation toMap omits extras when empty`() {
        val location = makeTestLocation(extras = emptyMap())
        val map = location.toMap()
        assertFalse(map.containsKey("extras"), "Empty extras should be omitted")
    }

    @Test
    fun `TraceletLocation fromMap reads is_moving key`() {
        val map = makeTestLocationMap(motionKey = "is_moving")
        val location = TraceletLocation.fromMap(map)
        assertTrue(location.isMoving)
    }

    @Test
    fun `TraceletLocation fromMap reads mock key`() {
        val map = makeTestLocationMap()
        val modded = map.toMutableMap().apply { put("mock", true) }
        val location = TraceletLocation.fromMap(modded)
        assertTrue(location.isMock)
    }

    @Test
    fun `TraceletLocation full round-trip preserves all fields`() {
        val original = makeTestLocation(isMock = true, extras = mapOf("task" to "delivery"))
        val map = original.toMap()
        val restored = TraceletLocation.fromMap(map)

        assertEquals(original.coords.latitude, restored.coords.latitude)
        assertEquals(original.coords.longitude, restored.coords.longitude)
        assertEquals(original.coords.accuracy, restored.coords.accuracy)
        assertEquals(original.coords.speed, restored.coords.speed)
        assertEquals(original.coords.heading, restored.coords.heading)
        assertEquals(original.coords.altitude, restored.coords.altitude)
        assertEquals(original.coords.altitudeAccuracy, restored.coords.altitudeAccuracy)
        assertEquals(original.coords.speedAccuracy, restored.coords.speedAccuracy)
        assertEquals(original.coords.headingAccuracy, restored.coords.headingAccuracy)
        assertEquals(original.timestamp, restored.timestamp)
        assertEquals(original.isMoving, restored.isMoving)
        assertEquals(original.uuid, restored.uuid)
        assertEquals(original.odometer, restored.odometer)
        assertEquals(original.event, restored.event)
        assertEquals(original.isMock, restored.isMock)
        assertEquals(original.activity.type, restored.activity.type)
        assertEquals(original.activity.confidence, restored.activity.confidence)
        assertEquals(original.battery.isCharging, restored.battery.isCharging)
        assertEquals(original.battery.level, restored.battery.level)
        assertEquals(original.extras, restored.extras)
    }

    // =========================================================================
    // Simulated EventDispatcher consumption — verifies readability
    // =========================================================================

    @Test
    fun `simulated EventDispatcher can read TraceletLocation toMap correctly`() {
        val location = makeTestLocation()
        val data = location.toMap()

        // Simulate what Android EventDispatcher.mapToTlLocation does:
        @Suppress("UNCHECKED_CAST")
        val coordsMap = data["coords"] as? Map<String, Any?> ?: emptyMap()
        @Suppress("UNCHECKED_CAST")
        val batteryMap = data["battery"] as? Map<String, Any?> ?: emptyMap()
        @Suppress("UNCHECKED_CAST")
        val activityMap = data["activity"] as? Map<String, Any?>

        // coords
        assertEquals(37.7749, (coordsMap["latitude"] as? Number)?.toDouble())
        assertEquals(-122.4194, (coordsMap["longitude"] as? Number)?.toDouble())
        assertEquals(10.0, (coordsMap["accuracy"] as? Number)?.toDouble())
        assertEquals(5.0, (coordsMap["speed"] as? Number)?.toDouble())
        assertEquals(180.0, (coordsMap["heading"] as? Number)?.toDouble())
        assertEquals(50.0, (coordsMap["altitude"] as? Number)?.toDouble())
        assertEquals(3.0, (coordsMap["altitudeAccuracy"] as? Number)?.toDouble())
        assertEquals(1.5, (coordsMap["speedAccuracy"] as? Number)?.toDouble())
        assertEquals(5.0, (coordsMap["headingAccuracy"] as? Number)?.toDouble())

        // battery
        assertEquals(0.85, (batteryMap["level"] as? Number)?.toDouble())
        assertEquals(true, batteryMap["is_charging"] as? Boolean)

        // top-level
        assertEquals("test-uuid-123", data["uuid"] as? String)
        assertEquals("2024-06-15T12:00:00.000Z", data["timestamp"] as? String)
        val isMoving = (data["is_moving"] ?: data["isMoving"]) as? Boolean
        assertEquals(true, isMoving)
        assertEquals(1500.5, (data["odometer"] as? Number)?.toDouble())
        assertEquals("location", data["event"] as? String)

        // activity
        assertNotNull(activityMap)
        assertEquals("walking", activityMap["type"] as? String)
        assertEquals(85, (activityMap["confidence"] as? Number)?.toInt())
    }

    @Test
    fun `simulated EventDispatcher handles missing optional fields gracefully`() {
        // Minimal location map — only required fields
        val data = mapOf<String, Any?>(
            "coords" to mapOf(
                "latitude" to 0.0,
                "longitude" to 0.0,
            ),
            "battery" to mapOf(
                "level" to -1.0,
                "is_charging" to false,
            ),
            "timestamp" to "",
            "uuid" to "",
            "isMoving" to false,
            "odometer" to 0.0,
        )

        // EventDispatcher reads these with defaults
        @Suppress("UNCHECKED_CAST")
        val coordsMap = data["coords"] as? Map<String, Any?> ?: emptyMap()
        assertEquals(0.0, (coordsMap["latitude"] as? Number)?.toDouble())
        assertEquals(-1.0, (coordsMap["accuracy"] as? Number)?.toDouble() ?: -1.0)

        val event = data["event"] as? String  // null/absent is OK
        assertNull(event)

        @Suppress("UNCHECKED_CAST")
        val activityMap = data["activity"] as? Map<String, Any?>
        assertNull(activityMap) // null activity is acceptable
    }

    // =========================================================================
    // TraceletGeofenceEvent — location nesting in geofence events
    // =========================================================================

    @Test
    fun `TraceletGeofenceEvent toMap nests location correctly`() {
        val location = makeTestLocation()
        val event = TraceletGeofenceEvent(
            identifier = "office",
            action = "ENTER",
            location = location,
        )
        val map = event.toMap()
        assertEquals("office", map["identifier"])
        assertEquals("ENTER", map["action"])

        @Suppress("UNCHECKED_CAST")
        val locMap = map["location"] as? Map<String, Any?>
        assertNotNull(locMap, "Geofence event must contain nested 'location'")
        assertTrue(locMap.containsKey("coords"), "Nested location must have 'coords'")
        assertTrue(locMap.containsKey("battery"), "Nested location must have 'battery'")
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    private fun makeTestLocation(
        isMock: Boolean = false,
        extras: Map<String, Any?> = emptyMap(),
    ): TraceletLocation = TraceletLocation(
        coords = TraceletCoords(
            latitude = 37.7749,
            longitude = -122.4194,
            altitude = 50.0,
            speed = 5.0,
            heading = 180.0,
            accuracy = 10.0,
            speedAccuracy = 1.5,
            headingAccuracy = 5.0,
            altitudeAccuracy = 3.0,
        ),
        timestamp = "2024-06-15T12:00:00.000Z",
        isMoving = true,
        uuid = "test-uuid-123",
        odometer = 1500.5,
        event = "location",
        isMock = isMock,
        activity = TraceletActivity(type = "walking", confidence = 85),
        battery = TraceletBattery(isCharging = true, level = 0.85),
        extras = extras,
    )

    private fun makeTestLocationMap(motionKey: String = "is_moving"): Map<String, Any?> = mapOf(
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
            "level" to 0.85,
            "is_charging" to true,
        ),
        "activity" to mapOf(
            "type" to "walking",
            "confidence" to 85,
        ),
        "timestamp" to "2024-06-15T12:00:00.000Z",
        "uuid" to "test-uuid-123",
        motionKey to true,
        "odometer" to 1500.5,
        "event" to "location",
        "mock" to false,
    )
}
