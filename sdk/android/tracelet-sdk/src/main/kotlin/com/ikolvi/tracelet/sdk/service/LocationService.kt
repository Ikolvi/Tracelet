package com.ikolvi.tracelet.sdk.service
import com.ikolvi.tracelet.sdk.util.TraceletLog

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.annotation.VisibleForTesting
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.ikolvi.tracelet.sdk.ConfigManager
import com.ikolvi.tracelet.sdk.HeadersRefreshable
import com.ikolvi.tracelet.sdk.ListenerEventSender
import com.ikolvi.tracelet.sdk.TraceletBootstrap
import com.ikolvi.tracelet.sdk.TraceletEventSender
import com.ikolvi.tracelet.sdk.StateManager
import com.ikolvi.tracelet.sdk.geofence.GeofenceManager
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker
import com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.util.OemCompat

/**
 * Applies the self-ticking elapsed timer: count-up only, future [startedAt]
 * clamped to [now], and no timer without a start instant.
 */
@VisibleForTesting
internal fun applyChronometer(
    builder: NotificationCompat.Builder,
    showTimer: Boolean,
    startedAt: Long?,
    now: Long,
) {
    if (!showTimer) return
    if (startedAt == null) {
        TraceletLog.debug("notificationShowTimer is set but notificationStartedAt is not — no timer shown")
        return
    }
    builder.setWhen(minOf(startedAt, now))
    builder.setShowWhen(true)
    builder.setUsesChronometer(true)
}

/** Applies whether only the first post of this notification should alert. */
@VisibleForTesting
internal fun applyOnlyAlertOnce(
    builder: NotificationCompat.Builder,
    onlyAlertOnce: Boolean,
) {
    builder.setOnlyAlertOnce(onlyAlertOnce)
}

/**
 * Foreground service for persistent background location tracking.
 *
 * Android requires a foreground service with FOREGROUND_SERVICE_TYPE_LOCATION
 * for reliable background location access (especially Android 14+).
 *
 * This service displays a persistent notification and keeps the location
 * engine alive when the app UI is removed from recents.
 *
 * After a device reboot (started via [BootReceiver]), the service bootstraps
 * a native [LocationEngine] to immediately resume tracking without waiting
 * for a Dart FlutterEngine. Locations are persisted to SQLite and also
 * forwarded to the headless dispatcher if a headless callback is registered.
 */
class LocationService : Service(), DefaultLifecycleObserver {

    companion object {
        private const val TAG = "LocationService"
        private const val NOTIFICATION_ID = 7701

        /**
         * Auto-expiry safety timeout for the OEM-safe wakelock. Comfortably
         * exceeds [WAKELOCK_RENEWAL_INTERVAL_MS] so the lock never lapses
         * between renewals, while still bounding a leaked lock so it eventually
         * self-releases.
         */
        private const val WAKELOCK_TIMEOUT_MS = 15 * 60 * 1000L

        /**
         * How often the held wakelock is renewed so it never reaches its
         * auto-expiry timeout while tracking is active. Must be shorter than
         * [WAKELOCK_TIMEOUT_MS]. Without renewal the lock expired after the
         * default 10 minutes and aggressive OEMs (Samsung One UI, etc.) let the
         * CPU enter deep sleep, silently freezing FusedLocationProvider updates
         * even though the foreground service was still alive (#222).
         */
        private const val WAKELOCK_RENEWAL_INTERVAL_MS = 10 * 60 * 1000L

        /**
         * Backoff for re-attempting a boot/task-removal bootstrap that could not
         * complete (#317). Doubles per attempt from this base: 5s, 10s, 20s, 40s,
         * 80s, 160s — roughly five minutes of retrying, which comfortably covers a
         * slow cold boot without spinning indefinitely on a genuine init failure.
         */
        private const val BOOT_RETRY_BASE_DELAY_MS = 5_000L
        private const val BOOT_RETRY_MAX_ATTEMPTS = 6

        const val ACTION_START = "com.tracelet.ACTION_START"
        const val ACTION_STOP = "com.tracelet.ACTION_STOP"
        const val ACTION_UPDATE_NOTIFICATION = "com.tracelet.ACTION_UPDATE_NOTIFICATION"
        const val ACTION_BUTTON = "com.tracelet.ACTION_BUTTON"
        const val ACTION_ACQUIRE_WAKELOCK = "com.tracelet.ACTION_ACQUIRE_WAKELOCK"
        const val ACTION_RELEASE_WAKELOCK = "com.tracelet.ACTION_RELEASE_WAKELOCK"
        const val EXTRA_BUTTON_ACTION = "button_action"
        const val EXTRA_BOOT_START = "boot_start"

        @Volatile
        private var isRunning = false

        // ── Foreground-service health (#255) ──
        // Authoritative native foreground-service state, so Dart can distinguish
        // the *desired* tracking state (StateManager.enabled) from what the OS
        // actually granted. On Android 12+ a foreground-service start can be
        // deferred or rejected even while enabled=true, so enabled alone is not
        // proof that background tracking is operational.

        /** Whether the service is currently promoted to the foreground (last
         *  startForeground() succeeded and it has not been demoted/stopped). */
        @Volatile
        private var foregroundPromoted = false

        /** Result of the most recent foreground promotion attempt:
         *  `success`, `deferred`, or `failed`; null before any attempt. */
        @Volatile
        private var lastPromotionResult: String? = null

        /** Exception class of the most recent failed/deferred promotion. */
        @Volatile
        private var lastPromotionFailureClass: String? = null

        /** Message of the most recent failed/deferred promotion. */
        @Volatile
        private var lastPromotionFailureMessage: String? = null

        /** Epoch-ms of the most recent promotion transition (0 = never). */
        @Volatile
        private var lastPromotionTimestampMs: Long = 0L

        /** Records the outcome of a foreground-promotion attempt (#255). */
        private fun recordPromotion(
            result: String,
            promoted: Boolean,
            failureClass: String? = null,
            failureMessage: String? = null,
        ) {
            lastPromotionResult = result
            foregroundPromoted = promoted
            lastPromotionFailureClass = failureClass
            lastPromotionFailureMessage = failureMessage
            lastPromotionTimestampMs = System.currentTimeMillis()
        }

        /**
         * Authoritative snapshot of the foreground-service state (#255).
         *
         * Reports what the OS actually granted — independent of the desired
         * `enabled` flag — so apps can build tracking-health indicators,
         * diagnostics, and recovery. Callers typically merge in `desiredEnabled`
         * and `foregroundServiceEnabled` at the SDK layer.
         */
        fun foregroundServiceHealth(): Map<String, Any?> = mapOf(
            "serviceRunning" to isRunning,
            "serviceForeground" to foregroundPromoted,
            "foregroundNotificationId" to if (foregroundPromoted) NOTIFICATION_ID.toLong() else null,
            "lastForegroundPromotionResult" to lastPromotionResult,
            "lastForegroundPromotionFailureClass" to lastPromotionFailureClass,
            "lastForegroundPromotionFailureMessage" to lastPromotionFailureMessage,
            "lastForegroundTransitionAt" to lastPromotionTimestampMs.takeIf { it > 0L },
        )

        // Boot-mode native tracking state — accessible by the plugin.
        @JvmStatic
        @androidx.annotation.VisibleForTesting
        var bootLocationEngine: LocationEngine? = null

        @Volatile
        var bootSpeedMotionManager: com.ikolvi.tracelet.sdk.motion.SpeedMotionManager? = null
            private set

        @JvmStatic
        @androidx.annotation.VisibleForTesting
        var bootMotionDetector: com.ikolvi.tracelet.sdk.motion.MotionDetector? = null

        @Volatile
        var bootSmartMotionCoordinator: com.ikolvi.tracelet.sdk.motion.SmartMotionCoordinator? = null
            private set

        // Boot-mode heartbeat timer state.
        @Volatile
        private var bootHeartbeatHandler: Handler? = null
        @Volatile
        private var bootHeartbeatRunnable: Runnable? = null

        @Volatile
        var stationaryTimerHandler: Handler? = null
            private set
        @Volatile
        var stationaryTimerRunnable: Runnable? = null
            private set

        /**
         * Switches the location engine to stationary periodic mode.
         * Sets up a timer to fire a location fix every N minutes.
         */
        fun switchToStationaryPeriodic(
            engine: com.ikolvi.tracelet.sdk.location.LocationEngine,
            config: ConfigManager,
            state: StateManager
        ) {
            stopStationaryTimer()
            engine.stop()
            // Mark state as stationary so motion change events fire correctly
            state.isMoving = false
            state.trackingMode = com.ikolvi.tracelet.sdk.model.TrackingMode.PERIODIC

            val intervalMs = config.getStationaryPeriodicInterval() * 1000L
            val accuracy = config.getStationaryPeriodicAccuracy()

            val handler = Handler(Looper.getMainLooper())
            stationaryTimerHandler = handler

            val lastLoc = engine.getLastLocation()
            var lastLat = lastLoc?.latitude ?: Double.NaN
            var lastLng = lastLoc?.longitude ?: Double.NaN
            var lastTime = lastLoc?.time ?: 0L

            val runnable = object : Runnable {
                override fun run() {
                    if (!state.enabled) {
                        com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(engine.context).logger
                            .info("stationary periodic tick — tracking disabled, stopping timer")
                        stopStationaryTimer()
                        return
                    }
                    // persist=false: this timer inserts the enriched "periodic" record
                    // itself below. Letting getCurrentPosition() persist too stored the
                    // same map (same uuid) first, so the insert below failed every tick
                    // with "UNIQUE constraint failed: location_events.uuid" (#248).
                    engine.getCurrentPosition(mapOf("desiredAccuracy" to accuracy, "skipCache" to true, "persist" to false)) { locationMap ->
                        if (locationMap != null) {
                            val coords = locationMap["coords"] as? Map<*, *>
                            var speed = (coords?.get("speed") as? Number)?.toDouble() ?: 0.0
                            val lat = (coords?.get("latitude") as? Number)?.toDouble()
                            val lng = (coords?.get("longitude") as? Number)?.toDouble()
                            
                            val now = System.currentTimeMillis()
                            
                            // If platform speed is 0 or missing, calculate from distance
                            if (speed <= 0.0 && lat != null && lng != null && !lastLat.isNaN() && !lastLng.isNaN()) {
                                val results = FloatArray(1)
                                android.location.Location.distanceBetween(lastLat, lastLng, lat, lng, results)
                                val distance = results[0].toDouble()
                                val timeDelta = (now - lastTime) / 1000.0
                                if (timeDelta > 0) {
                                    speed = distance / timeDelta
                                }
                                
                                val stationaryRadius = config.getStationaryRadius()
                                val movingThreshold = config.getSpeedMovingThreshold()
                                if (distance >= stationaryRadius && speed < movingThreshold) {
                                    speed = movingThreshold + 0.1
                                }
                            }
                            
                            if (lat != null && lng != null) {
                                lastLat = lat
                                lastLng = lng
                                lastTime = now
                                
                                // Update odometer if accuracy is acceptable
                                val accuracy = (coords?.get("accuracy") as? Number)?.toDouble() ?: 0.0
                                val lastPeriodicLat = state.lastPeriodicLatitude
                                val lastPeriodicLng = state.lastPeriodicLongitude
                                if (!lastPeriodicLat.isNaN() && !lastPeriodicLng.isNaN()) {
                                    val results = FloatArray(1)
                                    android.location.Location.distanceBetween(lastPeriodicLat, lastPeriodicLng, lat, lng, results)
                                    val dist = results[0].toDouble()
                                    val threshold = config.getOdometerAccuracyThreshold()
                                    if (threshold <= 0 || accuracy <= threshold) {
                                        state.addOdometer(dist)
                                    }
                                }
                                state.lastPeriodicLatitude = lat
                                state.lastPeriodicLongitude = lng
                            }
                            
                            // Send location to the UI so it updates during STATIONARY mode
                            val enriched = locationMap.toMutableMap()
                            enriched["event"] = "periodic"
                            enriched["odometer"] = state.odometer
                            
                            // Insert to DB immediately so it can be synced (crucial for auto-sync in periodic mode)
                            com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(engine.context).insertLocation(enriched)
                            
                            engine.events?.sendLocation(enriched)
                            
                            engine.speedMotionSpeedSink?.invoke(speed)
                        }
                    }
                    handler.postDelayed(this, intervalMs)
                }
            }
            stationaryTimerRunnable = runnable

            // Fire first fix after one interval.
            handler.postDelayed(runnable, intervalMs)
            TraceletLog.debug("switchToStationaryPeriodic() — interval=${intervalMs}ms, accuracy=$accuracy")
        }

        /**
         * Switches to stationary geofences mode.
         */
        fun switchToStationaryGeofences(
            engine: com.ikolvi.tracelet.sdk.location.LocationEngine,
            state: StateManager,
            config: com.ikolvi.tracelet.sdk.ConfigManager
        ) {
            stopStationaryTimer()
            if (config.getGeofenceModeHighAccuracy()) {
                engine.start()
            } else {
                engine.stop()
            }
            // Mark state as stationary so motion change events fire correctly
            state.isMoving = false
            state.trackingMode = com.ikolvi.tracelet.sdk.model.TrackingMode.GEOFENCES
            TraceletLog.debug("switchToStationaryGeofences() — continuous stopped, geofences active")
        }

        /**
         * Switches back to continuous tracking.
         */
        fun switchToContinuous(engine: com.ikolvi.tracelet.sdk.location.LocationEngine, state: StateManager) {
            stopStationaryTimer()
            // Mark state as moving so motion change events fire correctly
            state.isMoving = true
            state.trackingMode = com.ikolvi.tracelet.sdk.model.TrackingMode.CONTINUOUS
            engine.start()
            TraceletLog.debug("switchToContinuous() — continuous tracking resumed")
        }

        /**
         * Whether the stationary-periodic timer is currently running (#319).
         *
         * This is what "the engine is actually in stationary mode" means, as
         * opposed to what the persisted state claims — the two diverging is the
         * bug [reconcileBootTrackingMode] exists to catch.
         */
        internal fun isStationaryTimerActive(): Boolean = stationaryTimerRunnable != null

        /** Cancels the stationary periodic timer if active. */
        fun stopStationaryTimer() {
            stationaryTimerRunnable?.let { stationaryTimerHandler?.removeCallbacks(it) }
            stationaryTimerRunnable = null
            stationaryTimerHandler = null
        }

        fun isServiceRunning(): Boolean = isRunning

        fun start(context: Context) {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_START
            }
            startForegroundServiceSafely(context.applicationContext, intent, isBoot = false)
        }

        /**
         * Start from BootReceiver with the boot flag for native tracking.
         *
         * Returns `true` if the foreground service start was dispatched, or
         * `false` if the platform refused it (Android 12+ background start
         * restriction — e.g. Android 14 disallows starting a `location`-type
         * foreground service from `BOOT_COMPLETED`). On `false` the caller MUST
         * fall back to a background-eligible mechanism (WorkManager/AlarmManager);
         * unlike the foreground [start] path, the boot start is NOT deferred until
         * the app returns to the foreground, because after a reboot the user never
         * opens the app and tracking would otherwise never resume.
         */
        fun startFromBoot(context: Context): Boolean {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_BOOT_START, true)
            }
            return startForegroundServiceSafely(context.applicationContext, intent, isBoot = true)
        }

        // Pending deferred-start observer (one-shot). See startForegroundServiceSafely.
        @Volatile
        private var deferredStartObserver: DefaultLifecycleObserver? = null

        /**
         * Starts the location foreground service without ever crashing the host app.
         *
         * On Android 12+ (API 31), calling [Context.startForegroundService] while the
         * app is in the background throws [android.app.ForegroundServiceStartNotAllowedException]
         * (an [IllegalStateException]). This happens, for example, when `ready()` is
         * invoked from a background isolate and auto-resumes tracking. We catch it so
         * the exception never propagates through Pigeon as an unhandled PlatformException,
         * and we register a one-shot ProcessLifecycle observer to retry the start the
         * next time the process moves to the foreground.
         */
        private fun startForegroundServiceSafely(appContext: Context, intent: Intent, isBoot: Boolean): Boolean {
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appContext.startForegroundService(intent)
                } else {
                    appContext.startService(intent)
                }
                true
            } catch (e: IllegalStateException) {
                // Android 12+ background foreground-service start restriction.
                if (isBoot) {
                    // Boot path: deferring until the app is foregrounded is useless
                    // here — after a reboot the user never opens the app, so the
                    // deferred start would never fire and tracking would silently
                    // never resume. Report the failure so BootReceiver can fall
                    // back to a background-eligible mechanism (WorkManager/alarms).
                    TraceletLog.warning("Boot foreground-service start blocked (Android 12+ background restriction): ${e.message}. Caller will fall back to WorkManager.")
                    // #255: boot promotion is not retried as a foreground service
                    // (falls back to WorkManager), so record it as a failure.
                    recordPromotion(
                        result = "failed",
                        promoted = false,
                        failureClass = e.javaClass.name,
                        failureMessage = e.message,
                    )
                } else {
                    TraceletLog.warning("startForegroundService blocked (app likely backgrounded on Android 12+): ${e.message}. Deferring until foreground.")
                    // #255: the promotion is deferred until the app returns to the
                    // foreground (see scheduleDeferredStart); surface that state.
                    recordPromotion(
                        result = "deferred",
                        promoted = false,
                        failureClass = e.javaClass.name,
                        failureMessage = e.message,
                    )
                    scheduleDeferredStart(appContext, isBoot)
                }
                false
            } catch (e: SecurityException) {
                TraceletLog.warning("startForegroundService blocked by SecurityException (missing permissions?): ${e.message}")
                recordPromotion(
                    result = "failed",
                    promoted = false,
                    failureClass = e.javaClass.name,
                    failureMessage = e.message,
                )
                false
            } catch (e: Exception) {
                TraceletLog.error("startForegroundService failed unexpectedly: ${e.message}")
                recordPromotion(
                    result = "failed",
                    promoted = false,
                    failureClass = e.javaClass.name,
                    failureMessage = e.message,
                )
                false
            }
        }

        /**
         * Registers a one-shot [ProcessLifecycleOwner] observer that retries the
         * foreground-service start once the app is in the foreground. If the app is
         * already foregrounded, androidx Lifecycle replays `onStart` immediately, so
         * the retry happens right away. The retry does NOT re-schedule on failure,
         * preventing any retry loop.
         */
        private fun scheduleDeferredStart(appContext: Context, isBoot: Boolean) {
            Handler(Looper.getMainLooper()).post {
                deferredStartObserver?.let {
                    ProcessLifecycleOwner.get().lifecycle.removeObserver(it)
                }
                val observer = object : DefaultLifecycleObserver {
                    override fun onStart(owner: LifecycleOwner) {
                        ProcessLifecycleOwner.get().lifecycle.removeObserver(this)
                        deferredStartObserver = null
                        if (!StateManager(appContext).enabled) {
                            com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(appContext).logger
                                .info("Deferred foreground-service start skipped — tracking was stopped")
                            return
                        }
                        val retryIntent = Intent(appContext, LocationService::class.java).apply {
                            action = ACTION_START
                            if (isBoot) putExtra(EXTRA_BOOT_START, true)
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                appContext.startForegroundService(retryIntent)
                            } else {
                                appContext.startService(retryIntent)
                            }
                            TraceletLog.debug("Deferred foreground-service start succeeded after returning to foreground")
                        } catch (e: IllegalStateException) {
                            TraceletLog.warning("Deferred foreground-service start still blocked: ${e.message}")
                        } catch (e: SecurityException) {
                            TraceletLog.warning("Deferred foreground-service start blocked by SecurityException (missing permissions?): ${e.message}")
                        } catch (e: Exception) {
                            TraceletLog.error("Deferred foreground-service start failed unexpectedly: ${e.message}")
                        }
                    }
                }
                deferredStartObserver = observer
                ProcessLifecycleOwner.get().lifecycle.addObserver(observer)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        fun updateNotification(context: Context) {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_UPDATE_NOTIFICATION
            }
            context.startService(intent)
        }

        fun acquireWakelock(context: Context) {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_ACQUIRE_WAKELOCK
            }
            context.startService(intent)
        }

        fun releaseWakelock(context: Context) {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_RELEASE_WAKELOCK
            }
            context.startService(intent)
        }

        /**
         * Stops and releases the boot-mode LocationEngine.
         *
         * Called by [TraceletAndroidPlugin] when it attaches and takes over
         * tracking with its own engine + EventChannels.
         */
        fun stopBootTracking() {
            stopBootHeartbeat()
            stopStationaryTimer()
            bootSpeedMotionManager?.stop()
            bootSpeedMotionManager = null
            bootMotionDetector?.stop()
            bootMotionDetector = null
            bootSmartMotionCoordinator = null
            bootLocationEngine?.speedMotionSpeedSink = null
            bootLocationEngine?.destroy()
            bootLocationEngine = null
            TraceletLog.debug("Boot-mode native tracking stopped — ready() taking over")
        }

        private fun stopBootHeartbeat() {
            bootHeartbeatRunnable?.let { bootHeartbeatHandler?.removeCallbacks(it) }
            bootHeartbeatRunnable = null
            bootHeartbeatHandler = null
        }
    }

    // Populated from ConfigManager at start time
    private lateinit var configManager: ConfigManager

    private var isForegroundService = false
    private var lastInForeground: Boolean? = null
    private var wakeLock: PowerManager.WakeLock? = null

    // Renews the OEM-safe wakelock before its auto-expiry timeout so continuous
    // tracking is never silently frozen by CPU deep-sleep on aggressive OEMs.
    private val wakelockHandler = Handler(Looper.getMainLooper())
    private var wakelockRenewalRunnable: Runnable? = null

    // #317: retry state for a boot/task-removal bootstrap that could not complete.
    private val bootRetryHandler = Handler(Looper.getMainLooper())
    private var bootRetryRunnable: Runnable? = null
    private var bootRetryAttempt = 0

    // Callback for notification action button taps dispatched to TraceletEventSender
    var onNotificationAction: ((String) -> Unit)? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super<Service>.onCreate()
        configManager = ConfigManager.getInstance(applicationContext)

        // #318: wire the persistent logger before anything else runs here.
        // Touching `.logger` is what calls TraceletLog.attach(), and on a cold
        // boot process this service is the first thing to execute — so without
        // this every lifecycle entry below would fall back to logcat, which is
        // precisely the evidence that is unavailable when a user reports that
        // background tracking stopped while their phone was idle.
        try {
            com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(applicationContext).logger
        } catch (e: Throwable) {
            TraceletLog.warning("Could not attach the persistent logger: ${e.message}")
        }
        TraceletLog.lifecycle("service: onCreate")

        // Layer 1: Process-level lifecycle monitoring.
        // We register as an observer to automatically manage notification
        // visibility when the app moves between foreground and background.
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        TraceletLog.debug("App moved to FOREGROUND — checking notification visibility")
        // ProcessLifecycleOwner is authoritative about UI foreground state —
        // pass it explicitly so we don't depend on the laggy process-importance
        // heuristic (which our own foreground service also skews).
        updateNotificationVisibility(forcedForeground = true)
        try {
            val sdk = com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(applicationContext)
            if (sdk.isReady) {
                TraceletLog.debug("App moved to FOREGROUND — requesting state flush to Dart")
                sdk.requestStateFlush()
            }
        } catch (e: Exception) {
            TraceletLog.error("Error flushing state on foreground transition: ${e.message}")
        }
    }

    override fun onStop(owner: LifecycleOwner) {
        TraceletLog.debug("App moved to BACKGROUND — checking notification visibility")
        // Authoritative background transition — show the pause-only notification
        // even though the OS process importance may still report foreground
        // (our foreground service pins it, and importance updates lag).
        updateNotificationVisibility(forcedForeground = false)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        TraceletLog.debug("onStartCommand: action=${intent?.action}")

        // START_STICKY restart after process death delivers a null intent.
        // Re-validate against the persisted state/config before resurrecting
        // the foreground notification: tracking may have been stopped, or the
        // active strategy may not use a foreground service at all (periodic
        // WorkManager mode, or foregroundService.enabled=false — #243).
        if (intent == null) {
            val state = StateManager(applicationContext)
            val periodicWithoutService =
                state.trackingMode == com.ikolvi.tracelet.sdk.model.TrackingMode.PERIODIC &&
                    !configManager.getPeriodicUseForegroundService()
            val wantsService = state.enabled &&
                configManager.isForegroundServiceEnabled() &&
                !periodicWithoutService
            if (!wantsService) {
                TraceletLog.lifecycle(
                    "service: sticky restart declined — enabled=${state.enabled} " +
                        "mode=${state.trackingMode} fgsEnabled=" +
                        "${configManager.isForegroundServiceEnabled()}; stopping"
                )
                stopSelf()
                isRunning = false
                return START_NOT_STICKY
            }
            TraceletLog.lifecycle(
                "service: sticky restart after process death — mode=${state.trackingMode}"
            )
        }

        // Initial setup for the very first start command
        if (lastInForeground == null) {
            lastInForeground = isAppInForeground()
        }

        // Requirement #3 & #4: Ensure the foreground contract is satisfied immediately.
        // We set isRunning true immediately so updateNotificationVisibility() works on the first call.
        if (intent?.action == ACTION_START || intent?.action == null) {
            isRunning = true
        }

        if (!isForegroundService) {
            TraceletLog.debug("Satisfying foreground contract...")
            isForegroundService = startForegroundWithNotification()
        }

        updateNotificationVisibility()

        when (intent?.action) {
            ACTION_START -> {
                acquireOemWakelock()
                // If started after a device reboot, bootstrap native tracking
                val isBootStart = intent.getBooleanExtra(EXTRA_BOOT_START, false)
                if (isBootStart) {
                    startBootTracking()
                }
            }
            ACTION_STOP -> {
                TraceletLog.debug("Stopping service via ACTION_STOP")
                stopBootTrackingInternal()
                releaseOemWakelock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                isForegroundService = false
                stopSelf()
                isRunning = false
            }
            ACTION_UPDATE_NOTIFICATION -> {
                // #257: repost the notification so ForegroundServiceConfig
                // changes (title/text/icon/color/actions/priority/ongoing)
                // applied via setConfig() take effect on the live notification
                // without restarting tracking. Visibility (whether it should be
                // shown at all) is still governed by updateNotificationVisibility()
                // above, so only repost content when currently promoted — this
                // avoids resurrecting a notification that pause-only mode just
                // suppressed while the app is in the foreground.
                if (isForegroundService) {
                    createNotificationChannel()
                    updateNotificationContent()
                }
            }
            ACTION_BUTTON -> {
                val action = intent.getStringExtra(EXTRA_BUTTON_ACTION)
                if (action != null) {
                    onNotificationAction?.invoke(action)
                }
            }
            ACTION_ACQUIRE_WAKELOCK -> {
                acquireOemWakelock()
            }
            ACTION_RELEASE_WAKELOCK -> {
                releaseOemWakelock()
            }
            null -> {
                // Sticky restart after system kill
                if (!StateManager(applicationContext).enabled) {
                    com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(applicationContext).logger
                        .info("Sticky restart but tracking is disabled — stopping service")
                    stopBootTrackingInternal()
                    releaseOemWakelock()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isForegroundService = false
                    stopSelf()
                    isRunning = false
                } else {
                    TraceletLog.debug("Sticky restart detected — bootstrapping native tracking")
                    acquireOemWakelock()
                    startBootTracking()
                }
            }
        }

        // Final sync of visibility state
        updateNotificationVisibility()

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        // If stopOnTerminate is false, keep tracking alive.
        // The plugin's LocationEngine is about to be destroyed when the
        // FlutterEngine is torn down, so we bootstrap native tracking.
        if (!configManager.getStopOnTerminate()) {

            // Guard: verify background location permission before attempting
            // to continue tracking in a killed/background context.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val hasBackground = ContextCompat.checkSelfPermission(
                    applicationContext, Manifest.permission.ACCESS_BACKGROUND_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
                if (!hasBackground) {
                    TraceletLog.warning("ACCESS_BACKGROUND_LOCATION not granted — stopping tracking on task removal")
                    stopBootTrackingInternal()
                    releaseOemWakelock()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    isRunning = false
                    return
                }
                TraceletLog.debug("ACCESS_BACKGROUND_LOCATION granted — continuing tracking after task removal")
            }

            val state = StateManager(applicationContext)

            // For periodic mode without foreground service, we don't need
            // the foreground service at all — WorkManager/AlarmManager handles
            // the scheduling independently. Stop the service to avoid showing
            // an unnecessary persistent notification.
            if (state.trackingMode == TrackingMode.PERIODIC && !configManager.getPeriodicUseForegroundService()) {
                // Ensure WorkManager/AlarmManager is scheduled (may already be)
                PeriodicLocationWorker.eventSender = null // No UI

                // HTTP sync is handled natively by Rust Core now

                if (configManager.getPeriodicUseExactAlarms()) {
                    PeriodicLocationWorker.scheduleOneTime(applicationContext)
                    PeriodicLocationWorker.scheduleExactAlarm(
                        applicationContext,
                        configManager.getPeriodicLocationInterval(),
                    )
                } else {
                    PeriodicLocationWorker.schedule(
                        applicationContext,
                        configManager.getPeriodicLocationInterval(),
                    )
                }
                TraceletLog.debug("Task removed — periodic mode continues via WorkManager/AlarmManager")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                isRunning = false
                return
            }

            // The UI is gone — for foreground-service tracking modes the
            // persistent notification must now be visible (with
            // showNotificationOnPauseOnly it was suppressed while the app was
            // open). Force it on before the process is torn down.
            lastInForeground = false
            updateNotificationVisibility(forcedForeground = false)

            startBootTracking()
            return // Service survives task removal with native tracking
        }
        stopBootTrackingInternal()
        releaseOemWakelock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        isRunning = false
    }

    override fun onDestroy() {
        // #318/#324: the pair to "service: onCreate", and at debug it was dropped at
        // every default log level. `stopRequested` is the finding: every path
        // that stands the service down deliberately clears `isRunning` first, so
        // a destroy with `stopRequested=false` is the OS reclaiming a service
        // nobody asked to stop — the shape of "tracking died while idle".
        TraceletLog.lifecycle("service: onDestroy — stopRequested=${!isRunning}")
        cancelBootTrackingRetry()
        stopBootTrackingInternal()
        releaseOemWakelock()
        isRunning = false
        // #255: the service is gone — it is no longer a foreground service.
        foregroundPromoted = false
        super<Service>.onDestroy()
    }

    // =========================================================================
    // OEM wakelock management
    // =========================================================================

    /**
     * Acquires an OEM-safe partial wakelock.
     *
     * On Huawei EMUI 9+, uses the "LocationManagerService" tag to bypass
     * PowerGenie process killing. On other devices, uses a standard tag.
     * The wakelock is held for the lifetime of the service to prevent
     * aggressive OEM power managers from suspending our process.
     */
    private fun acquireOemWakelock() {
        if (wakeLock?.isHeld != true) {
            wakeLock = OemCompat.acquireOemSafeWakelock(applicationContext, WAKELOCK_TIMEOUT_MS)
        }
        scheduleWakelockRenewal()
    }

    /**
     * Schedules periodic re-acquisition of the OEM-safe wakelock so its
     * auto-expiry timeout never lapses while the foreground service is
     * tracking. The lock keeps a finite timeout as a leak safety-net, but the
     * renewal guarantees the CPU stays awake for the lifetime of tracking —
     * preventing the silent location-update freeze on aggressive OEMs (#222).
     */
    private fun scheduleWakelockRenewal() {
        wakelockRenewalRunnable?.let { wakelockHandler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                // Acquire a fresh lock BEFORE releasing the old one so there is
                // never a gap during which the CPU could be allowed to sleep.
                try {
                    val fresh = OemCompat.acquireOemSafeWakelock(applicationContext, WAKELOCK_TIMEOUT_MS)
                    val previous = wakeLock
                    wakeLock = fresh
                    if (previous?.isHeld == true) previous.release()
                    TraceletLog.debug("Renewed OEM wakelock")
                } catch (e: Exception) {
                    TraceletLog.error("Error renewing OEM wakelock: ${e.message}")
                }
                wakelockHandler.postDelayed(this, WAKELOCK_RENEWAL_INTERVAL_MS)
            }
        }
        wakelockRenewalRunnable = runnable
        wakelockHandler.postDelayed(runnable, WAKELOCK_RENEWAL_INTERVAL_MS)
    }

    private fun releaseOemWakelock() {
        wakelockRenewalRunnable?.let { wakelockHandler.removeCallbacks(it) }
        wakelockRenewalRunnable = null
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                TraceletLog.debug("Released OEM wakelock")
            }
        } catch (e: Exception) {
            TraceletLog.error("Error releasing wakelock: ${e.message}")
        }
        wakeLock = null
    }

    // =========================================================================
    // Boot-mode native tracking
    // =========================================================================

    /**
     * Bootstraps a native [LocationEngine] for post-boot / task-removal tracking.
     *
     * Creates minimal versions of the required managers and restarts
     * the correct tracking mode based on persisted [StateManager.trackingMode]:
     * - Mode 0 (continuous): starts LocationEngine.start()
     * - Mode 1 (geofences): starts LocationEngine.start() for proximity monitoring
     *   (geofences are re-registered by Google Play Services automatically)
     * - Mode 2 (periodic): restarts the configured periodic strategy
     *   (foreground-service timer, exact alarms, or WorkManager)
     *
     * Locations are persisted to SQLite. Events are routed to the headless
     * dispatcher via [TraceletBootstrap] if a headless callback was
     * previously registered.
     */
    private fun startBootTracking() {
        if (bootLocationEngine != null) return // Already tracking

        val ctx = applicationContext

        // Guard: require background location permission for boot/task-removal tracking.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val hasBackground = ContextCompat.checkSelfPermission(
                ctx, Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            if (!hasBackground) {
                TraceletLog.warning("ACCESS_BACKGROUND_LOCATION not granted \u2014 cannot bootstrap boot tracking")
                return
            }
            TraceletLog.debug("ACCESS_BACKGROUND_LOCATION granted \u2014 bootstrapping native tracking")
        }

        val config = ConfigManager.getInstance(ctx)
        val state = StateManager(ctx)

        // Tracking was explicitly stopped — never resurrect it from a boot,
        // sticky-restart, or task-removal path.
        if (!state.enabled) {
            com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(ctx).logger
                .info("startBootTracking() — tracking disabled (stop() was called), not bootstrapping")
            return
        }

        val eventSender = TraceletBootstrap.eventSenderFactory?.invoke(ctx)
            ?: run {
                // Fallback: use a no-op ListenerEventSender so native tracking
                // and HTTP sync still work even when the Flutter engine hasn't
                // set the factory (e.g., cold boot before plugin initialization).
                TraceletLog.warning("No event sender factory — falling back to ListenerEventSender for boot tracking")
                ListenerEventSender()
            }

        // Headless event routing is handled by the EventDispatcher's
        // headlessFallback, wired by the host framework's eventSenderFactory
        // (e.g. TraceletAndroidPlugin). The headless *sync* bridge (token
        // refresh + custom body) is installed at process start by the host's
        // ContentProvider (TraceletStartupProvider), which sets
        // TraceletSdk.dartSyncInterceptor so NativeSyncProvider can reach the
        // registered headless Dart callbacks even in this boot process.

        // HTTP sync is handled natively by Rust Core now
        val sdk = com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(ctx)
        // Wait for the SDK to finish initializing before touching any manager.
        // bootstrapForBackground() now blocks on the init latch and returns false
        // if the Rust DB / geofenceManager are not ready. On a cold boot the
        // async tracelet-init thread may not have assigned the lateinit
        // geofenceManager yet; touching it below (reRegisterAll / static
        // receiver wiring) would throw UninitializedPropertyAccessException and
        // crash the service (#264). Defer gracefully instead — the foreground
        // notification is already posted and START_STICKY (plus the next app
        // launch / ready()) will retry once init is complete.
        if (!sdk.bootstrapForBackground(eventSender)) {
            TraceletLog.warning(
                "startBootTracking() — SDK initialization did not complete; deferring boot " +
                    "tracking without touching managers (#264)"
            )
            // #317: retry rather than give up. START_STICKY only redelivers after
            // the process is killed, and this service is alive and healthy — it
            // just returned early — so nothing would ever call this again short of
            // the user reopening the app. Meanwhile the foreground notification is
            // already posted, so the user is shown an active tracking session that
            // is tracking nothing. bootstrapForBackground() also fails *fast* when
            // init already failed (rather than after the 30 s await), so this is
            // not necessarily a slow-boot race that would resolve on its own.
            TraceletLog.lifecycle(
                "boot-tracking: bootstrap failed — SDK init did not complete; " +
                    "scheduling retry (#317)"
            )
            scheduleBootTrackingRetry()
            return
        }
        // Bootstrap succeeded — cancel any retry armed by an earlier attempt.
        cancelBootTrackingRetry()

        val trackingMode = state.trackingMode
        TraceletLog.debug("Bootstrapping native tracking after boot/task-removal (trackingMode=$trackingMode, isMoving=${state.isMoving}, speedState=${state.speedMotionState}, enabled=${state.enabled})")
        // #318: the anchor entry for every killed-state investigation — it records
        // that the background pipeline actually came up, in which mode, and what
        // motion state it inherited. Its *absence* in a bug report is the finding.
        TraceletLog.lifecycle(
            "boot-tracking: bootstrapping — mode=$trackingMode " +
                "isMoving=${state.isMoving} speedState=${state.speedMotionState} " +
                "motionMode=${config.getMotionDetectionMode()}"
        )

        when (trackingMode) {
            TrackingMode.PERIODIC -> {
                // Periodic mode — restart the correct scheduling strategy.
                // Wire the shared event sender so WorkManager workers can dispatch.
                PeriodicLocationWorker.eventSender = eventSender

                if (config.getPeriodicUseForegroundService()) {
                    // Foreground service + timer strategy — needs a LocationEngine
                    val engine = LocationEngine(ctx, config, state, eventSender)
                    engine.startPeriodic()
                    bootLocationEngine = engine
                    TraceletLog.debug("Periodic mode restored with foreground-service timer")
                } else if (config.getPeriodicUseExactAlarms()) {
                    // Exact alarms + OneTimeWorkRequest — no LocationEngine needed
                    PeriodicLocationWorker.scheduleOneTime(ctx)
                    PeriodicLocationWorker.scheduleExactAlarm(
                        ctx,
                        config.getPeriodicLocationInterval(),
                    )
                    TraceletLog.debug("Periodic mode restored with exact alarms")
                } else {
                    // WorkManager — already survives app kill natively,
                    // but explicitly re-schedule to ensure consistency after boot
                    PeriodicLocationWorker.schedule(
                        ctx,
                        config.getPeriodicLocationInterval(),
                    )
                    TraceletLog.debug("Periodic mode restored with WorkManager")
                }

                // Start heartbeat for periodic mode if configured
                if (bootLocationEngine != null) {
                    startBootHeartbeat(config, bootLocationEngine!!, eventSender)
                }
            }
            else -> {
                // Standard (low-power) geofence-only mode must NOT start the
                // continuous engine (#316). Mirror TraceletSdk.startGeofences():
                // rely solely on the native GeofencingClient, which fires
                // ENTER/EXIT while the app is suspended or terminated without
                // continuous GPS.
                //
                // Sharing the continuous branch (as this used to) silently
                // converted every geofence-only app to continuous tracking after
                // a reboot or task removal — burning battery, pinning the
                // location indicator, and leaving a foreground service running
                // *solely* for geofencing, which Google Play prohibits as of
                // 2026-10-28. Nothing converted it back until the app was
                // reopened.
                //
                // The fences themselves are re-registered below, outside this
                // `when`, so they are restored on this path too.
                val geofenceOnlyLowPower = trackingMode == TrackingMode.GEOFENCES &&
                    !config.getGeofenceModeHighAccuracy()
                if (geofenceOnlyLowPower) {
                    TraceletLog.debug(
                        "Standard geofence-only mode — native geofences only, " +
                            "no continuous engine (#316)"
                    )
                } else {
                    // Continuous (0), or geofences (1) in high-accuracy mode,
                    // which genuinely needs continuous GPS for in-app proximity
                    // detection.
                    val engine = LocationEngine(ctx, config, state, eventSender)
                    engine.start()
                    bootLocationEngine = engine
                    TraceletLog.debug("Boot-mode native tracking started (trackingMode=$trackingMode)")
                    startBootHeartbeat(config, engine, eventSender)
                }
            }
        }

        bootLocationEngine?.let { engine ->
            // Register SDK sink for persistence and native sync
            engine.registerSink(object : com.ikolvi.tracelet.sdk.location.LocationDataSink {
                override fun insertLocation(location: Map<String, Any?>) {
                    sdk.insertLocation(location)
                }
            })
            
            // Register SyncProvider if initialized natively
            sdk.syncProvider?.let { provider ->
                if (provider is com.ikolvi.tracelet.sdk.location.LocationDataSink) {
                    engine.registerSink(provider)
                }
            }

            // Speed, Accelerometer, or Smart motion detection setup
            val motionMode = config.getMotionDetectionMode()
                if (motionMode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SPEED) {
                    val smm = com.ikolvi.tracelet.sdk.motion.SpeedMotionManager(
                        config, state, eventSender,
                        object : com.ikolvi.tracelet.sdk.motion.SpeedMotionManager.SpeedMotionCallback {
                            override fun switchToContinuous() {
                                LocationService.switchToContinuous(engine, state)
                                if (!state.isMoving) {
                                    state.isMoving = true
                                    val locMap = engine.getLastLocation()?.let { engine.enrichLocation(it, "motionchange") } ?: mapOf("is_moving" to true)
                                    eventSender.sendMotionChange(locMap)
                                }
                            }
                            override fun switchToStationaryPeriodic() {
                                LocationService.switchToStationaryPeriodic(engine, config, state)
                                if (state.isMoving) {
                                    state.isMoving = false
                                    val locMap = engine.getLastLocation()?.let { engine.enrichLocation(it, "motionchange") } ?: mapOf("is_moving" to false)
                                    eventSender.sendMotionChange(locMap)
                                }
                            }
                            override fun switchToStationaryGeofences() {
                                LocationService.switchToStationaryGeofences(engine, state, config)
                                if (state.isMoving) {
                                    state.isMoving = false
                                    val locMap = engine.getLastLocation()?.let { engine.enrichLocation(it, "motionchange") } ?: mapOf("is_moving" to false)
                                    eventSender.sendMotionChange(locMap)
                                }
                            }
                        },
                    )
                    smm.start()
                    bootSpeedMotionManager = smm
                    engine.speedMotionSpeedSink = { speed -> smm.onLocation(speed) }
                    TraceletLog.debug("Speed-based motion detection started (boot mode)")

                    // If persisted state was STATIONARY, immediately switch to
                    // the appropriate stationary tracking mode.
                    if (state.speedMotionState == com.ikolvi.tracelet.sdk.model.SpeedMotionState.STATIONARY) {
                        when (config.getStationaryTrackingMode()) {
                            com.ikolvi.tracelet.sdk.model.StationaryTrackingMode.GEOFENCES -> LocationService.switchToStationaryGeofences(engine, state, config)
                            else -> LocationService.switchToStationaryPeriodic(engine, config, state)
                        }
                        TraceletLog.debug("Restored stationary mode from persisted speed state")
                    }
                } else if (motionMode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART) {
                    val detector = com.ikolvi.tracelet.sdk.motion.MotionDetector(
                        ctx, config, state, eventSender, sdk.logger
                    )
                    bootMotionDetector = detector

                    val coordinator = com.ikolvi.tracelet.sdk.motion.SmartMotionCoordinator(
                        ctx, config, state, eventSender, engine, detector, sdk.logger
                    )
                    bootSmartMotionCoordinator = coordinator
                    
                    val smm = com.ikolvi.tracelet.sdk.motion.SpeedMotionManager(
                        config, state, eventSender,
                        object : com.ikolvi.tracelet.sdk.motion.SpeedMotionManager.SpeedMotionCallback {
                            override fun switchToContinuous() {
                                bootSmartMotionCoordinator?.onSpeedStateChange(true)
                            }
                            override fun switchToStationaryPeriodic() {
                                bootSmartMotionCoordinator?.onSpeedStateChange(false)
                            }
                            override fun switchToStationaryGeofences() {
                                bootSmartMotionCoordinator?.onSpeedStateChange(false)
                            }
                        }
                    )
                    smm.start()
                    bootSpeedMotionManager = smm
                    engine.speedMotionSpeedSink = { speed -> smm.onLocation(speed) }

                    coordinator.syncCurrentMode()
                    TraceletLog.debug("Boot SMART: syncCurrentMode done (trackingMode=$trackingMode)")
                    
                    // Sync restored states to the coordinator so it doesn't default to true/false blindly
                    val restoredSpeedMoving = state.speedMotionState == com.ikolvi.tracelet.sdk.model.SpeedMotionState.MOVING || 
                                              state.speedMotionState == com.ikolvi.tracelet.sdk.model.SpeedMotionState.SLOWING
                    TraceletLog.debug("Boot SMART: restoring coordinator — speedMoving=$restoredSpeedMoving (speedState=${state.speedMotionState}), accelMoving=${state.isMoving}")
                    val speedAction = coordinator.onSpeedStateChange(restoredSpeedMoving)
                    val accelAction = coordinator.onAccelStateChange(state.isMoving)
                    TraceletLog.debug("Boot SMART: coordinator restored — speedAction=$speedAction, accelAction=$accelAction, isAccelMoving=${coordinator.isAccelMoving}, isSpeedMoving=${coordinator.isSpeedMoving}")
                    
                    // CRITICAL FIX: If the persisted state was STATIONARY but the engine
                    // was started in continuous mode (because trackingMode was CONTINUOUS
                    // or GEOFENCES at time of kill), we need to explicitly switch the
                    // engine to the correct mode. The coordinator's syncCurrentMode()
                    // only updates internal Rust state, not the actual native engine.
                    if (!restoredSpeedMoving && !state.isMoving && trackingMode != TrackingMode.PERIODIC) {
                        TraceletLog.debug("Boot SMART: persisted state is STATIONARY but engine started in continuous — switching engine to stationary periodic")
                        LocationService.switchToStationaryPeriodic(engine, config, state)
                    }

                    detector.onMotionStateChanged = { isMoving ->
                        TraceletLog.debug("Boot SMART: MotionDetector state changed — isMoving=$isMoving")
                        // #318: pace changes in the killed state are invisible by
                        // definition — no UI, no attached logcat — so persist the
                        // transition itself.
                        TraceletLog.lifecycle(
                            "motion (killed-state, smart): isMoving=$isMoving"
                        )

                        // Call coordinator first so it can switch the engine state (e.g. engine.start())
                        // This prevents engine.start() from overwriting forcePersistNextFilteredLocation to false.
                        bootSpeedMotionManager?.onManualPaceChange(isMoving)
                        val action = coordinator.onAccelStateChange(isMoving)
                        TraceletLog.debug("Boot SMART: coordinator accelAction=$action, isAccelMoving=${coordinator.isAccelMoving}, isSpeedMoving=${coordinator.isSpeedMoving}")
                        
                        // Fire event to Dart / headless so UI and listeners know about the pace change
                        val locMap = engine.getLastLocation()?.let { 
                            engine.enrichLocation(it, "motionchange").toMutableMap().apply { 
                                put("is_moving", isMoving) 
                            } 
                        } ?: mutableMapOf<String, Any?>("is_moving" to isMoving)
                        eventSender.sendMotionChange(locMap)
                        
                        // Force persist the location to ensure the server receives the pace change event
                        // because RustProcessor might filter the actual location (distance=0) and the server won't know we woke up.
                        try {
                            if (locMap.containsKey("coords")) {
                                val sdk = com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(ctx)
                                sdk.insertLocation(locMap)
                                sdk.sync {}
                            } else {
                                TraceletLog.debug("Boot SMART: No cached location available to persist motion change. Forcing next GPS fix to be accepted.")
                                engine.forcePersistNextFilteredLocation = true
                            }
                        } catch (e: Exception) {
                            TraceletLog.error("Failed to persist motion change location: ${e.message}")
                        }
                    }
                    detector.onStopRequested = {}

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val hasMotion = ContextCompat.checkSelfPermission(
                            ctx, Manifest.permission.ACTIVITY_RECOGNITION
                        ) == PackageManager.PERMISSION_GRANTED
                        if (hasMotion) {
                            detector.start()
                        } else {
                            // #318: a killed-state session with no motion detector
                            // can never change pace. Recorded as a lifecycle entry
                            // because it explains "stationary forever" days later,
                            // and a warning at the default OFF level is not kept.
                            TraceletLog.lifecycle(
                                "motion (killed-state, smart): DETECTOR NOT STARTED — " +
                                    "ACTIVITY_RECOGNITION not granted; pace cannot change"
                            )
                            TraceletLog.warning("ACTIVITY_RECOGNITION not granted in boot mode")
                        }
                    } else {
                        detector.start()
                    }
                    TraceletLog.debug("Smart-based motion detection started (boot mode)")
                    TraceletLog.lifecycle(
                        "motion (killed-state): smart detector started " +
                            "(initial isMoving=${state.isMoving})"
                    )
                } else {
                    // Accelerometer / Activity Recognition only
                    val detector = com.ikolvi.tracelet.sdk.motion.MotionDetector(
                        ctx, config, state, eventSender, sdk.logger
                    )
                    bootMotionDetector = detector
                    detector.onMotionStateChanged = { isMoving ->
                        // #318: see the smart branch — killed-state pace changes
                        // leave no other trace.
                        TraceletLog.lifecycle(
                            "motion (killed-state, accelerometer): isMoving=$isMoving"
                        )
                        val locMap = engine.getLastLocation()?.let { engine.enrichLocation(it, "motionchange") } ?: mapOf("is_moving" to isMoving)
                        eventSender.sendMotionChange(locMap)

                        if (isMoving) {
                            LocationService.switchToContinuous(engine, state)
                        } else {
                            when (config.getStationaryTrackingMode()) {
                                com.ikolvi.tracelet.sdk.model.StationaryTrackingMode.GEOFENCES -> LocationService.switchToStationaryGeofences(engine, state, config)
                                else -> LocationService.switchToStationaryPeriodic(engine, config, state)
                            }
                        }
                    }
                    detector.onStopRequested = {}

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val hasMotion = ContextCompat.checkSelfPermission(
                            ctx, Manifest.permission.ACTIVITY_RECOGNITION
                        ) == PackageManager.PERMISSION_GRANTED
                        if (hasMotion) {
                            detector.start()
                        } else {
                            TraceletLog.warning("ACTIVITY_RECOGNITION not granted in boot mode")
                        }
                    } else {
                        detector.start()
                    }
                    TraceletLog.debug("Accelerometer-based motion detection started (boot mode)")
                }
            } // end let

            // Re-register persisted geofences with Play Services (it clears them
            // on every reboot) and restore the static BroadcastReceiver reference
            // so transition events are not silently dropped after process death.
            // Safe to read geofenceManager here: startBootTracking() only reaches
            // this point when bootstrapForBackground() returned true, which
            // already awaited init (awaitInit) AND verified geofenceManager is
            // assigned — so the background "tracelet-init" thread has finished
            // wiring the lateinit and this cannot throw
            // UninitializedPropertyAccessException (#264).
            //
            // Previously gated on `trackingMode == TrackingMode.GEOFENCES`, which
            // conflated the dedicated geofence-only *session* (startGeofences())
            // with "there are geofences to restore" — addGeofence()/addGeofences()
            // never set that tracking mode, so a continuous-tracking app with
            // standalone geofences never got them re-registered after a reboot or
            // task removal (paired with the destroyAll() fix, #353). reRegisterAll()
            // is a cheap no-op when there are no persisted geofences, so calling it
            // unconditionally is safe for every mode.
            val geoManager = sdk.geofenceManager
            val fenceCountBeforeRestore = geoManager.getGeofences().size
            geoManager.reRegisterAll()
            if (fenceCountBeforeRestore > 0) {
                TraceletLog.lifecycle(
                    "geofences: re-registered $fenceCountBeforeRestore geofence(s) " +
                        "after boot/task-removal — mode=$trackingMode (#353)"
                )
            }
            GeofenceBroadcastReceiver.geofenceManager = geoManager

            // Wire the location stream into proximity evaluation. Without this,
            // geofenceModeHighAccuracy — which suppresses OS-level geofence
            // transitions and relies entirely on per-location proximity checks
            // (see GeofenceManager.handleGeofenceEvent / evaluateHighAccuracyProximity)
            // — produces NO enter/exit events after a reboot or task removal:
            // the foreground service and engine run, but transitions never fire.
            // Mirrors TraceletSdk.startGeofences() and TraceletSdk.start().
            //
            // Both duties ride the RAW stream (#352). This path had them on the
            // persistence-filtered `onLocationUpdate`, so it never received the
            // #297 fix at all: after a reboot or task removal even high-accuracy
            // crossings were gated by the tracking filter, and proximity scope —
            // which in standard mode is what registers fences with Play Services
            // — froze whenever the filter rejected fixes. With 3.8.0's auto-tune
            // (#299) retuning a committed `still` mode to maxImpliedSpeed=3 m/s,
            // that is every fix once the device moves.
            //
            // Ownership is per fence, not per config flag (#355): polygons and
            // sub-100 m circles are evaluated in-app whatever
            // geofenceModeHighAccuracy says, so the boot path must wire the
            // evaluator for them too or a small fence stops firing the moment the
            // app is killed — precisely the state it is most needed in.
            // The flag is read from *this* service's ConfigManager, not the
            // manager's: the boot-bootstrapped SDK can hold a different instance,
            // and reading it only through geoManager silently lost high-accuracy
            // mode on the boot path.
            val needsInAppEvaluation =
                config.getGeofenceModeHighAccuracy() || geoManager.hasEvaluatorOwnedGeofences()
            if (needsInAppEvaluation) {
                geoManager.clearHighAccuracyState()
            }
            bootLocationEngine?.geofenceHighAccuracyMode = needsInAppEvaluation
            bootLocationEngine?.onRawGeofenceLocation = { lat, lng, accuracy ->
                geoManager.updateProximity(lat, lng)
                geoManager.evaluateHighAccuracyProximity(lat, lng, accuracy)
            }
            // Claim the wake-up the inflated OS registration exists to produce:
            // if the stream has been throttled (doze, an OEM, or #319's
            // reconcile before this guard existed), coming near a small fence
            // must bring it back or the evaluator has nothing to decide on
            // (#355).
            geoManager.onEvaluatorWakeup = {
                val engine = bootLocationEngine
                if (engine != null && isStationaryTimerActive()) {
                    switchToContinuous(engine, StateManager(applicationContext))
                }
            }
            TraceletLog.debug("Geofence registrations restored after boot/task-removal (proximity stream wired)")

            // #316: standard (low-power) geofence-only mode is now fully restored
            // — the fences are re-registered with Play Services and the receiver
            // is wired — and none of that needs this service. Stand it down so a
            // geofence-only app does not keep a foreground service (and its
            // notification) alive purely for geofencing, matching what
            // TraceletSdk.startGeofences() does in the same mode.
            //
            // The service could not simply be skipped at boot: Play Services
            // clears all geofences on reboot, so something has to run
            // reRegisterAll() first. It just does not have to stay running.
            //
            // "Needs no service" now means "the OS can decide every fence"
            // (#355) — a restored polygon or sub-100 m circle is evaluated from
            // the location stream, and stopping the service here would kill the
            // stream and with it the only thing that can report its crossings.
            if (trackingMode == TrackingMode.GEOFENCES && !needsInAppEvaluation) {
                TraceletLog.debug(
                    "Standard geofence-only mode — geofences restored, stopping the " +
                        "foreground service (#316)"
                )
                stopForeground(STOP_FOREGROUND_REMOVE)
                isForegroundService = false
                stopSelf()
                isRunning = false
            }
        }

    /**
     * Re-attempts [startBootTracking] after a failed bootstrap, with capped
     * exponential backoff (#317).
     *
     * Retries at 5s, 10s, 20s, 40s, 80s and 160s (~5 minutes total). If the SDK
     * still cannot initialize after that, the failure is not transient, so the
     * service stops rather than leaving a "tracking active" notification standing
     * over a session that never started — a silent failure is worse than a
     * visibly stopped one.
     */
    private fun scheduleBootTrackingRetry() {
        if (bootRetryRunnable != null) return // A retry is already armed.
        if (bootRetryAttempt >= BOOT_RETRY_MAX_ATTEMPTS) {
            TraceletLog.error(
                "startBootTracking() — SDK initialization still failing after " +
                    "$BOOT_RETRY_MAX_ATTEMPTS attempts; stopping the service rather than " +
                    "showing a tracking notification for a session that never started (#317)"
            )
            bootRetryAttempt = 0
            releaseOemWakelock()
            stopForeground(STOP_FOREGROUND_REMOVE)
            isForegroundService = false
            stopSelf()
            isRunning = false
            return
        }
        val delayMs = BOOT_RETRY_BASE_DELAY_MS shl bootRetryAttempt
        bootRetryAttempt++
        TraceletLog.warning(
            "startBootTracking() — retrying bootstrap in ${delayMs}ms " +
                "(attempt $bootRetryAttempt/$BOOT_RETRY_MAX_ATTEMPTS) (#317)"
        )
        val runnable = Runnable {
            bootRetryRunnable = null
            // Only keep retrying while the session is still wanted. A stop() or a
            // permission revocation in the meantime must end the loop.
            if (!StateManager(applicationContext).enabled) {
                TraceletLog.debug("Boot-tracking retry abandoned — tracking is no longer enabled")
                bootRetryAttempt = 0
                return@Runnable
            }
            startBootTracking()
        }
        bootRetryRunnable = runnable
        bootRetryHandler.postDelayed(runnable, delayMs)
    }

    /** Cancels a pending boot-tracking retry and resets the backoff (#317). */
    private fun cancelBootTrackingRetry() {
        bootRetryRunnable?.let { bootRetryHandler.removeCallbacks(it) }
        bootRetryRunnable = null
        bootRetryAttempt = 0
    }

    /**
     * Starts a self-rescheduling heartbeat timer for boot-mode tracking.
     *
     * Mirrors the heartbeat logic in [TraceletAndroidPlugin.startHeartbeat]
     * but uses the boot-mode [LocationEngine] and [TraceletEventSender].
     */
    /**
     * Re-aligns the killed-state engine with the committed motion state (#319).
     *
     * In the killed state the engine's tracking mode is switched **only** from a
     * motion *transition* — `MotionDetector.onMotionStateChanged` and the
     * `SpeedMotionManager` callbacks. That is fine while transitions keep
     * arriving, but the motion subsystems can settle back into stationary
     * *without emitting one*: `MotionDetector.onManualPaceChange()` reconfigures
     * its sensors between the shake/significant-motion set and the stillness set
     * directly, and never routes through `declareStationary()`. When that
     * happens the detector reports stationary, `state.isMoving` reads false —
     * and the engine is still running continuous GPS, with the OS location
     * indicator pinned on and fixes landing every couple of seconds until the
     * user next opens the app.
     *
     * A field report showed exactly that: a single `isMoving=true` transition,
     * then 87 s of a demonstrably still device (peak 0.02 g against a 2.0 g
     * threshold) with continuous fixes still being persisted, and the detector
     * internally back in its stationary configuration.
     *
     * [startBootTracking] already reconciles this once at bootstrap, which is
     * why the divergence only appears mid-session. This runs the same check on
     * every heartbeat, so a missed transition costs one heartbeat interval
     * rather than the rest of the process lifetime.
     *
     * `state.isMoving` is the right authority here: both [switchToContinuous]
     * and [switchToStationaryPeriodic] write it as they switch, so it *is* the
     * committed intent rather than an independent opinion that could fight the
     * coordinator.
     *
     * Skipped when stationary tracking is configured for geofences: that mode
     * has no equivalent "is it running" signal to compare against, and guessing
     * would risk tearing down a correct session.
     */
    private fun reconcileBootTrackingMode(config: ConfigManager, engine: LocationEngine) {
        if (config.getStationaryTrackingMode() ==
            com.ikolvi.tracelet.sdk.model.StationaryTrackingMode.GEOFENCES
        ) {
            return
        }
        val state = StateManager(applicationContext)
        val wantsStationary = !state.isMoving
        val isStationary = isStationaryTimerActive()
        if (wantsStationary == isStationary) return

        // #319 throttles to stationary-periodic on the premise that nothing
        // needs the continuous stream while the device is still. A fence the OS
        // cannot resolve breaks that premise: it is decided from the stream, so
        // stopping the engine here is what makes a 10 m fence go quiet in the
        // killed state — the reporter's trace shows this switch landing 14 s
        // after the ENTER, and `switchToStationaryPeriodic` calls `engine.stop()`
        // (#355).
        val needsStream = runCatching {
            com.ikolvi.tracelet.sdk.TraceletSdk.getInstance(applicationContext)
                .geofenceManager.hasEvaluatorOwnedGeofences()
        }.getOrDefault(false)
        if (wantsStationary && needsStream) {
            TraceletLog.lifecycle(
                "motion (killed-state): staying continuous — an in-app-evaluated " +
                    "geofence needs the location stream, so the #319 throttle to " +
                    "stationary periodic does not apply (#355)"
            )
            return
        }

        if (wantsStationary) {
            TraceletLog.lifecycle(
                "motion (killed-state): engine was still tracking continuously " +
                    "while the committed state is stationary — switching to " +
                    "stationary periodic (#319)"
            )
            switchToStationaryPeriodic(engine, config, state)
        } else {
            TraceletLog.lifecycle(
                "motion (killed-state): engine was in stationary periodic while " +
                    "the committed state is moving — resuming continuous (#319)"
            )
            switchToContinuous(engine, state)
        }
    }

    private fun startBootHeartbeat(
        config: ConfigManager,
        engine: LocationEngine,
        dispatcher: TraceletEventSender
    ) {
        stopBootHeartbeat()
        val intervalSeconds = config.getHeartbeatInterval()
        if (intervalSeconds <= 0) return

        val handler = Handler(Looper.getMainLooper())
        bootHeartbeatHandler = handler

        val runnable = object : Runnable {
            override fun run() {
                if (bootLocationEngine == null) return // Tracking stopped
                TraceletLog.debug("Boot heartbeat fired")
                // #319: re-align the engine with the committed motion state. The
                // heartbeat is the only thing that ticks reliably in the killed
                // state, so it is where the two are re-checked.
                reconcileBootTrackingMode(config, engine)
                val cached = engine.getLastGpsLocation()
                if (cached != null) {
                    val locationData = engine.enrichLocation(cached, "heartbeat").toMutableMap()
                    dispatcher.sendHeartbeat(mapOf("location" to locationData))
                    TraceletLog.debug("Boot heartbeat: lat=${cached.latitude}, lon=${cached.longitude}, acc=${cached.accuracy}m")
                } else {
                    TraceletLog.debug("Boot heartbeat: no cached location, skipping")
                }
                handler.postDelayed(this, intervalSeconds * 1000L)
            }
        }
        bootHeartbeatRunnable = runnable
        handler.postDelayed(runnable, intervalSeconds * 1000L)
        TraceletLog.debug("Boot-mode heartbeat started (interval=${intervalSeconds}s)")
    }

    private fun stopBootTrackingInternal() {
        // #317: a pending bootstrap retry must not resurrect tracking that is
        // being torn down (ACTION_STOP, task removal with stopOnTerminate, a
        // permission revocation, or onDestroy).
        cancelBootTrackingRetry()
        stopBootHeartbeat()
        LocationService.stopStationaryTimer()
        bootSpeedMotionManager?.stop()
        bootSpeedMotionManager = null
        bootMotionDetector?.stop()
        bootMotionDetector = null
        bootSmartMotionCoordinator = null
        bootLocationEngine?.speedMotionSpeedSink = null
        bootLocationEngine?.destroy()
        bootLocationEngine = null
    }

    // =========================================================================
    // Notification
    // =========================================================================

    /**
     * Promote the service to the foreground with its notification.
     *
     * @return `true` if `startForeground()` succeeded, `false` if it threw and the
     *         service was torn down. Callers MUST gate `isForegroundService` on this
     *         result — on failure the service is stopping, so marking it as a running
     *         foreground service would leave the internal state inconsistent (see #253).
     */
    private fun startForegroundWithNotification(): Boolean {
        createNotificationChannel()
        val notification = buildNotification()

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            // #255: record the successful promotion for the health snapshot.
            recordPromotion(result = "success", promoted = true)
            true
        } catch (e: SecurityException) {
            TraceletLog.warning("SecurityException starting foreground service (missing permissions?): ${e.message}")
            recordPromotion(
                result = "failed",
                promoted = false,
                failureClass = e.javaClass.name,
                failureMessage = e.message,
            )
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            isRunning = false
            false
        } catch (e: Exception) {
            TraceletLog.error("Error starting foreground service: ${e.message}")
            recordPromotion(
                result = "failed",
                promoted = false,
                failureClass = e.javaClass.name,
                failureMessage = e.message,
            )
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            isRunning = false
            false
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = configManager.getFgChannelId()
            val channelName = configManager.getFgChannelName()
            val importance = when (configManager.getFgNotificationPriority()) {
                -2 -> NotificationManager.IMPORTANCE_MIN
                -1 -> NotificationManager.IMPORTANCE_LOW
                0 -> NotificationManager.IMPORTANCE_DEFAULT
                1 -> NotificationManager.IMPORTANCE_HIGH
                2 -> NotificationManager.IMPORTANCE_HIGH
                else -> NotificationManager.IMPORTANCE_DEFAULT
            }

            val channel = NotificationChannel(channelId, channelName, importance).apply {
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }

            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val channelId = configManager.getFgChannelId()
        val title = configManager.getFgNotificationTitle()
        val text = configManager.getFgNotificationText()
        val ongoing = configManager.getFgNotificationOngoing()

        // Launch activity intent
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        val builder = NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(ongoing)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(configManager.getFgNotificationPriority())

        // Set small icon
        val smallIconName = configManager.getFgNotificationSmallIcon()
        val smallIconResId = if (smallIconName != null) {
            resources.getIdentifier(smallIconName, "drawable", packageName)
        } else {
            // Default: app icon
            applicationInfo.icon
        }
        if (smallIconResId != 0) {
            builder.setSmallIcon(smallIconResId)
        } else {
            builder.setSmallIcon(applicationInfo.icon)
        }

        // Color
        val colorStr = configManager.getFgNotificationColor()
        if (colorStr != null) {
            try {
                builder.color = android.graphics.Color.parseColor(colorStr)
            } catch (_: IllegalArgumentException) {
            }
        }

        pendingIntent?.let { builder.setContentIntent(it) }

        // Add action buttons
        val actions = configManager.getFgActions()
        for ((index, actionLabel) in actions.withIndex()) {
            val actionIntent = Intent(this, LocationService::class.java).apply {
                action = ACTION_BUTTON
                putExtra(EXTRA_BUTTON_ACTION, actionLabel)
            }
            val actionPendingIntent = PendingIntent.getService(
                this, 1000 + index, actionIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, actionLabel, actionPendingIntent)
        }

        applyChronometer(
            builder,
            configManager.getFgNotificationShowTimer(),
            configManager.getFgNotificationStartedAt(),
            System.currentTimeMillis(),
        )
        applyOnlyAlertOnce(builder, configManager.getFgNotificationOnlyAlertOnce())

        return builder.build()
    }

    private fun updateNotificationContent() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun updateNotificationVisibility(forcedForeground: Boolean? = null) {
        if (!isRunning) return
        val showOnPauseOnly = configManager.getShowNotificationOnPauseOnly()
        // Lifecycle callbacks pass the real UI state; isAppInForeground() is only
        // a fallback for the onStartCommand / boot path where no authoritative
        // signal is available.
        val inForeground = forcedForeground ?: isAppInForeground()

        val changed = inForeground != lastInForeground
        lastInForeground = inForeground

        if (showOnPauseOnly) {
            if (inForeground) {
                if (isForegroundService) {
                    TraceletLog.debug("Suppressing notification (App in foreground)")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isForegroundService = false
                }
            } else {
                // Show in background if not already shown OR if we just transitioned.
                if (!isForegroundService || changed) {
                    TraceletLog.debug("Showing notification (App in background)")
                    isForegroundService = startForegroundWithNotification()
                }
            }
        } else {
            // Persistent mode: Always ensure it's shown.
            if (!isForegroundService) {
                TraceletLog.debug("Showing persistent notification")
                isForegroundService = startForegroundWithNotification()
            } else if (changed && !inForeground) {
                // Optimization: Re-show when moving to background in case it was
                // manually dismissed while the app was in the foreground.
                TraceletLog.debug("Restoring persistent notification on background transition")
                isForegroundService = startForegroundWithNotification()
            }
        }
    }

    private fun isAppInForeground(): Boolean {
        // Layer 1: Process-level lifecycle check (Accuracy-focused)
        val lifecycleState = ProcessLifecycleOwner.get().lifecycle.currentState
        val lifecycleForeground = lifecycleState.isAtLeast(Lifecycle.State.STARTED)

        // Layer 2: OS-level process importance check (Reliability-focused)
        // Using getMyMemoryState is more efficient and reliable for the current process.
        val processInfo = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(processInfo)
        // Our own foreground service pins importance at IMPORTANCE_FOREGROUND_SERVICE
        // (125, which is <= IMPORTANCE_VISIBLE), which would otherwise make the app
        // always look "in foreground" and permanently suppress the pause-only
        // notification. Exclude that level so only genuine UI visibility counts.
        val importanceForeground = processInfo.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE &&
            processInfo.importance != ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND_SERVICE

        TraceletLog.debug("Foreground check: lifecycle=$lifecycleState, importance=${processInfo.importance}")

        return lifecycleForeground || importanceForeground
    }
}
