package com.ikolvi.tracelet.sdk.location

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.work.*
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.db.TraceletDatabase
import com.ikolvi.tracelet.sdk.http.HttpSyncManager
import com.ikolvi.tracelet.sdk.receiver.PeriodicAlarmReceiver
import com.ikolvi.tracelet.sdk.util.BatteryUtils
import kotlinx.coroutines.suspendCancellableCoroutine
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/**
 * WorkManager Worker that performs a single one-shot location fix.
 *
 * Used by [TrackingMode.periodic] when [periodicUseForegroundService] is `false`.
 * The Worker wakes, fetches a single location via [FusedLocationProviderClient],
 * persists it to SQLite, dispatches it via EventChannel (if alive) or headless
 * Dart callback, and completes — keeping the GPS icon visible for only ~5–10 seconds.
 *
 * Scheduling:
 * - Default: [PeriodicWorkRequest] with `periodicLocationInterval` flex.
 * - Exact alarms: [OneTimeWorkRequest] chained via [AlarmManager], scheduled
 *   by the plugin when `periodicUseExactAlarms` is `true`.
 */
class PeriodicLocationWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "PeriodicLocationWorker"
        const val WORK_NAME = "com.tracelet.periodic_location"
        const val ACTION_PERIODIC_ALARM = "com.tracelet.PERIODIC_ALARM"
        private const val ALARM_REQUEST_CODE = 8001

        /**
         * Shared reference to the plugin's event sender.
         * Set by the host framework adapter when the UI engine is alive.
         * Null when the app process is running without a UI (headless).
         */
        @Volatile
        var eventSender: TraceletEventSender? = null

        /**
         * Shared reference to the plugin's HttpSyncManager.
         * Set by TraceletAndroidPlugin so periodic fixes trigger auto-sync.
         * Null when the app process is running without a Flutter UI (headless).
         */
        @Volatile
        var httpSyncManager: HttpSyncManager? = null

        /**
         * Schedules periodic location work using WorkManager.
         *
         * Uses a [PeriodicWorkRequest] with the configured interval.
         * WorkManager's minimum interval is 15 minutes.
         */
        fun schedule(context: Context, intervalSeconds: Int) {
            val interval = intervalSeconds.toLong().coerceAtLeast(900L)
            val request = PeriodicWorkRequestBuilder<PeriodicLocationWorker>(
                interval, TimeUnit.SECONDS,
                // Flex window: allow execution in the last 5 minutes of each interval
                5L.coerceAtMost(interval), TimeUnit.MINUTES,
            )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiresBatteryNotLow(false)
                        .build()
                )
                .addTag(WORK_NAME)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
            Log.d(TAG, "Scheduled periodic location work: interval=${interval}s")
        }

        /**
         * Schedules a one-time location work for exact-alarm chaining.
         * Called by the plugin when `periodicUseExactAlarms` is `true`.
         */
        fun scheduleOneTime(context: Context) {
            val request = OneTimeWorkRequestBuilder<PeriodicLocationWorker>()
                .addTag(WORK_NAME)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "${WORK_NAME}_onetime",
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }

        /** Cancels all periodic location work. */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            WorkManager.getInstance(context).cancelUniqueWork("${WORK_NAME}_onetime")
            cancelExactAlarm(context)
            Log.d(TAG, "Cancelled periodic location work")
        }

        // =================================================================
        // Exact Alarm scheduling
        // =================================================================

        /**
         * Schedules an alarm to fire after [intervalSeconds].
         *
         * On Android 12+ (API 31), checks [AlarmManager.canScheduleExactAlarms]
         * and falls back to a Doze-safe inexact alarm if the permission is
         * not granted. The inexact fallback uses [setAndAllowWhileIdle] which
         * can fire even in Doze mode, though timing is approximate.
         *
         * The alarm triggers [PeriodicAlarmReceiver], which enqueues a
         * [OneTimeWorkRequest] to perform the location fix.
         */
        fun scheduleExactAlarm(context: Context, intervalSeconds: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
                as? AlarmManager ?: return

            val triggerAtMs = System.currentTimeMillis() + (intervalSeconds * 1000L)
            val pi = createAlarmPendingIntent(context)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    // Permission not granted — fall back to Doze-safe inexact alarm
                    Log.w(TAG, "SCHEDULE_EXACT_ALARM not granted — using setAndAllowWhileIdle (inexact but Doze-safe)")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                    } else {
                        alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                    }
                    return
                }
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, triggerAtMs, pi
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                }
                Log.d(TAG, "Scheduled exact alarm in ${intervalSeconds}s")
            } catch (e: SecurityException) {
                // Fallback on SecurityException
                Log.w(TAG, "Exact alarm SecurityException — using setAndAllowWhileIdle", e)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                }
            }
        }

        /** Cancels any pending exact alarm. */
        fun cancelExactAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
                as? AlarmManager ?: return
            alarmManager.cancel(createAlarmPendingIntent(context))
            Log.d(TAG, "Cancelled exact periodic alarm")
        }

        /**
         * Checks whether exact alarms can be scheduled.
         * Returns `true` on API < 31 (no restriction) or if the permission is granted.
         */
        fun canScheduleExactAlarms(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
                as? AlarmManager ?: return false
            return alarmManager.canScheduleExactAlarms()
        }

        private fun createAlarmPendingIntent(context: Context): PendingIntent {
            val intent = Intent(ACTION_PERIODIC_ALARM)
                .setClass(context, PeriodicAlarmReceiver::class.java)
            return PendingIntent.getBroadcast(
                context,
                ALARM_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    override suspend fun doWork(): Result {
        // Proactive background permission check — if the user revoked
        // "Allow all the time" permission, stop periodic scheduling early
        // instead of relying on the SecurityException from FusedLocation.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val hasBackground = ContextCompat.checkSelfPermission(
                applicationContext, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            if (!hasBackground) {
                Log.w(TAG, "ACCESS_BACKGROUND_LOCATION revoked \u2014 stopping periodic work")
                // Mark tracking disabled so alarms / re-schedules also stop.
                StateManager(applicationContext).apply {
                    enabled = false
                }
                return Result.failure()
            }
            Log.d(TAG, "ACCESS_BACKGROUND_LOCATION granted \u2014 proceeding with periodic fix")
        }

        return try {
            val config = ConfigManager.getInstance(applicationContext)
            val state = StateManager(applicationContext)
            val location = fetchLocation(config)

            if (location != null) {
                val db = TraceletDatabase.getInstance(applicationContext)

                // Compute distance from last periodic fix for odometer
                val lastLat = state.lastPeriodicLatitude
                val lastLng = state.lastPeriodicLongitude
                if (!lastLat.isNaN() && !lastLng.isNaN()) {
                    val results = FloatArray(1)
                    android.location.Location.distanceBetween(
                        lastLat, lastLng,
                        location.latitude, location.longitude,
                        results,
                    )
                    val distance = results[0].toDouble()
                    val threshold = config.getOdometerAccuracyThreshold()
                    if (threshold <= 0 || location.accuracy <= threshold) {
                        state.addOdometer(distance)
                    }
                }
                state.lastPeriodicLatitude = location.latitude
                state.lastPeriodicLongitude = location.longitude
                state.lastLocationTime = location.time

                // Build enriched location map (reads updated odometer)
                val locationMap = buildLocationMap(location, config, state)

                // Persist to database
                db.insertLocation(locationMap)

                // Trigger HTTP auto-sync if manager is available
                httpSyncManager?.onLocationInserted()

                // Dispatch to Dart
                dispatchLocation(locationMap)

                Log.d(TAG, "Periodic fix: lat=${location.latitude}, lng=${location.longitude}, odo=${state.odometer}")
            } else {
                Log.w(TAG, "Periodic fix failed: no location obtained")
            }

            // Re-schedule next alarm if periodic tracking is still active.
            // Use exact alarms when explicitly configured OR when the interval
            // is under 15 min (matching the auto-select logic in
            // TraceletAndroidPlugin.handleStartPeriodic).
            val interval = config.getPeriodicLocationInterval()
            val useExact = config.getPeriodicUseExactAlarms() || interval < 900

            if (state.enabled && state.trackingMode == 2 && useExact) {
                scheduleExactAlarm(applicationContext, interval)
                Log.d(TAG, "Re-scheduled next alarm in ${interval}s")
            }

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Periodic location work failed: ${e.message}", e)
            Result.retry()
        }
    }

    /**
     * Fetches a single location using FusedLocationProviderClient.getCurrentLocation().
     * Returns an Android Location or null on timeout/failure.
     */
    private suspend fun fetchLocation(config: ConfigManager): android.location.Location? {
        val fusedClient = LocationServices.getFusedLocationProviderClient(applicationContext)
        val priority = mapAccuracyToPriority(config.getPeriodicDesiredAccuracy())
        val cancellationSource = CancellationTokenSource()

        return try {
            suspendCancellableCoroutine { continuation ->
                fusedClient.getCurrentLocation(priority, cancellationSource.token)
                    .addOnSuccessListener { location ->
                        continuation.resume(location)
                    }
                    .addOnFailureListener {
                        continuation.resume(null)
                    }

                continuation.invokeOnCancellation {
                    cancellationSource.cancel()
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission denied", e)
            null
        }
    }

    /**
     * Builds an enriched location map matching the format used by LocationEngine.
     */
    private fun buildLocationMap(
        location: android.location.Location,
        config: ConfigManager,
        state: StateManager,
    ): Map<String, Any?> {
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        val map = mutableMapOf<String, Any?>(
            "uuid" to UUID.randomUUID().toString(),
            "timestamp" to isoFormat.format(Date(location.time)),
            "coords" to mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "altitude" to location.altitude,
                "speed" to location.speed.toDouble(),
                "heading" to location.bearing.toDouble(),
                "accuracy" to location.accuracy.toDouble(),
                "altitudeAccuracy" to if (android.os.Build.VERSION.SDK_INT >= 26)
                    location.verticalAccuracyMeters.toDouble() else -1.0,
                "speedAccuracy" to if (android.os.Build.VERSION.SDK_INT >= 26)
                    location.speedAccuracyMetersPerSecond.toDouble() else -1.0,
                "headingAccuracy" to if (android.os.Build.VERSION.SDK_INT >= 26)
                    location.bearingAccuracyDegrees.toDouble() else -1.0,
            ),
            "isMoving" to (location.speed > 0),
            "odometer" to state.odometer,
            "event" to "periodic",
            "mock" to location.isFromMockProvider,
            "activity" to mapOf(
                "type" to "unknown",
                "confidence" to -1,
            ),
        )

        // Battery info
        val batteryInfo = BatteryUtils.getBatteryInfo(applicationContext)
        map["battery"] = batteryInfo

        // Age of fix (ms since boot vs location elapsed time)
        val ageMs = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
        map["age"] = ageMs

        return map
    }

    /**
     * Dispatches the location to the host framework via event sender or headless dispatcher.
     */
    private fun dispatchLocation(locationMap: Map<String, Any?>) {
        val sender = eventSender
        if (sender != null) {
            val hasListener = sender.hasListener("location")
            Log.d(TAG, "Dispatching to event sender (hasListener=$hasListener)")
            Handler(Looper.getMainLooper()).post {
                sender.sendLocation(locationMap)
            }
        } else {
            Log.d(TAG, "Event sender is null — trying headless dispatch")
            try {
                val headless = TraceletBootstrap.headlessDispatcherFactory?.invoke(applicationContext)
                if (headless != null && headless.isRegistered()) {
                    headless.dispatchEvent("location", locationMap)
                } else {
                    Log.w(TAG, "Headless not registered — location event dropped!")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Headless dispatch failed: ${e.message}")
            }
        }
    }

    /**
     * Maps DesiredAccuracy enum index to FusedLocationProvider Priority.
     */
    private fun mapAccuracyToPriority(accuracyIndex: Int): Int {
        return when (accuracyIndex) {
            0 -> Priority.PRIORITY_HIGH_ACCURACY
            1 -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
            2 -> Priority.PRIORITY_LOW_POWER
            3 -> Priority.PRIORITY_PASSIVE
            4 -> Priority.PRIORITY_PASSIVE
            else -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
        }
    }
}
