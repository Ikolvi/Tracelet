package com.ikolvi.tracelet.flutter.service

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.service.LocationService
import java.time.Duration
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.atLeastOnce
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * CI copy of the SDK's LocationServiceStationaryTimerTest (see
 * sdk/android/tracelet-sdk/src/test) — this module's test task is the one
 * gated in CI, so SDK-behavior regressions are duplicated here.
 *
 * Covers the stationary periodic timer in [LocationService]'s companion:
 * - it must cancel itself once the persisted `enabled` flag flips false
 *   (the "stop() doesn't stop" bug), and
 * - its ticks must request fixes with `persist=false` so the engine does
 *   not insert the same map (same uuid) the timer inserts itself — the
 *   "UNIQUE constraint failed: location_events.uuid" every ~120s bug (#248).
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [33])
internal class LocationServiceStationaryTimerTest {

    private lateinit var context: Context
    private lateinit var config: ConfigManager
    private lateinit var state: StateManager
    private lateinit var engine: LocationEngine

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        config = ConfigManager.getInstance(context)
        config.setConfig(mapOf("stationaryPeriodicInterval" to 1)) // 1s ticks
        state = StateManager(context)
        state.enabled = true
        // ListenerEventSender is internal to the SDK module; a mocked
        // TraceletEventSender is equivalent for these tests.
        engine = LocationEngine(context, config, state, mock<TraceletEventSender>())
    }

    @After
    fun tearDown() {
        LocationService.stopStationaryTimer()
        engine.destroy()
        ConfigManager.resetInstance()
        StateManager(context).enabled = false
    }

    @Test
    fun `stationary periodic timer cancels itself when tracking is disabled`() {
        LocationService.switchToStationaryPeriodic(engine, config, state)
        assertNotNull(
            LocationService.stationaryTimerRunnable,
            "Timer should be scheduled after switching to stationary periodic",
        )

        state.enabled = false
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(2))

        assertNull(
            LocationService.stationaryTimerRunnable,
            "Timer must cancel itself once tracking is disabled",
        )
    }

    @Test
    fun `stationary periodic tick requests fixes without engine-side persistence`() {
        // Regression for #248: the tick callback inserts the enriched
        // "periodic" record itself, so getCurrentPosition() must not persist
        // the same map (same uuid) first — that made every tick's insert fail
        // with "UNIQUE constraint failed: location_events.uuid".
        val mockEngine = mock<LocationEngine>()
        LocationService.switchToStationaryPeriodic(mockEngine, config, state)

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(2))

        val options = argumentCaptor<Map<String, Any?>>()
        verify(mockEngine, atLeastOnce()).getCurrentPosition(options.capture(), any())
        assertEquals(false, options.firstValue["persist"])
    }

    @Test
    fun `stationary periodic timer keeps running while tracking is enabled`() {
        LocationService.switchToStationaryPeriodic(engine, config, state)

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(2))

        assertNotNull(
            LocationService.stationaryTimerRunnable,
            "Timer must stay scheduled while tracking is enabled",
        )
    }
}
