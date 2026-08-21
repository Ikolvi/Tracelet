package com.ikolvi.tracelet.sdk.location

import android.Manifest
import android.app.Application
import android.content.Context
import android.location.Location
import android.os.Build
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.util.TraceletLog
import com.ikolvi.tracelet.sdk.wrapper.TraceletActivityRecognitionClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationToken
import com.ikolvi.tracelet.sdk.wrapper.TraceletEventExtractor
import com.ikolvi.tracelet.sdk.wrapper.TraceletGeofencingClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationCallback
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationClient
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationRequest
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletServicesProvider
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLog
import java.time.Duration

/**
 * Regression test for GitHub issue #407:
 *   "the stall watchdog is fix-driven, so a stream that delivers nothing never
 *    reports a stall"
 *
 * `noteFilterDecision` only runs when a fix arrives, so the one failure mode
 * where the SDK is completely blind — the provider delivering nothing at all —
 * produced no signal. A Doctor report covering a 52-second dead window (#405)
 * printed *"the stream has been accepting fixes"*; it had accepted none.
 *
 * The distinction these tests pin is not cosmetic. Rejection means the pipeline
 * is alive and mis-tuned, and a threshold change fixes it. Silence means the OS
 * has stopped talking to the app, and no threshold change will ever help. They
 * need different messages because they need different responses.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
class LocationEngineSilenceWatchdogTest {

    private lateinit var context: Context
    private lateinit var engine: LocationEngine
    private val client = SilenceLocationClient()

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        shadowOf(context as Application).grantPermissions(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        TraceletServices.setProvider(SilenceServicesProvider(client))
        // The lifecycle channel falls back to logcat until the SDK attaches a
        // real logger, which is what makes it readable here. Detach explicitly:
        // another test in the same JVM may have attached one, and the assertion
        // would then silently pass on an empty log.
        TraceletLog.detach()
        ShadowLog.clear()

        val config = ConfigManager.getInstance(context)
        config.reset(null)
        engine = LocationEngine(context, config, StateManager(context), mock<TraceletEventSender>())
    }

    @After
    fun tearDown() {
        engine.stop()
        TraceletServices.setProvider(null)
        ConfigManager.resetInstance()
        ShadowLog.clear()
    }

    private fun advance(seconds: Long) =
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(seconds))

    private fun logged(fragment: String) =
        ShadowLog.getLogs().any { it.msg?.contains(fragment) == true }

    /**
     * The reported failure. A continuous stream that never delivers must say so
     * on its own schedule — nothing else is going to call the watchdog.
     */
    @Test
    fun `a stream that delivers nothing announces silence on its own timer`() {
        engine.start()
        checkNotNull(client.callback) { "start() did not subscribe a location callback" }

        advance(30)
        assertFalse(
            "30s is inside the announce window — announcing here would fire on every " +
                "stationary-to-moving transition and be tuned out",
            logged("location stream silent"),
        )

        advance(30)
        assertTrue(
            "#407: 60s with no callback at all must be announced, and on the " +
                "always-on lifecycle channel so a released app can report it",
            logged("location stream silent"),
        )
    }

    /**
     * The line has to carry the request it is complaining about. "No fixes" with
     * no numbers is the same dead end as the bare `DISTANCE_FILTER` line #397
     * replaced — unfalsifiable without the source open.
     */
    @Test
    fun `the silence line carries the request that is supposedly live`() {
        engine.start()
        advance(60)

        val line = ShadowLog.getLogs()
            .mapNotNull { it.msg }
            .first { it.contains("location stream silent") }
        assertTrue("must name the interval: $line", line.contains("interval="))
        assertTrue("must name the accuracy: $line", line.contains("accuracy="))
        assertTrue(
            "must say this is the provider, not the filter — the two have different " +
                "fixes and the report is read by someone deciding which: $line",
            line.contains("not the filter"),
        )
    }

    /**
     * A delivered fix is a live stream, whatever the filter later decides about
     * it. Sharing the filter's clock is exactly the bug.
     */
    @Test
    fun `a delivered fix keeps the stream from being called silent`() {
        engine.start()
        val callback = checkNotNull(client.callback)

        advance(30)
        // The watchdog observes the callback boundary; what the filter and the
        // Rust processor do with the fix afterwards is covered by their own
        // tests. On a host JVM without a current `tracelet_core` dylib that
        // pipeline throws, and it must not be what decides this assertion.
        runCatching { callback.onLocationResult(listOf(fix())) }
        advance(30)

        assertFalse(
            "the provider delivered inside the window, so the stream is not silent — " +
                "whether the filter kept that fix is a different question with a " +
                "different watchdog (#397)",
            logged("location stream silent"),
        )
    }

    /**
     * A stopped stream is silent by definition. Announcing it would put a red
     * line in every bug report from a device that is simply parked, which is the
     * fastest way to get the real one ignored.
     */
    @Test
    fun `a stopped stream is not announced as silent`() {
        engine.start()
        advance(10)
        engine.stop()

        advance(120)

        assertFalse(
            "stop() cancels the watchdog: silence after a deliberate stop is the " +
                "design, and stationary-periodic mode spends most of its life there",
            logged("location stream silent"),
        )
    }

    private fun fix() = Location("gps").apply {
        latitude = 10.7879
        longitude = 76.6841
        accuracy = 5.0f
        time = System.currentTimeMillis()
        elapsedRealtimeNanos = android.os.SystemClock.elapsedRealtimeNanos()
    }
}

private class SilenceLocationClient : TraceletLocationClient {
    var callback: TraceletLocationCallback? = null

    override fun requestLocationUpdates(
        request: TraceletLocationRequest,
        callback: TraceletLocationCallback,
        looper: Looper,
    ) {
        this.callback = callback
    }

    override fun removeLocationUpdates(callback: TraceletLocationCallback) {
        this.callback = null
    }

    override fun getCurrentLocation(
        priority: Int,
        cancellationToken: TraceletCancellationToken?,
        onSuccess: (Location?) -> Unit,
    ) = onSuccess(null)

    override fun getLastLocation(onSuccess: (Location?) -> Unit, onFailure: (Exception) -> Unit) =
        onSuccess(null)
}

private class SilenceServicesProvider(
    private val client: TraceletLocationClient,
) : TraceletServicesProvider {
    override fun getLocationClient(context: Context) = client
    override fun getGeofencingClient(context: Context) = mock<TraceletGeofencingClient>()
    override fun getActivityRecognitionClient(context: Context) =
        mock<TraceletActivityRecognitionClient>()
    override fun getEventExtractor() = mock<TraceletEventExtractor>()
}
