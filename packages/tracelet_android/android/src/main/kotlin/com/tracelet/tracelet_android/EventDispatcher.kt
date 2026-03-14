package com.tracelet.tracelet_android

import android.os.Handler
import android.os.Looper
import com.tracelet.core.TraceletEventSender
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Flutter-specific [TraceletEventSender] implementation using EventChannels.
 *
 * Manages 15 EventChannels and their EventSinks. All event dispatch
 * is marshalled to the main thread for Flutter platform channel safety.
 *
 * When no Dart UI listener is attached for a given event, the dispatcher
 * falls back to [headlessFallback] (if set) so that events can be routed
 * to a background Dart isolate via HeadlessTaskService.
 */
class EventDispatcher : TraceletEventSender {

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
    // TraceletEventSender implementation (all marshal to main thread)
    // ---------------------------------------------------------------------------

    override fun sendLocation(data: Map<String, Any?>) = send("location", data)

    override fun sendMotionChange(data: Map<String, Any?>) = send("motionchange", data)

    override fun sendActivityChange(data: Map<String, Any?>) = send("activitychange", data)

    override fun sendProviderChange(data: Map<String, Any?>) = send("providerchange", data)

    override fun sendGeofence(data: Map<String, Any?>) = send("geofence", data)

    override fun sendGeofencesChange(data: Map<String, Any?>) = send("geofenceschange", data)

    override fun sendHeartbeat(data: Map<String, Any?>) = send("heartbeat", data)

    override fun sendHttp(data: Map<String, Any?>) = send("http", data)

    override fun sendSchedule(data: Map<String, Any?>) = send("schedule", data)

    override fun sendPowerSaveChange(isPowerSaveMode: Boolean) = send("powersavechange", isPowerSaveMode)

    override fun sendConnectivityChange(data: Map<String, Any?>) = send("connectivitychange", data)

    override fun sendEnabledChange(enabled: Boolean) = send("enabledchange", enabled)

    override fun sendNotificationAction(action: String) = send("notificationaction", action)

    override fun sendAuthorization(data: Map<String, Any?>) = send("authorization", data)

    override fun sendWatchPosition(data: Map<String, Any?>) = send("watchposition", data)

    /** Returns true if a listener is attached for the given event name. */
    override fun hasListener(eventName: String): Boolean = sinks[eventName] != null

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
