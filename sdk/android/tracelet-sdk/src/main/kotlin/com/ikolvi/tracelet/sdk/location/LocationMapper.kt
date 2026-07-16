package com.ikolvi.tracelet.sdk.location

import org.json.JSONArray
import org.json.JSONObject

/**
 * Single source of truth for converting a persisted location record into the
 * nested location schema emitted by `onLocation` and `getLocations`.
 *
 * Issue #126: the sync interceptor sinks (`TraceletSyncSink`, `NativeSyncProvider`)
 * previously built a flat map with a raw `String` `activity`, diverging from the
 * live nested schema and forcing developers to write conditional parsing
 * (and crashing code that assumed the nested shape). Routing every DB-sourced
 * map through this mapper guarantees an identical shape everywhere and restores
 * `route_context` / audit-hash metadata that `getLocations` used to drop.
 */
object LocationMapper {

    /**
     * Builds the canonical nested location map from raw record fields.
     *
     * `route_context` (a JSON string persisted with the record) is split:
     * audit fields (`audit_hash`, `audit_previous_hash`, `audit_chain_index`)
     * are promoted to top-level keys so they populate `Location.auditHash` etc.,
     * while the remaining fields are nested under `extras.route_context` so they
     * surface as `Location.extras['route_context']`.
     */
    fun buildLocationMap(
        id: Long,
        uuid: String?,
        timestamp: String,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        speed: Double,
        heading: Double,
        accuracy: Double,
        isMock: Boolean,
        activity: String,
        activityConfidence: Int = -1,
        routeContext: String?,
        isMoving: Boolean,
        odometer: Double,
        eventType: String = "location",
        eventPayload: String? = null,
        address: String? = null,
    ): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>(
            "uuid" to (uuid ?: id.toString()),
            "timestamp" to timestamp,
            "is_moving" to isMoving,
            "odometer" to odometer,
            "event" to eventType,
            "mock" to isMock,
            "coords" to mapOf(
                "latitude" to latitude,
                "longitude" to longitude,
                "altitude" to altitude,
                "speed" to speed,
                "heading" to heading,
                "accuracy" to accuracy,
            ),
            "activity" to mapOf(
                // #245: the persisted confidence — was hardcoded 100, masking
                // the real AR/fused value on every DB-sourced read.
                "type" to activity,
                "confidence" to activityConfidence,
            ),
            "battery" to mapOf(
                "level" to -1.0,
                "isCharging" to false,
            ),
        )
        
        if (eventType == "geofence" && !eventPayload.isNullOrBlank()) {
            try {
                map["geofence"] = jsonToKotlin(JSONObject(eventPayload))
            } catch (e: Exception) {
                // ignore
            }
        }

        // #187: surface the persisted reverse-geocoded address into the same
        // nested shape used by the live onLocation event, so it appears in
        // getLocations() and the sync payload.
        if (!address.isNullOrBlank()) {
            try {
                map["address"] = jsonToKotlin(JSONObject(address))
            } catch (e: Exception) {
                // ignore malformed address JSON
            }
        }

        applyRouteContext(map, routeContext)
        return map
    }

    private fun applyRouteContext(map: MutableMap<String, Any?>, routeContext: String?) {
        val raw = routeContext?.takeIf { it.isNotBlank() } ?: return
        val json = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return
        }
        val extrasRouteContext = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            when (val key = keys.next()) {
                "audit_hash" -> map["audit_hash"] = json.optString(key)
                "audit_previous_hash" -> map["audit_previous_hash"] = json.optString(key)
                "audit_chain_index" -> map["audit_chain_index"] = json.optInt(key)
                "battery" -> {
                    val batteryJson = json.optJSONObject(key)
                    if (batteryJson != null) {
                        map["battery"] = mapOf(
                            "level" to batteryJson.optDouble("level", -1.0),
                            "isCharging" to batteryJson.optBoolean("is_charging", batteryJson.optBoolean("isCharging", false))
                        )
                    }
                }
                "extras" -> {
                    val extrasJson = json.optJSONObject(key)
                    if (extrasJson != null) {
                        val parsed = jsonToKotlin(extrasJson)
                        if (parsed is Map<*, *>) {
                            map["extras"] = parsed
                        }
                    }
                }
                else -> extrasRouteContext[key] = jsonToKotlin(json.get(key))
            }
        }
        if (extrasRouteContext.isNotEmpty()) {
            val existingExtras = map["extras"] as? Map<*, *> ?: emptyMap<String, Any?>()
            val newExtras = existingExtras.toMutableMap()
            newExtras["route_context"] = extrasRouteContext
            map["extras"] = newExtras
        }
    }

    /** Recursively converts org.json values into plain Kotlin so the map is MethodChannel-safe. */
    private fun jsonToKotlin(value: Any?): Any? = when (value) {
        is JSONObject -> {
            val m = mutableMapOf<String, Any?>()
            val it = value.keys()
            while (it.hasNext()) {
                val k = it.next()
                m[k] = jsonToKotlin(value.get(k))
            }
            m
        }
        is JSONArray -> (0 until value.length()).map { jsonToKotlin(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }
}
