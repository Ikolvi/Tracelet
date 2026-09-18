package com.ikolvi.tracelet.sdk.service

import android.app.ActivityManager
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
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * Regression test for GitHub issue #405:
 *   "a foreground service started from the background is denied location for
 *    its whole life, and the SDK reports it as healthy"
 *
 * Android 12+ latches `mAllowWhileInUsePermissionInFgs` when the ServiceRecord
 * is created — at `startService()`, not at `startForeground()` — and the value
 * lives for the life of the record. A record created from the background gives
 * a foreground service that posts its notification, reports `isForeground=true`
 * and carries `FOREGROUND_SERVICE_TYPE_LOCATION`, while the OS withholds the
 * foreground-location capability. Confirmed on a LAVA LXX503 running Android
 * 14: backgrounded, `curProcState=4 (FGS)` with `caps=---NFU` — no `L` — and
 * `gps provider: ProviderRequest[OFF]` for the whole session. The same build
 * relaunched from the foreground reported `caps=L--NFU` and GPS at
 * `[@+2s0ms, HIGH_ACCURACY]`.
 *
 * The SDK cannot read process capabilities — there is no public API — so it
 * records the procstate the record was created in, which is the input the OS
 * latches on. These tests pin that the health snapshot separates "promoted"
 * from "promoted and able to use location", because six green rows over a
 * service that recorded nothing for 52 seconds is what made this take a
 * physically connected device to diagnose.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class LocationServiceWhileInUseLocationTest {

    private lateinit var context: Context
    private var controller: ServiceController<LocationService>? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        ConfigManager.getInstance(context).reset(null)
        ConfigManager.getInstance(context).setConfig(
            mapOf(
                "android" to mapOf(
                    "foregroundService" to mapOf(
                        "enabled" to true,
                        "channelId" to "tl_test_channel",
                    ),
                ),
            ),
        )
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

    /**
     * Drives the two signals `isAppInForeground()` reads.
     *
     * `ProcessLifecycleOwner` is the authoritative one; process importance is
     * the fallback for the boot / `onStartCommand` path where no lifecycle
     * signal exists, and it has to be moved too or the fallback alone reports a
     * foreground app.
     */
    private fun setProcessImportance(importance: Int) {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.RunningAppProcessInfo(
            context.packageName,
            android.os.Process.myPid(),
            emptyArray(),
        )
        info.importance = importance
        info.uid = android.os.Process.myUid()
        shadowOf(am).setProcesses(listOf(info))
    }

    private fun startService(): LocationService {
        val intent = Intent().apply { action = LocationService.ACTION_START }
        val c = Robolectric.buildService(LocationService::class.java)
        controller = c
        return c.create().withIntent(intent).startCommand(0, 1).get()
    }

    /**
     * The reported state. Everything here says "healthy" except the one field
     * that was missing.
     */
    @Test
    fun `a service created in the background is reported as unable to use location`() {
        setProcessImportance(ActivityManager.RunningAppProcessInfo.IMPORTANCE_SERVICE)
        val service = startService()

        assertNotNull(
            shadowOf(service).lastForegroundNotification,
            "the service still promotes itself — that is the point: the promotion " +
                "succeeds and the notification shows, which is why this state looked " +
                "healthy in every bug report (#405)",
        )

        val health = LocationService.foregroundServiceHealth()
        assertEquals(
            true,
            health["serviceForeground"],
            "promoted is still promoted; the fix does not change what the OS granted",
        )
        assertEquals(
            false,
            health["serviceStartedInForeground"],
            "the procstate the record was created in is what Android latches on, and " +
                "it is the only input the SDK can observe",
        )
        assertEquals(
            true,
            health["locationCapabilityLikelyDenied"],
            "#405: this is the field that separates a service that can track from one " +
                "that will post a notification and never deliver a fix",
        )
    }

    /**
     * #406: the OS refuses the promotion outright in the "Restricted" battery
     * state, and says so only in its own log —
     * `Service.startForeground() not allowed due to bg restriction` — without
     * throwing. `startForeground()` returns, so the SDK recorded `success`.
     *
     * Confirmed on the same LAVA LXX503: `isForeground=false types=00000000`
     * with `caps=------` and GPS turned off ~1s after every registration, while
     * the report read `Promoted to foreground: true / Last promotion result:
     * success`. A report that says the service is healthy while the OS has
     * switched it off sends every investigation into the SDK.
     */
    @Test
    fun `a promotion the OS refuses is not reported as a successful one`() {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        shadowOf(am).setBackgroundRestricted(true)
        setProcessImportance(ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND)
        startService()

        val health = LocationService.foregroundServiceHealth()
        assertEquals(
            false,
            health["serviceForeground"],
            "the OS refused the promotion, so there is no foreground service to report",
        )
        assertEquals(
            "refused",
            health["lastForegroundPromotionResult"],
            "`refused` separates 'the OS said no' from `success`, `failed` and " +
                "`suppressed` — the four are not interchangeable (#406)",
        )
        assertEquals(
            null,
            health["foregroundNotificationId"],
            "and no notification id, which is what a consumer keys 'we are promoted' on",
        )
    }

    /**
     * The other half: a session started from the foreground must not be flagged,
     * or the warning is noise and gets ignored on the day it matters.
     */
    @Test
    fun `a service created in the foreground is not flagged`() {
        setProcessImportance(ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND)
        val service = startService()
        (service as DefaultLifecycleObserver).onStart(ProcessLifecycleOwner.get())

        val health = LocationService.foregroundServiceHealth()
        assertEquals(
            true,
            health["serviceStartedInForeground"],
            "a record created from TOP carries the while-in-use grant for its life",
        )
        assertEquals(
            false,
            health["locationCapabilityLikelyDenied"],
            "no finding to report — a foreground-created service tracks normally in " +
                "the background, which is the behaviour the A/B on the device showed",
        )
    }

    /**
     * The latch belongs to the record, not the process. A destroyed service
     * must not leave its verdict behind for the next one, which may well be
     * created from the opposite state.
     */
    @Test
    fun `the verdict is cleared when the service is destroyed`() {
        setProcessImportance(ActivityManager.RunningAppProcessInfo.IMPORTANCE_SERVICE)
        startService()
        assertEquals(true, LocationService.foregroundServiceHealth()["locationCapabilityLikelyDenied"])

        controller?.destroy()
        controller = null

        val health = LocationService.foregroundServiceHealth()
        assertEquals(
            null,
            health["serviceStartedInForeground"],
            "no service, no latch — reporting the previous record's would be a " +
                "guess about a record that does not exist yet",
        )
        assertEquals(
            false,
            health["locationCapabilityLikelyDenied"],
            "nothing is promoted, so nothing is denied",
        )
    }
}
