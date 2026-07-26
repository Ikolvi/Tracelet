package com.ikolvi.tracelet.sdk.service

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.location.LocationEngine
import java.time.Duration
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.atLeastOnce
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * Regression tests for the "stop() doesn't stop" bug: the stationary
 * periodic timer lives in [LocationService]'s companion (not in the
 * SDK's LocationEngine), so it kept fetching/persisting/syncing
 * locations after the user pressed stop. The timer must cancel itself
 * as soon as it observes the persisted `enabled == false` state.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [33])
class LocationServiceStationaryTimerTest {

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
        engine = LocationEngine(context, config, state, ListenerEventSender())
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

        // Simulate stop(): only the persisted flag flips; the timer's own
        // guard must cancel it on the next tick even if no one called
        // stopStationaryTimer() explicitly.
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
