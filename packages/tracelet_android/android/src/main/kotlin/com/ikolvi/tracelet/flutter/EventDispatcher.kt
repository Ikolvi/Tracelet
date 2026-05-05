package com.ikolvi.tracelet.flutter

import android.os.Handler
import android.os.Looper
import com.ikolvi.tracelet.TlActivity
import com.ikolvi.tracelet.TlActivityChangeEvent
import com.ikolvi.tracelet.TlAuthorizationEvent
import com.ikolvi.tracelet.TlBattery
import com.ikolvi.tracelet.TlConnectivityChangeEvent
import com.ikolvi.tracelet.TlCoords
import com.ikolvi.tracelet.TlGeofence
import com.ikolvi.tracelet.TlGeofenceAction
import com.ikolvi.tracelet.TlGeofenceEvent
import com.ikolvi.tracelet.TlGeofencesChangeEvent
import com.ikolvi.tracelet.TlHeartbeatEvent
import com.ikolvi.tracelet.TlHttpEvent
import com.ikolvi.tracelet.TlLocation
import com.ikolvi.tracelet.TlProviderChangeEvent
import com.ikolvi.tracelet.TlState
import com.ikolvi.tracelet.TraceletEventApi
import com.ikolvi.tracelet.sdk.TraceletEventSender
import io.flutter.plugin.common.BinaryMessenger

/**
 * Flutter-specific [TraceletEventSender] implementation using Pigeon FlutterApi.
 *
 * Converts SDK map data to Pigeon typed objects and sends via
 * [TraceletEventApi]. All event dispatch is marshalled to the main thread.
 *
 * When no Flutter engine is attached, the dispatcher falls back to
 * [headlessFallback] (if set) so events can be routed to a background
 * Dart isolate via HeadlessTaskService.
 */
class EventDispatcher : TraceletEventSender {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventApi: TraceletEventApi? = null

    /**
     * Optional headless fallback. When no Flutter engine is attached,
     * the dispatcher calls this lambda with (eventName, eventData) so the
     * event can be forwarded to HeadlessTaskService.
     */
    var headlessFallback: ((eventName: String, data: Map<String, Any?>) -> Unit)? = null

    /** Connects to the Flutter engine's binary messenger. */
    fun register(messenger: BinaryMessenger) {
        eventApi = TraceletEventApi(messenger)
    }

    /** Disconnects from the Flutter engine. */
    fun unregister() {
        eventApi = null
    }

    // ---------------------------------------------------------------------------
    // TraceletEventSender implementation
    // ---------------------------------------------------------------------------

    override fun sendLocation(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val location = mapToTlLocation(data)
            postToMain { api.onLocation(location) {} }
        } else {
            fallback("location", data)
        }
    }

    override fun sendMotionChange(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val location = mapToTlLocation(data)
            postToMain { api.onMotionChange(location) {} }
        } else {
            fallback("motionchange", data)
        }
    }

    override fun sendActivityChange(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val event = TlActivityChangeEvent(
                activity = data["activity"] as? String ?: "unknown",
                confidence = (data["confidence"] as? Number)?.toLong() ?: -1L,
            )
            postToMain { api.onActivityChange(event) {} }
        } else {
            fallback("activitychange", data)
        }
    }

    override fun sendProviderChange(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val event = TlProviderChangeEvent(
                enabled = data["enabled"] as? Boolean ?: false,
                gps = data["gps"] as? Boolean ?: false,
                network = data["network"] as? Boolean ?: false,
                status = (data["status"] as? Number)?.toLong() ?: 0L,
                accuracyAuthorization = (data["accuracyAuthorization"] as? Number)?.toLong(),
            )
            postToMain { api.onProviderChange(event) {} }
        } else {
            fallback("providerchange", data)
        }
    }

    override fun sendGeofence(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            @Suppress("UNCHECKED_CAST")
            val locMap = data["location"] as? Map<String, Any?> ?: emptyMap()
            val actionStr = (data["action"] as? String ?: "ENTER").uppercase()
            val action = when (actionStr) {
                "EXIT" -> TlGeofenceAction.EXIT
                "DWELL" -> TlGeofenceAction.DWELL
                else -> TlGeofenceAction.ENTER
            }
            @Suppress("UNCHECKED_CAST")
            val event = TlGeofenceEvent(
                identifier = data["identifier"] as? String ?: "",
                action = action,
                location = mapToTlLocation(locMap),
                extras = data["extras"] as? Map<String?, Any?>,
            )
            postToMain { api.onGeofence(event) {} }
        } else {
            fallback("geofence", data)
        }
    }

    @Suppress("UNCHECKED_CAST")
    override fun sendGeofencesChange(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val onList = (data["on"] as? List<Map<String, Any?>>)?.map { mapToTlGeofence(it) }
            val offList = (data["off"] as? List<Map<String, Any?>>)?.map { mapToTlGeofence(it) }
            val event = TlGeofencesChangeEvent(on = onList, off = offList)
            postToMain { api.onGeofencesChange(event) {} }
        } else {
            fallback("geofenceschange", data)
        }
    }

    override fun sendHeartbeat(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            @Suppress("UNCHECKED_CAST")
            val locMap = data["location"] as? Map<String, Any?> ?: emptyMap()
            val event = TlHeartbeatEvent(location = mapToTlLocation(locMap))
            postToMain { api.onHeartbeat(event) {} }
        } else {
            fallback("heartbeat", data)
        }
    }

    override fun sendHttp(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val event = TlHttpEvent(
                isSuccess = data["success"] as? Boolean ?: false,
                status = (data["status"] as? Number)?.toLong() ?: 0L,
                responseText = data["responseText"] as? String ?: "",
            )
            postToMain { api.onHttp(event) {} }
        } else {
            fallback("http", data)
        }
    }

    override fun sendSchedule(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val state = mapToTlState(data)
            postToMain { api.onSchedule(state) {} }
        } else {
            fallback("schedule", data)
        }
    }

    override fun sendPowerSaveChange(isPowerSaveMode: Boolean) {
        val api = eventApi
        if (api != null) {
            postToMain { api.onPowerSaveChange(isPowerSaveMode) {} }
        } else {
            fallback("powersavechange", mapOf("value" to isPowerSaveMode))
        }
    }

    override fun sendConnectivityChange(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val event = TlConnectivityChangeEvent(
                connected = data["connected"] as? Boolean ?: false,
            )
            postToMain { api.onConnectivityChange(event) {} }
        } else {
            fallback("connectivitychange", data)
        }
    }

    override fun sendEnabledChange(enabled: Boolean) {
        val api = eventApi
        if (api != null) {
            postToMain { api.onEnabledChange(enabled) {} }
        } else {
            fallback("enabledchange", mapOf("value" to enabled))
        }
    }

    override fun sendNotificationAction(action: String) {
        val api = eventApi
        if (api != null) {
            postToMain { api.onNotificationAction(action) {} }
        } else {
            fallback("notificationaction", mapOf("value" to action))
        }
    }

    override fun sendAuthorization(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val event = TlAuthorizationEvent(
                success = data["success"] as? Boolean ?: false,
                status = (data["status"] as? Number)?.toLong() ?: 0L,
                response = data["response"] as? String ?: "",
            )
            postToMain { api.onAuthorization(event) {} }
        } else {
            fallback("authorization", data)
        }
    }

    override fun sendWatchPosition(data: Map<String, Any?>) {
        val api = eventApi
        if (api != null) {
            val location = mapToTlLocation(data)
            postToMain { api.onWatchPosition(location) {} }
        } else {
            fallback("watchposition", data)
        }
    }

    // Events without Pigeon FlutterApi counterparts — route to headless only.
    override fun sendRemoteConfigEvent(data: Map<String, Any?>) = fallback("remoteconfig", data)
    override fun sendTrip(data: Map<String, Any?>) = fallback("trip", data)
    override fun sendBudgetAdjustment(data: Map<String, Any?>) = fallback("budgetadjustment", data)

    override fun hasListener(eventName: String): Boolean = eventApi != null

    // ---------------------------------------------------------------------------
    // Map → Pigeon type converters
    // ---------------------------------------------------------------------------

    @Suppress("UNCHECKED_CAST")
    private fun mapToTlLocation(data: Map<String, Any?>): TlLocation {
        val coordsMap = data["coords"] as? Map<String, Any?> ?: emptyMap()
        val batteryMap = data["battery"] as? Map<String, Any?> ?: emptyMap()
        val activityMap = data["activity"] as? Map<String, Any?>

        return TlLocation(
            coords = TlCoords(
                latitude = (coordsMap["latitude"] as? Number)?.toDouble() ?: 0.0,
                longitude = (coordsMap["longitude"] as? Number)?.toDouble() ?: 0.0,
                accuracy = (coordsMap["accuracy"] as? Number)?.toDouble() ?: -1.0,
                speed = (coordsMap["speed"] as? Number)?.toDouble() ?: -1.0,
                heading = (coordsMap["heading"] as? Number)?.toDouble() ?: -1.0,
                altitude = (coordsMap["altitude"] as? Number)?.toDouble() ?: 0.0,
                altitudeAccuracy = (coordsMap["altitudeAccuracy"] as? Number)?.toDouble() ?: -1.0,
                speedAccuracy = (coordsMap["speedAccuracy"] as? Number)?.toDouble() ?: -1.0,
                headingAccuracy = (coordsMap["headingAccuracy"] as? Number)?.toDouble() ?: -1.0,
            ),
            battery = TlBattery(
                level = (batteryMap["level"] as? Number)?.toDouble() ?: -1.0,
                isCharging = batteryMap["is_charging"] as? Boolean ?: false,
            ),
            timestamp = data["timestamp"] as? String ?: "",
            uuid = data["uuid"] as? String ?: "",
            isMoving = (data["is_moving"] ?: data["isMoving"]) as? Boolean ?: false,
            odometer = (data["odometer"] as? Number)?.toDouble() ?: 0.0,
            event = data["event"] as? String,
            activity = activityMap?.let {
                TlActivity(
                    type = it["type"] as? String ?: "unknown",
                    confidence = (it["confidence"] as? Number)?.toLong() ?: -1L,
                )
            },
            extras = data["extras"] as? Map<String?, Any?>,
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun mapToTlGeofence(data: Map<String, Any?>): TlGeofence {
        val verticesRaw = data["vertices"] as? List<*>
        val vertices = verticesRaw?.map { v ->
            (v as? List<*>)?.map { (it as? Number)?.toDouble() }
        }
        return TlGeofence(
            identifier = data["identifier"] as? String ?: "",
            latitude = (data["latitude"] as? Number)?.toDouble() ?: 0.0,
            longitude = (data["longitude"] as? Number)?.toDouble() ?: 0.0,
            radius = (data["radius"] as? Number)?.toDouble() ?: 0.0,
            notifyOnEntry = data["notifyOnEntry"] as? Boolean ?: true,
            notifyOnExit = data["notifyOnExit"] as? Boolean ?: true,
            notifyOnDwell = data["notifyOnDwell"] as? Boolean ?: false,
            loiteringDelay = (data["loiteringDelay"] as? Number)?.toLong() ?: 0L,
            extras = data["extras"] as? Map<String?, Any?>,
            vertices = vertices,
        )
    }

    private fun mapToTlState(data: Map<String, Any?>): TlState {
        val modeInt = (data["trackingMode"] as? Number)?.toInt() ?: 0
        return TlState(
            enabled = data["enabled"] as? Boolean ?: false,
            isMoving = (data["isMoving"] ?: data["is_moving"]) as? Boolean ?: false,
            trackingMode = TlTrackingMode.ofRaw(modeInt) ?: TlTrackingMode.LOCATION,
            schedulerEnabled = data["schedulerEnabled"] as? Boolean ?: false,
            odometer = (data["odometer"] as? Number)?.toDouble() ?: 0.0,
            lastLocationTimestamp = data["lastLocationTimestamp"] as? String,
        )
    }

    // ---------------------------------------------------------------------------
    // Private
    // ---------------------------------------------------------------------------

    private inline fun postToMain(crossinline block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post { block() }
        }
    }

    private fun fallback(eventName: String, data: Map<String, Any?>) {
        headlessFallback?.invoke(eventName, data)
    }
}
