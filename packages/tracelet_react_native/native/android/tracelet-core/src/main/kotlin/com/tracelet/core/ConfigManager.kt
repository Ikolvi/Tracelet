package com.tracelet.core

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Persists and retrieves plugin configuration using SharedPreferences.
 *
 * All config values are stored as a single JSON blob in SharedPreferences.
 * This manager provides typed getters with defaults matching the Dart Config model.
 */
class ConfigManager internal constructor(context: Context) {

    companion object {
        private const val PREFS_NAME = "com.tracelet.config"
        private const val KEY_CONFIG = "config_json"

        /** Singleton instance — avoids repeated JSON parsing from SharedPreferences (A-M1). */
        @Volatile
        private var instance: ConfigManager? = null

        /** Returns the shared [ConfigManager], creating it on first call. */
        fun getInstance(context: Context): ConfigManager {
            return instance ?: synchronized(this) {
                instance ?: ConfigManager(context.applicationContext).also { instance = it }
            }
        }

        /** Resets the singleton for test isolation. */
        @JvmStatic
        internal fun resetInstance() {
            instance = null
        }

        // GeoConfig defaults
        const val DEFAULT_DESIRED_ACCURACY = 0 // DesiredAccuracy.high
        const val DEFAULT_DISTANCE_FILTER = 10.0
        const val DEFAULT_LOCATION_UPDATE_INTERVAL = 1000L
        const val DEFAULT_FASTEST_LOCATION_UPDATE_INTERVAL = 500L
        const val DEFAULT_STATIONARY_RADIUS = 25.0
        const val DEFAULT_LOCATION_TIMEOUT = 60

        const val DEFAULT_STOP_AFTER_ELAPSED_MINUTES = -1
        const val DEFAULT_DEFER_TIME = 0
        const val DEFAULT_ALLOW_IDENTICAL_LOCATIONS = false
        const val DEFAULT_GEOFENCE_MODE_HIGH_ACCURACY = false
        const val DEFAULT_MAX_MONITORED_GEOFENCES = -1
        const val DEFAULT_ENABLE_TIMESTAMP_META = false

        // Periodic mode defaults
        const val DEFAULT_PERIODIC_LOCATION_INTERVAL = 900 // 15 min in seconds
        const val DEFAULT_PERIODIC_DESIRED_ACCURACY = 1 // DesiredAccuracy.medium
        const val DEFAULT_PERIODIC_USE_FOREGROUND_SERVICE = false
        const val DEFAULT_PERIODIC_USE_EXACT_ALARMS = false

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
        const val DEFAULT_ACTIVITY_RECOGNITION_INTERVAL = 10000
        const val DEFAULT_MIN_ACTIVITY_RECOGNITION_CONFIDENCE = 75
        const val DEFAULT_DISABLE_STOP_DETECTION = false
        const val DEFAULT_STOP_DETECTION_DELAY = 0
        const val DEFAULT_STOP_ON_STATIONARY = false
        const val DEFAULT_TRIGGER_ACTIVITIES = ""
        const val DEFAULT_SHAKE_THRESHOLD = 2.5
        const val DEFAULT_STILL_THRESHOLD = 0.4
        const val DEFAULT_STILL_SAMPLE_COUNT = 25

        // GeofenceConfig defaults
        const val DEFAULT_GEOFENCE_PROXIMITY_RADIUS = 1000
        const val DEFAULT_GEOFENCE_INITIAL_TRIGGER_ENTRY = true
        const val DEFAULT_GEOFENCE_MODE_KNOCK_OUT = false

        // ForegroundServiceConfig defaults
        const val DEFAULT_FG_ENABLED = true
        const val DEFAULT_CHANNEL_ID = "tracelet_channel"
        const val DEFAULT_CHANNEL_NAME = "Tracelet"
        const val DEFAULT_NOTIFICATION_TITLE = "Tracelet"
        const val DEFAULT_NOTIFICATION_TEXT = "Tracking location in background"
        const val DEFAULT_NOTIFICATION_PRIORITY = 0
        const val DEFAULT_NOTIFICATION_ONGOING = true

        // AppConfig extras
        const val DEFAULT_SCHEDULE_USE_ALARM_MANAGER = false

        // HttpConfig extras
        const val DEFAULT_DISABLE_AUTO_SYNC_ON_CELLULAR = false

        // PersistenceConfig defaults
        const val DEFAULT_PERSIST_MODE = 0 // PersistMode.all
        const val DEFAULT_MAX_DAYS_TO_PERSIST = -1
        const val DEFAULT_MAX_RECORDS_TO_PERSIST = -1
        const val DEFAULT_DISABLE_PROVIDER_CHANGE_RECORD = false

        // LocationFilter defaults
        const val DEFAULT_ODOMETER_ACCURACY_THRESHOLD = 0
        const val DEFAULT_REJECT_MOCK_LOCATIONS = false

        // AuditConfig defaults
        const val DEFAULT_AUDIT_ENABLED = false
        const val DEFAULT_AUDIT_HASH_ALGORITHM = "SHA-256"
        const val DEFAULT_AUDIT_INCLUDE_EXTRAS_IN_HASH = false

        // PrivacyZoneConfig defaults
        const val DEFAULT_PRIVACY_ZONE_ENABLED = false
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

        // Dart sends a nested structure: {geo: {...}, app: {...}, http: {...}, ...}
        // Flatten known section sub-maps into the top level first.
        val sectionKeys = setOf("geo", "app", "http", "logger", "motion", "geofence", "persistence", "audit", "privacyZone")
        val flat = mutableMapOf<String, Any?>()
        for ((key, value) in newConfig) {
            if (key in sectionKeys && value is Map<*, *>) {
                @Suppress("UNCHECKED_CAST")
                for ((k, v) in value as Map<String, Any?>) {
                    flat[k] = v
                }
            } else {
                flat[key] = value
            }
        }

        // Flatten foregroundService sub-map (nested inside app section) with fg_ prefix
        val fgService = flat["foregroundService"]
        if (fgService is Map<*, *>) {
            @Suppress("UNCHECKED_CAST")
            for ((k, v) in fgService as Map<String, Any?>) {
                merged["fg_$k"] = v
            }
        }

        // Flatten filter sub-map (nested inside geo section)
        val filter = flat["filter"]
        if (filter is Map<*, *>) {
            @Suppress("UNCHECKED_CAST")
            for ((k, v) in filter as Map<String, Any?>) {
                merged[k] = v
            }
        }

        for ((key, value) in flat) {
            if (key == "foregroundService" || key == "filter") continue
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

    fun getStopAfterElapsedMinutes(): Int =
        getInt("stopAfterElapsedMinutes", DEFAULT_STOP_AFTER_ELAPSED_MINUTES)

    fun getDeferTime(): Int =
        getInt("deferTime", DEFAULT_DEFER_TIME)

    fun getAllowIdenticalLocations(): Boolean =
        getBool("allowIdenticalLocations", DEFAULT_ALLOW_IDENTICAL_LOCATIONS)

    fun getGeofenceModeHighAccuracy(): Boolean =
        getBool("geofenceModeHighAccuracy", DEFAULT_GEOFENCE_MODE_HIGH_ACCURACY)

    fun getMaxMonitoredGeofences(): Int =
        getInt("maxMonitoredGeofences", DEFAULT_MAX_MONITORED_GEOFENCES)

    fun getEnableTimestampMeta(): Boolean =
        getBool("enableTimestampMeta", DEFAULT_ENABLE_TIMESTAMP_META)

    // Periodic mode config
    fun getPeriodicLocationInterval(): Int =
        getInt("periodicLocationInterval", DEFAULT_PERIODIC_LOCATION_INTERVAL)

    fun getPeriodicDesiredAccuracy(): Int =
        getInt("periodicDesiredAccuracy", DEFAULT_PERIODIC_DESIRED_ACCURACY)

    fun getPeriodicUseForegroundService(): Boolean =
        getBool("periodicUseForegroundService", DEFAULT_PERIODIC_USE_FOREGROUND_SERVICE)

    fun getPeriodicUseExactAlarms(): Boolean =
        getBool("periodicUseExactAlarms", DEFAULT_PERIODIC_USE_EXACT_ALARMS)

    // LocationFilter sub-config
    fun getOdometerAccuracyThreshold(): Int =
        getInt("odometerAccuracyThreshold", DEFAULT_ODOMETER_ACCURACY_THRESHOLD)

    fun getRejectMockLocations(): Boolean =
        getBool("rejectMockLocations", DEFAULT_REJECT_MOCK_LOCATIONS)

    fun getMockDetectionLevel(): Int =
        getInt("mockDetectionLevel", 1)

    // ---------------------------------------------------------------------------
    // Typed Getters (AuditConfig — Enterprise)
    // ---------------------------------------------------------------------------

    fun getAuditEnabled(): Boolean =
        getBool("enabled", DEFAULT_AUDIT_ENABLED)

    fun getAuditHashAlgorithm(): String =
        getString("hashAlgorithm", DEFAULT_AUDIT_HASH_ALGORITHM)

    fun getAuditIncludeExtrasInHash(): Boolean =
        getBool("includeExtrasInHash", DEFAULT_AUDIT_INCLUDE_EXTRAS_IN_HASH)

    // ---------------------------------------------------------------------------
    // Typed Getters (PrivacyZoneConfig — Enterprise)
    // ---------------------------------------------------------------------------

    fun getPrivacyZoneEnabled(): Boolean =
        getBool("privacyZoneEnabled", DEFAULT_PRIVACY_ZONE_ENABLED)

    // ---------------------------------------------------------------------------
    // Typed Getters (AppConfig)
    // ---------------------------------------------------------------------------

    fun getStopOnTerminate(): Boolean =
        getBool("stopOnTerminate", DEFAULT_STOP_ON_TERMINATE)

    fun getStartOnBoot(): Boolean =
        getBool("startOnBoot", DEFAULT_START_ON_BOOT)

    fun getHeartbeatInterval(): Int =
        getInt("heartbeatInterval", DEFAULT_HEARTBEAT_INTERVAL)

    fun getScheduleUseAlarmManager(): Boolean =
        getBool("scheduleUseAlarmManager", DEFAULT_SCHEDULE_USE_ALARM_MANAGER)

    fun getSchedule(): List<String> {
        val raw = configCache["schedule"]
        if (raw is List<*>) return raw.filterIsInstance<String>()
        return emptyList()
    }

    // ForegroundService config
    fun isForegroundServiceEnabled(): Boolean =
        getBool("fg_enabled", DEFAULT_FG_ENABLED)

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

    fun getActivityRecognitionInterval(): Int =
        getInt("activityRecognitionInterval", DEFAULT_ACTIVITY_RECOGNITION_INTERVAL)

    fun getMinimumActivityRecognitionConfidence(): Int =
        getInt("minimumActivityRecognitionConfidence", DEFAULT_MIN_ACTIVITY_RECOGNITION_CONFIDENCE)

    fun getDisableStopDetection(): Boolean =
        getBool("disableStopDetection", DEFAULT_DISABLE_STOP_DETECTION)

    fun getStopDetectionDelay(): Int =
        getInt("stopDetectionDelay", DEFAULT_STOP_DETECTION_DELAY)

    fun getStopOnStationary(): Boolean =
        getBool("stopOnStationary", DEFAULT_STOP_ON_STATIONARY)

    fun getTriggerActivities(): String =
        getString("triggerActivities", DEFAULT_TRIGGER_ACTIVITIES)

    fun getShakeThreshold(): Double =
        getDouble("shakeThreshold", DEFAULT_SHAKE_THRESHOLD)

    fun getStillThreshold(): Double =
        getDouble("stillThreshold", DEFAULT_STILL_THRESHOLD)

    fun getStillSampleCount(): Int =
        getInt("stillSampleCount", DEFAULT_STILL_SAMPLE_COUNT)

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
    // Typed Getters (HttpConfig extras)
    // ---------------------------------------------------------------------------

    fun getDisableAutoSyncOnCellular(): Boolean =
        getBool("disableAutoSyncOnCellular", DEFAULT_DISABLE_AUTO_SYNC_ON_CELLULAR)

    fun getMaxRetries(): Int = getInt("maxRetries", 10)

    fun getRetryBackoffBase(): Int = getInt("retryBackoffBase", 1000)

    fun getRetryBackoffCap(): Int = getInt("retryBackoffCap", 300000)

    fun getEnableDeltaCompression(): Boolean =
        getBool("enableDeltaCompression", false)

    fun getDeltaCoordinatePrecision(): Int =
        getInt("deltaCoordinatePrecision", 6)

    // ---------------------------------------------------------------------------
    // Typed Getters (PersistenceConfig)
    // ---------------------------------------------------------------------------

    fun getPersistMode(): Int =
        getInt("persistMode", DEFAULT_PERSIST_MODE)

    fun getMaxDaysToPersist(): Int =
        getInt("maxDaysToPersist", DEFAULT_MAX_DAYS_TO_PERSIST)

    fun getMaxRecordsToPersist(): Int =
        getInt("maxRecordsToPersist", DEFAULT_MAX_RECORDS_TO_PERSIST)

    fun getLocationTemplate(): String? =
        configCache["locationTemplate"] as? String

    fun getGeofenceTemplate(): String? =
        configCache["geofenceTemplate"] as? String

    fun getDisableProviderChangeRecord(): Boolean =
        getBool("disableProviderChangeRecord", DEFAULT_DISABLE_PROVIDER_CHANGE_RECORD)

    fun getPersistenceExtras(): Map<String, Any?> {
        val raw = configCache["extras"]
        if (raw is Map<*, *>) {
            @Suppress("UNCHECKED_CAST")
            return raw as Map<String, Any?>
        }
        return emptyMap()
    }

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
