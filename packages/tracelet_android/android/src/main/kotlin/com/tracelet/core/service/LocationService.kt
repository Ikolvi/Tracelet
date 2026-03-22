package com.tracelet.core.service

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
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.tracelet.core.ConfigManager
import com.tracelet.core.TraceletBootstrap
import com.tracelet.core.TraceletEventSender
import com.tracelet.core.StateManager
import com.tracelet.core.db.TraceletDatabase
import com.tracelet.core.geofence.GeofenceManager
import com.tracelet.core.http.HttpSyncManager
import com.tracelet.core.location.LocationEngine
import com.tracelet.core.location.PeriodicLocationWorker
import com.tracelet.core.receiver.GeofenceBroadcastReceiver
import com.tracelet.core.util.OemCompat

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
class LocationService : Service() {

    companion object {
        private const val TAG = "LocationService"
        private const val NOTIFICATION_ID = 7701
        const val ACTION_START = "com.tracelet.ACTION_START"
        const val ACTION_STOP = "com.tracelet.ACTION_STOP"
        const val ACTION_UPDATE_NOTIFICATION = "com.tracelet.ACTION_UPDATE_NOTIFICATION"
        const val ACTION_BUTTON = "com.tracelet.ACTION_BUTTON"
        const val EXTRA_BUTTON_ACTION = "button_action"
        const val EXTRA_BOOT_START = "boot_start"

        @Volatile
        private var isRunning = false

        // Boot-mode native tracking state — accessible by the plugin.
        @Volatile
        var bootLocationEngine: LocationEngine? = null
            private set

        // Boot-mode HTTP sync manager — auto-syncs locations when app is killed.
        @Volatile
        var bootHttpSyncManager: HttpSyncManager? = null
            private set

        // Boot-mode heartbeat timer state.
        @Volatile
        private var bootHeartbeatHandler: Handler? = null
        @Volatile
        private var bootHeartbeatRunnable: Runnable? = null

        fun isServiceRunning(): Boolean = isRunning

        fun start(context: Context) {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** Start from BootReceiver with the boot flag for native tracking. */
        fun startFromBoot(context: Context) {
            val intent = Intent(context, LocationService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_BOOT_START, true)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
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

        /**
         * Stops and releases the boot-mode LocationEngine.
         *
         * Called by [TraceletAndroidPlugin] when it attaches and takes over
         * tracking with its own engine + EventChannels.
         */
        fun stopBootTracking() {
            stopBootHeartbeat()
            stopBootHttpSync()
            bootLocationEngine?.destroy()
            bootLocationEngine = null
            Log.d(TAG, "Boot-mode native tracking stopped — plugin taking over")
        }

        private fun stopBootHttpSync() {
            val manager = bootHttpSyncManager ?: return
            // Clear periodic worker reference if it was using our boot manager
            if (PeriodicLocationWorker.httpSyncManager === manager) {
                PeriodicLocationWorker.httpSyncManager = null
            }
            manager.stop()
            bootHttpSyncManager = null
        }

        private fun stopBootHeartbeat() {
            bootHeartbeatRunnable?.let { bootHeartbeatHandler?.removeCallbacks(it) }
            bootHeartbeatRunnable = null
            bootHeartbeatHandler = null
        }
    }

    // Populated from ConfigManager at start time
    private lateinit var configManager: ConfigManager

    // OEM-safe wakelock to prevent aggressive power management
    private var wakelock: PowerManager.WakeLock? = null

    // Callback for notification action button taps dispatched to TraceletEventSender
    var onNotificationAction: ((String) -> Unit)? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        configManager = ConfigManager.getInstance(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundWithNotification()
                acquireOemWakelock()
                isRunning = true

                // If started after a device reboot, bootstrap native tracking
                val isBootStart = intent.getBooleanExtra(EXTRA_BOOT_START, false)
                if (isBootStart) {
                    startBootTracking()
                }
            }
            ACTION_STOP -> {
                stopBootTrackingInternal()
                releaseOemWakelock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                isRunning = false
            }
            ACTION_UPDATE_NOTIFICATION -> {
                updateNotificationContent()
            }
            ACTION_BUTTON -> {
                val action = intent?.getStringExtra(EXTRA_BUTTON_ACTION) ?: return START_STICKY
                onNotificationAction?.invoke(action)
            }
        }
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
                    Log.w(TAG, "ACCESS_BACKGROUND_LOCATION not granted — stopping tracking on task removal")
                    stopBootTrackingInternal()
                    releaseOemWakelock()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    isRunning = false
                    return
                }
                Log.d(TAG, "ACCESS_BACKGROUND_LOCATION granted — continuing tracking after task removal")
            }

            val state = StateManager(applicationContext)

            // For periodic mode without foreground service, we don't need
            // the foreground service at all — WorkManager/AlarmManager handles
            // the scheduling independently. Stop the service to avoid showing
            // an unnecessary persistent notification.
            if (state.trackingMode == 2 && !configManager.getPeriodicUseForegroundService()) {
                // Ensure WorkManager/AlarmManager is scheduled (may already be)
                PeriodicLocationWorker.eventSender = null // No UI

                // Create a boot-mode HttpSyncManager so periodic locations
                // are auto-synced even though the service is about to stop.
                val database = TraceletDatabase.getInstance(applicationContext)
                val bootEventSender = TraceletBootstrap.eventSenderFactory?.invoke(applicationContext)
                if (bootEventSender != null) {
                    val httpSync = HttpSyncManager(applicationContext, configManager, bootEventSender, database)
                    httpSync.start()
                    bootHttpSyncManager = httpSync
                    PeriodicLocationWorker.httpSyncManager = httpSync
                    Log.d(TAG, "Boot-mode HTTP sync manager started for periodic worker")
                }

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
                Log.d(TAG, "Task removed — periodic mode continues via WorkManager/AlarmManager")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                isRunning = false
                return
            }

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
        stopBootTrackingInternal()
        releaseOemWakelock()
        isRunning = false
        super.onDestroy()
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
        if (wakelock?.isHeld == true) return
        wakelock = OemCompat.acquireOemSafeWakelock(applicationContext)
    }

    private fun releaseOemWakelock() {
        try {
            if (wakelock?.isHeld == true) {
                wakelock?.release()
                Log.d(TAG, "Released OEM wakelock")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing wakelock: ${e.message}")
        }
        wakelock = null
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
                Log.w(TAG, "ACCESS_BACKGROUND_LOCATION not granted \u2014 cannot bootstrap boot tracking")
                return
            }
            Log.d(TAG, "ACCESS_BACKGROUND_LOCATION granted \u2014 bootstrapping native tracking")
        }

        val config = ConfigManager.getInstance(ctx)
        val state = StateManager(ctx)
        val database = TraceletDatabase.getInstance(ctx)
        val eventSender = TraceletBootstrap.eventSenderFactory?.invoke(ctx)
            ?: run {
                Log.w(TAG, "No event sender factory registered \u2014 cannot bootstrap boot tracking")
                return
            }

        // Wire headless fallback so events can reach the headless runtime
        val headless = TraceletBootstrap.headlessDispatcherFactory?.invoke(ctx)
        if (headless != null && headless.isRegistered()) {
            // The event sender implementation handles headless routing internally
            Log.d(TAG, "Headless dispatcher registered for boot tracking")
        }

        // Create HTTP sync manager for boot-mode auto-sync.
        // This ensures locations are synced to the server even when the
        // Flutter engine is not running (app killed / device rebooted).
        val httpSync = HttpSyncManager(ctx, config, eventSender, database)

        // Wire 401 authorization refresh for boot-mode sync.
        if (headless != null && headless.isRegistered()) {
            httpSync.onAuthorizationRequired = {
                (headless as? com.tracelet.tracelet_android.service.HeadlessTaskService)
                    ?.requestHeadersRefresh(10_000L) ?: false
            }
        }

        httpSync.start()
        bootHttpSyncManager = httpSync
        Log.d(TAG, "Boot-mode HTTP sync manager started")

        val trackingMode = state.trackingMode
        Log.d(TAG, "Bootstrapping native tracking after boot/task-removal (trackingMode=$trackingMode)")

        when (trackingMode) {
            2 -> {
                // Periodic mode — restart the correct scheduling strategy.
                // Wire the shared event sender so WorkManager workers can dispatch.
                PeriodicLocationWorker.eventSender = eventSender
                PeriodicLocationWorker.httpSyncManager = httpSync

                if (config.getPeriodicUseForegroundService()) {
                    // Foreground service + timer strategy — needs a LocationEngine
                    val engine = LocationEngine(ctx, config, state, eventSender, database)
                    engine.onLocationPersisted = { httpSync.onLocationInserted() }
                    engine.startPeriodic()
                    bootLocationEngine = engine
                    Log.d(TAG, "Periodic mode restored with foreground-service timer")
                } else if (config.getPeriodicUseExactAlarms()) {
                    // Exact alarms + OneTimeWorkRequest — no LocationEngine needed
                    PeriodicLocationWorker.scheduleOneTime(ctx)
                    PeriodicLocationWorker.scheduleExactAlarm(
                        ctx,
                        config.getPeriodicLocationInterval(),
                    )
                    Log.d(TAG, "Periodic mode restored with exact alarms")
                } else {
                    // WorkManager — already survives app kill natively,
                    // but explicitly re-schedule to ensure consistency after boot
                    PeriodicLocationWorker.schedule(
                        ctx,
                        config.getPeriodicLocationInterval(),
                    )
                    Log.d(TAG, "Periodic mode restored with WorkManager")
                }

                // Start heartbeat for periodic mode if configured
                if (bootLocationEngine != null) {
                    startBootHeartbeat(config, bootLocationEngine!!, eventSender)
                }
            }
            else -> {
                // Continuous (0) or geofences (1) — start full LocationEngine
                val engine = LocationEngine(ctx, config, state, eventSender, database)
                engine.onLocationPersisted = { httpSync.onLocationInserted() }
                engine.start()
                bootLocationEngine = engine
                Log.d(TAG, "Boot-mode native tracking started (trackingMode=$trackingMode)")
                startBootHeartbeat(config, engine, eventSender)

                // Geofence mode: re-register persisted geofences with Play Services
                // and restore the static BroadcastReceiver reference so transition
                // events are not silently dropped after process death.
                if (trackingMode == 1) {
                    val geoManager = GeofenceManager(ctx, config, eventSender, database)
                    geoManager.reRegisterAll()
                    GeofenceBroadcastReceiver.geofenceManager = geoManager
                    Log.d(TAG, "Geofence registrations restored after boot/task-removal")
                }
            }
        }
    }

    /**
     * Starts a self-rescheduling heartbeat timer for boot-mode tracking.
     *
     * Mirrors the heartbeat logic in [TraceletAndroidPlugin.startHeartbeat]
     * but uses the boot-mode [LocationEngine] and [TraceletEventSender].
     */
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
                engine.getCurrentPosition(emptyMap()) { location ->
                    val locationData = location
                        ?: engine.getLastLocation()?.let {
                            engine.enrichLocation(it, "heartbeat")
                        }
                        ?: emptyMap()
                    dispatcher.sendHeartbeat(mapOf("location" to locationData))
                }
                handler.postDelayed(this, intervalSeconds * 1000L)
            }
        }
        bootHeartbeatRunnable = runnable
        handler.postDelayed(runnable, intervalSeconds * 1000L)
        Log.d(TAG, "Boot-mode heartbeat started (interval=${intervalSeconds}s)")
    }

    private fun stopBootTrackingInternal() {
        stopBootHeartbeat()
        bootHttpSyncManager?.stop()
        bootHttpSyncManager = null
        bootLocationEngine?.destroy()
        bootLocationEngine = null
    }

    // =========================================================================
    // Notification
    // =========================================================================

    private fun startForegroundWithNotification() {
        createNotificationChannel()
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) { // API 34
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
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

        return builder.build()
    }

    private fun updateNotificationContent() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification())
    }
}
