package com.ikolvi.tracelet.sdk

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

    fun sendSpeedMotionChange(data: Map<String, Any?>)

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

    fun sendTrip(data: Map<String, Any?>)

    /**
     * Emitted when a trip begins, carrying the id every record written during
     * it will be stamped with (#402).
     *
     * Defaulted to a no-op: this is a public interface, so an implementation
     * outside the SDK must keep compiling across the addition.
     */
    fun sendTripStart(data: Map<String, Any?>) {}

    fun sendBudgetAdjustment(data: Map<String, Any?>)

    fun sendDrivingEvent(data: Map<String, Any?>)

    fun sendImpact(data: Map<String, Any?>)

    fun sendModeChange(data: Map<String, Any?>)

    /**
     * ML crash-model lifecycle status (download/load), so apps can show the user
     * that the model is being prepared. [data] carries `status` (`unlocking`,
     * `downloading`, `decrypting`, `ready`, `failed`, `disabled`) and an optional
     * `detail` string. Default no-op for hosts that don't surface it.
     */
    fun sendCrashModelStatus(data: Map<String, Any?>) {}

    /** Returns true if a listener is attached for the given event name. */
    fun hasListener(eventName: String): Boolean
}
