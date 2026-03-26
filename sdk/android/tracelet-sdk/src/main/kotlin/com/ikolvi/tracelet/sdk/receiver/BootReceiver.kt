package com.ikolvi.tracelet.sdk.receiver

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
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        Log.d(TAG, "Boot completed — checking startOnBoot config")

        val configManager = ConfigManager.getInstance(context)
        if (!configManager.hasConfig()) {
            Log.d(TAG, "No persisted config found, skipping")
            return
        }

        if (!configManager.getStartOnBoot()) {
            Log.d(TAG, "startOnBoot is false, skipping")
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
                Log.w(TAG, "ACCESS_BACKGROUND_LOCATION not granted — cannot restart tracking on boot")
                // Persist disabled state so the plugin doesn't retry on next boot
                val statePrefs = context.getSharedPreferences("com.tracelet.state", Context.MODE_PRIVATE)
                statePrefs.edit().putBoolean("enabled", false).apply()
                return
            }
            Log.d(TAG, "ACCESS_BACKGROUND_LOCATION granted — proceeding with boot restart")
        }

        val stateManager = StateManager(context)
        val trackingMode = stateManager.trackingMode

        Log.d(TAG, "startOnBoot=true, trackingMode=$trackingMode — restoring tracking")

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

        if (trackingMode == 2 && !configManager.getPeriodicUseForegroundService()) {
            // Periodic mode without foreground service —
            // re-schedule WorkManager/AlarmManager work directly.
            // No foreground service needed (no persistent notification).
            //
            // Auto-select exact alarms when interval < 15 min, matching
            // the same logic in TraceletAndroidPlugin.handleStartPeriodic().
            val interval = configManager.getPeriodicLocationInterval()
            val useExactAlarms = configManager.getPeriodicUseExactAlarms() ||
                interval < 900

            if (useExactAlarms) {
                PeriodicLocationWorker.scheduleOneTime(context)
                PeriodicLocationWorker.scheduleExactAlarm(context, interval)
                Log.d(TAG, "Periodic mode restored with exact alarms (interval=${interval}s)")
            } else {
                PeriodicLocationWorker.schedule(context, interval)
                Log.d(TAG, "Periodic mode restored with WorkManager (interval=${interval}s)")
            }
        } else {
            // Continuous (0), geofences (1), or periodic with foreground service —
            // start the foreground service with boot flag for native tracking
            LocationService.startFromBoot(context)
        }

        // Wakelock auto-releases after 60s timeout (A-M5). Do NOT release it
        // manually here — the foreground service start is asynchronous and the
        // device could sleep before the service's onCreate acquires its own lock.
    }
}
