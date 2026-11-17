package com.ikolvi.tracelet.sdk.location

import android.content.Context
import android.location.Location
import android.os.Build
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.R])
class LocationEngineReportedSpeedTest {
    @Test
    fun `measured zero survives coordinate drift`() {
        assertSpeeds(reported = 0f, expected = 0.0)
    }

    @Test
    fun `missing speed still uses displacement`() {
        assertSpeeds(reported = null, expected = 3.0)
    }

    private fun assertSpeeds(reported: Float?, expected: Double) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val config = ConfigManager(context).apply {
            setConfig(mapOf("persistMode" to 3, "distanceFilter" to 10.0))
        }
        val state = StateManager(context).apply { enabled = true }
        val engine = LocationEngine(context, config, state, mock())
        val rawSpeeds = mutableListOf<Double>()
        val paceSpeeds = mutableListOf<Double>()
        engine.rawSpeedSink = { rawSpeeds.add(it) }
        engine.speedMotionSpeedSink = { paceSpeeds.add(it) }

        val receive = LocationEngine::class.java.getDeclaredMethod(
            "onLocationReceived", Location::class.java, String::class.java, Boolean::class.javaPrimitiveType,
        ).apply { isAccessible = true }
        val timeMs = System.currentTimeMillis()
        val elapsedNanos = SystemClock.elapsedRealtimeNanos()
        try {
            receive.invoke(engine, fixAt(10.787929, timeMs - 1000, elapsedNanos - 1_000_000_000), "", false)
            // A drift of about 3 m with a 10 m distance gate. Filtering the fix
            // for storage must not turn its measured stop into movement (#459).
            val second = fixAt(10.787956, timeMs, elapsedNanos)
            reported?.let { second.speed = it }
            receive.invoke(engine, second, "", false)

            assertEquals(2, rawSpeeds.size)
            assertEquals(2, paceSpeeds.size)
            assertEquals(expected, rawSpeeds.last(), 0.1)
            assertEquals(expected, paceSpeeds.last(), 0.1)
        } finally {
            engine.destroy()
        }
    }

    private fun fixAt(lat: Double, timeMs: Long, elapsedNanos: Long) = Location("gps").apply {
        latitude = lat
        longitude = 76.684183
        accuracy = 5f
        time = timeMs
        elapsedRealtimeNanos = elapsedNanos
    }
}
