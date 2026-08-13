package com.ikolvi.tracelet.sdk.service

import android.content.Context
import android.content.Intent
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.test.core.app.ApplicationProvider
import com.ikolvi.tracelet.sdk.ConfigManager
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Regression test for GitHub issue #378:
 *   "showNotificationOnPauseOnly: true silently defeats stopOnTerminate: false"
 *
 * Pause-only visibility hides the notification by demoting the service, and a
 * demoted service is not a foreground service — so `ActivityManager` kills the
 * hosting process on task removal. It chooses which processes to kill from
 * `proc.foregroundServices` while holding its own lock, before `onTaskRemoved`
 * reaches the app's main thread, so the forced promotion there cannot rescue
 * it. Everything `stopOnTerminate = false` promises was lost to a swipe timed
 * inside that window: no headless engine, no events, no logs.
 *
 * These tests pin the resolution: the promise wins over the preference. With
 * `stopOnTerminate = false` the service is never demoted; with
 * `stopOnTerminate = true` — where nothing is promised past the swipe —
 * pause-only visibility works exactly as it did.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class LocationServicePauseOnlySurvivalTest {

    private lateinit var context: Context
    private var controller: ServiceController<LocationService>? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        ConfigManager.getInstance(context).reset(null)
    }

    @After
    fun tearDown() {
        try {
            controller?.destroy()
        } catch (_: Throwable) {
        }
        controller = null
        ConfigManager.getInstance(context).reset(null)
    }

    /** The reported configuration, minus the field under test. */
    private fun configure(stopOnTerminate: Boolean, pauseOnly: Boolean) {
        ConfigManager.getInstance(context).setConfig(
            mapOf(
                "app" to mapOf("stopOnTerminate" to stopOnTerminate),
                "android" to mapOf(
                    "foregroundService" to mapOf(
                        "enabled" to true,
                        "channelId" to "tl_test_channel",
                        "showNotificationOnPauseOnly" to pauseOnly,
                    ),
                ),
            ),
        )
    }

    private fun startService(): LocationService {
        val intent = Intent().apply { action = LocationService.ACTION_START }
        val c = Robolectric.buildService(LocationService::class.java)
        controller = c
        return c.create().withIntent(intent).startCommand(0, 1).get()
    }

    /**
     * The authoritative foreground/background signal. The service observes
     * `ProcessLifecycleOwner` and passes the real UI state to
     * `updateNotificationVisibility`, rather than depending on the
     * process-importance heuristic its own foreground service skews.
     */
    private fun appOnScreen(service: LocationService) =
        (service as DefaultLifecycleObserver).onStart(ProcessLifecycleOwner.get())

    private fun appBackgrounded(service: LocationService) =
        (service as DefaultLifecycleObserver).onStop(ProcessLifecycleOwner.get())

    /**
     * The fix. This is the exact state the report was filed from, and the whole
     * bug is one `stopForeground` call away.
     */
    @Test
    fun `pause-only never demotes the service while stopOnTerminate is false`() {
        configure(stopOnTerminate = false, pauseOnly = true)
        val service = startService()

        appOnScreen(service)

        val shadow = shadowOf(service)
        assertFalse(
            shadow.isForegroundStopped,
            "stopForeground() must not run while stopOnTerminate=false: a process " +
                "with no foreground service is one ActivityManager kills on task " +
                "removal, and it decides that before onTaskRemoved can post the " +
                "notification back (#378)",
        )
        assertNotNull(
            shadow.lastForegroundNotification,
            "the notification must still be attached — it is what keeps the " +
                "process alive across a swipe from recents",
        )
        assertEquals(
            true,
            LocationService.foregroundServiceHealth()["serviceForeground"],
            "health must report the service as promoted, because it is",
        )
    }

    /**
     * The other half of the contract: an app that has not asked to outlive task
     * removal keeps the feature it configured. Without this, the fix above
     * would just be a removal of `showNotificationOnPauseOnly`.
     */
    @Test
    fun `pause-only still hides the notification while stopOnTerminate is true`() {
        configure(stopOnTerminate = true, pauseOnly = true)
        val service = startService()

        appOnScreen(service)

        val shadow = shadowOf(service)
        assertTrue(
            shadow.isForegroundStopped,
            "with stopOnTerminate=true nothing is promised past the swipe, so the " +
                "notification is still hidden while the app is on screen",
        )
        assertNull(
            shadow.lastForegroundNotification,
            "STOP_FOREGROUND_REMOVE takes the notification down with the promotion",
        )

        val health = LocationService.foregroundServiceHealth()
        assertEquals(
            false,
            health["serviceForeground"],
            "#378: the demotion must be visible in the health snapshot — it used to " +
                "keep reporting the last successful promotion, so the API that " +
                "exists to say whether background tracking is operational claimed a " +
                "foreground service during the window where there was none",
        )
        assertEquals(
            "suppressed",
            health["lastForegroundPromotionResult"],
            "a deliberate demotion must be distinguishable from an OS refusal: " +
                "`suppressed` still means tracking, `failed` does not",
        )
    }

    /**
     * `lastForegroundTransitionAt` is what makes the window measurable — the
     * log table stores whole seconds and the window is shorter than one. It is
     * only meaningful if a re-post of a notification the service already holds
     * does not masquerade as a transition.
     */
    @Test
    fun `the transition stamp moves on a real transition and not on a re-post`() {
        configure(stopOnTerminate = false, pauseOnly = true)
        val service = startService()
        appOnScreen(service)

        val afterStart = LocationService.foregroundServiceHealth()["lastForegroundTransitionAt"]
        assertNotNull(afterStart, "the first successful promotion is a transition")

        // Persistent mode re-posts on the background transition, in case the
        // notification was dismissed while the app was open. Nothing about the
        // service's foreground state changed.
        ShadowSystemClock.advanceBy(Duration.ofSeconds(5))
        appBackgrounded(service)

        assertEquals(
            afterStart,
            LocationService.foregroundServiceHealth()["lastForegroundTransitionAt"],
            "a re-post of an already-promoted notification is not a transition; " +
                "counting it as one would report a fresh promotion after every " +
                "backgrounding and hide the window it exists to measure (#378)",
        )

        // A genuine demotion is a transition, and must move the stamp.
        ConfigManager.getInstance(context).setConfig(mapOf("app" to mapOf("stopOnTerminate" to true)))
        ShadowSystemClock.advanceBy(Duration.ofSeconds(5))
        appOnScreen(service)

        val afterSuppression =
            LocationService.foregroundServiceHealth()["lastForegroundTransitionAt"] as Long
        assertTrue(
            afterSuppression > afterStart as Long,
            "the demotion is a transition and must be stamped, or the window has no " +
                "measurable start",
        )
    }
}
