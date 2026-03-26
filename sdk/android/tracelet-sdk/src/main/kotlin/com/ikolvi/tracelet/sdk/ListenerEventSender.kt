package com.ikolvi.tracelet.sdk

import android.os.Handler
import android.os.Looper

/**
 * Bridges the [TraceletEventSender] interface (used by core engines) to
 * the [TraceletListener] interface (used by SDK consumers).
 *
 * Forwards all events from the internal machinery to the consumer's listener
 * on the main thread. Also supports a [headlessFallback] for background
 * event delivery when no listener is attached.
 */
internal class ListenerEventSender : TraceletEventSender {

    private val mainHandler = Handler(Looper.getMainLooper())

    /** The consumer's listener. */
    var listener: TraceletListener? = null

    /** Headless fallback for when no listener is set. */
    var headlessFallback: ((eventName: String, data: Map<String, Any?>) -> Unit)? = null

    override fun sendLocation(data: Map<String, Any?>) =
        dispatch("location", data) { listener?.onLocation(data) }

    override fun sendMotionChange(data: Map<String, Any?>) =
        dispatch("motionchange", data) { listener?.onMotionChange(data) }

    override fun sendActivityChange(data: Map<String, Any?>) =
        dispatch("activitychange", data) { listener?.onActivityChange(data) }

    override fun sendProviderChange(data: Map<String, Any?>) =
        dispatch("providerchange", data) { listener?.onProviderChange(data) }

    override fun sendGeofence(data: Map<String, Any?>) =
        dispatch("geofence", data) { listener?.onGeofence(data) }

    override fun sendGeofencesChange(data: Map<String, Any?>) =
        dispatch("geofenceschange", data) { listener?.onGeofencesChange(data) }

    override fun sendHeartbeat(data: Map<String, Any?>) =
        dispatch("heartbeat", data) { listener?.onHeartbeat(data) }

    override fun sendHttp(data: Map<String, Any?>) =
        dispatch("http", data) { listener?.onHttp(data) }

    override fun sendSchedule(data: Map<String, Any?>) =
        dispatch("schedule", data) { listener?.onSchedule(data) }

    override fun sendPowerSaveChange(isPowerSaveMode: Boolean) =
        dispatch("powersavechange", mapOf("value" to isPowerSaveMode)) {
            listener?.onPowerSaveChange(isPowerSaveMode)
        }

    override fun sendConnectivityChange(data: Map<String, Any?>) =
        dispatch("connectivitychange", data) { listener?.onConnectivityChange(data) }

    override fun sendEnabledChange(enabled: Boolean) =
        dispatch("enabledchange", mapOf("value" to enabled)) {
            listener?.onEnabledChange(enabled)
        }

    override fun sendNotificationAction(action: String) =
        dispatch("notificationaction", mapOf("value" to action)) {
            listener?.onNotificationAction(action)
        }

    override fun sendAuthorization(data: Map<String, Any?>) =
        dispatch("authorization", data) { listener?.onAuthorization(data) }

    override fun sendWatchPosition(data: Map<String, Any?>) =
        dispatch("watchposition", data) { listener?.onWatchPosition(data) }

    override fun sendRemoteConfigEvent(data: Map<String, Any?>) =
        dispatch("remoteconfig", data) { listener?.onRemoteConfig(data) }

    override fun sendTrip(data: Map<String, Any?>) =
        dispatch("trip", data) { listener?.onTrip(data) }

    override fun sendBudgetAdjustment(data: Map<String, Any?>) =
        dispatch("budgetadjustment", data) { listener?.onBudgetAdjustment(data) }

    override fun hasListener(eventName: String): Boolean = listener != null

    private inline fun dispatch(
        eventName: String,
        data: Map<String, Any?>,
        crossinline action: () -> Unit
    ) {
        if (listener != null) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                action()
            } else {
                mainHandler.post { action() }
            }
        } else {
            headlessFallback?.invoke(eventName, data)
        }
    }
}
