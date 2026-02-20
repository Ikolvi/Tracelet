package com.tracelet.tracelet_android.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.tracelet.tracelet_android.ConfigManager
import com.tracelet.tracelet_android.service.LocationService

/**
 * Receives BOOT_COMPLETED broadcast to restart tracking after device reboot.
 *
 * Enabled/disabled via PackageManager based on the startOnBoot config setting.
 * When enabled, reads persisted config and starts the foreground location service.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        Log.d(TAG, "Boot completed — checking startOnBoot config")

        val configManager = ConfigManager(context)
        if (!configManager.hasConfig()) {
            Log.d(TAG, "No persisted config found, skipping")
            return
        }

        if (!configManager.getStartOnBoot()) {
            Log.d(TAG, "startOnBoot is false, skipping")
            return
        }

        Log.d(TAG, "startOnBoot=true, starting LocationService")

        // Update state to indicate background launch
        val statePrefs = context.getSharedPreferences("com.tracelet.state", Context.MODE_PRIVATE)
        statePrefs.edit()
            .putBoolean("didDeviceReboot", true)
            .putBoolean("didLaunchInBackground", true)
            .putBoolean("enabled", true)
            .apply()

        // Start the foreground service
        LocationService.start(context)
    }
}
