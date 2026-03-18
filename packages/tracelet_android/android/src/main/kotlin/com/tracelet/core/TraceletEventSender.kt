package com.tracelet.core

/**
 * Abstraction for dispatching Tracelet events from engine code to the
 * host framework (Flutter EventChannel, React Native NativeEventEmitter, etc.).
 *
 * All method implementations must be safe to call from any thread —
 * the implementation is responsible for marshalling to the correct thread.
 */
interface TraceletEventSender {

    fun sendLocation(data: Map<String, Any?>)

    fun sendMotionChange(data: Map<String, Any?>)

    fun sendActivityChange(data: Map<String, Any?>)

    fun sendProviderChange(data: Map<String, Any?>)

    fun sendGeofence(data: Map<String, Any?>)

    fun sendGeofencesChange(data: Map<String, Any?>)

    fun sendHeartbeat(data: Map<String, Any?>)

    fun sendHttp(data: Map<String, Any?>)

    fun sendSchedule(data: Map<String, Any?>)

    fun sendPowerSaveChange(isPowerSaveMode: Boolean)

    fun sendConnectivityChange(data: Map<String, Any?>)

    fun sendEnabledChange(enabled: Boolean)

    fun sendNotificationAction(action: String)

    fun sendAuthorization(data: Map<String, Any?>)

    fun sendWatchPosition(data: Map<String, Any?>)

    fun sendRemoteConfigEvent(data: Map<String, Any?>)

    /** Returns true if a listener is attached for the given event name. */
    fun hasListener(eventName: String): Boolean
}
