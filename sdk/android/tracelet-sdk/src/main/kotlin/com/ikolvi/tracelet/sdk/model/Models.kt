package com.ikolvi.tracelet.sdk.model

/**
 * Geographic coordinates and accuracy metrics.
 */
data class TraceletCoords(
    val latitude: Double,
    val longitude: Double,
    val altitude: Double = 0.0,
    val speed: Double = -1.0,
    val heading: Double = -1.0,
    val accuracy: Double = -1.0,
    val speedAccuracy: Double = -1.0,
    val headingAccuracy: Double = -1.0,
    val altitudeAccuracy: Double = -1.0,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletCoords = TraceletCoords(
            latitude = (map["latitude"] as? Number)?.toDouble() ?: 0.0,
            longitude = (map["longitude"] as? Number)?.toDouble() ?: 0.0,
            altitude = (map["altitude"] as? Number)?.toDouble() ?: 0.0,
            speed = (map["speed"] as? Number)?.toDouble() ?: -1.0,
            heading = (map["heading"] as? Number)?.toDouble() ?: -1.0,
            accuracy = (map["accuracy"] as? Number)?.toDouble() ?: -1.0,
            speedAccuracy = (map["speedAccuracy"] as? Number)?.toDouble() ?: -1.0,
            headingAccuracy = (map["headingAccuracy"] as? Number)?.toDouble() ?: -1.0,
            altitudeAccuracy = (map["altitudeAccuracy"] as? Number)?.toDouble() ?: -1.0,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "latitude" to latitude,
        "longitude" to longitude,
        "altitude" to altitude,
        "speed" to speed,
        "heading" to heading,
        "accuracy" to accuracy,
        "speedAccuracy" to speedAccuracy,
        "headingAccuracy" to headingAccuracy,
        "altitudeAccuracy" to altitudeAccuracy,
    )
}

/**
 * Activity recognition data.
 */
data class TraceletActivity(
    val type: String = "unknown",
    val confidence: Int = -1,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletActivity = TraceletActivity(
            type = map["type"] as? String ?: "unknown",
            confidence = (map["confidence"] as? Number)?.toInt() ?: -1,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "type" to type,
        "confidence" to confidence,
    )
}

/**
 * Battery state data.
 */
data class TraceletBattery(
    val isCharging: Boolean = false,
    val level: Double = -1.0,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletBattery = TraceletBattery(
            isCharging = map["is_charging"] as? Boolean ?: false,
            level = (map["level"] as? Number)?.toDouble() ?: -1.0,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "is_charging" to isCharging,
        "level" to level,
    )
}

/**
 * A recorded location from the Tracelet SDK.
 *
 * Contains GPS coordinates, motion state, activity recognition data,
 * battery state, and metadata.
 */
data class TraceletLocation(
    val coords: TraceletCoords,
    val timestamp: String,
    val isMoving: Boolean,
    val uuid: String,
    val odometer: Double = 0.0,
    val locationSource: String = "unknown",
    val reducedAccuracy: Boolean = false,
    val isMock: Boolean = false,
    val mockHeuristics: Map<String, Any?>? = null,
    val activity: TraceletActivity = TraceletActivity(),
    val battery: TraceletBattery = TraceletBattery(),
    val event: String? = null,
    val extras: Map<String, Any?> = emptyMap(),
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): TraceletLocation {
            val coordsMap = map["coords"] as? Map<String, Any?> ?: emptyMap()
            val activityMap = map["activity"] as? Map<String, Any?> ?: emptyMap()
            val batteryMap = map["battery"] as? Map<String, Any?> ?: emptyMap()

            return TraceletLocation(
                coords = TraceletCoords.fromMap(coordsMap),
                timestamp = map["timestamp"] as? String ?: "",
                isMoving = map["is_moving"] as? Boolean ?: false,
                uuid = map["uuid"] as? String ?: "",
                odometer = (map["odometer"] as? Number)?.toDouble() ?: 0.0,
                locationSource = map["locationSource"] as? String ?: "unknown",
                reducedAccuracy = map["reducedAccuracy"] as? Boolean ?: false,
                isMock = map["mock"] as? Boolean ?: false,
                mockHeuristics = map["mockHeuristics"] as? Map<String, Any?>,
                activity = TraceletActivity.fromMap(activityMap),
                battery = TraceletBattery.fromMap(batteryMap),
                event = map["event"] as? String,
                extras = map["extras"] as? Map<String, Any?> ?: emptyMap(),
            )
        }
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("coords", coords.toMap())
        put("timestamp", timestamp)
        put("is_moving", isMoving)
        put("uuid", uuid)
        put("odometer", odometer)
        put("locationSource", locationSource)
        put("reducedAccuracy", reducedAccuracy)
        put("mock", isMock)
        mockHeuristics?.let { put("mockHeuristics", it) }
        put("activity", activity.toMap())
        put("battery", battery.toMap())
        event?.let { put("event", it) }
        if (extras.isNotEmpty()) put("extras", extras)
    }
}

/**
 * Geofence event data.
 */
data class TraceletGeofenceEvent(
    val identifier: String,
    val action: String,
    val location: TraceletLocation? = null,
    val extras: Map<String, Any?> = emptyMap(),
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): TraceletGeofenceEvent {
            val locMap = map["location"] as? Map<String, Any?>
            return TraceletGeofenceEvent(
                identifier = map["identifier"] as? String ?: "",
                action = map["action"] as? String ?: "",
                location = locMap?.let { TraceletLocation.fromMap(it) },
                extras = map["extras"] as? Map<String, Any?> ?: emptyMap(),
            )
        }
    }

    fun toMap(): Map<String, Any?> = buildMap {
        put("identifier", identifier)
        put("action", action)
        location?.let { put("location", it.toMap()) }
        if (extras.isNotEmpty()) put("extras", extras)
    }
}

/**
 * Geofence definition (for registration, not events).
 */
data class TraceletGeofence(
    val identifier: String,
    val latitude: Double,
    val longitude: Double,
    val radius: Double,
    val notifyOnEntry: Boolean = true,
    val notifyOnExit: Boolean = true,
    val notifyOnDwell: Boolean = false,
    val loiteringDelay: Int = 0,
    val extras: Map<String, Any?> = emptyMap(),
    val vertices: List<List<Double>> = emptyList(),
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): TraceletGeofence {
            val verticesRaw = map["vertices"] as? List<*> ?: emptyList<Any>()
            val verticesList = verticesRaw.mapNotNull { v ->
                (v as? List<*>)?.mapNotNull { (it as? Number)?.toDouble() }
            }
            return TraceletGeofence(
                identifier = map["identifier"] as? String ?: "",
                latitude = (map["latitude"] as? Number)?.toDouble() ?: 0.0,
                longitude = (map["longitude"] as? Number)?.toDouble() ?: 0.0,
                radius = (map["radius"] as? Number)?.toDouble() ?: 0.0,
                notifyOnEntry = map["notifyOnEntry"] as? Boolean ?: true,
                notifyOnExit = map["notifyOnExit"] as? Boolean ?: true,
                notifyOnDwell = map["notifyOnDwell"] as? Boolean ?: false,
                loiteringDelay = (map["loiteringDelay"] as? Number)?.toInt() ?: 0,
                extras = map["extras"] as? Map<String, Any?> ?: emptyMap(),
                vertices = verticesList,
            )
        }
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "identifier" to identifier,
        "latitude" to latitude,
        "longitude" to longitude,
        "radius" to radius,
        "notifyOnEntry" to notifyOnEntry,
        "notifyOnExit" to notifyOnExit,
        "notifyOnDwell" to notifyOnDwell,
        "loiteringDelay" to loiteringDelay,
        "extras" to extras,
        "vertices" to vertices,
    )
}

/**
 * Tracking mode for the Tracelet SDK.
 *
 * @property value The integer value persisted to SharedPreferences and
 *                 serialized to the Dart layer via platform channels.
 */
enum class TrackingMode(val value: Int) {
    /** Continuous GPS tracking — LocationEngine is always running. */
    CONTINUOUS(0),

    /** Geofence-only monitoring — LocationEngine runs for proximity updates. */
    GEOFENCES(1),

    /** Periodic one-shot fixes via WorkManager / AlarmManager. */
    PERIODIC(2);

    companion object {
        /** Converts a raw integer (from SharedPreferences or Dart) to a [TrackingMode]. */
        fun fromInt(value: Int): TrackingMode = entries.firstOrNull { it.value == value } ?: CONTINUOUS
    }
}

/**
 * Current state of the Tracelet SDK.
 */
data class TraceletState(
    val enabled: Boolean,
    val trackingMode: TrackingMode = TrackingMode.CONTINUOUS,
    val isMoving: Boolean = false,
    val schedulerEnabled: Boolean = false,
    val odometer: Double = 0.0,
    val didLaunchInBackground: Boolean = false,
    val didDeviceReboot: Boolean = false,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletState = TraceletState(
            enabled = map["enabled"] as? Boolean ?: false,
            trackingMode = TrackingMode.fromInt((map["trackingMode"] as? Number)?.toInt() ?: 0),
            isMoving = (map["isMoving"] ?: map["is_moving"]) as? Boolean ?: false,
            schedulerEnabled = map["schedulerEnabled"] as? Boolean ?: false,
            odometer = (map["odometer"] as? Number)?.toDouble() ?: 0.0,
            didLaunchInBackground = map["didLaunchInBackground"] as? Boolean ?: false,
            didDeviceReboot = map["didDeviceReboot"] as? Boolean ?: false,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "trackingMode" to trackingMode.value,
        "isMoving" to isMoving,
        "schedulerEnabled" to schedulerEnabled,
        "odometer" to odometer,
        "didLaunchInBackground" to didLaunchInBackground,
        "didDeviceReboot" to didDeviceReboot,
    )
}

/**
 * Provider change event — location services state change.
 */
data class TraceletProviderChangeEvent(
    val enabled: Boolean,
    val status: Int = 0,
    val gps: Boolean = false,
    val network: Boolean = false,
    val accuracyAuthorization: Int = 0,
    val mockLocationsDetected: Boolean = false,
    val gpsFallback: Boolean = false,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletProviderChangeEvent = TraceletProviderChangeEvent(
            enabled = map["enabled"] as? Boolean ?: false,
            status = (map["status"] as? Number)?.toInt() ?: 0,
            gps = map["gps"] as? Boolean ?: false,
            network = map["network"] as? Boolean ?: false,
            accuracyAuthorization = (map["accuracyAuthorization"] as? Number)?.toInt() ?: 0,
            mockLocationsDetected = map["mockLocationsDetected"] as? Boolean ?: false,
            gpsFallback = map["gpsFallback"] as? Boolean ?: false,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "status" to status,
        "gps" to gps,
        "network" to network,
        "accuracyAuthorization" to accuracyAuthorization,
        "mockLocationsDetected" to mockLocationsDetected,
        "gpsFallback" to gpsFallback,
    )
}

/**
 * Heartbeat event — periodic status pulse with latest location.
 */
data class TraceletHeartbeatEvent(
    val location: TraceletLocation,
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): TraceletHeartbeatEvent {
            val locMap = map["location"] as? Map<String, Any?> ?: emptyMap()
            return TraceletHeartbeatEvent(location = TraceletLocation.fromMap(locMap))
        }
    }

    fun toMap(): Map<String, Any?> = mapOf("location" to location.toMap())
}

/**
 * HTTP sync event — result of an HTTP sync operation.
 */
data class TraceletHttpEvent(
    val success: Boolean,
    val status: Int,
    val responseText: String = "",
    val isRetry: Boolean = false,
    val retryCount: Int = 0,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletHttpEvent = TraceletHttpEvent(
            success = map["success"] as? Boolean ?: false,
            status = (map["status"] as? Number)?.toInt() ?: 0,
            responseText = map["responseText"] as? String ?: "",
            isRetry = map["isRetry"] as? Boolean ?: false,
            retryCount = (map["retryCount"] as? Number)?.toInt() ?: 0,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "success" to success,
        "status" to status,
        "responseText" to responseText,
        "isRetry" to isRetry,
        "retryCount" to retryCount,
    )
}

/**
 * Connectivity change event.
 */
data class TraceletConnectivityChangeEvent(
    val connected: Boolean,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletConnectivityChangeEvent =
            TraceletConnectivityChangeEvent(connected = map["connected"] as? Boolean ?: false)
    }

    fun toMap(): Map<String, Any?> = mapOf("connected" to connected)
}

/**
 * Authorization event — OAuth token exchange result.
 */
data class TraceletAuthorizationEvent(
    val success: Boolean,
    val status: Int,
    val response: String = "",
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletAuthorizationEvent = TraceletAuthorizationEvent(
            success = map["success"] as? Boolean ?: false,
            status = (map["status"] as? Number)?.toInt() ?: 0,
            response = map["response"] as? String ?: "",
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "success" to success,
        "status" to status,
        "response" to response,
    )
}

/**
 * Activity change event — detected device activity.
 */
data class TraceletActivityChangeEvent(
    val activity: String = "unknown",
    val confidence: Int = -1,
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): TraceletActivityChangeEvent = TraceletActivityChangeEvent(
            activity = map["activity"] as? String ?: "unknown",
            confidence = (map["confidence"] as? Number)?.toInt() ?: -1,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "activity" to activity,
        "confidence" to confidence,
    )
}

/**
 * Motion change event — moving/stationary transition.
 */
data class TraceletMotionChangeEvent(
    val isMoving: Boolean,
    val location: TraceletLocation,
) {
    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): TraceletMotionChangeEvent {
            val locMap = map["location"] as? Map<String, Any?> ?: emptyMap()
            return TraceletMotionChangeEvent(
                isMoving = (map["isMoving"] ?: map["is_moving"]) as? Boolean ?: false,
                location = TraceletLocation.fromMap(locMap),
            )
        }
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "isMoving" to isMoving,
        "location" to location.toMap(),
    )
}

/**
 * Trip event — detected trip (start → stop).
 */
data class TraceletTripEvent(
    val isMoving: Boolean,
    val distance: Double = 0.0,
    val duration: Double = 0.0,
    val startLocation: TraceletLocation,
    val stopLocation: TraceletLocation,
    val waypoints: List<TraceletLocation> = emptyList(),
) {
    val averageSpeed: Double
        get() = if (duration > 0) distance / duration else 0.0

    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromMap(map: Map<String, Any?>): TraceletTripEvent {
            val startMap = map["startLocation"] as? Map<String, Any?> ?: emptyMap()
            val stopMap = map["stopLocation"] as? Map<String, Any?> ?: emptyMap()
            val waypointsList = (map["waypoints"] as? List<*>)?.mapNotNull { wp ->
                (wp as? Map<String, Any?>)?.let { TraceletLocation.fromMap(it) }
            } ?: emptyList()

            return TraceletTripEvent(
                isMoving = map["isMoving"] as? Boolean ?: false,
                distance = (map["distance"] as? Number)?.toDouble() ?: 0.0,
                duration = (map["duration"] as? Number)?.toDouble() ?: 0.0,
                startLocation = TraceletLocation.fromMap(startMap),
                stopLocation = TraceletLocation.fromMap(stopMap),
                waypoints = waypointsList,
            )
        }
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "isMoving" to isMoving,
        "distance" to distance,
        "duration" to duration,
        "startLocation" to startLocation.toMap(),
        "stopLocation" to stopLocation.toMap(),
        "waypoints" to waypoints.map { it.toMap() },
    )
}

/**
 * Privacy zone definition.
 *
 * Actions:
 * - `0` (EXCLUDE): Drop location entirely — not persisted, not dispatched.
 * - `1` (DEGRADE): Snap coordinates to a grid at [degradedAccuracyMeters] resolution.
 * - `2` (EVENT_ONLY): Dispatch to listeners but do not persist to database.
 */
data class TraceletPrivacyZone(
    val identifier: String,
    val latitude: Double,
    val longitude: Double,
    val radius: Double,
    val action: Int = 0,
    val degradedAccuracyMeters: Double = 1000.0,
) {
    companion object {
        /** Action: drop location entirely. */
        const val ACTION_EXCLUDE = 0
        /** Action: degrade coordinate precision. */
        const val ACTION_DEGRADE = 1
        /** Action: dispatch to listeners but skip persistence. */
        const val ACTION_EVENT_ONLY = 2

        fun fromMap(map: Map<String, Any?>): TraceletPrivacyZone = TraceletPrivacyZone(
            identifier = map["identifier"] as? String ?: "",
            latitude = (map["latitude"] as? Number)?.toDouble() ?: 0.0,
            longitude = (map["longitude"] as? Number)?.toDouble() ?: 0.0,
            radius = (map["radius"] as? Number)?.toDouble() ?: 0.0,
            action = (map["action"] as? Number)?.toInt() ?: 0,
            degradedAccuracyMeters = (map["degradedAccuracyMeters"] as? Number)?.toDouble() ?: 1000.0,
        )
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "identifier" to identifier,
        "latitude" to latitude,
        "longitude" to longitude,
        "radius" to radius,
        "action" to action,
        "degradedAccuracyMeters" to degradedAccuracyMeters,
    )
}
