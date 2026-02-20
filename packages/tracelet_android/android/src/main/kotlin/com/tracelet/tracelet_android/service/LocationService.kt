package com.tracelet.tracelet_android.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.tracelet.tracelet_android.ConfigManager
import com.tracelet.tracelet_android.EventDispatcher
import com.tracelet.tracelet_android.StateManager
import com.tracelet.tracelet_android.db.TraceletDatabase
import com.tracelet.tracelet_android.location.LocationEngine

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
 * forwarded to [HeadlessTaskService] if a headless Dart callback is registered.
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

        private var isRunning = false

        // Boot-mode native tracking state — accessible by the plugin.
        @Volatile
        var bootLocationEngine: LocationEngine? = null
            private set

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
            bootLocationEngine?.destroy()
            bootLocationEngine = null
            Log.d(TAG, "Boot-mode native tracking stopped — plugin taking over")
        }
    }

    // Populated from ConfigManager at start time
    private lateinit var configManager: ConfigManager

    // Callback for notification action button taps dispatched to EventDispatcher
    var onNotificationAction: ((String) -> Unit)? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        configManager = ConfigManager(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundWithNotification()
                isRunning = true

                // If started after a device reboot, bootstrap native tracking
                val isBootStart = intent.getBooleanExtra(EXTRA_BOOT_START, false)
                if (isBootStart) {
                    startBootTracking()
                }
            }
            ACTION_STOP -> {
                stopBootTrackingInternal()
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
        // If stopOnTerminate is false, keep service running and bootstrap
        // native tracking — the plugin's LocationEngine is about to be
        // destroyed when the FlutterEngine is torn down.
        if (!configManager.getStopOnTerminate()) {
            startBootTracking()
            return // Service survives task removal with native tracking
        }
        stopBootTrackingInternal()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        isRunning = false
    }

    override fun onDestroy() {
        stopBootTrackingInternal()
        isRunning = false
        super.onDestroy()
    }

    // =========================================================================
    // Boot-mode native tracking
    // =========================================================================

    /**
     * Bootstraps a native [LocationEngine] for post-boot tracking.
     *
     * Creates minimal versions of the required managers and starts
     * location tracking. Locations are persisted to SQLite. Events are
     * routed to [HeadlessTaskService] via [EventDispatcher.headlessFallback]
     * if a headless Dart callback was previously registered.
     */
    private fun startBootTracking() {
        if (bootLocationEngine != null) return // Already tracking

        Log.d(TAG, "Bootstrapping native location tracking after boot")

        val ctx = applicationContext
        val config = ConfigManager(ctx)
        val state = StateManager(ctx)
        val database = TraceletDatabase.getInstance(ctx)
        val eventDispatcher = EventDispatcher()

        // Wire headless fallback so events can reach the Dart headless isolate
        val headlessService = HeadlessTaskService(ctx)
        if (headlessService.isRegistered()) {
            eventDispatcher.headlessFallback = { eventName, eventData ->
                headlessService.dispatchEvent(eventName, eventData)
            }
        }

        val engine = LocationEngine(ctx, config, state, eventDispatcher, database)
        engine.start()

        bootLocationEngine = engine
        Log.d(TAG, "Boot-mode native tracking started")
    }

    private fun stopBootTrackingInternal() {
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
