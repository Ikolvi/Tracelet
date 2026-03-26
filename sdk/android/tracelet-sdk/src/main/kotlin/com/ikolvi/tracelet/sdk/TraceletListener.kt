package com.ikolvi.tracelet.sdk

/**
 * Callback interface for receiving Tracelet SDK events.
 *
 * Implement this interface to receive location updates, motion changes,
 * geofence events, and other tracking events from the SDK.
 *
 * All callbacks are invoked on the main thread.
 */
interface TraceletListener {

    /** Called when a new location is received. */
    fun onLocation(location: Map<String, Any?>) {}

    /** Called when the motion state changes (moving/stationary). */
    fun onMotionChange(data: Map<String, Any?>) {}

    /** Called when a new activity is detected. */
    fun onActivityChange(data: Map<String, Any?>) {}

    /** Called when the location provider state changes. */
    fun onProviderChange(data: Map<String, Any?>) {}

    /** Called when a geofence event occurs (enter/exit/dwell). */
    fun onGeofence(data: Map<String, Any?>) {}

    /** Called when the set of monitored geofences changes. */
    fun onGeofencesChange(data: Map<String, Any?>) {}

    /** Called on each heartbeat interval. */
    fun onHeartbeat(data: Map<String, Any?>) {}

    /** Called when an HTTP sync event occurs. */
    fun onHttp(data: Map<String, Any?>) {}

    /** Called when a schedule event fires. */
    fun onSchedule(data: Map<String, Any?>) {}

    /** Called when power-save mode changes. */
    fun onPowerSaveChange(isPowerSaveMode: Boolean) {}

    /** Called when connectivity state changes. */
    fun onConnectivityChange(data: Map<String, Any?>) {}

    /** Called when tracking is enabled or disabled. */
    fun onEnabledChange(enabled: Boolean) {}

    /** Called when a notification action is tapped. */
    fun onNotificationAction(action: String) {}

    /** Called when an authorization event occurs (HTTP 401 refresh). */
    fun onAuthorization(data: Map<String, Any?>) {}

    /** Called when a watch-position update is received. */
    fun onWatchPosition(data: Map<String, Any?>) {}

    /** Called when remote config is received. */
    fun onRemoteConfig(data: Map<String, Any?>) {}

    /** Called when a trip ends. */
    fun onTrip(data: Map<String, Any?>) {}

    /** Called when the battery budget engine adjusts parameters. */
    fun onBudgetAdjustment(data: Map<String, Any?>) {}
}
