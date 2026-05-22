package com.ikolvi.tracelet.sdk.util

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
import com.ikolvi.tracelet.sdk.model.AuthorizationStatus

/**
 * Pure permission primitives — **no dialogs**.
 *
 * Status codes match the Dart `AuthorizationStatus` enum:
 *
 * | Code | Dart name        | Meaning |
 * |------|------------------|---------|
 * | 0    | notDetermined    | Never asked |
 * | 1    | denied           | Denied but can ask again |
 * | 2    | whenInUse        | Foreground granted |
 * | 3    | always           | Background granted |
 * | 4    | deniedForever    | Permanently denied — must open Settings |
 */
class TraceletPermissionManager(private val context: Context) {

    companion object {
        const val REQUEST_CODE_LOCATION = 1001
        const val REQUEST_CODE_BACKGROUND_LOCATION = 1002
        const val REQUEST_CODE_ACTIVITY_RECOGNITION = 1003
        const val REQUEST_CODE_NOTIFICATION = 1004

        private const val PREFS_NAME = "tracelet_permissions"
        private const val KEY_EVER_REQUESTED = "permission_ever_requested"
        // Tracks whether the most recent OS dialog resulted in a grant.
        // Needed to distinguish "one-time grant expired" (denied, can ask
        // again) from "truly permanently denied" on Android 11+, because
        // both states show shouldShowRequestPermissionRationale == false.
        private const val KEY_LAST_RESULT_WAS_GRANT = "permission_last_result_was_grant"
        private const val KEY_NOTIFICATION_EVER_REQUESTED = "notification_ever_requested"
        private const val KEY_MOTION_EVER_REQUESTED = "motion_ever_requested"
    }

    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // ── Status ────────────────────────────────────────────────────────────

    /**
     * Returns the current authorization status **without** triggering any
     * dialog or permission request.
     *
     * Uses `shouldShowRequestPermissionRationale` + SharedPrefs to
     * distinguish notDetermined, denied, and deniedForever.
     */
    fun getAuthorizationStatus(activity: Activity? = null): AuthorizationStatus {
        val hasFine = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val hasCoarse = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasFine && !hasCoarse) {
            if (activity != null) {
                val canShowRationale = ActivityCompat.shouldShowRequestPermissionRationale(
                    activity, Manifest.permission.ACCESS_FINE_LOCATION
                )
                return when {
                    canShowRationale -> AuthorizationStatus.DENIED          // denied, can ask again
                    !hasEverRequested() -> AuthorizationStatus.NOT_DETERMINED // never asked
                    // Both "Only this time" expiry and true permanent deny look
                    // the same: !canShowRationale && hasEverRequested.  Use the
                    // last OS dialog result to disambiguate: if the user's most
                    // recent choice was a grant (temporary or otherwise), the OS
                    // will still show the dialog on the next request → STATUS_DENIED.
                    wasLastResultGrant() -> AuthorizationStatus.DENIED       // one-time grant expired
                    else -> AuthorizationStatus.DENIED_FOREVER               // permanently denied
                }
            }
            // No activity — best effort
            return if (hasEverRequested()) AuthorizationStatus.DENIED else AuthorizationStatus.NOT_DETERMINED
        }

        val hasBackground = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Pre-Q: foreground grant = always
        }

        return if (hasBackground) AuthorizationStatus.ALWAYS else AuthorizationStatus.WHEN_IN_USE
    }

    // ── Request primitives (fire-only, result comes via onRequestPermissionsResult) ──

    /**
     * Request foreground location permission.
     * The actual result arrives in `onRequestPermissionsResult`.
     */
    fun requestForegroundPermission(activity: Activity) {
        markPermissionRequested()
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            REQUEST_CODE_LOCATION
        )
    }

    /**
     * Request background (always) location permission (API 29+).
     * Only valid after foreground permission is already granted.
     */
    fun requestBackgroundPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            markPermissionRequested()
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                REQUEST_CODE_BACKGROUND_LOCATION
            )
        }
    }

    /** Request ACTIVITY_RECOGNITION permission (API 29+). */
    fun requestActivityRecognition(activity: Activity?): Boolean {
        if (activity == null) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true

        if (ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
        ) return true

        markMotionRequested()
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
            REQUEST_CODE_ACTIVITY_RECOGNITION
        )
        return false
    }

    // ── Motion / Activity Recognition permission (Android 10+ / API 29+) ──

    /**
     * Returns the motion (ACTIVITY_RECOGNITION) permission status.
     *
     * Returns:
     * - `NOT_DETERMINED` — never asked
     * - `DENIED` — denied but can ask again
     * - `ALWAYS` — permission granted
     * - `DENIED_FOREVER` — permanently denied
     *
     * On API < 29, activity recognition is always allowed → returns ALWAYS.
     */
    fun getMotionPermissionStatus(activity: Activity? = null): AuthorizationStatus {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return AuthorizationStatus.ALWAYS // Pre-10: no runtime permission needed
        }

        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACTIVITY_RECOGNITION
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) return AuthorizationStatus.ALWAYS

        if (activity != null) {
            val canShowRationale = ActivityCompat.shouldShowRequestPermissionRationale(
                activity, Manifest.permission.ACTIVITY_RECOGNITION
            )
            return when {
                canShowRationale -> AuthorizationStatus.DENIED       // denied, can ask again
                hasEverRequestedMotion() -> AuthorizationStatus.DENIED_FOREVER
                else -> AuthorizationStatus.NOT_DETERMINED            // never asked
            }
        }
        return if (hasEverRequestedMotion()) AuthorizationStatus.DENIED else AuthorizationStatus.NOT_DETERMINED
    }

    // ── Post-request status (called from onRequestPermissionsResult) ─────

    /**
     * Determine the status after a permission dialog has closed.
     *
     * Must be called from `onRequestPermissionsResult` where
     * `shouldShowRequestPermissionRationale` reflects the user's last choice.
     *
     * Saves whether the result was a grant so that future calls to
     * `getAuthorizationStatus` can distinguish "one-time grant expired"
     * from "truly permanently denied".
     */
    fun getStatusAfterRequest(activity: Activity): AuthorizationStatus {
        val status = getAuthorizationStatus(activity)

        // Record whether the user granted anything (even temporarily).
        // This flag is read on the *next* app launch when the one-time
        // grant may have expired and the API signals look identical to
        // a permanent deny.
        val granted = status == AuthorizationStatus.WHEN_IN_USE || status == AuthorizationStatus.ALWAYS
        markLastResultGrant(granted)

        // If the general check returns NOT_DETERMINED but we just requested,
        // it means the user denied AND shouldShowRequestPermissionRationale is
        // false (permanent deny). Override to DENIED_FOREVER.
        if (status == AuthorizationStatus.NOT_DETERMINED && hasEverRequested()) {
            return AuthorizationStatus.DENIED_FOREVER
        }
        return status
    }
    // ── Notification permission (Android 13+ / API 33+) ─────────────

    /**
     * Returns the notification permission status.
     *
     * Returns:
     * - `NOT_DETERMINED` — never asked (API 33+) or not applicable (< 33)
     * - `DENIED` — denied but can ask again
     * - `ALWAYS` — permission granted
     * - `DENIED_FOREVER` — permanently denied
     *
     * On API < 33, notifications are always allowed → returns ALWAYS.
     */
    fun getNotificationPermissionStatus(activity: Activity? = null): AuthorizationStatus {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return AuthorizationStatus.ALWAYS // Pre-13: no runtime permission needed
        }

        val granted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) return AuthorizationStatus.ALWAYS

        if (activity != null) {
            val canShowRationale = ActivityCompat.shouldShowRequestPermissionRationale(
                activity, Manifest.permission.POST_NOTIFICATIONS
            )
            return when {
                canShowRationale -> AuthorizationStatus.DENIED       // denied, can ask again
                hasEverRequestedNotification() -> AuthorizationStatus.DENIED_FOREVER
                else -> AuthorizationStatus.NOT_DETERMINED            // never asked
            }
        }
        return if (hasEverRequestedNotification()) AuthorizationStatus.DENIED else AuthorizationStatus.NOT_DETERMINED
    }

    /**
     * Request POST_NOTIFICATIONS permission (API 33+).
     * Result arrives in `onRequestPermissionsResult`.
     *
     * On API < 33, this is a no-op (notifications always allowed).
     */
    fun requestNotificationPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            markNotificationRequested()
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_CODE_NOTIFICATION
            )
        }
    }
    // ── Battery / Settings ───────────────────────────────────────────────

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

    // ── Private ──────────────────────────────────────────────────────────

    private fun markPermissionRequested() {
        prefs.edit().putBoolean(KEY_EVER_REQUESTED, true).apply()
    }

    private fun hasEverRequested(): Boolean {
        return prefs.getBoolean(KEY_EVER_REQUESTED, false)
    }

    private fun markLastResultGrant(granted: Boolean) {
        prefs.edit().putBoolean(KEY_LAST_RESULT_WAS_GRANT, granted).apply()
    }

    private fun wasLastResultGrant(): Boolean {
        return prefs.getBoolean(KEY_LAST_RESULT_WAS_GRANT, false)
    }

    private fun markNotificationRequested() {
        prefs.edit().putBoolean(KEY_NOTIFICATION_EVER_REQUESTED, true).apply()
    }

    private fun hasEverRequestedNotification(): Boolean {
        return prefs.getBoolean(KEY_NOTIFICATION_EVER_REQUESTED, false)
    }

    private fun markMotionRequested() {
        prefs.edit().putBoolean(KEY_MOTION_EVER_REQUESTED, true).apply()
    }

    private fun hasEverRequestedMotion(): Boolean {
        return prefs.getBoolean(KEY_MOTION_EVER_REQUESTED, false)
    }
}
