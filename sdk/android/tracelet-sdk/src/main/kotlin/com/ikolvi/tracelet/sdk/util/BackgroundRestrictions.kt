package com.ikolvi.tracelet.sdk.util

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.os.Process

/**
 * Reads the OS-level background restrictions that silently disable tracking
 * (#406).
 *
 * The SDK already reports the Doze allowlist, and that check kept coming back
 * green on devices where background tracking was dead. It was the wrong
 * question: the Doze allowlist and Forced App Standby are independent, and an
 * app can be exempt from the first while the second refuses to let it run at
 * all. A field report from a LAVA LXX503 had `isIgnoringBatteryOptimizations =
 * true`, standby bucket `EXEMPTED`, and `RUN_ANY_IN_BACKGROUND = ignore` — the
 * Doctor printed "all systems healthy" over a service the OS would not promote.
 *
 * Everything here is readable without a permission: an app may always query its
 * own app-ops and its own standby bucket.
 */
object BackgroundRestrictions {

    /**
     * The app-op behind the "Restricted" battery setting.
     *
     * Not in [AppOpsManager]'s public constants, but the op *name* is stable
     * public API surface for [AppOpsManager.unsafeCheckOpNoThrow], which is the
     * only way to read it without reflection.
     */
    private const val OPSTR_RUN_ANY_IN_BACKGROUND = "android:run_any_in_background"

    /**
     * Whether the user (or an OEM battery manager) has put the app in the
     * "Restricted" battery state — Forced App Standby.
     *
     * In this state the OS blocks background service starts, defers jobs and
     * alarms, and refuses to promote a foreground service, so tracking stops
     * without a single error surfacing to the app. Returns `false` when the
     * state cannot be read, so an unreadable op is never reported as a fault.
     */
    fun isBackgroundRestricted(context: Context): Boolean {
        // ActivityManager exposes the same state directly from API 28, which is
        // both cheaper and less brittle than the op lookup.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            if (am != null) {
                return runCatching { am.isBackgroundRestricted }.getOrDefault(false)
            }
        }
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        return runCatching {
            val mode = appOps.unsafeCheckOpNoThrow(
                OPSTR_RUN_ANY_IN_BACKGROUND,
                Process.myUid(),
                context.packageName,
            )
            mode != AppOpsManager.MODE_ALLOWED
        }.getOrDefault(false)
    }

    /**
     * The app's standby bucket, or `null` below API 28 / when unreadable.
     *
     * Reported alongside [isBackgroundRestricted] because the two answer
     * different questions and look alike in a bug report: `RESTRICTED` (45) is a
     * bucket the OS assigns from usage, while Forced App Standby is a setting.
     * A `RARE` app is throttled; a restricted app is stopped.
     */
    fun standbyBucket(context: Context): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        val usage = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return null
        return runCatching { usage.appStandbyBucket }.getOrNull()
    }

    /**
     * [standbyBucket] as the name the platform documents, for a bug report.
     *
     * Numeric literals rather than [UsageStatsManager] constants: `EXEMPTED`
     * (5) and `NEVER` (50) are `@hide`, and `RESTRICTED` (45) only became
     * public in API 30, so half the ladder is unavailable to reference by name.
     * The values themselves are stable platform API — they appear in every
     * `dumpsys usagestats` and in `am get-standby-bucket` output.
     */
    fun standbyBucketName(bucket: Int?): String? = when (bucket) {
        null -> null
        5 -> "exempted"
        10 -> "active"
        20 -> "working_set"
        30 -> "frequent"
        40 -> "rare"
        45 -> "restricted"
        50 -> "never"
        else -> "unknown($bucket)"
    }
}
