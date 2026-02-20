package com.tracelet.tracelet_android.util

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Handles location, activity recognition, and background permissions.
 *
 * Sequential permission flow:
 * 1. ACCESS_FINE_LOCATION (or COARSE)
 * 2. ACCESS_BACKGROUND_LOCATION (separate prompt, API 30+)
 * 3. ACTIVITY_RECOGNITION (API 29+)
 *
 * Status codes: 0=DENIED, 1=DENIED_FOREVER, 2=WHEN_IN_USE, 3=ALWAYS, 4=RESTRICTED
 */
class PermissionManager(private val context: Context) {

    companion object {
        const val REQUEST_CODE_LOCATION = 1001
        const val REQUEST_CODE_BACKGROUND_LOCATION = 1002
        const val REQUEST_CODE_ACTIVITY_RECOGNITION = 1003
        const val REQUEST_CODE_NOTIFICATIONS = 1004

        // Status codes matching Dart AuthorizationStatus enum
        const val STATUS_DENIED = 0
        const val STATUS_DENIED_FOREVER = 1
        const val STATUS_WHEN_IN_USE = 2
        const val STATUS_ALWAYS = 3
    }

    /**
     * Returns the current authorization status.
     * 0=DENIED, 2=WHEN_IN_USE, 3=ALWAYS
     */
    fun getAuthorizationStatus(): Int {
        val hasFine = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val hasCoarse = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasFine && !hasCoarse) return STATUS_DENIED

        val hasBackground = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        return if (hasBackground) STATUS_ALWAYS else STATUS_WHEN_IN_USE
    }

    /**
     * Request location permissions. Follows the sequential flow.
     * Returns current status after request.
     */
    fun requestPermission(activity: Activity?): Int {
        if (activity == null) return getAuthorizationStatus()

        val status = getAuthorizationStatus()

        when (status) {
            STATUS_DENIED -> {
                // Request foreground location first
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                    ),
                    REQUEST_CODE_LOCATION
                )
            }
            STATUS_WHEN_IN_USE -> {
                // Request background location (must be separate dialog on API 30+)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                        REQUEST_CODE_BACKGROUND_LOCATION
                    )
                }
            }
        }

        return status
    }

    /** Request ACTIVITY_RECOGNITION permission (API 29+). */
    fun requestActivityRecognition(activity: Activity?): Boolean {
        if (activity == null) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true // Not needed pre-Q

        if (ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
        ) return true

        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
            REQUEST_CODE_ACTIVITY_RECOGNITION
        )
        return false
    }

    /** Check if app is ignoring battery optimizations. */
    fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false
    }

    /** Request to disable battery optimizations for this app. */
    fun requestIgnoreBatteryOptimizations(activity: Activity?): Boolean {
        if (activity == null) return false
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
            activity.startActivity(intent)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    /** Open device location settings. */
    fun showLocationSettings(activity: Activity?): Boolean {
        if (activity == null) return false
        try {
            activity.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            return true
        } catch (e: Exception) {
            return false
        }
    }

    /** Open app settings page. */
    fun showAppSettings(activity: Activity?): Boolean {
        if (activity == null) return false
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
            activity.startActivity(intent)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    /** Check if device is in power save mode. */
    fun isPowerSaveMode(): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return pm?.isPowerSaveMode ?: false
    }
}
