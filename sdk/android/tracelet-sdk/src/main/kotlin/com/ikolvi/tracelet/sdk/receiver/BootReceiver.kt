package com.ikolvi.tracelet.sdk.receiver
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.service.LocationService
import com.ikolvi.tracelet.sdk.util.OemCompat

/**
 * Receives BOOT_COMPLETED broadcast to restart tracking after device reboot.
 *
 * Enabled/disabled via PackageManager based on the startOnBoot config setting.
 * When enabled, reads persisted config and restarts the correct tracking mode:
 * - Continuous (mode 0): starts foreground LocationService with native tracking
 * - Geofences (mode 1): starts foreground LocationService (geofences re-registered by Play Services)
 * - Periodic (mode 2): re-schedules WorkManager/AlarmManager work, only starts
 *   foreground service if periodicUseForegroundService is true
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        // Accept the standard boot broadcast plus the OEM quick-boot variants that
        // some devices emit instead of BOOT_COMPLETED on fast power-on.
        val action = intent?.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        TraceletLog.debug("Boot completed — checking startOnBoot config")

        val configManager = ConfigManager.getInstance(context)
        if (!configManager.hasConfig()) {
            TraceletLog.debug("No persisted config found, skipping")
            return
        }

        if (!configManager.getStartOnBoot()) {
            TraceletLog.debug("startOnBoot is false, skipping")
            return
        }

        // Guard: background location permission is required for boot restart.
        // If the user only granted "While In Use" or revoked permission,
        // do not attempt tracking — it would silently fail or violate policy.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val hasBackground = ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            if (!hasBackground) {
                TraceletLog.warning("ACCESS_BACKGROUND_LOCATION not granted — cannot restart tracking on boot")
                // Persist disabled state so the plugin doesn't retry on next boot
                val statePrefs = context.getSharedPreferences("com.tracelet.state", Context.MODE_PRIVATE)
                statePrefs.edit().putBoolean("enabled", false).apply()
                return
            }
            TraceletLog.debug("ACCESS_BACKGROUND_LOCATION granted — proceeding with boot restart")
        }

        val stateManager = StateManager(context)

        // Only resume tracking that was active when the device shut down.
        // If the user explicitly called stop(), a reboot must not resurrect
        // tracking — startOnBoot means "survive reboots", not "auto-start".
        if (!stateManager.enabled) {
            TraceletLog.debug("Tracking was stopped before reboot — not resuming")
            return
        }

        // The strategy the app started, not the pace. A parked SMART session has
        // `trackingMode = PERIODIC` (the stationary switch writes it), and reading
        // that here rebooted a `start()` session into a 15-minute WorkManager fix
        // with no service, detector or heartbeat (#447) — the same split
        // `onTaskRemoved` and `startBootTracking` already read (#428).
        val trackingMode = stateManager.sessionTrackingMode

        TraceletLog.debug("startOnBoot=true, trackingMode=$trackingMode (pace=${stateManager.trackingMode}) — restoring tracking")

        // Acquire a temporary OEM-safe wakelock to prevent aggressive power
        // managers (Huawei PowerGenie, Xiaomi MIUI) from killing our process
        // between onReceive() returning and the foreground service starting.
        // The service acquires its own wakelock, so we release after 60s max.
        val wakelock = OemCompat.acquireOemSafeWakelock(context, timeout = 60_000)

        // Update state to indicate background launch (synchronous commit)
        val statePrefs = context.getSharedPreferences("com.tracelet.state", Context.MODE_PRIVATE)
        statePrefs.edit()
            .putBoolean("didDeviceReboot", true)
            .putBoolean("didLaunchInBackground", true)
            .putBoolean("enabled", true)
            .commit() // synchronous write — must complete before service starts

        if (trackingMode == TrackingMode.PERIODIC && !configManager.getPeriodicUseForegroundService()) {
            // Periodic mode without foreground service —
            // re-schedule WorkManager/AlarmManager work directly.
            // No foreground service needed (no persistent notification).
            scheduleBackgroundFallback(context, configManager)
        } else {
            // Continuous (0), geofences (1), or periodic with foreground service —
            // start the foreground service with boot flag for native tracking.
            val started = LocationService.startFromBoot(context)
            if (!started) {
                // The platform refused the foreground-service start (e.g. Android 14
                // disallows starting a location-type FGS from BOOT_COMPLETED). Don't
                // give up — fall back to the background-eligible WorkManager/alarm
                // path so tracking still resumes after the reboot.
                TraceletLog.warning("Boot foreground service refused by OS — falling back to background WorkManager/alarm tracking")
                scheduleBackgroundFallback(context, configManager)
            }
        }

        // Wakelock auto-releases after 60s timeout (A-M5). Do NOT release it
        // manually here — the foreground service start is asynchronous and the
        // device could sleep before the service's onCreate acquires its own lock.
    }

    /**
     * Re-schedules tracking via the background-eligible WorkManager/AlarmManager
     * path. Used both for periodic-mode boot restore and as the fallback when a
     * foreground-service start is refused at boot (Android 12+ background
     * restriction). Auto-selects exact alarms when the interval is < 15 min,
     * matching TraceletAndroidPlugin.handleStartPeriodic().
     */
    private fun scheduleBackgroundFallback(context: Context, configManager: ConfigManager) {
        val interval = configManager.getPeriodicLocationInterval()
        val useExactAlarms = configManager.getPeriodicUseExactAlarms() ||
            interval < 900

        if (useExactAlarms) {
            PeriodicLocationWorker.scheduleOneTime(context)
            PeriodicLocationWorker.scheduleExactAlarm(context, interval)
            TraceletLog.debug("Background tracking scheduled with exact alarms (interval=${interval}s)")
        } else {
            PeriodicLocationWorker.schedule(context, interval)
            TraceletLog.debug("Background tracking scheduled with WorkManager (interval=${interval}s)")
        }
    }
}
