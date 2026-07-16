package com.ikolvi.tracelet.sdk.location
import com.ikolvi.tracelet.sdk.util.TraceletLog

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
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.receiver.PeriodicAlarmReceiver
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.util.BatteryUtils
import com.ikolvi.tracelet.sdk.wrapper.TraceletLocationPriority
import com.ikolvi.tracelet.sdk.wrapper.TraceletServices
import com.ikolvi.tracelet.sdk.wrapper.TraceletCancellationTokenSource
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

        @Volatile
        var eventSender: TraceletEventSender? = null

        fun schedule(context: Context, intervalSeconds: Int) {
            val interval = intervalSeconds.toLong().coerceAtLeast(900L)
            val request = PeriodicWorkRequestBuilder<PeriodicLocationWorker>(
                interval, TimeUnit.SECONDS,
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
            TraceletLog.debug("Scheduled periodic location work: interval=${interval}s")
        }

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

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            WorkManager.getInstance(context).cancelUniqueWork("${WORK_NAME}_onetime")
            cancelExactAlarm(context)
            TraceletLog.debug("Cancelled periodic location work")
        }

        fun scheduleExactAlarm(context: Context, intervalSeconds: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
                as? AlarmManager ?: return

            val triggerAtMs = System.currentTimeMillis() + (intervalSeconds * 1000L)
            val pi = createAlarmPendingIntent(context)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!alarmManager.canScheduleExactAlarms()) {
                    TraceletLog.warning("SCHEDULE_EXACT_ALARM not granted \u2014 using setAndAllowWhileIdle")
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
                TraceletLog.debug("Scheduled exact alarm in ${intervalSeconds}s")
            } catch (e: SecurityException) {
                TraceletLog.warning("Exact alarm SecurityException \u2014 using setAndAllowWhileIdle", e)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
                }
            }
        }

        fun cancelExactAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE)
                as? AlarmManager ?: return
            alarmManager.cancel(createAlarmPendingIntent(context))
            TraceletLog.debug("Cancelled exact periodic alarm")
        }

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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val hasBackground = ContextCompat.checkSelfPermission(
                applicationContext, android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            if (!hasBackground) {
                TraceletLog.warning("ACCESS_BACKGROUND_LOCATION revoked \u2014 stopping periodic work")
                StateManager(applicationContext).apply {
                    enabled = false
                }
                return Result.failure()
            }
        }

        return try {
            val config = ConfigManager.getInstance(applicationContext)
            val state = StateManager(applicationContext)

            // Tracking was stopped after this work was enqueued — don't
            // capture, persist, or sync anything.
            if (!state.enabled) {
                com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(applicationContext).logger
                    .info("Tracking disabled — skipping periodic location work")
                return Result.success()
            }

            var location = fetchLocation(config)

            // Mock rejection applies to periodic fixes too — they bypass the
            // engine's onLocationReceived() defense-in-depth check.
            if (location != null &&
                config.getRejectMockLocations() &&
                isLocationMock(location, config.getMockDetectionLevel(), config.getDeferTime(), applicationContext)
            ) {
                TraceletLog.warning("Periodic fix rejected: mock location")
                location = null
            }

            if (location != null) {
                var effectiveSpeed = location.speed.toDouble()
                val locationMap = buildLocationMap(location, config, state)

                // Bootstrap native tracking and persist location so it can be synced even if UI is dead.
                val sdk = com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(applicationContext)
                val fallbackSender = TraceletBootstrap.eventSenderFactory?.invoke(applicationContext) ?: com.ikolvi.tracelet.sdk.ListenerEventSender()
                sdk.bootstrapForBackground(fallbackSender)
                sdk.insertLocation(locationMap)

                // Dispatch to the event sender which will route to UI/Headless
                dispatchLocation(locationMap)
                TraceletLog.debug("Periodic fix: lat=${location.latitude}, lng=${location.longitude}, speed=$effectiveSpeed")

                // Feed speed to motion coordinators to allow wake up from stationary
                if (sdk.isReady) {
                    sdk.locationEngine.speedMotionSpeedSink?.invoke(effectiveSpeed)
                }
            }

            val interval = config.getPeriodicLocationInterval()
            val useExact = config.getPeriodicUseExactAlarms() || interval < 900

            if (state.enabled && state.trackingMode == TrackingMode.PERIODIC && useExact) {
                scheduleExactAlarm(applicationContext, interval)
            }

            // CRITICAL FIX: The tracelet_sync plugin delays HTTP syncs by autoSyncDelay.
            // If we exit immediately, the OS will release the WakeLock and suspend the app,
            // failing the upload. So we hold the worker alive for (autoSyncDelay + 1) seconds.
            val traceletSdk = com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(applicationContext)
            val httpConfig = traceletSdk.rustEngineState?.getConfig()?.http
            if (httpConfig != null && httpConfig.autoSync) {
                val delayMs = httpConfig.autoSyncDelay.toLong()
                TraceletLog.debug("Delaying worker exit for ${delayMs + 1000L} ms to allow tracelet_sync background upload...")
                kotlinx.coroutines.delay(delayMs + 1000L)
            }

            Result.success()
        } catch (e: kotlinx.coroutines.CancellationException) {
            // Cooperative cancellation — not a failure. Typically the SDK
            // switched from PERIODIC to CONTINUOUS mode (ready()/start()) and
            // cancelled this periodic job while we were holding it open for the
            // sync delay above. Never swallow CancellationException; let it
            // propagate so WorkManager records the work as cancelled cleanly.
            TraceletLog.debug("Periodic location work cancelled")
            throw e
        } catch (e: Exception) {
            TraceletLog.error("Periodic location work failed: ${e.message}", e)
            Result.retry()
        }
    }

    private suspend fun fetchLocation(config: ConfigManager): android.location.Location? {
        val client = TraceletServices.getInstance(applicationContext).getLocationClient(applicationContext)
        val priority = mapAccuracyToPriority(config.getPeriodicDesiredAccuracy())
        val cts = TraceletCancellationTokenSource()

        return suspendCancellableCoroutine { continuation ->
            client.getCurrentLocation(priority, cts.token) { location ->
                continuation.resume(location)
            }
            continuation.invokeOnCancellation {
                cts.cancel()
            }
        }
    }

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
            "is_moving" to (location.speed > 0),
            "odometer" to state.odometer,
            "event" to "periodic",
            "mock" to location.isFromMockProvider,
            "activity" to mapOf(
                "type" to "unknown",
                "confidence" to -1,
            ),
        )

        val batteryInfo = BatteryUtils.getBatteryInfo(applicationContext)
        map["battery"] = batteryInfo

        val extras = config.getHttpExtras()
        if (extras.isNotEmpty()) {
            map["extras"] = extras
        }

        val ageMs = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
        map["age"] = ageMs

        return map
    }

    private fun dispatchLocation(locationMap: Map<String, Any?>) {
        val sender = eventSender
        if (sender != null) {
            Handler(Looper.getMainLooper()).post {
                sender.sendLocation(locationMap)
            }
        } else {
            try {
                val headless = TraceletBootstrap.headlessDispatcherFactory?.invoke(applicationContext)
                if (headless != null && headless.isRegistered()) {
                    headless.dispatchEvent("location", locationMap)
                }
            } catch (_: Exception) {}
        }
    }

    private fun mapAccuracyToPriority(accuracyIndex: Int): Int {
        return when (accuracyIndex) {
            0 -> TraceletLocationPriority.PRIORITY_HIGH_ACCURACY
            1 -> TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY
            2 -> TraceletLocationPriority.PRIORITY_LOW_POWER
            3 -> TraceletLocationPriority.PRIORITY_PASSIVE
            4 -> TraceletLocationPriority.PRIORITY_PASSIVE
            else -> TraceletLocationPriority.PRIORITY_BALANCED_POWER_ACCURACY
        }
    }
}
