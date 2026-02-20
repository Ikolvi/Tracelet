package com.tracelet.tracelet_android

import android.content.Context
import android.content.SharedPreferences

/**
 * Tracks the runtime state of the Tracelet plugin.
 *
 * State includes: enabled, trackingMode, schedulerEnabled, odometer,
 * didLaunchInBackground, didDeviceReboot.
 */
class StateManager(context: Context) {

    companion object {
        private const val PREFS_NAME = "com.tracelet.state"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_TRACKING_MODE = "trackingMode" // 0=location, 1=geofences
        private const val KEY_SCHEDULER_ENABLED = "schedulerEnabled"
        private const val KEY_ODOMETER = "odometer"
        private const val KEY_IS_MOVING = "isMoving"
        private const val KEY_DID_LAUNCH_IN_BACKGROUND = "didLaunchInBackground"
        private const val KEY_DID_DEVICE_REBOOT = "didDeviceReboot"
        private const val KEY_LAST_LOCATION_TIME = "lastLocationTime"
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    /** 0 = location tracking, 1 = geofences only */
    var trackingMode: Int
        get() = prefs.getInt(KEY_TRACKING_MODE, 0)
        set(value) = prefs.edit().putInt(KEY_TRACKING_MODE, value).apply()

    var schedulerEnabled: Boolean
        get() = prefs.getBoolean(KEY_SCHEDULER_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_SCHEDULER_ENABLED, value).apply()

    var odometer: Double
        get() = java.lang.Double.longBitsToDouble(
            prefs.getLong(KEY_ODOMETER, java.lang.Double.doubleToLongBits(0.0))
        )
        set(value) = prefs.edit().putLong(
            KEY_ODOMETER, java.lang.Double.doubleToLongBits(value)
        ).apply()

    var isMoving: Boolean
        get() = prefs.getBoolean(KEY_IS_MOVING, false)
        set(value) = prefs.edit().putBoolean(KEY_IS_MOVING, value).apply()

    var didLaunchInBackground: Boolean
        get() = prefs.getBoolean(KEY_DID_LAUNCH_IN_BACKGROUND, false)
        set(value) = prefs.edit().putBoolean(KEY_DID_LAUNCH_IN_BACKGROUND, value).apply()

    var didDeviceReboot: Boolean
        get() = prefs.getBoolean(KEY_DID_DEVICE_REBOOT, false)
        set(value) = prefs.edit().putBoolean(KEY_DID_DEVICE_REBOOT, value).apply()

    var lastLocationTime: Long
        get() = prefs.getLong(KEY_LAST_LOCATION_TIME, 0L)
        set(value) = prefs.edit().putLong(KEY_LAST_LOCATION_TIME, value).apply()

    /** Adds [distance] meters to the cumulative odometer. */
    fun addOdometer(distance: Double) {
        odometer += distance
    }

    /** Returns the full state as a map for Dart consumption. */
    fun toMap(config: Map<String, Any?>? = null): Map<String, Any?> {
        return mapOf(
            "enabled" to enabled,
            "trackingMode" to trackingMode,
            "schedulerEnabled" to schedulerEnabled,
            "odometer" to odometer,
            "isMoving" to isMoving,
            "didLaunchInBackground" to didLaunchInBackground,
            "didDeviceReboot" to didDeviceReboot,
            "config" to config,
        )
    }

    /** Resets all state to defaults. */
    fun reset() {
        prefs.edit().clear().apply()
    }
}
