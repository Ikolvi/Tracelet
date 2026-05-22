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
 *
 * Events dispatched before a listener or headless fallback is available are
 * buffered and replayed in order once either becomes available.
 */
internal class ListenerEventSender : TraceletEventSender {

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Events buffered while both [listener] and [headlessFallback] are null.
     * Protected by `synchronized(pendingEvents)`.
     */
    private val pendingEvents = mutableListOf<Pair<String, Map<String, Any?>>>()

    /** The consumer's listener. Setting this flushes any buffered events. */
    var listener: TraceletListener? = null
        set(value) {
            field = value
            if (value != null) flushPendingEvents()
        }

    /** Headless fallback for when no listener is set. Setting this flushes any buffered events. */
    var headlessFallback: ((eventName: String, data: Map<String, Any?>) -> Unit)? = null
        set(value) {
            field = value
            if (value != null && listener == null) flushPendingEvents()
        }

    override fun sendLocation(data: Map<String, Any?>) =
        dispatch("location", data) { listener?.onLocation(data) }

    override fun sendSpeedMotionChange(data: Map<String, Any?>) {
        // Not exposed to standard Java/Kotlin listeners directly.
        // It's meant for internal state propagation to Dart.
    }

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
        } else if (headlessFallback != null) {
            headlessFallback?.invoke(eventName, data)
        } else {
            // Neither listener nor headless fallback — buffer the event
            synchronized(pendingEvents) {
                pendingEvents.add(eventName to data)
            }
        }
    }

    /**
     * Replays all buffered events through [dispatch], then clears the buffer.
     * Called automatically when [listener] or [headlessFallback] is set.
     */
    private fun flushPendingEvents() {
        val snapshot: List<Pair<String, Map<String, Any?>>>
        synchronized(pendingEvents) {
            if (pendingEvents.isEmpty()) return
            snapshot = pendingEvents.toList()
            pendingEvents.clear()
        }
        for ((name, data) in snapshot) {
            replayEvent(name, data)
        }
    }

    /** Dispatches a single buffered event by name. */
    private fun replayEvent(eventName: String, data: Map<String, Any?>) {
        when (eventName) {
            "location" -> sendLocation(data)
            "motionchange" -> sendMotionChange(data)
            "activitychange" -> sendActivityChange(data)
            "providerchange" -> sendProviderChange(data)
            "geofence" -> sendGeofence(data)
            "geofenceschange" -> sendGeofencesChange(data)
            "heartbeat" -> sendHeartbeat(data)
            "http" -> sendHttp(data)
            "schedule" -> sendSchedule(data)
            "powersavechange" -> sendPowerSaveChange(data["value"] as? Boolean ?: false)
            "connectivitychange" -> sendConnectivityChange(data)
            "enabledchange" -> sendEnabledChange(data["value"] as? Boolean ?: false)
            "notificationaction" -> sendNotificationAction(data["value"] as? String ?: "")
            "authorization" -> sendAuthorization(data)
            "watchposition" -> sendWatchPosition(data)
            "remoteconfig" -> sendRemoteConfigEvent(data)
            "trip" -> sendTrip(data)
            "budgetadjustment" -> sendBudgetAdjustment(data)
        }
    }
}
