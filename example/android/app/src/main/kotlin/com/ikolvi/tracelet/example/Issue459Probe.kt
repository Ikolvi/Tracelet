package com.ikolvi.tracelet.example

import android.content.Context
import android.content.ContextWrapper
import android.location.Location
import android.os.SystemClock
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.location.LocationEngine

/** Drives the real location engine with controlled fixes without starting a GPS session (#459). */
internal fun probeIssue459(context: Context): Map<String, List<Double>> {
    val probeContext = object : ContextWrapper(context.applicationContext) {
        override fun getSharedPreferences(name: String, mode: Int) =
            super.getSharedPreferences("issue459-$name", mode)
    }
    val config = ConfigManager(probeContext).apply {
        setConfig(mapOf("persistMode" to 3, "distanceFilter" to 10.0))
    }
    val state = StateManager(probeContext).apply { enabled = true }
    val events = object : TraceletEventSender by TraceletSdk.getInstance(context).getEventSender() {
        override fun sendLocation(data: Map<String, Any?>) = Unit
    }
    val engine = LocationEngine(probeContext, config, state, events)
    val raw = mutableListOf<Double>()
    val pace = mutableListOf<Double>()
    engine.rawSpeedSink = { raw.add(it) }
    engine.speedMotionSpeedSink = { pace.add(it) }

    // Keep the injection seam in the Example app. The SDK has no test-only API.
    val receive = LocationEngine::class.java.getDeclaredMethod(
        "onLocationReceived", Location::class.java, String::class.java, Boolean::class.javaPrimitiveType,
    ).apply { isAccessible = true }
    val now = System.currentTimeMillis()
    val elapsed = SystemClock.elapsedRealtimeNanos()
    fun fix(latitude: Double, ageMs: Long, speedMps: Float?): Location =
        Location("gps").apply {
            this.latitude = latitude
            longitude = 76.684183
            accuracy = 5f
            time = now - ageMs
            elapsedRealtimeNanos = elapsed - ageMs * 1_000_000
            speedMps?.let { speed = it }
        }
    try {
        receive.invoke(engine, fix(10.787929, 2000, null), "", false)
        receive.invoke(engine, fix(10.787956, 1000, 0f), "", false)
        receive.invoke(engine, fix(10.787983, 0, null), "", false)
        return mapOf("raw" to raw, "pace" to pace)
    } finally {
        engine.destroy()
    }
}
