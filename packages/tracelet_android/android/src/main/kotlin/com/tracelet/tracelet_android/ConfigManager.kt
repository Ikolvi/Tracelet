package com.tracelet.tracelet_android

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Persists and retrieves plugin configuration using SharedPreferences.
 *
 * All config values are stored as a single JSON blob in SharedPreferences.
 * This manager provides typed getters with defaults matching the Dart Config model.
 */
class ConfigManager(context: Context) {

    companion object {
        private const val PREFS_NAME = "com.tracelet.config"
        private const val KEY_CONFIG = "config_json"

        // GeoConfig defaults
        const val DEFAULT_DESIRED_ACCURACY = 0 // DesiredAccuracy.high
        const val DEFAULT_DISTANCE_FILTER = 10.0
        const val DEFAULT_LOCATION_UPDATE_INTERVAL = 1000L
        const val DEFAULT_FASTEST_LOCATION_UPDATE_INTERVAL = 500L
        const val DEFAULT_STATIONARY_RADIUS = 25.0
        const val DEFAULT_LOCATION_TIMEOUT = 60

        // AppConfig defaults
        const val DEFAULT_STOP_ON_TERMINATE = true
        const val DEFAULT_START_ON_BOOT = false
        const val DEFAULT_HEARTBEAT_INTERVAL = 60

        // HttpConfig defaults
        const val DEFAULT_HTTP_ROOT_PROPERTY = "location"
        const val DEFAULT_BATCH_SYNC = false
        const val DEFAULT_MAX_BATCH_SIZE = 250
        const val DEFAULT_AUTO_SYNC = true
        const val DEFAULT_AUTO_SYNC_THRESHOLD = 0
        const val DEFAULT_HTTP_TIMEOUT = 60000
        const val DEFAULT_HTTP_METHOD = 0 // POST

        // LoggerConfig defaults
        const val DEFAULT_LOG_LEVEL = 0 // OFF
        const val DEFAULT_LOG_MAX_DAYS = 3
        const val DEFAULT_DEBUG = false

        // MotionConfig defaults
        const val DEFAULT_STOP_TIMEOUT = 5
        const val DEFAULT_MOTION_TRIGGER_DELAY = 0
        const val DEFAULT_DISABLE_MOTION_ACTIVITY_UPDATES = false
        const val DEFAULT_IS_MOVING = false

        // GeofenceConfig defaults
        const val DEFAULT_GEOFENCE_PROXIMITY_RADIUS = 1000
        const val DEFAULT_GEOFENCE_INITIAL_TRIGGER_ENTRY = true
        const val DEFAULT_GEOFENCE_MODE_KNOCK_OUT = false

        // ForegroundServiceConfig defaults
        const val DEFAULT_CHANNEL_ID = "tracelet_channel"
        const val DEFAULT_CHANNEL_NAME = "Tracelet"
        const val DEFAULT_NOTIFICATION_TITLE = "Tracelet"
        const val DEFAULT_NOTIFICATION_TEXT = "Tracking location in background"
        const val DEFAULT_NOTIFICATION_PRIORITY = 0
        const val DEFAULT_NOTIFICATION_ONGOING = true
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Volatile
    private var configCache: Map<String, Any?> = loadFromPrefs()

    /** Returns the full config map. */
    fun getConfig(): Map<String, Any?> = configCache

    /**
     * Merges [newConfig] into the existing config and persists.
     * Returns the full merged config.
     */
    fun setConfig(newConfig: Map<String, Any?>): Map<String, Any?> {
        val merged = configCache.toMutableMap()
        // Flatten foregroundService sub-map
        val fgService = newConfig["foregroundService"]
        if (fgService is Map<*, *>) {
            @Suppress("UNCHECKED_CAST")
            for ((k, v) in fgService as Map<String, Any?>) {
                merged["fg_$k"] = v
            }
        }
        for ((key, value) in newConfig) {
            if (key == "foregroundService") continue
            if (key == "schedule" && value is List<*>) {
                merged[key] = value.filterIsInstance<String>()
            } else {
                merged[key] = value
            }
        }
        configCache = merged
        persistToPrefs(merged)
        return merged
    }

    /** Resets config to defaults, optionally applying [newConfig] on top. */
    fun reset(newConfig: Map<String, Any?>?): Map<String, Any?> {
        configCache = emptyMap()
        prefs.edit().remove(KEY_CONFIG).apply()
        return if (newConfig != null) setConfig(newConfig) else configCache
    }

    /** Returns whether [ready] has been called (config has been persisted at least once). */
    fun hasConfig(): Boolean = prefs.contains(KEY_CONFIG)

    // ---------------------------------------------------------------------------
    // Typed Getters (GeoConfig)
    // ---------------------------------------------------------------------------

    fun getDesiredAccuracy(): Int =
        getInt("desiredAccuracy", DEFAULT_DESIRED_ACCURACY)

    fun getDistanceFilter(): Double =
        getDouble("distanceFilter", DEFAULT_DISTANCE_FILTER)

    fun getLocationUpdateInterval(): Long =
        getLong("locationUpdateInterval", DEFAULT_LOCATION_UPDATE_INTERVAL)

    fun getFastestLocationUpdateInterval(): Long =
        getLong("fastestLocationUpdateInterval", DEFAULT_FASTEST_LOCATION_UPDATE_INTERVAL)

    fun getStationaryRadius(): Double =
        getDouble("stationaryRadius", DEFAULT_STATIONARY_RADIUS)

    fun getLocationTimeout(): Int =
        getInt("locationTimeout", DEFAULT_LOCATION_TIMEOUT)

    // ---------------------------------------------------------------------------
    // Typed Getters (AppConfig)
    // ---------------------------------------------------------------------------

    fun getStopOnTerminate(): Boolean =
        getBool("stopOnTerminate", DEFAULT_STOP_ON_TERMINATE)

    fun getStartOnBoot(): Boolean =
        getBool("startOnBoot", DEFAULT_START_ON_BOOT)

    fun getHeartbeatInterval(): Int =
        getInt("heartbeatInterval", DEFAULT_HEARTBEAT_INTERVAL)

    fun getSchedule(): List<String> {
        val raw = configCache["schedule"]
        if (raw is List<*>) return raw.filterIsInstance<String>()
        return emptyList()
    }

    // ForegroundService config
    fun getFgChannelId(): String =
        getString("fg_channelId", DEFAULT_CHANNEL_ID)

    fun getFgChannelName(): String =
        getString("fg_channelName", DEFAULT_CHANNEL_NAME)

    fun getFgNotificationTitle(): String =
        getString("fg_notificationTitle", DEFAULT_NOTIFICATION_TITLE)

    fun getFgNotificationText(): String =
        getString("fg_notificationText", DEFAULT_NOTIFICATION_TEXT)

    fun getFgNotificationColor(): String? =
        configCache["fg_notificationColor"] as? String

    fun getFgNotificationSmallIcon(): String? =
        configCache["fg_notificationSmallIcon"] as? String

    fun getFgNotificationLargeIcon(): String? =
        configCache["fg_notificationLargeIcon"] as? String

    fun getFgNotificationPriority(): Int =
        getInt("fg_notificationPriority", DEFAULT_NOTIFICATION_PRIORITY)

    fun getFgNotificationOngoing(): Boolean =
        getBool("fg_notificationOngoing", DEFAULT_NOTIFICATION_ONGOING)

    fun getFgActions(): List<String> {
        val raw = configCache["fg_actions"]
        if (raw is List<*>) return raw.filterIsInstance<String>()
        return emptyList()
    }

    // ---------------------------------------------------------------------------
    // Typed Getters (HttpConfig)
    // ---------------------------------------------------------------------------

    fun getHttpUrl(): String? = configCache["url"] as? String

    fun getHttpMethod(): Int = getInt("method", DEFAULT_HTTP_METHOD)

    fun getHttpHeaders(): Map<String, String> {
        val raw = configCache["headers"]
        if (raw is Map<*, *>) {
            @Suppress("UNCHECKED_CAST")
            return (raw as Map<String, Any?>).mapValues { it.value?.toString() ?: "" }
        }
        return emptyMap()
    }

    fun getHttpRootProperty(): String =
        getString("httpRootProperty", DEFAULT_HTTP_ROOT_PROPERTY)

    fun getBatchSync(): Boolean = getBool("batchSync", DEFAULT_BATCH_SYNC)

    fun getMaxBatchSize(): Int = getInt("maxBatchSize", DEFAULT_MAX_BATCH_SIZE)

    fun getAutoSync(): Boolean = getBool("autoSync", DEFAULT_AUTO_SYNC)

    fun getAutoSyncThreshold(): Int =
        getInt("autoSyncThreshold", DEFAULT_AUTO_SYNC_THRESHOLD)

    fun getHttpTimeout(): Int = getInt("httpTimeout", DEFAULT_HTTP_TIMEOUT)

    fun getHttpParams(): Map<String, Any?> {
        val raw = configCache["params"]
        if (raw is Map<*, *>) {
            @Suppress("UNCHECKED_CAST")
            return raw as Map<String, Any?>
        }
        return emptyMap()
    }

    fun getLocationsOrderDirection(): Int =
        getInt("locationsOrderDirection", 0)

    fun getHttpExtras(): Map<String, Any?> {
        val raw = configCache["extras"]
        if (raw is Map<*, *>) {
            @Suppress("UNCHECKED_CAST")
            return raw as Map<String, Any?>
        }
        return emptyMap()
    }

    // ---------------------------------------------------------------------------
    // Typed Getters (LoggerConfig)
    // ---------------------------------------------------------------------------

    fun getLogLevel(): Int = getInt("logLevel", DEFAULT_LOG_LEVEL)

    fun getLogMaxDays(): Int = getInt("logMaxDays", DEFAULT_LOG_MAX_DAYS)

    fun isDebug(): Boolean = getBool("debug", DEFAULT_DEBUG)

    // ---------------------------------------------------------------------------
    // Typed Getters (MotionConfig)
    // ---------------------------------------------------------------------------

    fun getStopTimeout(): Int = getInt("stopTimeout", DEFAULT_STOP_TIMEOUT)

    fun getMotionTriggerDelay(): Int =
        getInt("motionTriggerDelay", DEFAULT_MOTION_TRIGGER_DELAY)

    fun isMotionActivityUpdatesDisabled(): Boolean =
        getBool("disableMotionActivityUpdates", DEFAULT_DISABLE_MOTION_ACTIVITY_UPDATES)

    fun getIsMoving(): Boolean = getBool("isMoving", DEFAULT_IS_MOVING)

    // ---------------------------------------------------------------------------
    // Typed Getters (GeofenceConfig)
    // ---------------------------------------------------------------------------

    fun getGeofenceProximityRadius(): Int =
        getInt("geofenceProximityRadius", DEFAULT_GEOFENCE_PROXIMITY_RADIUS)

    fun getGeofenceInitialTriggerEntry(): Boolean =
        getBool("geofenceInitialTriggerEntry", DEFAULT_GEOFENCE_INITIAL_TRIGGER_ENTRY)

    fun getGeofenceModeKnockOut(): Boolean =
        getBool("geofenceModeKnockOut", DEFAULT_GEOFENCE_MODE_KNOCK_OUT)

    // ---------------------------------------------------------------------------
    // Private helpers
    // ---------------------------------------------------------------------------

    private fun getInt(key: String, default: Int): Int {
        val value = configCache[key]
        return when (value) {
            is Int -> value
            is Long -> value.toInt()
            is Double -> value.toInt()
            is String -> value.toIntOrNull() ?: default
            else -> default
        }
    }

    private fun getLong(key: String, default: Long): Long {
        val value = configCache[key]
        return when (value) {
            is Long -> value
            is Int -> value.toLong()
            is Double -> value.toLong()
            is String -> value.toLongOrNull() ?: default
            else -> default
        }
    }

    private fun getDouble(key: String, default: Double): Double {
        val value = configCache[key]
        return when (value) {
            is Double -> value
            is Int -> value.toDouble()
            is Long -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: default
            else -> default
        }
    }

    private fun getBool(key: String, default: Boolean): Boolean {
        val value = configCache[key]
        return when (value) {
            is Boolean -> value
            is Int -> value != 0
            is Long -> value != 0L
            else -> default
        }
    }

    private fun getString(key: String, default: String): String {
        return configCache[key]?.toString() ?: default
    }

    private fun persistToPrefs(config: Map<String, Any?>) {
        val json = JSONObject(config).toString()
        prefs.edit().putString(KEY_CONFIG, json).apply()
    }

    private fun loadFromPrefs(): Map<String, Any?> {
        val json = prefs.getString(KEY_CONFIG, null) ?: return emptyMap()
        return try {
            jsonToMap(JSONObject(json))
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in json.keys()) {
            val value = json.get(key)
            map[key] = when (value) {
                JSONObject.NULL -> null
                is JSONObject -> jsonToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                else -> value
            }
        }
        return map
    }

    private fun jsonArrayToList(array: org.json.JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until array.length()) {
            val value = array.get(i)
            list.add(when (value) {
                JSONObject.NULL -> null
                is JSONObject -> jsonToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                else -> value
            })
        }
        return list
    }
}
