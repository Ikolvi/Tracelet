package com.tracelet.tracelet_android

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Centralized EventChannel sink manager for all Tracelet event streams.
 *
 * Manages 15 EventChannels and their EventSinks. All event dispatch
 * is marshalled to the main thread for Flutter platform channel safety.
 *
 * When no Dart UI listener is attached for a given event, the dispatcher
 * falls back to [headlessFallback] (if set) so that events can be routed
 * to a background Dart isolate via HeadlessTaskService.
 */
class EventDispatcher {

    companion object {
        private const val BASE = "com.tracelet/events"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Optional headless fallback. When no EventSink exists for a given event,
     * the dispatcher calls this lambda with (eventName, eventData) so the
     * event can be forwarded to HeadlessTaskService.
     */
    var headlessFallback: ((eventName: String, data: Map<String, Any?>) -> Unit)? = null

    // EventChannel instances
    private val channels = mutableMapOf<String, EventChannel>()

    // Active EventSinks (null when no Dart listener)
    private val sinks = mutableMapOf<String, EventChannel.EventSink?>()

    // All event channel suffixes
    private val eventNames = listOf(
        "location",
        "motionchange",
        "activitychange",
        "providerchange",
        "geofence",
        "geofenceschange",
        "heartbeat",
        "http",
        "schedule",
        "powersavechange",
        "connectivitychange",
        "enabledchange",
        "notificationaction",
        "authorization",
        "watchposition",
    )

    /** Registers all EventChannels with the Flutter binary messenger. */
    fun register(messenger: BinaryMessenger) {
        for (name in eventNames) {
            val path = "$BASE/$name"
            val channel = EventChannel(messenger, path)
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sinks[name] = events
                }
                override fun onCancel(arguments: Any?) {
                    sinks[name] = null
                }
            })
            channels[name] = channel
        }
    }

    /** Unregisters all EventChannels. */
    fun unregister() {
        for ((_, channel) in channels) {
            channel.setStreamHandler(null)
        }
        channels.clear()
        sinks.clear()
    }

    // ---------------------------------------------------------------------------
    // Type-safe dispatch methods (all marshal to main thread)
    // ---------------------------------------------------------------------------

    fun sendLocation(data: Map<String, Any?>) = send("location", data)

    fun sendMotionChange(data: Map<String, Any?>) = send("motionchange", data)

    fun sendActivityChange(data: Map<String, Any?>) = send("activitychange", data)

    fun sendProviderChange(data: Map<String, Any?>) = send("providerchange", data)

    fun sendGeofence(data: Map<String, Any?>) = send("geofence", data)

    fun sendGeofencesChange(data: Map<String, Any?>) = send("geofenceschange", data)

    fun sendHeartbeat(data: Map<String, Any?>) = send("heartbeat", data)

    fun sendHttp(data: Map<String, Any?>) = send("http", data)

    fun sendSchedule(data: Map<String, Any?>) = send("schedule", data)

    fun sendPowerSaveChange(isPowerSaveMode: Boolean) = send("powersavechange", isPowerSaveMode)

    fun sendConnectivityChange(data: Map<String, Any?>) = send("connectivitychange", data)

    fun sendEnabledChange(enabled: Boolean) = send("enabledchange", enabled)

    fun sendNotificationAction(action: String) = send("notificationaction", action)

    fun sendAuthorization(data: Map<String, Any?>) = send("authorization", data)

    fun sendWatchPosition(data: Map<String, Any?>) = send("watchposition", data)

    /** Returns true if a listener is attached for the given event name. */
    fun hasListener(eventName: String): Boolean = sinks[eventName] != null

    // ---------------------------------------------------------------------------
    // Private
    // ---------------------------------------------------------------------------

    private fun send(eventName: String, data: Any?) {
        val sink = sinks[eventName]
        if (sink != null) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                sink.success(data)
            } else {
                mainHandler.post { sink.success(data) }
            }
        } else {
            // No Dart UI listener — route to headless fallback if available.
            headlessFallback?.let { fallback ->
                @Suppress("UNCHECKED_CAST")
                val eventData = when (data) {
                    is Map<*, *> -> data as Map<String, Any?>
                    else -> mapOf("value" to data)
                }
                fallback(eventName, eventData)
            }
        }
    }
}
