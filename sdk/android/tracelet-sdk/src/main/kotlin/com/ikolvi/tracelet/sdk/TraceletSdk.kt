package com.ikolvi.tracelet.sdk

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.ikolvi.tracelet.sdk.algorithm.BatteryBudgetEngine
import com.ikolvi.tracelet.sdk.algorithm.BudgetAdjustmentEvent
import com.ikolvi.tracelet.sdk.algorithm.TripManager
import com.ikolvi.tracelet.sdk.attestation.DeviceAttestor
import com.ikolvi.tracelet.sdk.audit.AuditTrailManager
import uniffi.tracelet_core.DatabaseManager as RustDatabaseManager
import uniffi.tracelet_core.EngineState as RustEngineState
import uniffi.tracelet_core.EventDispatcher as RustEventDispatcher


import com.ikolvi.tracelet.sdk.geofence.GeofenceManager
import com.ikolvi.tracelet.sdk.impact.CrashConfirmStore
import com.ikolvi.tracelet.sdk.impact.PendingImpact
import com.ikolvi.tracelet.sdk.location.LocationDataSink
import com.ikolvi.tracelet.sdk.location.LocationEngine
import com.ikolvi.tracelet.sdk.location.PeriodicLocationWorker
import com.ikolvi.tracelet.sdk.motion.MotionDetector
import com.ikolvi.tracelet.sdk.privacy.PrivacyZoneManager
import com.ikolvi.tracelet.sdk.receiver.BootReceiver
import com.ikolvi.tracelet.sdk.receiver.CrashConfirmReceiver
import com.ikolvi.tracelet.sdk.receiver.GeofenceBroadcastReceiver
import com.ikolvi.tracelet.sdk.schedule.ScheduleManager
import com.ikolvi.tracelet.sdk.service.LocationService
import com.ikolvi.tracelet.sdk.model.TraceletTripEvent
import com.ikolvi.tracelet.sdk.model.AuthorizationStatus
import com.ikolvi.tracelet.sdk.model.TrackingMode
import com.ikolvi.tracelet.sdk.util.BatteryUtils
import com.ikolvi.tracelet.sdk.util.OemCompat
import com.ikolvi.tracelet.sdk.util.SoundManager
import com.ikolvi.tracelet.sdk.util.TraceletLog
import com.ikolvi.tracelet.sdk.util.TraceletLogger
import com.ikolvi.tracelet.sdk.util.TraceletPermissionManager
import com.ikolvi.tracelet.sdk.sync.DartSyncInterceptor

/**
 * Main entry point for the Tracelet Background Geolocation SDK (Android).
 *
 * Framework-agnostic singleton that orchestrates all subsystems: location
 * engine, motion detector, geofence manager, HTTP sync, database, and
 * foreground service. Flutter, React Native, or native Android apps inject
 * their own [TraceletEventSender] before calling [initialize].
 *
 * Usage:
 * ```kotlin
 * val sdk = TraceletSdk.getInstance(context)
 * sdk.setEventSender(myEventSender)
 * sdk.initialize()
 * sdk.ready(configMap) { state -> /* ready */ }
 * sdk.start()
 * ```
 */
class TraceletSdk private constructor(private val context: Context) {

    companion object {
        @Volatile
        private var instance: TraceletSdk? = null

        /** Battery budget sampling interval: 5 minutes. */
        private const val BATTERY_SAMPLE_INTERVAL_MS = 5 * 60 * 1000L

        /**
         * Retention pruning runs on the first location insert and every N-th
         * thereafter, instead of on every insert (#361).
         */
        private const val PRUNE_EVERY_N_INSERTS = 100L

        /**
         * How many already-synced telematics events stay readable through
         * `getTelematicsEvents()` (#366).
         *
         * Sync marks rows instead of deleting them so uploading an event doesn't
         * erase it from the app's own history (#313) — this is what stops that
         * from growing for the lifetime of the install. Unsynced rows are never
         * subject to it; they are still owed to the server.
         */
        private const val MAX_SYNCED_TELEMATICS_RETAINED = 1000

        fun getInstance(context: Context): TraceletSdk {
            return instance ?: synchronized(this) {
                instance ?: TraceletSdk(context.applicationContext).also { instance = it }
            }
        }
    }

    // =========================================================================
    // Subsystems — public so host frameworks (Flutter, React Native, etc.)
    // can do post-init wiring (e.g. connecting headless callbacks)
    // =========================================================================

    val configManager: ConfigManager by lazy { ConfigManager.getInstance(context) }
    val stateManager: StateManager by lazy { StateManager(context) }

    /**
     * Fetches + applies remote config overrides (Enterprise `remoteConfigUrl`).
     * Created lazily so apps that never set a remote URL pay nothing.
     */
    val remoteConfigManager: RemoteConfigManager by lazy {
        RemoteConfigManager(context, configManager) { msg -> logger.info(msg) }
    }

    lateinit var locationEngine: LocationEngine
        internal set
    lateinit var motionDetector: MotionDetector
        internal set
    lateinit var speedMotionManager: com.ikolvi.tracelet.sdk.motion.SpeedMotionManager
        internal set
    lateinit var geofenceManager: GeofenceManager
        internal set
    lateinit var smartMotionCoordinator: com.ikolvi.tracelet.sdk.motion.SmartMotionCoordinator
        internal set

    lateinit var scheduleManager: ScheduleManager
        internal set
    val logger: TraceletLogger by lazy {
        TraceletLogger(context, configManager).also { TraceletLog.attach(it) }
    }
    lateinit var soundManager: SoundManager
        internal set
    lateinit var permissionManager: TraceletPermissionManager
        internal set
    lateinit var auditTrailManager: AuditTrailManager
        internal set
    lateinit var privacyZoneManager: PrivacyZoneManager
        internal set

    lateinit var deviceAttestor: DeviceAttestor
        internal set

    // ── Rust Core subsystems ──
    /** Rust-native SQLite database for location persistence. */
    var rustDatabase: RustDatabaseManager? = null
        private set

    /** Rust-native engine state (config + health). */
    var rustEngineState: RustEngineState? = null
        private set
    /** Rust-native event dispatcher that orchestrates persist → sync. */
    var rustEventDispatcher: RustEventDispatcher? = null
        private set

    private lateinit var eventSender: TraceletEventSender
    val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    // Algorithms
    lateinit var tripManager: TripManager
        internal set
    private var batteryBudgetEngine: BatteryBudgetEngine? = null
    private var batteryBudgetRunnable: Runnable? = null

    /**
     * Test seam: whether the battery-budget engine is currently built/active.
     * Exposed so regression tests can assert that a runtime `setConfig()` (the
     * remote-config apply path) actually (re)builds the engine when
     * `batteryBudgetPerHour` changes — see [applyBatteryBudgetConfig].
     */
    internal val isBatteryBudgetEngineActive: Boolean
        get() = batteryBudgetEngine != null

    // 3.3.0 behavior engines (opt-in, default off)
    private var telematicsEngine: uniffi.tracelet_core.TelematicsEngine? = null
    private var transportClassifier: uniffi.tracelet_core.TransportModeClassifier? = null
    private var impactDetector: uniffi.tracelet_core.ImpactDetector? = null

    /** Opt-in ML crash model (#183); null ⇒ rule engine. Loaded off-thread. */
    @Volatile
    private var crashModel: uniffi.tracelet_core.CrashModel? = null
    private val accelBuffer = java.util.Collections.synchronizedList(mutableListOf<Double>())
    private val gyroBuffer = java.util.Collections.synchronizedList(mutableListOf<Double>())
    private val rawAccelBuffer = java.util.Collections.synchronizedList(mutableListOf<Double>())
    // #173 barometer cue: recent ambient-pressure samples (hPa) for the
    // cabin-pressure crash corroboration. Empty on the (common) devices with no
    // pressure sensor, in which case the cue simply never fires.
    private val baroBuffer = java.util.Collections.synchronizedList(mutableListOf<Double>())
    private var accelWindowRunnable: Runnable? = null
    private var impactConfirmRunnable: Runnable? = null
    @Volatile private var lastSpeedMps: Double = 0.0

    /**
     * Speed (m/s) of the most recent **raw** fix, fed by `LocationEngine.rawSpeedSink`.
     *
     * Only the transport classifier reads this. Telematics and impact detection
     * deliberately keep using [lastSpeedMps] (accepted fixes) — their thresholds
     * are calibrated against filtered speeds.
     */
    @Volatile private var lastRawSpeedMps: Double = 0.0
    @Volatile private var lastLat: Double = 0.0
    @Volatile private var lastLng: Double = 0.0
    private val accelWindowMs = 1000L
    private val impactConfirmPollMs = 1000L
    // #181: delay before sampling post-impact GPS speed for Δv corroboration.
    private val crashDvDelayMs = 2000L

    // #183 ML features: recent GPS speed history (timestamp ms → km/h) used to
    // derive the model's `speed_max` and `dv` (pre-impact speed drop) over the
    // same ~16 s event window the crash model was trained on.
    private val crashSpeedWindowMs = 16_000L
    private val speedHistory = ArrayDeque<Pair<Long, Double>>()

    /**
     * One processed accel window's model features (#310).
     *
     * The model was trained on scalars reduced from a fixed **16 s** event
     * window, but detection runs every [accelWindowMs]. Keeping the per-window
     * features lets [crashFeatureVector] aggregate back up to the training
     * window while the detector still evaluates once a second.
     */
    private data class AccelWindowFeatures(
        val timestampMs: Long,
        val peakG: Double,
        val meanG: Double,
        val gyroPeakDps: Double,
    )

    /**
     * Rolling ~16 s history of per-window accel/gyro features (#310).
     *
     * `peak_g`, `mean_g` and `gyro_peak_dps` used to be taken from the single
     * 1 s window being scored, while `speed_max`/`dv` came from the 16 s
     * [speedHistory] — so the model saw a feature vector straddling two time
     * bases, none of it matching how it was trained. `mean_g` was the worst
     * offender: the mean over the 1 s window containing a spike is nothing like
     * the mean over 16 s of driving.
     */
    private val crashFeatureHistory = ArrayDeque<AccelWindowFeatures>()

    /**
     * How far back [preImpactSpeedMps] looks for the speed the vehicle was
     * carrying into an impact (#312).
     *
     * A crash collapses speed within 1–2 s and GPS arrives at ~1 Hz, so the
     * "current" speed at the moment a window is scored can already be the
     * post-impact one. Short enough that it is still *this* event's speed, long
     * enough to survive a fix or two of collapse.
     */
    private val crashPreImpactWindowMs = 3_000L

    var activity: Activity? = null
    var isReady: Boolean = false
        private set

    val isTracking: Boolean
        get() = ::locationEngine.isInitialized && (locationEngine.isTracking || LocationService.isServiceRunning())

    /**
     * Whether *this* process already has a live session engine (#410).
     *
     * Deliberately narrower than [isTracking], which is true whenever the
     * service is running — including from inside the service itself, where it
     * answers a different question and is always true. This one asks only
     * whether the SDK's own engine is currently producing fixes, which is what
     * decides whether a second, boot-mode engine would be a duplicate.
     */
    val hasLiveSessionEngine: Boolean
        get() = ::locationEngine.isInitialized &&
            (locationEngine.isTracking || locationEngine.isPeriodicTracking)

    interface SyncProvider {
        fun syncBatchBlocking(config: uniffi.tracelet_core.HttpConfig, records: List<uniffi.tracelet_core.DbLocationRecord>): Long

        /**
         * Cancels any pending/in-flight auto-sync (e.g. a debounced background
         * sync) so nothing keeps POSTing after [stop] is called. Default no-op
         * for providers that don't queue work.
         */
        fun cancelPendingSync() {}

        /**
         * POSTs `body` to `url` — the separate telematics endpoint (#368).
         * Returns whether the server accepted it; `false` leaves the events
         * unsynced for the next attempt.
         *
         * Defaults to `false` so a provider that hasn't implemented it reports
         * "not delivered" rather than silently settling events it never sent.
         * Only reached when `telematicsUrl` is set, so providers that don't
         * override it keep their existing behaviour untouched.
         */
        fun postTelematicsBlocking(
            config: uniffi.tracelet_core.HttpConfig,
            url: String,
            body: String,
        ): Boolean = false
    }

    var syncProvider: SyncProvider? = null
    var dartSyncInterceptor: DartSyncInterceptor? = null

    private var heartbeatRunnable: Runnable? = null
    private var stopAfterElapsedRunnable: Runnable? = null
    private var syncIntervalRunnable: Runnable? = null

    /**
     * Running total of locations that have been successfully synced and pruned
     * from the local store since the last [destroySyncedLocations] call (#154).
     */
    private val syncedLocationsRemoved = java.util.concurrent.atomic.AtomicLong(0L)

    /** Async permission callback — set before triggering OS dialog. */
    internal var pendingPermissionCallback: ((AuthorizationStatus) -> Unit)? = null

    /**
     * Clears any pending permission callback, invoking it with the current
     * permission status so callers are not left waiting indefinitely.
     *
     * Called by the Flutter plugin when the Activity is detached while a
     * permission dialog may still be showing.
     */
    fun clearPendingPermissionCallback() {
        val callback = pendingPermissionCallback
        pendingPermissionCallback = null
        callback?.invoke(getPermissionStatus())
    }

    // =========================================================================
    // Injection
    // =========================================================================

    /**
     * Sets the event sender implementation. Must be called before [initialize].
     */
    fun setEventSender(sender: TraceletEventSender) {
        this.eventSender = sender
        
        if (::locationEngine.isInitialized) locationEngine.events = sender
        if (::motionDetector.isInitialized) motionDetector.events = sender
        if (::speedMotionManager.isInitialized) speedMotionManager.events = sender
        if (::smartMotionCoordinator.isInitialized) smartMotionCoordinator.events = sender
        
        // Propagate to active background boot trackers so the UI gets events
        // after being swiped away and reopened.
        try {
            com.ikolvi.tracelet.sdk.service.LocationService.bootLocationEngine?.events = sender
            com.ikolvi.tracelet.sdk.service.LocationService.bootMotionDetector?.events = sender
            com.ikolvi.tracelet.sdk.service.LocationService.bootSpeedMotionManager?.events = sender
            com.ikolvi.tracelet.sdk.service.LocationService.bootSmartMotionCoordinator?.events = sender
        } catch (e: Exception) {
            TraceletLog.error("Failed to update boot event senders: ${e.message}")
        }
    }

    fun getEventSender(): TraceletEventSender = eventSender

    /**
     * Safely registers a SyncProvider (like TraceletSyncSink).
     * This ensures it attaches to the foreground LocationEngine if ready() was called,
     * OR the background LocationService.bootLocationEngine if the app launched in the background
     * and ready() was bypassed.
     */
    fun registerSyncProvider(provider: SyncProvider) {
        val previous = this.syncProvider
        if (previous != null && previous !== provider) {
            // A provider is already attached — typically the NativeSyncProvider
            // fallback created during a background boot (checkSyncProvider). If we
            // simply added the new one, BOTH would be registered as sinks and each
            // would independently debounce + fire requestSyncBody for the same
            // batch, causing duplicate uploads (Issue #204). Cancel and unregister
            // the previous provider so exactly one sync provider is ever active.
            previous.cancelPendingSync()
            (previous as? com.ikolvi.tracelet.sdk.location.LocationDataSink)?.let { prev ->
                if (::locationEngine.isInitialized) {
                    locationEngine.unregisterSink(prev)
                }
                com.ikolvi.tracelet.sdk.service.LocationService.bootLocationEngine?.unregisterSink(prev)
            }
        }
        this.syncProvider = provider
        if (provider is com.ikolvi.tracelet.sdk.location.LocationDataSink) {
            if (::locationEngine.isInitialized) {
                locationEngine.registerSink(provider)
            }
            com.ikolvi.tracelet.sdk.service.LocationService.bootLocationEngine?.registerSink(provider)
        }
    }

    // =========================================================================
    // Initialization
    // =========================================================================

    /**
     * Creates all subsystems. Call [setEventSender] first.
     */
    fun initialize() {
        check(::eventSender.isInitialized) {
            "setEventSender() must be called before initialize()"
        }
        // Run the heavy setup — which opens the Rust DB and fsyncs it to disk —
        // off the calling thread. onAttachedToEngine runs on the platform main
        // thread; when a background FlutterEngine (e.g. audio_service's
        // MediaBrowserService, spun up by the system after the app was killed)
        // attaches, GeneratedPluginRegistrant re-attaches this plugin and this
        // init would otherwise fsync on that service's main thread → ANR on a
        // large DB. ready() blocks on initCompleteLatch before it uses the DB or
        // the engines set up here.
        synchronized(initLock) {
            if (initStarted) return
            initStarted = true
        }
        Thread({
            try {
                initializeInternal()
            } catch (t: Throwable) {
                // Preserve the failure so awaitInit()/bootstrapForBackground()
                // can report it instead of letting callers dereference
                // half-wired lateinit managers and crash later with a
                // misleading UninitializedPropertyAccessException on the boot /
                // broadcast paths (#264). Log the full stacktrace, not just the
                // message, so the underlying init failure is diagnosable.
                initializationFailure = t
                logger.error("initializeInternal failed: ${t.stackTraceToString()}")
            } finally {
                initCompleteLatch.countDown()
            }
        }, "tracelet-init").start()
    }

    private val initLock = Any()
    @Volatile private var initStarted = false
    @Volatile private var initializationFailure: Throwable? = null
    private val initCompleteLatch = java.util.concurrent.CountDownLatch(1)

    /**
     * Blocks until [initializeInternal] has finished wiring the subsystems
     * (Rust DB, engines, geofenceManager). Every entry point that touches those
     * lateinit managers synchronously — ready() and the native boot / broadcast
     * paths (GeofenceBroadcastReceiver, CrashConfirmReceiver) — must call this
     * after ensuring initialize() has been kicked off, otherwise it risks
     * reading an unassigned lateinit while the background "tracelet-init" thread
     * is still running.
     *
     * Safe to call from any service / broadcast / plugin thread; it must never
     * be called on the "tracelet-init" thread itself, which would self-deadlock.
     *
     * @return true if init completed and did not fail (subsystems are safe to
     * touch), false on timeout or init failure — callers on paths that
     * dereference lateinit managers should bail instead of proceeding when this
     * returns false.
     */
    internal fun awaitInit(): Boolean {
        val done = try {
            initCompleteLatch.await(30, java.util.concurrent.TimeUnit.SECONDS)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
        if (!done) {
            logger.error("awaitInit() timed out — subsystems still unset")
            return false
        }
        return initializationFailure == null
    }

    private fun initializeInternal() {
        // Bootstrap factory for headless/boot restart
        TraceletBootstrap.eventSenderFactory = { ctx ->
            getInstance(ctx).getEventSender()
        }

        // Persistence and Logger are now lazy properties.

        // ── Rust Core bootstrap ──
        val dbDir = context.filesDir.resolve("tracelet")
        if (!dbDir.exists()) dbDir.mkdirs()
        val dbPath = dbDir.resolve("tracelet.db").absolutePath
        try {
            val db = RustDatabaseManager(dbPath)
            
            val savedConfig = configManager.getConfig()
            if (savedConfig["encryptDatabase"] == true) {
                val key = configManager.getEncryptionKey() ?: ""
                db.setEncryptionKey(key)
            } else {
                db.setEncryptionKey("")
            }
            
            rustDatabase = db
            logger.rustDatabase = db // Inject the DB instance so it can persist logs
            logger.debug("Successfully initialized Rust Native Database: $dbPath")

            val state = RustEngineState()
            val dispatcher = RustEventDispatcher(db, state)
            rustDatabase = db
            rustEngineState = state
            rustEventDispatcher = dispatcher
            logger.info("Rust Core initialized: $dbPath")
            syncConfigToRustFlat()
        } catch (e: Exception) {
            logger.error("Failed to initialize Rust Core: ${e.message}")
        }

        // Enterprise
        auditTrailManager = AuditTrailManager(context, configManager, rustDatabase)
        privacyZoneManager = PrivacyZoneManager(context, configManager, rustDatabase)
        deviceAttestor = DeviceAttestor(context)

        // Location engine
        locationEngine = LocationEngine(
            context, configManager, stateManager, eventSender
        )
        locationEngine.auditTrailManager = auditTrailManager
        locationEngine.privacyZoneManager = privacyZoneManager
        locationEngine.onLocationPersisted = {
        }
        
        // Register the Rust Database sink
        locationEngine.registerSink(object : com.ikolvi.tracelet.sdk.location.LocationDataSink {
            override fun insertLocation(location: Map<String, Any?>) {
                this@TraceletSdk.insertLocation(location)
                processTelematics(location)
            }
        })

        // Register sync provider as a sink if it was attached prior to initialization
        if (syncProvider is com.ikolvi.tracelet.sdk.location.LocationDataSink) {
            locationEngine.registerSink(syncProvider as com.ikolvi.tracelet.sdk.location.LocationDataSink)
        }

        // Trip manager
        tripManager = TripManager()
        // #402: the database is told the trip *before* any location for it is
        // written, so every row recorded during the trip is stamped with it.
        // Both edges run on the motion-change thread that produced them, ahead
        // of the location that follows.
        tripManager.onTripStart = { data ->
            rustDatabase?.setActiveTripId(data["tripId"] as? String)
            eventSender.sendTripStart(data)
        }
        tripManager.onTripEnd = { data ->
            eventSender.sendTrip(data)
            // Cleared only after the summary is out, and never restored: the
            // next trip mints its own id.
            rustDatabase?.setActiveTripId(null)
        }

        // Motion detector
        motionDetector = MotionDetector(
            context, configManager, stateManager, eventSender, logger
        )
        motionDetector.onMotionStateChanged = { isMoving ->
            handleMotionStateChange(isMoving)
            // Keep the LocationEngine's activity in sync so enriched locations
            // don't report a permanent "unknown" (#155).
            val (activityType, activityConfidence) = motionDetector.getCurrentActivity()
            locationEngine.setCurrentActivity(activityType, activityConfidence)
        }
        // Push activity into the LocationEngine the moment it changes, even when
        // no motion-state transition occurs (#155).
        motionDetector.onActivityChanged = { type, confidence ->
            locationEngine.setCurrentActivity(type, confidence)
        }
        // 3.3.0: feed accelerometer samples (g) to the classifier/impact window
        // keystone — only buffers while a consumer engine is active.
        motionDetector.onAccelSample = { magnitudeG ->
            if (transportClassifier != null || impactDetector != null) {
                accelBuffer.add(magnitudeG)
            }
        }
        // 3.3.0/#179: feed gyroscope samples (deg/s) for crash corroboration.
        motionDetector.onGyroSample = { dps ->
            if (impactDetector != null) {
                gyroBuffer.add(dps)
            }
        }
        // #173: feed barometer samples (hPa) for the cabin-pressure crash cue.
        motionDetector.onPressureSample = { hpa ->
            if (impactDetector != null) {
                baroBuffer.add(hpa)
            }
        }
        // #180: buffer raw total-g to detect a free-fall preceding a fall impact.
        motionDetector.onAccelRawSample = { totalG ->
            if (impactDetector != null) {
                rawAccelBuffer.add(totalG)
            }
        }
        motionDetector.onStopRequested = {
            mainHandler.post {
                stateManager.enabled = false
                stateManager.isMoving = false
                locationEngine.stop()
                motionDetector.stop()
                stopHeartbeat()
                if (configManager.isForegroundServiceEnabled()) {
                    LocationService.stop(context)
                }
                eventSender.sendEnabledChange(false)
                logger.info("stopOnStationary — tracking stopped by motion detector")
            }
        }

        // Speed-based motion detector
        speedMotionManager = com.ikolvi.tracelet.sdk.motion.SpeedMotionManager(
            configManager, stateManager, eventSender,
            object : com.ikolvi.tracelet.sdk.motion.SpeedMotionManager.SpeedMotionCallback {
                override fun switchToContinuous() {
                    if (configManager.getMotionDetectionMode() == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART) {
                        smartMotionCoordinator.onSpeedStateChange(true)
                        return
                    }
                    val useForeground = configManager.isForegroundServiceEnabled()
                    if (useForeground) {
                        LocationService.switchToContinuous(locationEngine, stateManager)
                    } else {
                        PeriodicLocationWorker.cancel(context)
                        stateManager.trackingMode = TrackingMode.CONTINUOUS
                        locationEngine.start()
                    }
                    // Dispatch motionchange event so Flutter UI updates _isMoving
                    stateManager.isMoving = true
                    val locationMap = locationEngine.getLastLocation()?.let {
                        locationEngine.enrichLocation(it, "motionchange")
                    } ?: mapOf("is_moving" to true)
                    eventSender.sendMotionChange(locationMap)
                }

                override fun switchToStationaryPeriodic() {
                    if (configManager.getMotionDetectionMode() == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART) {
                        smartMotionCoordinator.onSpeedStateChange(false)
                        return
                    }
                    val useForeground = configManager.isForegroundServiceEnabled()
                    if (useForeground) {
                        LocationService.switchToStationaryPeriodic(locationEngine, configManager, stateManager)
                    } else {
                        locationEngine.stop()
                        val lastLoc = locationEngine.getLastLocation()
                        if (lastLoc != null) {
                            stateManager.lastPeriodicLatitude = lastLoc.latitude
                            stateManager.lastPeriodicLongitude = lastLoc.longitude
                            stateManager.lastLocationTime = lastLoc.time
                        }
                        stateManager.trackingMode = TrackingMode.PERIODIC
                        val interval = configManager.getStationaryPeriodicInterval()
                        
                        val useExactAlarms = configManager.getPeriodicUseExactAlarms() || interval < 900
                        if (useExactAlarms) {
                            PeriodicLocationWorker.scheduleOneTime(context)
                            PeriodicLocationWorker.scheduleExactAlarm(context, interval)
                        } else {
                            PeriodicLocationWorker.schedule(context, interval)
                        }
                    }
                    // Dispatch motionchange event so Flutter UI updates _isMoving
                    stateManager.isMoving = false
                    val locationMap = locationEngine.getLastLocation()?.let {
                        locationEngine.enrichLocation(it, "motionchange")
                    } ?: mapOf("is_moving" to false)
                    eventSender.sendMotionChange(locationMap)
                }

                override fun switchToStationaryGeofences() {
                    if (configManager.getMotionDetectionMode() == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART) {
                        smartMotionCoordinator.onSpeedStateChange(false)
                        return
                    }
                    val useForeground = configManager.isForegroundServiceEnabled()
                    if (useForeground) {
                        LocationService.switchToStationaryGeofences(locationEngine, stateManager, configManager)
                    } else {
                        if (configManager.getGeofenceModeHighAccuracy()) {
                            locationEngine.start()
                        } else {
                            locationEngine.stop()
                        }
                        stateManager.trackingMode = TrackingMode.GEOFENCES
                    }
                    // Dispatch motionchange event so Flutter UI updates _isMoving
                    stateManager.isMoving = false
                    val locationMap = locationEngine.getLastLocation()?.let {
                        locationEngine.enrichLocation(it, "motionchange")
                    } ?: mapOf("is_moving" to false)
                    eventSender.sendMotionChange(locationMap)
                }
            }
        )
        
        smartMotionCoordinator = com.ikolvi.tracelet.sdk.motion.SmartMotionCoordinator(
            context, configManager, stateManager, eventSender, locationEngine, motionDetector, logger
        )
        smartMotionCoordinator.syncCurrentMode()

        // Geofencing
        geofenceManager = GeofenceManager(
            context, configManager, eventSender, rustDatabase,
            lastLocationProvider = {
                if (::locationEngine.isInitialized) locationEngine.getLastGpsLocation() else null
            },
        ).apply {
            onGeofenceEvent = { eventMap ->
                persistGeofenceIfAllowed(eventMap)
            }
        }
        GeofenceBroadcastReceiver.geofenceManager = geofenceManager

        // Schedule
        scheduleManager = ScheduleManager(
            context, configManager, stateManager, eventSender
        )
        scheduleManager.onScheduleStart = { handleScheduleStart() }
        scheduleManager.onScheduleStop = { handleScheduleStop() }

        // Utilities
        soundManager = SoundManager(context, configManager)
        permissionManager = TraceletPermissionManager(context)

        // Re-wire periodic mode if already active (process restart)
        if (stateManager.enabled && stateManager.trackingMode == TrackingMode.PERIODIC) {
            PeriodicLocationWorker.eventSender = eventSender
        }
    }

    // =========================================================================
    // Lifecycle — ready
    // =========================================================================

    /**
     * Initializes configuration and completes SDK startup.
     *
     * Typed overload that accepts a [TraceletConfig] for type-safe
     * configuration matching the Dart API:
     *
     * ```kotlin
     * sdk.ready(TraceletConfig(
     *     app = AppConfig(stopOnTerminate = false, startOnBoot = true),
     * )) { state -> /* ready */ }
     * ```
     */
    fun requestStateFlush() {
        val providerState = locationEngine.buildProviderState().toMutableMap()
        providerState["event"] = "providerchange"
        eventSender.sendProviderChange(providerState)
        
        val isMoving = stateManager.isMoving
        val locationMap = locationEngine.getLastGpsLocation()?.let { 
            val map = locationEngine.enrichLocation(it, "motionchange").toMutableMap()
            map["is_moving"] = isMoving
            map
        } ?: mutableMapOf<String, Any?>("is_moving" to isMoving)
        eventSender.sendMotionChange(locationMap)
    }

    /**
     * Initializes configuration and completes SDK startup.
     *
     * Example:
     * ```
     *
     * @param config Typed configuration.
     * @param callback Receives the current state map when ready.
     */
    fun ready(config: com.ikolvi.tracelet.sdk.model.TraceletConfig, callback: (Map<String, Any?>) -> Unit) {
        ready(config.toMap(), callback)
    }

    /**
     * Initializes configuration and completes SDK startup.
     *
     * @param config Configuration map.
     * @param callback Receives the current state map when ready.
     */
    fun ready(config: Map<String, Any?>, callback: (Map<String, Any?>) -> Unit) {
        // (see its comment). Ensure it has been kicked off (idempotent via the
        // initStarted guard) then block until it finishes, otherwise
        // completeReady() would touch not-yet-initialized lateinit engines. Kept
        // consistent with bootstrapForBackground so ready() never depends on an
        // external ordering guarantee for who called initialize() first.
        initialize()
        if (!awaitInit()) {
            logger.error("ready() proceeding without a completed initialize() — startup may be degraded")
        }
        val merged = configManager.setConfig(config)

        if (merged["encryptDatabase"] == true) {
            val key = merged["encryptionKey"] as? String ?: ""
            rustDatabase?.setEncryptionKey(key)
        } else {
            rustDatabase?.setEncryptionKey("")
        }

        // Auto-encrypt if enabled
        if (merged["encryptDatabase"] == true) {
            encryptDatabase()
        }

        // Remote config (Enterprise): fetch overrides from a remote HTTPS
        // endpoint. Apply the last-good cached copy synchronously so a restart
        // resumes on the freshest known config instantly and offline, complete
        // ready() without waiting on the network, then fetch a fresh copy in the
        // background and keep it refreshed on the configured interval.
        val remoteUrl = configManager.getRemoteConfigUrl()
        val cachedRemote = if (!remoteUrl.isNullOrEmpty()) {
            remoteConfigManager.cachedConfig()
        } else {
            null
        }
        val effective = cachedRemote?.let { configManager.setConfig(it) } ?: merged

        completeReady(effective, callback)

        // Mirror the applied cached override to Dart so activeConfig/diagnostics
        // reflect the cached remote config on this cold start too.
        if (cachedRemote != null) {
            eventSender.sendRemoteConfigEvent(cachedRemote)
        }

        if (!remoteUrl.isNullOrEmpty()) {
            remoteConfigManager.start(remoteUrl) { remote ->
                // Apply on the main thread: setConfig() may restart the active
                // tracking pipeline (location engine, motion sensors), which must
                // run off the background fetch thread.
                mainHandler.post {
                    setConfig(remote)
                    // Notify Dart so activeConfig / diagnostics / the Dart-side
                    // battery-budget engine reflect the freshly fetched override.
                    eventSender.sendRemoteConfigEvent(remote)
                }
            }
        }
    }

    private fun completeReady(
        config: Map<String, Any?>,
        callback: (Map<String, Any?>) -> Unit,
    ) {
        // Stop boot-mode native tracking now that the Dart side has
        // explicitly called ready().  Deferring this from initialize()
        // ensures killed-state / headless-restart boot tracking keeps
        // running until the foreground app is fully ready to take over.
        LocationService.stopBootTracking()

        if (configManager.isDebug()) soundManager.start()

        logger.pruneOldLogs()
        updateBootReceiverState()

        if (configManager.getAttestationEnabled()) {
            deviceAttestor.startRefresh(configManager.getAttestationRefreshInterval())
        }

        // Initialize battery budget engine from config
        applyBatteryBudgetConfig()

        initBehaviorEngines()

        isReady = true
        syncConfigToRustFlat()
        checkSyncProvider()

        // Apply the interval-based sync cadence from the freshly-applied config (#149).
        startSyncIntervalTimer()

        // Rebuild the native location processor with the config just applied by
        // ready(). Without this the engine keeps the previous/default processor
        // (e.g. distanceFilter=20) in memory and silently filters fixes the new
        // config (e.g. distanceFilter=0) should have accepted (#157).
        if (::locationEngine.isInitialized) locationEngine.rebuildProcessor()

        if (stateManager.enabled) {
            val motionMode = configManager.getMotionDetectionMode()
            if (motionMode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART || 
                motionMode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SPEED) {
                logger.info("Resuming tracking with motion detection on ready/takeover")
                start(isResume = true)
            } else {
                when (stateManager.trackingMode) {
                    TrackingMode.CONTINUOUS -> {
                        logger.info("Resuming continuous tracking on ready/takeover")
                        start(isResume = true)
                    }
                    TrackingMode.PERIODIC -> {
                        logger.info("Resuming periodic tracking on ready/takeover")
                        startPeriodic()
                    }
                    TrackingMode.GEOFENCES -> {
                        logger.info("Resuming geofence tracking on ready/takeover")
                        startGeofences(isResume = true)
                    }
                }
            }
        }

        val stateMap = stateManager.toMap(config)
        logger.info("ready() called")
        callback(stateMap)
    }

    // =========================================================================
    // Lifecycle — start / stop
    // =========================================================================

    /**
     * Reconciles the speed-motion machine with the pace this `start()` is
     * committed to, for a start that did *not* force MOVING.
     *
     * [SpeedMotionManager.start] restores whatever the last session persisted,
     * and anything but STATIONARY means "moving". Adopting that is right for a
     * **resume**: a relaunched process has no other record of the pace it was
     * killed in. It is wrong for a **fresh start()**, which committed a pace from
     * `motion.isMoving` a few lines earlier — adopting the restored value there
     * let a previous session's MOVING silently overrule an explicit
     * `motion.isMoving: false`, and the caller was handed `isMoving=true` from a
     * start it had asked to begin stationary. `syncCurrentMode()` (#344) has
     * already read the committed pace by this point, so the seeded
     * `onAccelStateChange(true)` below then woke the coordinator too — a whole
     * session in the wrong pace, from stale state the app never asked for.
     *
     * A fresh start therefore keeps its committed pace and pushes it *into* the
     * machine. That has to happen before the last-known-speed seed further down:
     * a restored MOVING left in place falls to SLOWING on the first low-speed
     * sample, and SLOWING is still "moving", so it writes `isMoving` back to true.
     */
    private fun adoptSpeedMotionPace(isResume: Boolean) {
        val restoredMoving = speedMotionManager.getCurrentState() != "stationary"
        if (isResume) {
            stateManager.isMoving = restoredMoving
        } else if (restoredMoving) {
            speedMotionManager.onManualPaceChange(false)
        }
        if (::smartMotionCoordinator.isInitialized) {
            smartMotionCoordinator.onSpeedStateChange(stateManager.isMoving)
        }
    }

    /**
     * Starts continuous location tracking.
     *
     * @return Error string if not ready or permission denied, null on success.
     */
    fun start(isResume: Boolean = false): String? {
        if (!isReady) return "NOT_READY"

        val authStatus = permissionManager.getAuthorizationStatus(activity)
        if (authStatus != AuthorizationStatus.WHEN_IN_USE &&
            authStatus != AuthorizationStatus.ALWAYS
        ) {
            return "PERMISSION_DENIED"
        }

        // Clean up boot tracking
        LocationService.stopBootTracking()

        // Stop periodic if active
        locationEngine.stopPeriodic()
        PeriodicLocationWorker.cancel(context)
        PeriodicLocationWorker.eventSender = null

        // A manual start() while tracking is ALREADY active is a no-op. Previously
        // it reset isMoving to the configured default (isMoving=false) and forced
        // changePace(false), so calling start() a second time slammed the device
        // into the STATIONARY state even while moving. Calling start() again must
        // not disturb the live motion state — use changePace() to change pace.
        if (!isResume && isTracking) {
            stateManager.enabled = true
            stateManager.trackingMode = TrackingMode.CONTINUOUS
            logger.debug("start() — already tracking; ignoring redundant start (no pace reset)")
            // #318/#324: recorded even though nothing changed, because "I called
            // start() and nothing happened" is a real report and this is its
            // answer — the session was already live, so no fresh session
            // boundary follows and the pace was deliberately left alone.
            TraceletLog.lifecycle(
                "session: start ignored — already tracking continuously " +
                    "(isMoving=${stateManager.isMoving})"
            )
            return null
        }

        stateManager.enabled = true
        stateManager.trackingMode = TrackingMode.CONTINUOUS
        if (!isResume) {
            stateManager.isMoving = configManager.getIsMoving()
        }

        val shouldForceMoving = stateManager.isMoving

        if (configManager.isForegroundServiceEnabled()) {
            LocationService.start(context)
        } else if (configManager.isRestrictedOem()) {
            logger.warning(
                "Continuous tracking without a foreground service on an aggressive OEM " +
                    "(${android.os.Build.MANUFACTURER}) — the OS may kill tracking in the " +
                    "background. Consider foregroundService.enabled: true for reliability."
            )
        }

        // Wire geofence monitoring + trip waypoints.
        //
        // BOTH geofence duties ride the RAW stream; only trip waypoints stay on
        // the persistence-filtered one.
        //
        // #297 moved crossing *detection* to the raw stream but left proximity
        // *scope* on the filtered one, which turned out to be the same bug in a
        // less obvious place (#352). In standard (OS) geofence mode the SDK
        // detects nothing itself — Play Services does — so which fences are
        // registered with it IS the whole feature, and updateProximity() is what
        // registers them. Running that off the filtered stream means the
        // persistence filter silently decides whether geofencing works at all.
        //
        // 3.8.0's transport-mode auto-tune (#299) made that fatal: a committed
        // `still` mode retunes maxImpliedSpeed to 3 m/s and trackingAccuracy to
        // 15 m, so the moment the device starts moving every fix is rejected —
        // updateProximity() stops being called, fences coming into
        // geofenceProximityRadius are never registered, and ENTER/EXIT never
        // fire again. The filter is a persistence-volume control and must not
        // gate geofence registration.
        locationEngine.onLocationUpdate = { lat, lng, _ ->
            tripManager.onLocationReceived(lat, lng, System.currentTimeMillis().toString())
        }
        locationEngine.geofenceHighAccuracyMode = geofenceManager.hasEvaluatorOwnedGeofences()
        wireGeofenceOwnershipRefresh()
        // Called unconditionally: whether a fence is evaluated here or left to
        // the OS is a per-fence question the manager answers, and it is not one
        // the config flag alone can settle — polygons and sub-100 m circles are
        // ours to decide however `geofenceModeHighAccuracy` is set (#355).
        locationEngine.onRawGeofenceLocation = { lat, lng, accuracy ->
            geofenceManager.updateProximity(lat, lng)
            geofenceManager.evaluateHighAccuracyProximity(lat, lng, accuracy)
        }

        // Start the appropriate motion detector
        val motionMode = configManager.getMotionDetectionMode()
        
        if (motionMode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SPEED) {
            speedMotionManager.start(forceMoving = shouldForceMoving)
            if (!shouldForceMoving) adoptSpeedMotionPace(isResume)
            locationEngine.speedMotionSpeedSink = { speed -> speedMotionManager.onLocation(speed) }
            
            // Seed the machine with the last GPS speed this process actually
            // resolved — and only if there is one.
            //
            // `lastEffectiveSpeed` is 0.0 on a process that has not yet handled
            // a fix, which is exactly the state a killed-state relaunch or a
            // background takeover starts in. Feeding that 0.0 told a session
            // that had just resumed as MOVING that it was stopped: it dropped
            // straight to SLOWING and, `speedStationaryDelay` later, to
            // STATIONARY — switching off the continuous stream while the user
            // was still walking. The location indicator disappearing shortly
            // after backgrounding or killing the app is this, and nothing about
            // the device had changed.
            //
            // 0.0 means "no speed reported", not "stopped". A null
            // `getLastLocation()` is precisely "no fix handled in this process",
            // which is unknown rather than zero — the same reading
            // SmartMotionCoordinator.resolvedSpeed already takes.
            if (locationEngine.getLastLocation() != null) {
                speedMotionManager.onLocation(locationEngine.lastEffectiveSpeed)
            } else {
                com.ikolvi.tracelet.sdk.util.TraceletLog.lifecycle(
                    "pace: no fix resolved in this process yet — not seeding the machine " +
                        "with a fabricated 0.0 m/s, which would stand a resumed session down",
                )
            }
            
            if (shouldForceMoving || stateManager.isMoving) {
                val locationMap = locationEngine.getLastLocation()?.let {
                    locationEngine.enrichLocation(it, "motionchange")
                } ?: mapOf("is_moving" to stateManager.isMoving)
                eventSender.sendMotionChange(locationMap)
            }
        } else if (motionMode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART) {
            // Re-sync the Rust coordinator with the mode this start() just set.
            // syncCurrentMode() otherwise only ran in initialize(), from the
            // *persisted* trackingMode — so a session that ended stationary left
            // the coordinator on STATIONARY_PERIODIC while start() set CONTINUOUS.
            // Its evaluate_state only emits a stationary action when it believes
            // the current mode is Continuous, so the pace could never leave
            // MOVING again until the process was killed.
            smartMotionCoordinator.syncCurrentMode()
            speedMotionManager.start(forceMoving = shouldForceMoving)
            if (!shouldForceMoving) {
                adoptSpeedMotionPace(isResume)
            } else {
                // A forced-moving start left the coordinator's speed input on
                // whatever the *previous* session ended with: only
                // adoptSpeedMotionPace() ever writes it, and it does not run
                // here. `isSpeedMoving` is process-lived state behind the FFI
                // that no start() resets, so a session that parked stationary
                // handed the next one a `false` — and the core dedupes a repeat
                // of that flag to NONE, so the machine could never re-assert it
                // either. The whole session then hung on the accelerometer
                // alone. The mirror of the accel seed below: the machine was
                // just forced to MOVING, so the coordinator has to be told
                // (#409).
                smartMotionCoordinator.onSpeedStateChange(true)
            }
            locationEngine.speedMotionSpeedSink = { speed -> speedMotionManager.onLocation(speed) }
            
            // Seed the machine with the last GPS speed this process actually
            // resolved — and only if there is one.
            //
            // `lastEffectiveSpeed` is 0.0 on a process that has not yet handled
            // a fix, which is exactly the state a killed-state relaunch or a
            // background takeover starts in. Feeding that 0.0 told a session
            // that had just resumed as MOVING that it was stopped: it dropped
            // straight to SLOWING and, `speedStationaryDelay` later, to
            // STATIONARY — switching off the continuous stream while the user
            // was still walking. The location indicator disappearing shortly
            // after backgrounding or killing the app is this, and nothing about
            // the device had changed.
            //
            // 0.0 means "no speed reported", not "stopped". A null
            // `getLastLocation()` is precisely "no fix handled in this process",
            // which is unknown rather than zero — the same reading
            // SmartMotionCoordinator.resolvedSpeed already takes.
            if (locationEngine.getLastLocation() != null) {
                speedMotionManager.onLocation(locationEngine.lastEffectiveSpeed)
            } else {
                com.ikolvi.tracelet.sdk.util.TraceletLog.lifecycle(
                    "pace: no fix resolved in this process yet — not seeding the machine " +
                        "with a fabricated 0.0 m/s, which would stand a resumed session down",
                )
            }
            
            if (shouldForceMoving || stateManager.isMoving) {
                val locationMap = locationEngine.getLastLocation()?.let {
                    locationEngine.enrichLocation(it, "motionchange")
                } ?: mapOf("is_moving" to stateManager.isMoving)
                eventSender.sendMotionChange(locationMap)
            }

            // Seed the coordinator's accelerometer flag to the state we are
            // actually starting in. The Rust coordinator initialises
            // is_accel_moving = false and on_accel_state_change() early-returns
            // when the flag is unchanged, so starting in MOVING left the accel
            // input inert: MotionDetector's stopTimeout would fire
            // declareStationary() → onAccelStateChange(false) → no change → no
            // action, and the accelerometer could never contribute to a stationary
            // decision until something had first declared moving.
            if (stateManager.isMoving) {
                smartMotionCoordinator.onAccelStateChange(true)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val hasMotion = ContextCompat.checkSelfPermission(
                    context, Manifest.permission.ACTIVITY_RECOGNITION
                ) == PackageManager.PERMISSION_GRANTED
                if (!hasMotion) {
                    permissionManager.requestActivityRecognition(activity)
                } else {
                    motionDetector.start()
                }
            } else {
                motionDetector.start()
            }
        } else {
            // Activity recognition permission + accelerometer motion detector
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val hasMotion = ContextCompat.checkSelfPermission(
                    context, Manifest.permission.ACTIVITY_RECOGNITION
                ) == PackageManager.PERMISSION_GRANTED
                if (!hasMotion) {
                    permissionManager.requestActivityRecognition(activity)
                } else {
                    motionDetector.start()
                }
            } else {
                motionDetector.start()
            }
        }

        if (stateManager.isMoving) {
            locationEngine.start()
        } else {
            changePace(false)
            // A session that starts stationary runs no stream — that is the
            // point of the branch. A fence the OS cannot resolve is decided
            // *from* that stream (#355), so one already stored at start() would
            // otherwise stay dead until the device happened to move. The fence
            // set is re-asked on every later change; this covers the fences that
            // were there before the session was (#357).
            if (locationEngine.geofenceHighAccuracyMode) {
                TraceletLog.lifecycle(
                    "[geofence] starting the location stream for an " +
                        "in-app-evaluated fence — the session starts stationary, " +
                        "which otherwise runs no stream (#357)"
                )
                locationEngine.start()
            }
            // A stationary start is dark otherwise: no continuous stream (by
            // design), and no stationary schedule either — the coordinator is
            // synced to STATIONARY_PERIODIC above and *then* told both inputs
            // are stationary, so it reports no mode change and arms nothing.
            // The app was left with no position at all until the device
            // physically moved. One fix anchors the session; the pace it was
            // asked to start in is untouched (#385).
            //
            // Restores acquisition this path lost in 3.2.0 (bb8af6a0), which
            // replaced an unconditional locationEngine.start() with the pace
            // branch above. The stream had been doing double duty — ongoing
            // feed *and* initial fix — and only the first job was replaced.
            //
            // Fresh starts only. A resume runs on every process relaunch and
            // restores rather than commits its pace — the killed-state path
            // stays exactly as it was.
            if (!isResume) {
                TraceletLog.lifecycle(
                    "session: acquiring the initial fix for a stationary start (#385)"
                )
                locationEngine.requestStartupFix()
            }
        }

        startHeartbeat()
        startStopAfterElapsedTimer()
        startBatteryBudgetSampling()
        startBehaviorSampling()

        eventSender.sendEnabledChange(true)
        logger.info("start() — tracking started")
        // #318/#324: the session boundary itself. Every killed-state investigation
        // starts by asking when the session began and in which mode, and the
        // most common answer to "it stopped tracking" is a `session: stop` with
        // no start after it. `resume=true` marks the SDK's own takeover on
        // ready() rather than a call from the app, which distinguishes "the app
        // restarted us" from "the app asked for a fresh session".
        TraceletLog.lifecycle(
            "session: start — mode=continuous resume=$isResume " +
                "isMoving=${stateManager.isMoving} " +
                "motionMode=${configManager.getMotionDetectionMode()} " +
                "fgs=${configManager.isForegroundServiceEnabled()}"
        )
        return null // success
    }

    /**
     * Stops all tracking.
     *
     * @param preserveForegroundService when true, the active foreground
     * [LocationService] is NOT torn down. This exists for the in-place restart
     * performed by [setConfig]: sending `ACTION_STOP` here and immediately
     * `ACTION_START` from the following start*() races the service commands —
     * the `ACTION_STOP` handler's `stopSelf()` can win and destroy the service
     * right after `ACTION_START` promoted it, leaving NO foreground service at
     * all (#254, same race fixed for startPeriodic() in #237). When the restart
     * lands in a mode that still needs the service, the caller keeps it alive
     * and lets the idempotent `ACTION_START` re-assert foreground; when it lands
     * in a mode that does not, the caller passes false so the service is stopped
     * here cleanly (no immediately-following start ⇒ no race).
     */
    fun stop(preserveForegroundService: Boolean = false) {
        // #318/#324: read before the state is cleared, so the entry says what was
        // torn down rather than the zeroed state that follows.
        val wasTracking = stateManager.enabled
        val wasMode = stateManager.trackingMode
        val wasMoving = stateManager.isMoving

        stateManager.enabled = false
        stateManager.isMoving = false

        if (::locationEngine.isInitialized) {
            locationEngine.stop()
            locationEngine.onLocationUpdate = null
            locationEngine.onRawGeofenceLocation = null
            locationEngine.geofenceHighAccuracyMode = false
            locationEngine.speedMotionSpeedSink = null
        }
        if (::geofenceManager.isInitialized) {
            geofenceManager.onEvaluatorOwnershipChanged = null
        }
        // Cancel any pending/in-flight background sync so it doesn't keep POSTing
        // after tracking is stopped (e.g. a debounced headless sync mid-flight).
        syncProvider?.cancelPendingSync()
        if (::motionDetector.isInitialized) motionDetector.stop()
        if (::speedMotionManager.isInitialized) speedMotionManager.stop()
        stopHeartbeat()
        stopSyncIntervalTimer()
        cancelStopAfterElapsedTimer()
        if (::tripManager.isInitialized) tripManager.reset()
        stopBatteryBudgetSampling()
        batteryBudgetEngine?.reset()
        stopBehaviorSampling()
        telematicsEngine?.reset()

        PeriodicLocationWorker.cancel(context)
        PeriodicLocationWorker.eventSender = null

        // Tear down service-side tracking synchronously. The stationary
        // periodic timer and boot-mode engine live in LocationService's
        // companion, not in this SDK's locationEngine, so relying on the
        // async ACTION_STOP intent alone leaves them running (e.g. SMART
        // mode switched to stationary-periodic while backgrounded, or a
        // sticky service restart bootstrapped a boot engine).
        LocationService.stopStationaryTimer()
        LocationService.stopBootTracking()

        // #254: skip the ACTION_STOP when the caller is about to restart into a
        // mode that keeps the foreground service — otherwise stopSelf() races the
        // follow-up ACTION_START and can kill the just-promoted service.
        if (!preserveForegroundService &&
            (configManager.isForegroundServiceEnabled() || LocationService.isServiceRunning())
        ) {
            LocationService.stop(context)
        }

        if (::eventSender.isInitialized) eventSender.sendEnabledChange(false)
        logger.info(
            "stop() — tracking stopped" +
                if (preserveForegroundService) " (foreground service preserved for restart)" else ""
        )
        // #318/#324: the counterpart to `session: start`, and on its own the answer
        // to most "it stopped tracking" reports — tracking was stopped, and the
        // trail says when. `restart=true` marks setConfig()'s in-place restart,
        // which is immediately followed by a start and is NOT the session
        // ending; without it every config change would read as a stop.
        TraceletLog.lifecycle(
            "session: stop — was mode=$wasMode enabled=$wasTracking " +
                "isMoving=$wasMoving restart=$preserveForegroundService"
        )
    }

    fun getState(): Map<String, Any?> {
        return stateManager.toMap(configManager.getConfig())
    }

    // =========================================================================
    // Lifecycle — startGeofences
    // =========================================================================

    fun startGeofences(isResume: Boolean = false): String? {
        if (!isReady) return "NOT_READY"

        // A redundant re-start — already tracking in GEOFENCES mode — is not a
        // fresh session, even when the host app (not the SDK's own resume path)
        // makes the call. Apps commonly call startGeofences() on every launch to
        // "refresh" fences; treating that as a fresh start would reset the
        // inside-set and re-ENTER a stationary device on every launch (#292). So
        // only a genuine transition into geofence mode (from stopped or another
        // mode) resets inside-state; a redundant call is treated as a resume.
        val treatAsResume = isResume ||
            (stateManager.enabled && stateManager.trackingMode == TrackingMode.GEOFENCES)

        stateManager.enabled = true
        stateManager.trackingMode = TrackingMode.GEOFENCES

        geofenceManager.reRegisterAll()

        // Not just the config flag: a polygon or a sub-100 m circle is evaluated
        // in-app whatever the flag says, and in-app evaluation is exactly what
        // needs the continuous fix stream. Asking the manager keeps "who decides
        // this fence" and "what does deciding it cost" the same question (#355).
        val needsInAppEvaluation = geofenceManager.hasEvaluatorOwnedGeofences()

        // Crossing *detection* must see every fix — a stationary device inside a
        // small fence emits no accepted fixes on a stable provider (GMS Fused
        // since 3.7.3), which starved evaluateHighAccuracyProximity and dropped
        // ENTER/EXIT transitions (#297).
        //
        // Proximity *scope* rides the raw stream for the same reason (#352). It
        // was left on the filtered stream because scope only needs re-evaluating
        // when the device moves — true, but the filter rejects fixes for reasons
        // that have nothing to do with movement (accuracy, implied speed), and
        // in standard mode registering a fence with Play Services is the entire
        // feature. 3.8.0's auto-tune (#299) retunes a committed `still` mode to
        // maxImpliedSpeed=3 m/s / trackingAccuracy=15 m, so moving off rejects
        // every fix and freezes registration permanently.
        //
        // The persistence filter is a volume control; it must gate neither.
        locationEngine.onLocationUpdate = null
        locationEngine.geofenceHighAccuracyMode = needsInAppEvaluation
        wireGeofenceOwnershipRefresh()
        locationEngine.onRawGeofenceLocation = { lat, lng, accuracy ->
            geofenceManager.updateProximity(lat, lng)
            geofenceManager.evaluateHighAccuracyProximity(lat, lng, accuracy)
        }

        // Continuous GPS is needed exactly when a fence is evaluated in-app —
        // high-accuracy mode, a polygon, or a sub-100 m circle (#355). Fences the
        // OS can decide for itself need none of it: the native GeofencingClient
        // reports crossings without a location stream, and starting one keeps the
        // persistent location indicator on and wastes battery for no benefit
        // (parity with the iOS #210 fix).
        //
        // Foreground service: same condition, same reason. A geofence-only config
        // the OS can serve must NOT run one — the native Geofence API fires while
        // suspended/terminated without it, and Google Play prohibits a foreground
        // service used *solely* for geofencing as of 2026-10-28. Note the
        // corollary for small fences: they cannot be served by the OS, so opting
        // into one means opting into the location stream (and its FGS) that
        // in-app evaluation runs on. Any FGS left over from a previous
        // continuous/high-accuracy session is torn down.
        if (needsInAppEvaluation) {
            // A fresh start resets inside-state so the initial-entry trigger
            // fires exactly once. A resume/boot/redundant re-start must NOT reset
            // it, or a stationary device inside a fence re-emits ENTER on every
            // ready()/takeover or app-start refresh — false attendance punch-ins
            // (#292). The persisted knownInsideIds additionally suppresses the
            // re-ENTER a cold-start (empty evaluator) would otherwise produce.
            if (treatAsResume) {
                geofenceManager.clearHighAccuracyState()
            } else {
                geofenceManager.resetHighAccuracyInsideState()
            }
        } else if (configManager.isRestrictedOem()) {
            logger.warning(
                "startGeofences() in low-accuracy mode on an aggressive OEM " +
                    "(${android.os.Build.MANUFACTURER}) — native geofence delivery may be " +
                    "delayed or dropped. Consider geofenceModeHighAccuracy: true for reliability."
            )
        }
        applyGeofenceModePosture(needsInAppEvaluation)

        eventSender.sendEnabledChange(true)
        logger.info(
            "startGeofences() — geofence-only mode " +
                "(highAccuracy=${configManager.getGeofenceModeHighAccuracy()})"
        )
        // #318/#324: see start(). Recorded per mode because a geofence-only session
        // that never fires looks identical to no session at all in a report,
        // and low-accuracy mode deliberately runs with no foreground service —
        // so "no service entries" is expected here and a finding elsewhere.
        TraceletLog.lifecycle(
            "session: start — mode=geofences resume=$treatAsResume " +
                "highAccuracy=${configManager.getGeofenceModeHighAccuracy()} " +
                "inAppEvaluation=$needsInAppEvaluation " +
                "fences=${geofenceManager.getGeofences().size}"
        )
        return null
    }

    /**
     * Keeps the location cadence answering to the *current* fence set.
     *
     * The `geofenceHighAccuracyMode` assignments above settle it once, at
     * `start()`/`startGeofences()`, when there may be no fences at all —
     * `start()` then `addGeofence(radius = 10f)` is the ordinary order, and it
     * left the flag false for the rest of the session (#357).
     */
    private fun wireGeofenceOwnershipRefresh() {
        geofenceManager.onEvaluatorOwnershipChanged = { applyGeofenceEvaluationCadence() }
    }

    /**
     * Re-aligns the location cadence with who owns the currently-stored fences.
     *
     * With the flag left false the provider kept `minUpdateDistanceMeters` at
     * the configured distance filter, so the evaluator was handed one fix per
     * that many metres travelled. A device can cross a 10 m fence's exit band
     * and be back inside between two deliveries, and EXIT needs two
     * *consecutive* fixes beyond it — so the crossing was never confirmable
     * (#357).
     */
    private fun applyGeofenceEvaluationCadence() {
        if (!stateManager.enabled || !::locationEngine.isInitialized) return
        val needsInAppEvaluation = geofenceManager.hasEvaluatorOwnedGeofences()
        if (locationEngine.geofenceHighAccuracyMode == needsInAppEvaluation) return

        TraceletLog.lifecycle(
            "[geofence] fence set changed — in-app evaluation " +
                (if (needsInAppEvaluation) "required" else "no longer required") +
                ", realigning the location cadence (#357)"
        )
        // Setting this re-issues the fused request live when tracking.
        locationEngine.geofenceHighAccuracyMode = needsInAppEvaluation

        if (stateManager.trackingMode == TrackingMode.GEOFENCES) {
            applyGeofenceModePosture(needsInAppEvaluation)
        } else if (needsInAppEvaluation && !locationEngine.isTracking) {
            // Continuous mode does not necessarily have a stream running:
            // `start()` calls `changePace(false)` when the committed state is
            // stationary, and the motion detector stops it on every
            // moving → stationary transition. A fence added in that window was
            // registered against a dead stream — the device trace showed a 10 m
            // fence registered, the cadence re-aligned, and not one fix in the
            // following minute because the engine had never started (#357).
            TraceletLog.lifecycle(
                "[geofence] starting the location stream for an in-app-evaluated " +
                    "fence — the session is stationary, so nothing was running (#357)"
            )
            locationEngine.start()
        }
    }

    /**
     * Applies the power posture `geofences` mode runs at, given whether any
     * stored fence must be evaluated in-app.
     *
     * Continuous GPS — and the foreground service that keeps it alive — is
     * needed exactly when a fence is evaluated in-app (#355). A fence the OS can
     * decide for itself needs neither: the native Geofence API reports crossings
     * while suspended or terminated, and Google Play prohibits a foreground
     * service used *solely* for geofencing as of 2026-10-28.
     *
     * Shared by `startGeofences()` and the mid-session refresh so the two cannot
     * drift: a fence added later must be able to *reach* this posture, and one
     * removed later — KnockOut removes on EXIT — must be able to leave it, or
     * the mode leaks continuous GPS and its service for the rest of the session
     * (#357).
     */
    private fun applyGeofenceModePosture(needsInAppEvaluation: Boolean) {
        if (needsInAppEvaluation) {
            locationEngine.start()
            if (configManager.isForegroundServiceEnabled()) {
                LocationService.start(context)
            }
        } else {
            locationEngine.stop()
            if (LocationService.isServiceRunning()) {
                LocationService.stop(context)
            }
        }
    }

    // =========================================================================
    // Lifecycle — startPeriodic
    // =========================================================================

    fun startPeriodic(): String? {
        if (!isReady) return "NOT_READY"

        val authStatus = permissionManager.getAuthorizationStatus(activity)
        if (authStatus != AuthorizationStatus.WHEN_IN_USE &&
            authStatus != AuthorizationStatus.ALWAYS
        ) {
            return "PERMISSION_DENIED"
        }

        LocationService.stopBootTracking()

        locationEngine.stop()
        motionDetector.stop()
        // NOTE: do NOT tear down the foreground service up-front here. When the
        // foreground-service periodic strategy is selected we want it to keep
        // running; stopping it and immediately restarting it below races the
        // ACTION_STOP / ACTION_START service commands — on a fresh start the
        // ACTION_STOP handler's stopSelf() can win and destroy the service right
        // after ACTION_START promoted it, leaving NO foreground service at all
        // (#237). The non-foreground branches below stop it explicitly instead.

        stateManager.enabled = true
        stateManager.trackingMode = TrackingMode.PERIODIC
        stateManager.isMoving = false

        PeriodicLocationWorker.eventSender = eventSender

        val interval = configManager.getPeriodicLocationInterval()
        val useForeground = configManager.getPeriodicUseForegroundService()
        val useExactAlarms = configManager.getPeriodicUseExactAlarms() ||
            (!useForeground && interval < 900)

        if (!useForeground && configManager.isRestrictedOem()) {
            logger.warning(
                "startPeriodic() without a foreground service on an aggressive OEM " +
                    "(${android.os.Build.MANUFACTURER}) — WorkManager/alarm delivery may be " +
                    "throttled or killed. Consider periodicUseForegroundService: true for reliability."
            )
        }

        if (useForeground) {
            if (configManager.isForegroundServiceEnabled()) {
                // Idempotent: re-delivers ACTION_START; if the service is already
                // running (e.g. switching from continuous mode) it stays foreground.
                LocationService.start(context)
            }
            locationEngine.startPeriodic()
        } else if (useExactAlarms) {
            // No foreground service in this strategy — tear down any left over
            // from a previous continuous/foreground-periodic session. This must
            // not be gated on isForegroundServiceEnabled(): when the new config
            // just disabled the service, the leftover from the previous config
            // still needs stopping (#243).
            if (LocationService.isServiceRunning()) {
                LocationService.stop(context)
            }
            if (!PeriodicLocationWorker.canScheduleExactAlarms(context)) {
                logger.warning(
                    "SCHEDULE_EXACT_ALARM not granted — timing will be approximate. " +
                        "Grant 'Alarms & reminders' permission in Settings for precise intervals."
                )
                // Auto-prompt: open exact alarm settings if an Activity is available
                if (activity != null) {
                    openExactAlarmSettings()
                }
            }
            PeriodicLocationWorker.scheduleOneTime(context)
            PeriodicLocationWorker.scheduleExactAlarm(context, interval)
        } else {
            // WorkManager strategy — no foreground service; tear down any left
            // over from a previous continuous/foreground-periodic session. Not
            // gated on isForegroundServiceEnabled() — see the exact-alarms
            // branch above (#243).
            if (LocationService.isServiceRunning()) {
                LocationService.stop(context)
            }
            PeriodicLocationWorker.schedule(context, interval)
            PeriodicLocationWorker.scheduleOneTime(context)
        }

        startHeartbeat()
        startStopAfterElapsedTimer()
        eventSender.sendEnabledChange(true)

        val strategy = when {
            useForeground -> "foreground-service"
            useExactAlarms -> "exact-alarms"
            else -> "workmanager"
        }
        logger.info(
            "startPeriodic() — periodic tracking started " +
                "(interval=${interval}s, strategy=$strategy)"
        )
        // #318/#324: see start(). The strategy is the whole diagnosis for "periodic
        // stopped firing overnight" — WorkManager is throttled in Doze, exact
        // alarms are not, and the foreground-service strategy is neither.
        TraceletLog.lifecycle(
            "session: start — mode=periodic interval=${interval}s strategy=$strategy"
        )
        return null
    }

    // =========================================================================
    // Config
    // =========================================================================

    /**
     * Update the SDK configuration using a typed [TraceletConfig].
     *
     * Delegates to [setConfig] with the map produced by [TraceletConfig.toMap].
     */
    fun setConfig(config: com.ikolvi.tracelet.sdk.model.TraceletConfig): Map<String, Any?> {
        return setConfig(config.toMap())
    }

    fun setConfig(config: Map<String, Any?>): Map<String, Any?> {
        if (!isReady) return mapOf(
            "enabled" to false, "isMoving" to false,
            "trackingMode" to TrackingMode.CONTINUOUS.value, "schedulerEnabled" to false, "odometer" to 0.0,
        )
        val oldConfig = configManager.getConfig()
        val merged = configManager.setConfig(config)

        if (merged["encryptDatabase"] == true) {
            val key = merged["encryptionKey"] as? String ?: ""
            rustDatabase?.setEncryptionKey(key)
        } else {
            rustDatabase?.setEncryptionKey("")
        }

        // Keys whose changes require the active native tracking pipeline to be
        // rebuilt with the new values. Previously only a handful of location
        // keys were watched and only locationEngine was restarted — motion
        // detector / speed manager / smart coordinator kept running on stale
        // parameters until the app was force-killed (#230).
        val locationKeys = listOf(
            "desiredAccuracy", "distanceFilter", "locationUpdateInterval",
            "fastestLocationUpdateInterval", "stationaryRadius", "deferTime",
            "disableElasticity", "elasticityMultiplier",
        )
        val motionKeys = listOf(
            "motionDetectionMode", "shakeThreshold", "stillThreshold", "stillSampleCount",
            "stopTimeout", "motionTriggerDelay", "stopDetectionDelay", "disableStopDetection",
            "stopOnStationary", "triggerActivities", "minimumActivityRecognitionConfidence",
            "activityRecognitionInterval", "disableMotionActivityUpdates",
            "speedMovingThreshold", "speedStationaryDelay", "speedWakeConfirmCount",
            "stationaryTrackingMode", "stationaryPeriodicInterval", "stationaryPeriodicAccuracy",
        )
        // #303: the four thresholds transport-mode auto-tuning swaps. They reach
        // the processor through setBaseTuning, which preserves the positional
        // anchor — a rebuild would drop it and forfeit an odometer delta (#299).
        val tuningKeys = listOf(
            "distanceFilter", "trackingAccuracyThreshold",
            "odometerAccuracyThreshold", "maxImpliedSpeed",
        )
        // #303: the remaining LocationProcessor constructor parameters. These are
        // immutable in Rust, so changing one genuinely needs a rebuild — but not
        // a full pipeline restart, which is why they are kept out of
        // [needsRestart]. Every one of them used to be silently ignored until the
        // next cold start.
        val processorKeys = listOf(
            "filterPolicy", "enableAdaptiveMode", "rejectMockLocations",
            "mockDetectionLevel", "enableSparseUpdates", "sparseDistanceThreshold",
            "sparseMaxIdleSeconds",
        )
        val needsRestart = (locationKeys + motionKeys).any { key -> oldConfig[key] != merged[key] }
        val changed = { keys: List<String> -> keys.any { key -> oldConfig[key] != merged[key] } }

        if (stateManager.enabled) {
            if (needsRestart) {
                logger.info("setConfig: tracking-relevant config changed — restarting active pipeline")
                // Preserve the active tracking mode and motion state across the
                // clean stop/start so the device doesn't silently revert to a
                // stationary continuous default.
                val currentMode = stateManager.trackingMode
                val wasMoving = stateManager.isMoving

                // #256: in SPEED/SMART motion-detection modes the SDK runs a single
                // continuous motion-aware pipeline that TEMPORARILY flips
                // stateManager.trackingMode to PERIODIC/GEOFENCES while the device
                // is stationary (LocationService.switchToStationaryPeriodic /
                // switchToStationaryGeofences). That temporary value is NOT an
                // explicitly-started standalone mode — rebuilding it via
                // startPeriodic()/startGeofences() tears down the very
                // motion-detection pipeline that is supposed to switch it back to
                // continuous once the device moves again, stranding tracking in a
                // standalone stationary mode. Restart the continuous pipeline via
                // start(isResume = true) instead; it re-enters the stationary
                // sub-state on its own when still stationary. Mirrors the
                // resume-on-ready logic in completeReady().
                val motionMode = configManager.getMotionDetectionMode()
                val motionAware =
                    motionMode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART ||
                    motionMode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SPEED

                // #254: if the restart lands back in a mode that still needs the
                // foreground service, DON'T let stop() send ACTION_STOP — the
                // immediately-following ACTION_START from the start*() below would
                // race it and stopSelf() could destroy the freshly-promoted
                // service, leaving no foreground service at all (same race as
                // #237). Keep it alive and let the idempotent ACTION_START
                // re-assert foreground. When the target mode does NOT use the
                // service (periodic-without-fg / standard geofences / fg disabled)
                // we stop it here cleanly — there's no follow-up start to race.
                val keepForegroundService = configManager.isForegroundServiceEnabled() && when {
                    // Motion-aware pipeline restarts as continuous — it runs the
                    // foreground service exactly like TrackingMode.CONTINUOUS.
                    motionAware -> true
                    currentMode == TrackingMode.CONTINUOUS -> true
                    currentMode == TrackingMode.PERIODIC -> configManager.getPeriodicUseForegroundService()
                    currentMode == TrackingMode.GEOFENCES -> configManager.getGeofenceModeHighAccuracy()
                    else -> false
                }

                stop(preserveForegroundService = keepForegroundService)

                stateManager.enabled = true
                stateManager.trackingMode = currentMode
                stateManager.isMoving = wasMoving

                // Rebuild the Rust processor so distanceFilter/elasticity/etc.
                // changes take effect on the very first fix after restart (#157).
                if (::locationEngine.isInitialized) locationEngine.rebuildProcessor()

                if (motionAware) {
                    start(isResume = true)
                } else {
                    when (currentMode) {
                        TrackingMode.CONTINUOUS -> start(isResume = true)
                        TrackingMode.PERIODIC -> startPeriodic()
                        TrackingMode.GEOFENCES -> startGeofences(isResume = true)
                    }
                }
            }
        } else if (needsRestart && ::locationEngine.isInitialized) {
            // Not actively tracking — still rebuild the processor so the next
            // start() picks up the new location config without a stale cache.
            locationEngine.rebuildProcessor()
        }

        // #303: carry the rest of the location-filter config into the processor.
        // Only the handful of keys in `locationKeys` ever reached it; everything
        // else was accepted, cached, and ignored until the next cold start.
        //
        // Ordered cheapest-effect-first, and skipped entirely when a restart
        // already rebuilt the processor from current config above.
        if (::locationEngine.isInitialized && !needsRestart) {
            when {
                // Constructor-only parameters: nothing short of a rebuild moves
                // them. No anchor to protect that a restart wouldn't drop anyway.
                changed(processorKeys) -> locationEngine.rebuildProcessor()
                // Thresholds: swap in place so the odometer anchor survives.
                changed(tuningKeys) -> locationEngine.applyConfiguredBaseTuning()
            }
        }
        // Independent of the processor — the filter is its own object, so a
        // toggle must never cost the anchor.
        if (::locationEngine.isInitialized) locationEngine.syncKalmanFilter()

        // Behavior engines (telematics / transport / crash-fall + ML model) are
        // built in initBehaviorEngines() at ready(). Rebuild them when any of
        // their config changes at runtime — otherwise toggling crash detection or
        // supplying a license key via setConfig() would never (re)load the ML
        // crash model. initBehaviorEngines() is idempotent.
        val behaviorKeys = listOf(
            "enableDrivingEvents", "enableFusedClassifier",
            "autoTuneFromTransportMode",
            "enableCrashDetection", "enableFallDetection",
            "crashModelUrl", "crashModelUnlockUrl", "crashModelLicenseKey",
            "crashModelSha256", "crashModelThreshold",
        )
        if (behaviorKeys.any { key -> oldConfig[key] != merged[key] }) {
            initBehaviorEngines()
            // #301: initBehaviorEngines() creates the classifier but only start()
            // ever started the ~1 Hz accel-window loop that drives it. Enabling
            // the classifier mid-session therefore produced a classifier that
            // never classified — and, with auto-tuning on, never retuned.
            // startBehaviorSampling() stops the old loop first and no-ops when
            // there is no consumer, so this is safe to call unconditionally.
            if (stateManager.enabled) startBehaviorSampling()
        }

        // #301: any of the above can leave the processor's thresholds out of step
        // with the committed transport mode — a rebuilt processor has dropped an
        // active auto-tune, and a disabled auto-tune has left one in force.
        syncTransportModeTuning()

        // The battery-budget engine is built at ready() from batteryBudgetPerHour
        // and is otherwise never touched here — so enabling/disabling/retargeting
        // the budget at runtime (e.g. a remote-config push of
        // {"geo":{"batteryBudgetPerHour":1.0}}) previously had no effect until the
        // app was cold-started. Rebuild it when the target changes, and (re)start
        // or stop sampling to match the live tracking state.
        if (oldConfig["batteryBudgetPerHour"] != merged["batteryBudgetPerHour"]) {
            applyBatteryBudgetConfig()
            if (stateManager.enabled) {
                // startBatteryBudgetSampling() removes any pending callback first
                // and returns early when the engine is null, so this both starts a
                // newly-enabled budget and halts a newly-disabled one.
                startBatteryBudgetSampling()
            }
        } else if (oldConfig["distanceFilter"] != merged["distanceFilter"] ||
            oldConfig["desiredAccuracy"] != merged["desiredAccuracy"] ||
            oldConfig["periodicLocationInterval"] != merged["periodicLocationInterval"]
        ) {
            // The ladder is expressed relative to the app's own parameters, so a
            // change to those has to reach it — otherwise an overlay in force
            // would keep enforcing rungs measured from the previous
            // configuration (#396).
            syncBatteryBudgetConfigured()
        }

        updateBootReceiverState()
        syncConfigToRustFlat()
        checkSyncProvider()
        return stateManager.toMap(merged)
    }

    /**
     * Refreshes the active foreground-service notification so it reflects the
     * latest ForegroundServiceConfig applied via [setConfig], without
     * restarting the tracking pipeline (#257).
     *
     * Safe no-op when the foreground service is not currently running: the
     * dispatched ACTION_UPDATE_NOTIFICATION only reposts the notification when
     * the service is already promoted to the foreground.
     */
    fun updateNotification() {
        if (!LocationService.isServiceRunning()) {
            logger.info("updateNotification: foreground service not running — nothing to refresh")
            return
        }
        LocationService.updateNotification(context)
    }

    /**
     * Bootstraps the SDK for a headless / boot / task-removal restart.
     *
     * Returns `true` only when initialization has fully completed and the
     * lateinit subsystems (Rust DB, [geofenceManager], engines) are ready to
     * use. Returns `false` if init did not finish within the timeout, threw, or
     * left the DB/managers unassigned.
     *
     * This mirrors [ready], which already blocks on [initCompleteLatch] before
     * touching those subsystems. Previously this method kicked off [initialize]
     * (which runs on a background `tracelet-init` thread) and returned
     * immediately, so a caller like [LocationService.startBootTracking] could
     * read the still-unassigned [geofenceManager] and crash with
     * `UninitializedPropertyAccessException` on a cold boot (#264). Callers MUST
     * check the return value and bail out (stop/defer) instead of touching any
     * manager when it is `false`.
     */
    internal fun bootstrapForBackground(sender: TraceletEventSender): Boolean {
        if (!::eventSender.isInitialized) {
            setEventSender(sender)
        }
        // The boot / task-removal path (LocationService.onStartCommand →
        // startBootTracking) reads lateinit managers (geofenceManager,
        // locationEngine) as soon as this returns. Since initialize() runs its
        // heavy setup on the background "tracelet-init" thread, we must wait for
        // it to finish here — otherwise the service touches an unassigned
        // lateinit and crashes in onStartCommand ("lateinit property
        // geofenceManager has not been initialized"). Do NOT gate on
        // `rustDatabase == null`: rustDatabase is assigned early inside
        // initializeInternal, well before geofenceManager, so that check can
        // pass while the managers are still unset. initialize() is idempotent
        // (initStarted guard), so calling it unconditionally both starts init
        // when this is the first entry point and joins an in-flight init begun
        // by an engine attach; awaitInit() then blocks until it completes.
        initialize()
        // Block until the background init thread finishes wiring the DB and
        // lateinit managers (same contract ready() relies on). awaitInit()
        // returns false on timeout OR init failure. Do NOT proceed to touch
        // managers if it returns false.
        if (!awaitInit()) {
            logger.error("bootstrapForBackground: init not ready (timeout or failure) — deferring boot tracking")
            return false
        }
        // Defensive: the latch is released even on failure, so re-check the
        // actual lateinit state before returning success.
        if (rustDatabase == null || !::geofenceManager.isInitialized) {
            logger.error("bootstrapForBackground: DB/geofenceManager not initialized after init — deferring boot tracking")
            return false
        }

        // Initialize the behavior engines (telematics / transport / crash-fall) in
        // the background process too. Without this they stay null after a reboot or
        // task-removal restart, silently disabling crash and driving diagnostics
        // while the app UI is killed (#214). Honors the same config flags as ready().
        initBehaviorEngines()
        checkSyncProvider()
        return true
    }

    internal fun checkSyncProvider() {
        val url = configManager.getHttpUrl()
        if (!url.isNullOrEmpty() && syncProvider == null) {
            try {
                val clazz = Class.forName("com.ikolvi.tracelet.sdk.sync.NativeSyncProvider")
                val constructor = clazz.getConstructor(TraceletSdk::class.java)
                val instance = constructor.newInstance(this)
                val sink = instance as LocationDataSink
                if (::locationEngine.isInitialized) {
                    locationEngine.registerSink(sink)
                }
                syncProvider = instance as SyncProvider
                logger.info("NativeSyncProvider loaded for background sync.")
            } catch (e: Throwable) {
                logger.warning("⚠️ WARNING [Tracelet]: Failed to load NativeSyncProvider (tracelet_sync may be absent): ${e.message}")
            }
        }
    }

    fun reset(newConfig: Map<String, Any?>?) {
        if (!isReady) return
        locationEngine.destroy()
        motionDetector.stop()
        stopHeartbeat()
        stopSyncIntervalTimer()
        remoteConfigManager.stop()
        geofenceManager.destroy()
        LocationService.stop(context)

        stateManager.reset()
        configManager.reset(newConfig)
        isReady = false

        logger.info("reset() — all subsystems reset")
    }

    // =========================================================================
    // Location
    // =========================================================================

    fun getCurrentPosition(
        options: Map<String, Any?>,
        callback: (Map<String, Any?>?) -> Unit,
    ) {
        if (!isReady) { callback(null); return }
        locationEngine.getCurrentPosition(options, callback)
    }

    fun cancelCurrentPosition(requestId: String): Boolean {
        if (!isReady) return false
        return locationEngine.cancelCurrentPosition(requestId)
    }

    fun getLastKnownLocation(
        options: Map<String, Any?>,
        callback: (Map<String, Any?>?) -> Unit,
    ) {
        if (!isReady) { callback(null); return }
        locationEngine.getLastKnownLocation(options, callback)
    }

    fun watchPosition(options: Map<String, Any?>): Int {
        if (!isReady) return -1
        return locationEngine.watchPosition(options)
    }

    fun stopWatchPosition(watchId: Int): Boolean {
        if (!isReady) return false
        return locationEngine.stopWatchPosition(watchId)
    }

    fun changePace(isMoving: Boolean): Map<String, Any?> {
        if (!isReady) return mapOf(
            "enabled" to false, "isMoving" to false,
            "trackingMode" to TrackingMode.CONTINUOUS.value, "schedulerEnabled" to false, "odometer" to 0.0,
        )
        
        val mode = configManager.getMotionDetectionMode()
        if (mode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SPEED) {
            if (::speedMotionManager.isInitialized) {
                speedMotionManager.onManualPaceChange(isMoving)
            }
        } else if (mode == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART) {
            if (::speedMotionManager.isInitialized) {
                speedMotionManager.onManualPaceChange(isMoving)
            }
            if (::motionDetector.isInitialized) {
                motionDetector.onManualPaceChange(isMoving)
            }
            if (::smartMotionCoordinator.isInitialized) {
                smartMotionCoordinator.onManualPaceChange(isMoving)
            }
        } else {
            locationEngine.changePace(isMoving)
            // Re-sync MotionDetector's sensor state so it can wake the SDK back up
            // on real motion after a manual changePace(false). Without this, the
            // accelerometer + significant-motion listeners stay torn down and we
            // can never recover from the forced-stationary state.
            if (::motionDetector.isInitialized) {
                motionDetector.onManualPaceChange(isMoving)
            }
        }
        return stateManager.toMap(configManager.getConfig())
    }

    /**
     * Temporarily overrides the active location provider's acquisition policy.
     *
     * Unlike setConfig, this does not persist configuration, rebuild the
     * location processor, or restart the tracking pipeline — the existing
     * tracking callback is re-subscribed in place with the new request.
     * [desiredAccuracy] uses the config accuracy codes (0=high … 4=passive).
     * Passing null for both values restores the configured provider options;
     * stop() also clears the override.
     */
    fun updateLocationProviderOptions(desiredAccuracy: Int?, distanceFilter: Double?): Boolean {
        if (!isReady || !::locationEngine.isInitialized) return false
        return locationEngine.updateLocationProviderOptions(desiredAccuracy, distanceFilter)
    }

    fun getOdometer(): Double {
        if (!isReady) return 0.0
        return locationEngine.getOdometer()
    }

    fun setOdometer(value: Double): Map<String, Any?> {
        if (!isReady) return mapOf(
            "enabled" to false, "isMoving" to false,
            "trackingMode" to TrackingMode.CONTINUOUS.value, "schedulerEnabled" to false, "odometer" to 0.0,
        )
        return locationEngine.setOdometer(value)
    }

    // =========================================================================
    // Geofences
    // =========================================================================

    fun addGeofence(geofence: Map<String, Any?>): Boolean {
        if (!isReady) return false
        return geofenceManager.addGeofence(geofence)
    }

    /** Add a geofence using a typed [TraceletGeofence] model. */
    fun addGeofence(geofence: com.ikolvi.tracelet.sdk.model.TraceletGeofence): Boolean {
        return addGeofence(geofence.toMap())
    }

    fun addGeofences(geofences: List<Map<String, Any?>>) {
        if (!isReady) return
        geofenceManager.addGeofences(geofences)
    }

    /** Add multiple geofences using typed [TraceletGeofence] models. */
    fun addTypedGeofences(geofences: List<com.ikolvi.tracelet.sdk.model.TraceletGeofence>) {
        addGeofences(geofences.map { it.toMap() })
    }

    fun removeGeofence(identifier: String): Boolean {
        if (!isReady) return false
        return geofenceManager.removeGeofence(identifier)
    }

    fun removeGeofences(): Boolean {
        if (!isReady) return false
        return geofenceManager.removeGeofences()
    }

    fun getGeofences(): List<Map<String, Any?>> {
        return geofenceManager.getGeofences()
    }

    fun getGeofence(identifier: String): Map<String, Any?>? {
        return geofenceManager.getGeofence(identifier)
    }

    fun geofenceExists(identifier: String): Boolean {
        return geofenceManager.geofenceExists(identifier)
    }

    // =========================================================================
    // Persistence
    // =========================================================================

    fun getLocations(query: Map<String, Any?>?): List<Map<String, Any?>> {
        if (!isReady) return emptyList()
        val db = rustDatabase ?: return emptyList()
        
        val startTimeMs = (query?.get("start") as? Number)?.toLong() ?: (query?.get("from") as? Number)?.toLong()
        val endTimeMs = (query?.get("end") as? Number)?.toLong() ?: (query?.get("to") as? Number)?.toLong()
        val limit = (query?.get("limit") as? Number)?.toInt()
        val offset = (query?.get("offset") as? Number)?.toInt()
        val orderDescending = (query?.get("order") as? Number)?.toInt()?.let { it == 1 }
        
        val rustQuery = uniffi.tracelet_core.LocationQuery(
            startTimeMs = startTimeMs,
            endTimeMs = endTimeMs,
            limit = limit,
            offset = offset,
            orderDescending = orderDescending
        )
        
        return try {
            val records = db.getLocationsBatch(rustQuery)
            records.map { mapRecordToLocation(it) }
        } catch (e: Exception) {
            logger.error("getLocations failed: ${e.message}")
            emptyList()
        }
    }

    /**
     * Canonical mapping of a persisted [uniffi.tracelet_core.DbLocationRecord]
     * into the nested location schema used by `onLocation` and `getLocations`.
     *
     * Single source of truth so every consumer (getLocations + the sync
     * interceptor sinks) emits an identical shape and restores
     * `route_context` / audit-hash metadata (Issue #126). See [LocationMapper].
     */
    fun mapRecordToLocation(record: uniffi.tracelet_core.DbLocationRecord): Map<String, Any?> {
        val odometer = if (::locationEngine.isInitialized) locationEngine.getOdometer() else 0.0
        return com.ikolvi.tracelet.sdk.location.LocationMapper.buildLocationMap(
            id = record.id,
            uuid = record.uuid,
            timestamp = record.timestamp,
            latitude = record.latitude,
            longitude = record.longitude,
            altitude = record.altitude,
            speed = record.speed,
            heading = record.heading,
            accuracy = record.accuracy,
            isMock = record.isMock,
            activity = record.activity,
            activityConfidence = record.activityConfidence,
            routeContext = record.routeContext,
            isMoving = record.isMoving,
            odometer = odometer,
            eventType = record.eventType,
            eventPayload = record.eventPayload,
            address = record.address,
        )
    }

    fun getCount(query: Map<String, Any?>?): Int {
        if (!isReady) return 0
        val db = rustDatabase ?: return 0
        return try {
            val startTimeMs = (query?.get("start") as? Number)?.toLong()
                ?: (query?.get("from") as? Number)?.toLong()
            val endTimeMs = (query?.get("end") as? Number)?.toLong()
                ?: (query?.get("to") as? Number)?.toLong()
            if (startTimeMs == null && endTimeMs == null) {
                // No time filter — use the efficient native COUNT(*).
                db.getLocationsCount()
            } else {
                // The native get_locations_count ignores time bounds (#152), so a
                // filtered getCount() would otherwise return the whole-DB total.
                // Honor the query by counting the query-aware batch instead.
                db.getLocationsBatch(
                    uniffi.tracelet_core.LocationQuery(
                        startTimeMs = startTimeMs,
                        endTimeMs = endTimeMs,
                        limit = null,
                        offset = null,
                        orderDescending = null,
                    )
                ).size
            }
        } catch (e: Exception) {
            logger.error("getCount failed: ${e.message}")
            0
        }
    }

    fun destroyLocations(): Boolean {
        if (!isReady) return false
        val db = rustDatabase ?: return false
        return try {
            db.destroyLocations()
            true
        } catch (e: Exception) {
            logger.error("destroyLocations failed: ${e.message}")
            false
        }
    }

    /**
     * Destroys (clears) locations that have already been synced to the backend,
     * returning the number removed (#154).
     *
     * The Rust Core prunes each location from the local store the moment it is
     * confirmed synced (see [sync] / `clearLocationsUpTo`), so there is never a
     * "synced but still persisted" row to delete on demand. This method therefore
     * reports and resets the running total of locations that have been
     * synced-and-pruned since it was last called — a real, DB-backed figure
     * rather than the previous hardcoded `0` stub. Callers that have not synced
     * anything since the last call correctly receive `0`.
     */
    fun destroySyncedLocations(): Int {
        if (!isReady) return 0
        return syncedLocationsRemoved.getAndSet(0L).toInt()
    }

    /**
     * Destroys a single persisted location identified by its public UUID (#251).
     *
     * The public location identifier is a UUID string, not the internal numeric
     * database id. Previously this parsed the argument with `toLongOrNull()` and
     * bailed out for any real UUID (e.g. `36ef46cf-…`), so pending locations
     * could never be acknowledged. We now resolve the UUID to its row id via the
     * database and delete that record. A purely numeric argument still works
     * (treated as a raw row id) for backward compatibility.
     */
    fun destroyLocation(uuid: String): Boolean {
        if (!isReady) return false
        val db = rustDatabase ?: return false
        return try {
            val id = db.getLocationForAudit(uuid)?.id ?: uuid.toLongOrNull()
            if (id == null) {
                logger.warning("destroyLocation: no location found for uuid=$uuid")
                return false
            }
            db.destroyLocation(id)
            true
        } catch (e: Exception) {
            logger.error("destroyLocation failed: ${e.message}")
            false
        }
    }

    /**
     * Caches the timestamp of the last inserted location to prevent duplicate 
     * DB writes from the same GPS fix (e.g. from PeriodicLocationWorker).
     */
    private var lastInsertedTimestamp: String? = null

    /**
     * Persists a geofence ENTER/EXIT record only if allowed by persistMode (#383).
     *
     * The geofence counterpart of `LocationEngine.persistLocationIfAllowed` — geofence
     * transitions used to be wired straight to [insertLocation], so `location` and
     * `none` still wrote (and HTTP-synced) every crossing despite documenting otherwise.
     *
     * Only the DB write is gated. The listener event is dispatched separately by
     * `GeofenceManager` via `events.sendGeofence`, so `none` keeps its documented
     * "events are still fired" behaviour.
     *
     * Read live rather than latched at setup, so a `setConfig` mid-session takes
     * effect on the next transition.
     */
    private fun persistGeofenceIfAllowed(eventMap: Map<String, Any?>) {
        if (!configManager.shouldPersistGeofenceRecords()) return
        insertLocation(eventMap)
    }

    /**
     * Inserts a location record into the Rust database and notifies registered sync sinks.
     * Prevents duplicate insertions of the exact same GPS fix based on the timestamp.
     */
    fun insertLocation(params: Map<String, Any?>): String {
        // Persist whenever the Rust DB is initialized — NOT only when isReady.
        // The headless boot/background path (bootstrapForBackground) wires the
        // DB and sync provider but never calls ready() (no Dart UI), so isReady
        // stays false. Gating on isReady here silently dropped every location
        // captured after a reboot, so the DB stayed empty and auto-sync (which
        // reads from the DB) had nothing to send. The db null-check below is the
        // correct readiness signal for persistence.
        val db = rustDatabase ?: return ""
        val coords = (params["coords"] as? Map<*, *>) ?: params
        val lat = (coords["latitude"] as? Number)?.toDouble() ?: 0.0
        val lng = (coords["longitude"] as? Number)?.toDouble() ?: 0.0
        val acc = (coords["accuracy"] as? Number)?.toDouble() ?: 0.0
        val speed = (coords["speed"] as? Number)?.toDouble() ?: 0.0
        val heading = (coords["heading"] as? Number)?.toDouble() ?: 0.0
        val altitude = (coords["altitude"] as? Number)?.toDouble() ?: 0.0
        val isMock = params["mock"] == true || params["is_mock"] == true
        val isMoving = params["is_moving"] == true
        val activityMap = params["activity"] as? Map<*, *>
        val activity = (activityMap?.get("type") as? String) ?: "unknown"
        val activityConfidence = (activityMap?.get("confidence") as? Number)?.toInt() ?: -1
        val timestamp = params["timestamp"] as? String
        val uuid = params["uuid"] as? String
        val eventType = (params["event"] as? String) ?: "location"
        val eventPayload: String? = (params["event_payload"] as? String)
            ?: (params["geofence"] as? Map<*, *>)?.let { org.json.JSONObject(it as Map<String, Any?>).toString() }
        // #187: persist the reverse-geocoded address (added by resolveAddress) so
        // it survives into the DB-sourced sync payload, not just the live event.
        val address: String? = (params["address"] as? String)
            ?: (params["address"] as? Map<*, *>)?.let { org.json.JSONObject(it as Map<String, Any?>).toString() }
        
        // Prevent duplicate insertions of the exact same GPS fix (e.g. from
        // PeriodicLocationWorker). The heartbeat writer tags the last GPS fix
        // with event="heartbeat"; it must share the location writer's dedup key
        // so a fix already persisted by the normal dispatch is never re-inserted
        // as a byte-identical duplicate row (the iOS #252 gap — kept in parity
        // here even though the Android heartbeat currently does not persist).
        val persistsGpsFix = eventType == "location" || eventType == "heartbeat"
        if (persistsGpsFix && timestamp != null && timestamp == lastInsertedTimestamp) {
            return ""
        }
        if (persistsGpsFix) { lastInsertedTimestamp = timestamp }
        
        var routeContext = rustEngineState?.getRouteContext()

        // Audit trail (Enterprise): the canonical place audit links are created.
        // The LocationEngine.dispatch() path pre-computes `audit_hash` and passes
        // it in `params`. But background/headless persists — PeriodicLocationWorker,
        // LocationService, geofence events — call insertLocation() directly and
        // never went through dispatch(), so they previously skipped the chain
        // entirely. That left location_events rows with no matching audit_trail
        // row, so getAuditProof() returned null for any such record. Generate the
        // audit link here when it wasn't pre-computed, so EVERY persisted location
        // is covered regardless of source.
        var auditHash = params["audit_hash"] as? String
        var auditPrevHash = params["audit_previous_hash"]
        var auditChainIndex = params["audit_chain_index"]
        if (auditHash == null && uuid != null && ::auditTrailManager.isInitialized) {
            val auditFields = try {
                auditTrailManager.appendToChain(params)
            } catch (e: Exception) {
                logger.error("audit appendToChain failed: ${e.message}")
                null
            }
            if (auditFields != null) {
                auditHash = auditFields["audit_hash"] as? String
                auditPrevHash = auditFields["audit_previous_hash"]
                auditChainIndex = auditFields["audit_chain_index"]
            }
        }
        val batteryMap = params["battery"] as? Map<*, *>
        val extrasMap = params["extras"] as? Map<*, *>
        // #280: persist the location-source classification so it survives into
        // DB-sourced reads (getLocations) and the sync payload, instead of only
        // living on the live onLocation event. Stored as first-class
        // route_context keys (like audit_*), not inside extras.
        val locationSource = (params["locationSource"] as? String)?.takeIf { it.isNotEmpty() }
        val reducedAccuracy = params["reducedAccuracy"] as? Boolean

        if (auditHash != null || batteryMap != null || (extrasMap != null && extrasMap.isNotEmpty()) ||
            locationSource != null || reducedAccuracy != null
        ) {
            try {
                val jsonMap = if (routeContext != null) {
                    org.json.JSONObject(routeContext)
                } else {
                    org.json.JSONObject()
                }
                if (auditHash != null) {
                    jsonMap.put("audit_hash", auditHash)
                    if (auditPrevHash != null) jsonMap.put("audit_previous_hash", auditPrevHash)
                    if (auditChainIndex != null) jsonMap.put("audit_chain_index", auditChainIndex)
                }
                if (batteryMap != null) {
                    val bObj = org.json.JSONObject()
                    batteryMap["level"]?.let { bObj.put("level", it) }
                    batteryMap["is_charging"]?.let { bObj.put("is_charging", it) }
                    batteryMap["isCharging"]?.let { bObj.put("isCharging", it) }
                    jsonMap.put("battery", bObj)
                }
                if (extrasMap != null && extrasMap.isNotEmpty()) {
                    jsonMap.put("extras", org.json.JSONObject(extrasMap as Map<*, *>))
                }
                if (locationSource != null) {
                    jsonMap.put("locationSource", locationSource)
                }
                if (reducedAccuracy != null) {
                    jsonMap.put("reducedAccuracy", reducedAccuracy)
                }
                routeContext = jsonMap.toString()
            } catch (e: Exception) {
                // Ignore and use base route context
            }
        }

        return try {
            val newRowId = db.insertLocation(uuid, lat, lng, acc, speed, heading, altitude, isMock, isMoving, activity, activityConfidence, routeContext, timestamp, eventType, eventPayload, address)
            enforceRetentionCaps(db)
            // Notify the sync plugin so it can trigger auto-sync
            (syncProvider as? com.ikolvi.tracelet.sdk.location.LocationDataSink)?.insertLocation(params)
            newRowId.toString()
        } catch (e: Exception) {
            logger.error("insertLocation failed: ${e.message}")
            ""
        }
    }

    /** Location inserts seen this process. See [enforceRetentionCaps]. */
    private var locationInsertsSeen = 0L

    /**
     * Applies `maxDaysToPersist` and `maxRecordsToPersist` to `location_events`
     * (#361).
     *
     * Both caps were accepted by `ready()`/`setConfig()`, echoed back in
     * `State.config` — and enforced by nothing, so the local queue grew without
     * bound however they were set. They were real up to 3.0 via `pruneOldLocations`
     * / `enforceMaxRecords` on the Kotlin `TraceletDatabase`; the 3.1.0 migration
     * onto the Rust core replaced the persist body with a sink fan-out and deleted
     * the retention calls with it, leaving [PRUNE_EVERY_N_INSERTS] and a docstring
     * behind as the only trace.
     *
     * Deliberately here rather than back in `LocationEngine.persistLocationIfAllowed`,
     * where the leftover counter sat: this is the single funnel every location
     * reaches the DB through. The engine's persist path is only one caller — the
     * public `Tracelet.insertLocation()` API and the headless boot path insert
     * straight through here, and pruning in the engine would have left the
     * reporter's own repro (100+ explicit `insertLocation` calls) still unbounded.
     *
     * Amortized over [PRUNE_EVERY_N_INSERTS] inserts rather than run on each one,
     * so a COUNT-and-DELETE is not attached to every GPS fix. The queue can
     * therefore sit up to that many records above `maxRecordsToPersist` between
     * prunes; the cap bounds growth, it is not a per-insert invariant. The first
     * insert of the process prunes, so a cap tightened while stopped — or a backlog
     * inherited from a build that never enforced one — is cut down without waiting
     * out a whole window.
     *
     * A retention failure must not fail the insert: the record is already committed
     * and losing it to a prune error would be strictly worse than an oversized
     * queue.
     *
     * The counter is deliberately unsynchronized, like [lastInsertedTimestamp]
     * above it. Inserts arrive from both the location callback thread and the
     * public API, so a racy increment can make a prune land an insert early or
     * late — which costs nothing, and is cheaper than serializing every insert
     * behind a lock to schedule a periodic DELETE precisely.
     */
    private fun enforceRetentionCaps(db: RustDatabaseManager) {
        if (locationInsertsSeen++ % PRUNE_EVERY_N_INSERTS != 0L) return
        try {
            val maxDays = configManager.getMaxDaysToPersist()
            val maxRecords = configManager.getMaxRecordsToPersist()
            val byAge = db.pruneLocationsOlderThan(maxDays)
            val byCount = db.enforceMaxLocationRecords(maxRecords)
            if (byAge > 0u || byCount > 0u) {
                logger.debug(
                    "Retention: pruned $byAge location(s) older than $maxDays day(s), " +
                        "$byCount over the $maxRecords-record cap.",
                )
            }
        } catch (e: Exception) {
            logger.error("Retention pruning failed: ${e.message}")
        }
    }

    // =========================================================================
    // HTTP Sync
    // =========================================================================

    fun sync(callback: (List<Map<String, Any?>>) -> Unit) {
        val db = rustDatabase
        val state = rustEngineState
        val provider = syncProvider
        if (!isReady || db == null || state == null) {
            callback(emptyList())
            return
        }
        
        if (provider == null) {
            logger.error("Sync failed: No SyncProvider registered (is tracelet_sync installed?)")
            callback(emptyList())
            return
        }

        Thread {
            try {
                val config = state.getConfig()
                val batchSize = if (config.http.maxBatchSize > 0) config.http.maxBatchSize else 250
                val records = db.getLocationsBatch(uniffi.tracelet_core.LocationQuery(
                    startTimeMs = null,
                    endTimeMs = null,
                    limit = batchSize.toInt(),
                    offset = null,
                    orderDescending = null
                ))
                var configHttp = config.http
                // #370: this read `getConfig()["http"]["syncTelematics"]`, but
                // ConfigManager.setConfig flattens Dart's nested sections into
                // the top level — so `["http"]` was always null and the flag was
                // always false. syncTelematics never took effect here, whatever
                // the app configured. Use the accessor that knows the cache is
                // flat, as getSyncTelematics/getTelematicsUrl already do.
                val syncTelematics = configManager.getSyncTelematics()

                // #366: the id range we attach, so a *successful* upload can mark
                // exactly those synced. This used to be a bare boolean that fed an
                // unconditional `clearTelematicsEvents()` — a table-wide DELETE
                // that ran even when the POST had failed, so an offline device
                // destroyed its driving events instead of queueing them, and a
                // successful one also took any event recorded after the batch was
                // read. 0 means nothing was attached.
                var attachedTelematicsMaxId = 0L
                // #368: a separate endpoint means the telematics travel on their
                // own request, so they must not also ride the location payload.
                val telematicsUrl = configManager.getTelematicsUrl()?.takeIf { it.isNotBlank() }
                var telematicsToPost: List<uniffi.tracelet_core.DbTelematicsRecord> = emptyList()
                if (syncTelematics) {
                    val telematics = db.getTelematicsEvents(250)
                    if (telematics.isNotEmpty()) {
                        attachedTelematicsMaxId = telematics.maxOf { it.id }
                        if (telematicsUrl != null) {
                            telematicsToPost = telematics
                        } else {
                            val newExtras = (configHttp.extras ?: emptyMap()).toMutableMap()
                            newExtras["__telematics"] = telematicsJsonArray(telematics).toString()
                            configHttp = configHttp.copy(extras = newExtras)
                        }
                    }
                }

                val hasTelematics = attachedTelematicsMaxId > 0L
                if (records.isEmpty() && !hasTelematics) {
                    mainHandler.post { callback(emptyList()) }
                    return@Thread
                }

                // #368: posted before the locations so a telematics-only sync still
                // has something to do when `records` is empty.
                val telematicsPosted = if (telematicsToPost.isNotEmpty()) {
                    postTelematicsBatch(telematicsUrl!!, configHttp, telematicsToPost)
                } else {
                    false
                }

                // Skipping the location POST is only safe when the telematics
                // already went somewhere else (#368). On the default path they
                // ride this request, so it must still be made even with an empty
                // batch — otherwise they would sit unsynced until a location
                // happened along.
                val count = if (records.isEmpty() && telematicsUrl != null) {
                    0L
                } else {
                    provider.syncBatchBlocking(configHttp, records)
                }

                // #366: telematics are only settled when the request that carried
                // them actually succeeded. Attached to the location payload, that
                // is the location POST; sent to `telematicsUrl`, it is their own.
                // Anything else leaves them unsynced for the next attempt.
                val telematicsDelivered = if (telematicsUrl != null) telematicsPosted else count > 0L
                if (count > 0L || telematicsDelivered) {
                    if (count > 0L) {
                        val syncedCount = count.toInt()
                        val successfullySynced = records.take(syncedCount)
                        successfullySynced.lastOrNull()?.let { lastRecord ->
                            db.clearLocationsUpTo(lastRecord.id)
                            syncedLocationsRemoved.addAndGet(count)
                        }
                    }
                    if (telematicsDelivered && attachedTelematicsMaxId > 0L) {
                        // Mark, don't delete: #313 requires an uploaded event to
                        // stay visible in the app's own history. Bounded by the
                        // synced-tail trim below so the table can't grow forever.
                        db.markTelematicsSynced(attachedTelematicsMaxId)
                        db.pruneSyncedTelematics(MAX_SYNCED_TELEMATICS_RETAINED)
                    }
                    logger.info("TraceletSdk: Synced locations ($count) and telematics ($telematicsDelivered)")
                } else if (hasTelematics) {
                    logger.info(
                        "TraceletSdk: sync failed; telematics up to id $attachedTelematicsMaxId " +
                            "kept unsynced for the next attempt",
                    )
                }
                
                mainHandler.post {
                    callback(emptyList()) // Return empty to indicate native handled it
                }
            } catch (e: Exception) {
                logger.error("TraceletSdk: sync failed: ${e.message}")
                mainHandler.post {
                    callback(emptyList())
                }
            }
        }.start()
    }

    /**
     * Serializes telematics rows to the wire shape (#366, #367).
     *
     * The key names are the ones apps already parse out of `extras.__telematics`,
     * so this stays additive: `speed` and `value` join the object, nothing is
     * renamed or removed.
     */
    private fun telematicsJsonArray(
        events: List<uniffi.tracelet_core.DbTelematicsRecord>,
    ): org.json.JSONArray {
        val jsonArray = org.json.JSONArray()
        events.forEach { event ->
            val obj = org.json.JSONObject()
            obj.put("id", event.id)
            obj.put("event_type", event.eventType)
            obj.put("severity", event.severity)
            obj.put("speed", event.speed)
            obj.put("value", event.value)
            obj.put("latitude", event.latitude)
            obj.put("longitude", event.longitude)
            obj.put("timestamp", event.timestamp)
            obj.put("synced", event.synced)
            // #402: the trip this event was recorded during, or JSON null
            // outside one. Present either way so the key can be relied on.
            obj.put("trip_id", event.tripId ?: org.json.JSONObject.NULL)
            jsonArray.put(obj)
        }
        return jsonArray
    }

    /**
     * POSTs telematics to the dedicated [telematicsUrl] endpoint (#368).
     *
     * Wraps the array in `{"telematics": [...]}` so the body is an object, and
     * routes through the sync provider so pinning, headers, timeouts and retry
     * behave the same as the location path. Failures are swallowed into `false`
     * — the caller keeps the rows unsynced rather than losing them (#366).
     */
    private fun postTelematicsBatch(
        telematicsUrl: String,
        configHttp: uniffi.tracelet_core.HttpConfig,
        events: List<uniffi.tracelet_core.DbTelematicsRecord>,
    ): Boolean {
        val provider = syncProvider ?: return false
        return try {
            val body = org.json.JSONObject()
                .put("telematics", telematicsJsonArray(events))
                .toString()
            provider.postTelematicsBlocking(configHttp, telematicsUrl, body)
        } catch (e: Exception) {
            logger.error("Telematics sync to $telematicsUrl failed: ${e.message}")
            false
        }
    }

    fun setDynamicHeaders(headers: Map<String, String>) {
        if (!isReady) return
        configManager.setDynamicHeaders(headers)
        rustEngineState?.setDynamicHeaders(HashMap(headers))
    }

    fun setRouteContext(ctx: Map<String, Any?>) {
        if (!isReady) return
        configManager.setRouteContext(ctx)
        try {
            val json = org.json.JSONObject(ctx).toString()
            rustEngineState?.setRouteContext(json)
        } catch (e: Exception) {
            logger.error("Failed to serialize routeContext: ${e.message}")
        }
    }

    fun clearRouteContext() {
        if (!isReady) return
        configManager.clearRouteContext()
        rustEngineState?.setRouteContext(null)
    }

    // =========================================================================
    // Permissions
    // =========================================================================

    fun getPermissionStatus(): AuthorizationStatus {
        return permissionManager.getAuthorizationStatus(activity)
    }

    fun getNotificationPermissionStatus(): AuthorizationStatus {
        return permissionManager.getNotificationPermissionStatus(activity)
    }

    fun getMotionPermissionStatus(): AuthorizationStatus {
        return permissionManager.getMotionPermissionStatus(activity)
    }

    /**
     * Requests location permission. Callback receives the resulting status.
     */
    fun requestPermission(callback: (AuthorizationStatus) -> Unit) {
        val act = activity
        if (act == null || pendingPermissionCallback != null) {
            callback(permissionManager.getAuthorizationStatus(activity))
            return
        }

        val status = permissionManager.getAuthorizationStatus(act)
        when (status) {
            AuthorizationStatus.NOT_DETERMINED,
            AuthorizationStatus.DENIED -> {
                pendingPermissionCallback = callback
                permissionManager.requestForegroundPermission(act)
            }
            AuthorizationStatus.WHEN_IN_USE -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    pendingPermissionCallback = callback
                    permissionManager.requestBackgroundPermission(act)
                } else {
                    callback(AuthorizationStatus.ALWAYS)
                }
            }
            else -> callback(status)
        }
    }

    /**
     * Requests notification permission (Android 13+). Callback receives status.
     */
    fun requestNotificationPermission(callback: (AuthorizationStatus) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            callback(AuthorizationStatus.ALWAYS)
            return
        }

        val act = activity
        if (act == null || pendingPermissionCallback != null) {
            callback(permissionManager.getNotificationPermissionStatus(activity))
            return
        }

        val status = permissionManager.getNotificationPermissionStatus(act)

        if (status == AuthorizationStatus.DENIED_FOREVER || status == AuthorizationStatus.ALWAYS) {
            callback(status)
            return
        }

        pendingPermissionCallback = callback
        permissionManager.requestNotificationPermission(act)
    }

    /**
     * Requests activity recognition permission (API 29+). Callback receives status.
     */
    fun requestMotionPermission(callback: (AuthorizationStatus) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            callback(AuthorizationStatus.ALWAYS)
            return
        }

        val act = activity
        if (act == null || pendingPermissionCallback != null) {
            callback(permissionManager.getMotionPermissionStatus(activity))
            return
        }

        val status = permissionManager.getMotionPermissionStatus(act)

        if (status == AuthorizationStatus.DENIED_FOREVER || status == AuthorizationStatus.ALWAYS) {
            callback(status)
            return
        }

        pendingPermissionCallback = callback
        permissionManager.requestActivityRecognition(act)
    }

    /**
     * Called by the host framework after the OS permission dialog closes.
     *
     * @return true if this request code belongs to Tracelet.
     */
    fun handlePermissionResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != TraceletPermissionManager.REQUEST_CODE_LOCATION &&
            requestCode != TraceletPermissionManager.REQUEST_CODE_BACKGROUND_LOCATION &&
            requestCode != TraceletPermissionManager.REQUEST_CODE_ACTIVITY_RECOGNITION &&
            requestCode != TraceletPermissionManager.REQUEST_CODE_NOTIFICATION
        ) {
            return false
        }

        val callback = pendingPermissionCallback
        
        // Always handle ACTIVITY_RECOGNITION side-effects even without a
        // Dart callback — start() auto-requests this permission and never
        // sets pendingPermissionCallback.
        if (requestCode == TraceletPermissionManager.REQUEST_CODE_ACTIVITY_RECOGNITION) {
            val act = activity
            val motionStatus = permissionManager.getMotionPermissionStatus(act)
            if (motionStatus == AuthorizationStatus.ALWAYS &&
                stateManager.enabled
            ) {
                motionDetector.start()
            }
            callback?.invoke(motionStatus)
            pendingPermissionCallback = null
            return true
        }

        if (callback == null) return false

        val act = activity
        when (requestCode) {
            TraceletPermissionManager.REQUEST_CODE_NOTIFICATION -> {
                callback(permissionManager.getNotificationPermissionStatus(act))
                pendingPermissionCallback = null
            }
            TraceletPermissionManager.REQUEST_CODE_BACKGROUND_LOCATION -> {
                if (act != null) {
                    val status = permissionManager.getStatusAfterRequest(act)
                    callback(status)
                } else {
                    callback(permissionManager.getAuthorizationStatus(null))
                }
                pendingPermissionCallback = null
            }
            else -> {
                if (act != null) {
                    callback(permissionManager.getStatusAfterRequest(act))
                } else {
                    callback(permissionManager.getAuthorizationStatus(null))
                }
                pendingPermissionCallback = null
            }
        }
        return true
    }

    fun openExactAlarmSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return try {
            val intent = Intent(
                android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                android.net.Uri.parse("package:" + context.packageName)
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            logger.warning("Failed to open exact alarm settings: " + e.message)
            false
        }
    }

    fun canScheduleExactAlarms(): Boolean {
        return PeriodicLocationWorker.canScheduleExactAlarms(context)
    }

    fun isPowerSaveMode(): Boolean = permissionManager.isPowerSaveMode()

    fun isIgnoringBatteryOptimizations(): Boolean {
        return permissionManager.isIgnoringBatteryOptimizations()
    }

    fun requestSettings(action: String): Boolean {
        return when (action) {
            "ignoreOptimizations" ->
                permissionManager.requestIgnoreBatteryOptimizations(activity)
            "location" -> permissionManager.showLocationSettings(activity)
            else -> false
        }
    }

    fun showSettings(action: String): Boolean {
        return when (action) {
            "location" -> permissionManager.showLocationSettings(activity)
            "app" -> permissionManager.showAppSettings(activity)
            else -> false
        }
    }

    // =========================================================================
    // Provider & Sensors
    // =========================================================================

    fun getProviderState(): Map<String, Any?> {
        if (!isReady) return emptyMap()
        return locationEngine.buildProviderState()
    }

    fun getSensors(): Map<String, Any?> {
        if (!isReady) return emptyMap()
        return motionDetector.getSensors()
    }

    // =========================================================================
    // Logging
    // =========================================================================

    fun getLog(query: Map<String, Any?>?): String {
        if (!isReady) return ""
        return logger.getLog(query)
    }

    fun destroyLog(): Boolean {
        if (!isReady) return false
        return logger.destroyLog()
    }

    fun log(level: String, message: String): Boolean {
        if (!isReady) return false
        return logger.log(level, message)
    }

    // =========================================================================
    // Telematics
    // =========================================================================

    /**
     * The most recent stored driving/impact events — **newest first, whether or
     * not they have been synced** (#313).
     *
     * This is the history API behind `Tracelet.getTelematicsEvents()` and the
     * Doctor bug report. It used to share the sync batcher's query
     * (`WHERE synced = 0 ORDER BY id ASC`), which meant it returned the *oldest*
     * events rather than the most recent, and that enabling `syncTelematics`
     * silently emptied the app's own local history. Sync keeps that query via
     * [getUnsyncedTelematics].
     */
    fun getTelematicsEvents(limit: Int): List<uniffi.tracelet_core.DbTelematicsRecord> {
        if (!isReady) return emptyList()
        return try {
            rustDatabase?.getTelematicsHistory(limit) ?: emptyList()
        } catch (e: Exception) {
            logger.error("Failed to get telematics events: ${e.message}")
            emptyList()
        }
    }

    /**
     * Unsynced telematics events, oldest first — the *sync* view (#313).
     *
     * The batcher uploads these in id order and then marks everything up to the
     * highest id synced, so this must stay ascending and must exclude anything
     * already uploaded.
     */
    private fun getUnsyncedTelematics(limit: Int): List<uniffi.tracelet_core.DbTelematicsRecord> {
        if (!isReady) return emptyList()
        return try {
            rustDatabase?.getTelematicsEvents(limit) ?: emptyList()
        } catch (e: Exception) {
            logger.error("Failed to get unsynced telematics events: ${e.message}")
            emptyList()
        }
    }

    /**
     * Unsynced telematics events mapped for the custom sync-body builder context (#214).
     *
     * Returns an **empty list unless `syncTelematics` is enabled** — so apps that
     * don't opt into telematics get no extra data and no overhead — matching the
     * gating of the default payload's `__telematics` injection.
     */
    fun getTelematicsForCustomBuilder(limit: Int = 250): List<Map<String, Any?>> {
        if (!isReady || !configManager.getSyncTelematics()) return emptyList()
        val events = getUnsyncedTelematics(limit)
        // Remember the highest id we exposed so a successful sync can mark exactly
        // these synced — avoids re-sending them every batch (#214 dedup).
        lastExposedTelematicsMaxId = events.maxOfOrNull { it.id } ?: lastExposedTelematicsMaxId
        return events.map { e ->
            mapOf(
                "id" to e.id,
                "event_type" to e.eventType,
                "severity" to e.severity,
                // #367: additive — existing keys keep their names and meaning.
                "speed" to e.speed,
                "value" to e.value,
                "latitude" to e.latitude,
                "longitude" to e.longitude,
                "timestamp" to e.timestamp,
                "synced" to e.synced,
            )
        }
    }

    /**
     * Tracks the highest telematics id handed to a custom builder via
     * [getTelematicsForCustomBuilder], so [markExposedTelematicsSynced] can mark
     * exactly those synced after a successful custom-path sync (#214 dedup).
     */
    @Volatile
    private var lastExposedTelematicsMaxId: Long = 0L

    /**
     * Marks the telematics previously exposed to a custom builder as synced, after
     * a successful custom-path sync. No-op when nothing was exposed (e.g. the
     * default payload path), so it can't lose unsent telematics (#214 dedup).
     */
    fun markExposedTelematicsSynced() {
        val maxId = lastExposedTelematicsMaxId
        if (maxId <= 0L) return
        try {
            rustDatabase?.markTelematicsSynced(maxId)
        } catch (e: Exception) {
            logger.error("markTelematicsSynced failed: ${e.message}")
        }
        lastExposedTelematicsMaxId = 0L
    }

    fun getLogs(limit: Int): List<uniffi.tracelet_core.LogEntry> {
        val db = rustDatabase ?: return emptyList()
        return try {
            db.getLogs(limit)
        } catch (e: Exception) {
            logger.error("Failed to get logs: ${e.message}")
            emptyList()
        }
    }
    
    fun clearLogs() {
        val db = rustDatabase ?: return
        try {
            db.clearLogs()
        } catch (e: Exception) {
            logger.error("Failed to clear logs: ${e.message}")
        }
    }

    fun destroyTelematicsEvents(): Boolean {
        if (!isReady) return false
        return try {
            rustDatabase?.clearTelematicsEvents()
            true
        } catch (e: Exception) {
            logger.error("Failed to clear telematics events: ${e.message}")
            false
        }
    }

    fun simulateTelematicsEvent(eventType: String, severity: Double, latitude: Double, longitude: Double): Boolean {
        if (!isReady) return false
        return try {
            // #367: a simulated event has no measured magnitudes; 0.0 keeps the
            // public 4-arg signature (Pigeon + React Native) unchanged.
            rustDatabase?.insertTelematicsEvent(eventType, severity, 0.0, 0.0, latitude, longitude)
            true
        } catch (e: Exception) {
            logger.error("Failed to simulate telematics event: ${e.message}")
            false
        }
    }

    // =========================================================================
    // Scheduling
    // =========================================================================

    fun startSchedule() {
        if (!isReady) return
        scheduleManager.start()
    }

    fun stopSchedule() {
        if (!isReady) return
        scheduleManager.stop()
    }

    // =========================================================================
    // Sound
    // =========================================================================

    fun playSound(name: String): Boolean {
        if (!::soundManager.isInitialized) return false
        return soundManager.playSound(name)
    }

    // =========================================================================
    // OEM Compatibility
    // =========================================================================

    fun getSettingsHealth(): Map<String, Any?> = OemCompat.getSettingsHealth(context)

    /**
     * Authoritative Android foreground-service health (#255).
     *
     * Distinguishes the *desired* tracking state ([StateManager.enabled]) from
     * the *actual* native foreground-service state. On Android 12+ a
     * foreground-service start can be deferred or rejected even while
     * `enabled == true`, so `enabled` alone is not proof that background
     * tracking is operational. Combine both to build accurate tracking-health
     * indicators, diagnostics, and recovery behavior.
     *
     * Returned keys:
     * - `desiredEnabled` (Boolean): the persisted desired tracking state.
     * - `foregroundServiceEnabled` (Boolean): whether the active config runs a
     *   foreground service at all.
     * - `serviceRunning` (Boolean): whether [LocationService] is alive.
     * - `serviceForeground` (Boolean): whether it is currently promoted to the
     *   foreground (last `startForeground()` succeeded and not since demoted).
     * - `foregroundNotificationId` (Long?): the notification id while promoted.
     * - `lastForegroundPromotionResult` (String?): `success` | `deferred` |
     *   `failed` | `suppressed` (null before any attempt). `suppressed` is a
     *   deliberate demotion by `showNotificationOnPauseOnly` while the app is
     *   on screen — the service is alive and tracking, unlike `deferred` and
     *   `failed` (#378).
     * - `lastForegroundPromotionFailureClass` (String?): exception class of the
     *   last failed/deferred promotion.
     * - `lastForegroundPromotionFailureMessage` (String?): its message.
     * - `lastForegroundTransitionAt` (Long?): epoch-ms of the last promotion
     *   transition — a change of state, not every `startForeground` call, so
     *   the interval a process spent without a foreground service is
     *   measurable from it (#378).
     * - `platform` (String): `android`.
     */
    /**
     * The location-filter thresholds actually in force in the Rust processor,
     * or `null` before one exists (#303).
     *
     * Deliberately reads the processor rather than [ConfigManager]: the two
     * silently disagreeing is exactly the bug #303 fixed, so a getter answering
     * from config could never surface a regression. While a transport-mode
     * auto-tune is committed these are the tuned values, not the configured
     * ones — which is what makes an auto-tune observable rather than a silent
     * mutation.
     */
    fun getCurrentLocationTuning(): uniffi.tracelet_core.LocationTuning? {
        if (!::locationEngine.isInitialized) return null
        return locationEngine.currentTuning()
    }

    fun getForegroundServiceHealth(): Map<String, Any?> {
        val health = LocationService.foregroundServiceHealth().toMutableMap()
        health["desiredEnabled"] = stateManager.enabled
        health["foregroundServiceEnabled"] = configManager.isForegroundServiceEnabled()
        health["platform"] = "android"
        // #406: Forced App Standby is independent of the Doze allowlist the
        // health check already reports, and it is the stronger restriction —
        // it blocks the foreground-service promotion outright. Reported here
        // rather than in HealthCheck because this map is the snapshot that
        // exists to say whether background tracking is operational.
        val bucket = com.ikolvi.tracelet.sdk.util.BackgroundRestrictions.standbyBucket(context)
        health["backgroundRestricted"] =
            com.ikolvi.tracelet.sdk.util.BackgroundRestrictions.isBackgroundRestricted(context)
        health["standbyBucket"] = bucket?.toLong()
        health["standbyBucketName"] =
            com.ikolvi.tracelet.sdk.util.BackgroundRestrictions.standbyBucketName(bucket)
        return health
    }

    fun openOemSettings(label: String): Boolean {
        return OemCompat.openOemSettingsScreen(context, label)
    }

    fun showPowerManager(): Boolean {
        return OemCompat.showPowerManager(context)
    }

    // =========================================================================
    // Enterprise: Audit Trail
    // =========================================================================

    fun verifyAuditChain(): Map<String, Any?> {
        if (!::auditTrailManager.isInitialized) return emptyMap()
        return auditTrailManager.verifyChain()
    }

    fun getAuditProof(uuid: String): Map<String, Any?>? {
        if (!::auditTrailManager.isInitialized) return null
        return auditTrailManager.getProof(uuid)
    }

    // =========================================================================
    // Enterprise: Privacy Zones
    // =========================================================================

    fun addPrivacyZone(zone: Map<String, Any?>): Boolean {
        if (!::privacyZoneManager.isInitialized) return false
        return privacyZoneManager.addZone(zone)
    }

    /** Add a privacy zone using a typed [TraceletPrivacyZone] model. */
    fun addPrivacyZone(zone: com.ikolvi.tracelet.sdk.model.TraceletPrivacyZone): Boolean {
        return addPrivacyZone(zone.toMap())
    }

    fun addPrivacyZones(zones: List<Map<String, Any?>>): Boolean {
        if (!::privacyZoneManager.isInitialized) return false
        return privacyZoneManager.addZones(zones)
    }

    /** Add multiple privacy zones using typed [TraceletPrivacyZone] models. */
    fun addTypedPrivacyZones(zones: List<com.ikolvi.tracelet.sdk.model.TraceletPrivacyZone>): Boolean {
        return addPrivacyZones(zones.map { it.toMap() })
    }

    fun removePrivacyZone(id: String): Boolean {
        if (!::privacyZoneManager.isInitialized) return false
        return privacyZoneManager.removeZone(id)
    }

    fun removePrivacyZones(): Boolean {
        if (!::privacyZoneManager.isInitialized) return false
        return privacyZoneManager.removeAllZones()
    }

    fun getPrivacyZones(): List<Map<String, Any?>> {
        if (!::privacyZoneManager.isInitialized) return emptyList()
        return privacyZoneManager.getZones()
    }

    // =========================================================================
    // Enterprise: Database Encryption
    // =========================================================================

    fun isDatabaseEncrypted(): Boolean {
        if (!isReady) return false
        val state = rustEngineState ?: return false
        return state.getConfig().security.encryptDatabase
    }

    /**
     * Encrypts the database. Returns true on success.
     *
     * @throws Exception on encryption failure.
     */
    fun encryptDatabase(): Boolean {
        if (!isReady) return false
        val customKey = configManager.getEncryptionKey()
        val state = rustEngineState ?: return false
        return try {
            val currentConfig = state.getConfig()
            val newSecurity = uniffi.tracelet_core.SecurityConfig(encryptDatabase = true)
            val newConfig = uniffi.tracelet_core.EngineConfig(
                geo = currentConfig.geo,
                motion = currentConfig.motion,
                http = currentConfig.http,
                geofence = currentConfig.geofence,
                persistence = currentConfig.persistence,
                audit = currentConfig.audit,
                security = newSecurity,
                attestation = currentConfig.attestation
            )
            state.updateConfig(newConfig)
            true
        } catch (e: Exception) {
            logger.error("encryptDatabase failed: ${e.message}")
            false
        }
    }

    // =========================================================================
    // Enterprise: Device Attestation
    // =========================================================================

    fun attestDevice(callback: (Map<String, Any?>?) -> Unit) {
        if (!isReady) { callback(null); return }
        deviceAttestor.requestToken(callback)
    }

    // =========================================================================
    // Enterprise: Dead Reckoning
    // =========================================================================

    fun getDeadReckoningState(): Map<String, Any?>? {
        if (!isReady) return null
        return locationEngine.getDeadReckoningState()
    }

    // =========================================================================
    // Enterprise: Carbon Report
    // =========================================================================

    fun getCarbonReport(query: Map<String, Any?>?): Map<String, Any?> {
        if (!isReady) return mapOf(
            "totalCarbonGrams" to 0.0,
            "carbonByMode" to emptyMap<String, Double>(),
            "distanceByMode" to emptyMap<String, Double>(),
            "totalTrips" to 0,
        )
        val from = (query?.get("from") as? Number)?.toLong()
        val to = (query?.get("to") as? Number)?.toLong()
        val locations = getLocations(query)

        var totalGrams = 0.0
        val carbonByMode = mutableMapOf<String, Double>()
        val distanceByMode = mutableMapOf<String, Double>()
        var prevLat = 0.0
        var prevLng = 0.0
        var tripCount = 0
        var wasMoving = false

        for (location in locations) {
            val coords = location["coords"] as? Map<*, *>
            val lat = (coords?.get("latitude") as? Number)?.toDouble() ?: continue
            val lng = (coords?.get("longitude") as? Number)?.toDouble() ?: continue
            val act = location["activity"] as? Map<*, *>
            val actType = act?.get("type") as? String ?: "unknown"
            val isMoving = location["is_moving"] == 1 || location["is_moving"] == true

            if (!wasMoving && isMoving) tripCount++
            wasMoving = isMoving

            if (prevLat != 0.0 && prevLng != 0.0) {
                val dist = haversineDistance(prevLat, prevLng, lat, lng)
                distanceByMode[actType] = (distanceByMode[actType] ?: 0.0) + dist
                val factor = carbonFactorForMode(actType)
                val grams = dist / 1000.0 * factor
                carbonByMode[actType] = (carbonByMode[actType] ?: 0.0) + grams
                totalGrams += grams
            }
            prevLat = lat
            prevLng = lng
        }

        return mapOf(
            "totalCarbonGrams" to totalGrams,
            "carbonByMode" to carbonByMode,
            "distanceByMode" to distanceByMode,
            "totalTrips" to tripCount,
        )
    }

    // =========================================================================
    // Private — motion / schedule / heartbeat / timers
    // =========================================================================

    private fun handleMotionStateChange(isMoving: Boolean) {
        // #318: logged on the in-app path too, so one trace shows both. A report
        // of "pace only changes while the app is open" is diagnosed by comparing
        // these against the `motion (killed-state, …)` entries: if the foreground
        // ones are present and the killed-state ones are not, the background
        // detector never ran; if both are present, the transition was detected
        // and the problem is downstream (delivery, persistence, or sync).
        com.ikolvi.tracelet.sdk.util.TraceletLog.lifecycle(
            "motion (foreground): isMoving=$isMoving " +
                "mode=${configManager.getMotionDetectionMode()} " +
                "sessionMoving=${stateManager.isMoving}"
        )
        if (configManager.getMotionDetectionMode() == com.ikolvi.tracelet.sdk.model.MotionDetectionMode.SMART) {
            // In SMART mode, route the accel event through the coordinator first.
            // Only reset the speed state machine when the coordinator actually
            // decides to SWITCH_TO_CONTINUOUS (a genuine wake-up from stationary).
            // This prevents micro-vibrations from the significant motion sensor
            // from force-resetting the speed SM on every fire (infinite loop),
            // while still allowing the system to wake from stationary when the
            // coordinator determines real movement has begun.
            val action = smartMotionCoordinator.onAccelStateChange(isMoving)
            
            if (configManager.isForegroundServiceEnabled()) {
                if (isMoving) {
                    // Re-assert the wakelock on the moving transition (idempotent
                    // if already held) so CPU stays awake during active tracking.
                    LocationService.acquireWakelock(context)
                } else if (configManager.getReleaseWakelockWhenStationary() &&
                    motionDetector.getSensors()["significantMotion"] == true
                ) {
                    // Drop the wakelock when stationary to save battery — but only
                    // when the hardware TYPE_SIGNIFICANT_MOTION wake-up sensor is
                    // present, so the device can still wake from Doze on real
                    // movement. Without it we keep the wakelock (safe default) to
                    // avoid stranding the detector in the stationary state (#162).
                    LocationService.releaseWakelock(context)
                }
            }
            
            if (action == uniffi.tracelet_core.CoordinatorAction.SWITCH_TO_CONTINUOUS) {
                if (::speedMotionManager.isInitialized) {
                    speedMotionManager.onManualPaceChange(true)
                }
            } else if (isMoving && !stateManager.isMoving) {
                // A wake the coordinator declined, with the session still
                // stationary — and `declareMoving()` has already torn down both
                // ways of noticing the next one (stationary wake re-arm, PR #399).
                //
                // TYPE_SIGNIFICANT_MOTION is a one-shot trigger sensor: firing
                // consumes the registration, and re-arming it happens only on
                // the stationary transition, which a declined wake never makes.
                // `declareMoving()` also stops shake monitoring and switches the
                // accelerometer to stillness detection, which by construction
                // only notices the device *stopping*. So a declined wake leaves a
                // stationary session with no armed wake source at all.
                //
                // In the foreground that self-heals — the CPU stays awake and a
                // later shake or periodic fix rescues it. Backgrounded it does
                // not: TYPE_ACCELEROMETER is a non-wakeup sensor and delivers
                // nothing while the device is suspended, so significant motion
                // was the only thing that could have woken it. The session stays
                // stationary until the app is brought up and tracking restarted
                // by hand, which is exactly how this is reported.
                com.ikolvi.tracelet.sdk.util.TraceletLog.lifecycle(
                    "motion: wake declined by the coordinator (action=$action) while the " +
                        "session is stationary — re-arming the wake sensors so the next " +
                        "movement can still be seen (stationary wake re-arm, PR #399)",
                )
                motionDetector.onManualPaceChange(false)
            }
            return
        }

        logger.debug("Motion state changed: isMoving=$isMoving")
        stateManager.isMoving = isMoving

        if (isMoving) {
            locationEngine.start()
            if (::soundManager.isInitialized) soundManager.playMotionChange(true)
        } else {
            locationEngine.stop()
            if (::soundManager.isInitialized) soundManager.playMotionChange(false)
        }

        val locationMap =
            locationEngine.getLastLocation()?.let { loc ->
                val map = locationEngine.enrichLocation(
                    loc, "motionchange", locationEngine.lastEffectiveSpeed
                ).toMutableMap()
                map["isMoving"] = isMoving
                map
            } ?: mapOf("isMoving" to isMoving)

        // Feed TripManager with motion state change
        val lat = (locationMap["latitude"] as? Number)?.toDouble()
            ?: ((locationMap["coords"] as? Map<*, *>)?.get("latitude") as? Number)?.toDouble()
        val lng = (locationMap["longitude"] as? Number)?.toDouble()
            ?: ((locationMap["coords"] as? Map<*, *>)?.get("longitude") as? Number)?.toDouble()
        tripManager.onMotionStateChanged(
            isMoving = isMoving,
            latitude = lat,
            longitude = lng,
            timestamp = locationMap["timestamp"],
        )

        // #402: the trip id travels with the motion change that opened or
        // closed the trip. The Dart layer runs its own trip detection for
        // waypoints and distance, and would otherwise mint a *second* id for
        // the same journey — one that matched nothing in the database. Sending
        // it here rather than having Dart ask for it afterwards also makes it
        // race-free: the id is read on the same thread that just set it,
        // before the event leaves.
        val motionMap = locationMap.toMutableMap()
        motionMap["tripId"] = tripManager.currentTripId

        eventSender.sendMotionChange(motionMap)
    }

    private fun handleScheduleStart() {
        stateManager.enabled = true
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.start(context)
        }
        locationEngine.start()
        motionDetector.start()
        startHeartbeat()
        eventSender.sendEnabledChange(true)
    }

    private fun handleScheduleStop() {
        stateManager.enabled = false
        locationEngine.stop()
        motionDetector.stop()
        stopHeartbeat()
        if (configManager.isForegroundServiceEnabled()) {
            LocationService.stop(context)
        }
        eventSender.sendEnabledChange(false)
    }

    /** Last location persisted by a heartbeat — used to deduplicate DB writes. */
    private var lastHeartbeatLocationTime: Long = 0L

    internal fun startHeartbeat() {
        stopHeartbeat()
        val intervalSeconds = configManager.getHeartbeatInterval()
        if (intervalSeconds <= 0) return

        heartbeatRunnable = object : Runnable {
            override fun run() {
                if (!stateManager.enabled) return
                logger.debug("Heartbeat fired")
                val cached = locationEngine.getLastGpsLocation()
                if (cached != null) {
                    // Build enriched location map with UUID, battery, etc.
                    val locationData = locationEngine.enrichLocation(cached, "heartbeat").toMutableMap()

                    // Only persist to DB if this is a genuinely new GPS fix
                    // (different timestamp from the last heartbeat write).
                    // This avoids hundreds of redundant DB inserts per hour
                    // when the user is stationary and the cached location
                    // hasn't changed.
                    val fixTime = cached.time
                    if (fixTime != lastHeartbeatLocationTime) {
                        lastHeartbeatLocationTime = fixTime
                        // TODO: Port to Rust
                        locationEngine.onLocationPersisted?.invoke()
                    }

                    // Always send the event so Dart/Flutter UI stays alive
                    eventSender.sendHeartbeat(mapOf("location" to locationData))
                    logger.debug(
                        "Heartbeat: lat=${cached.latitude}, lon=${cached.longitude}, accuracy=${cached.accuracy}m")
                } else {
                    if (configManager.isDebug()) {
                        logger.debug("Heartbeat: no cached location, skipping")
                    }
                }
                mainHandler.postDelayed(this, intervalSeconds * 1000L)
            }
        }
        mainHandler.postDelayed(heartbeatRunnable!!, intervalSeconds * 1000L)
    }

    internal fun stopHeartbeat() {
        heartbeatRunnable?.let { mainHandler.removeCallbacks(it) }
        heartbeatRunnable = null
    }

    /**
     * Starts the interval-based sync timer (issue #149).
     *
     * When `HttpConfig.syncInterval` (seconds) is greater than 0 and auto-sync is
     * enabled, the SDK periodically flushes any pending locations to the configured
     * endpoint on this cadence — independent of the `autoSyncDelay` debounce that
     * fires on new inserts. A value of 0 (the default) leaves the timer disabled.
     */
    internal fun startSyncIntervalTimer() {
        stopSyncIntervalTimer()
        val intervalSeconds = configManager.getSyncInterval()
        if (intervalSeconds <= 0 || !configManager.getAutoSync()) return
        if (configManager.getHttpUrl().isNullOrEmpty()) return

        val periodMs = intervalSeconds * 1000L
        syncIntervalRunnable = object : Runnable {
            override fun run() {
                if (isReady) {
                    try {
                        sync { /* native handles upload + prune */ }
                    } catch (e: Exception) {
                        logger.error("syncInterval flush failed: ${e.message}")
                    }
                }
                mainHandler.postDelayed(this, periodMs)
            }
        }
        mainHandler.postDelayed(syncIntervalRunnable!!, periodMs)
        logger.info("syncInterval timer started (${intervalSeconds}s)")
    }

    internal fun stopSyncIntervalTimer() {
        syncIntervalRunnable?.let { mainHandler.removeCallbacks(it) }
        syncIntervalRunnable = null
    }

    // =========================================================================
    // 3.3.0 behavior engines: telematics, transport-mode classifier, impact
    // =========================================================================

    /** Instantiates the opt-in behavior engines from config. */
    private fun initBehaviorEngines() {
        telematicsEngine = if (configManager.getEnableDrivingEvents()) {
            uniffi.tracelet_core.TelematicsEngine(
                uniffi.tracelet_core.TelematicsConfig(
                    harshBrakingG = configManager.getHarshBrakingG(),
                    harshAccelerationG = configManager.getHarshAccelerationG(),
                    harshCorneringG = configManager.getHarshCorneringG(),
                    speedLimitKmh = configManager.getSpeedLimitKmh(),
                    speedingToleranceKmh = configManager.getSpeedingToleranceKmh(),
                    speedingMinDurationMs = configManager.getSpeedingMinDurationMs(),
                    minSpeedForEventsKmh = configManager.getMinSpeedForEventsKmh(),
                    eventDebounceMs = configManager.getEventDebounceMs(),
                ),
            )
        } else {
            null
        }

        transportClassifier = if (configManager.getEnableFusedClassifier()) {
            uniffi.tracelet_core.TransportModeClassifier(
                uniffi.tracelet_core.ClassifierConfig(
                    modeSwitchDwellMs = configManager.getModeSwitchDwellMs(),
                    minConfidence = configManager.getMinModeConfidence(),
                ),
            )
        } else {
            null
        }

        // #299: classify from raw pre-filter speeds. Left attached while the
        // classifier exists and detached with it, so a disabled classifier costs
        // nothing on the location path.
        if (::locationEngine.isInitialized) {
            locationEngine.rawSpeedSink = if (transportClassifier != null) {
                { speed -> lastRawSpeedMps = speed }
            } else {
                null
            }
        }

        impactDetector = if (configManager.getEnableCrashDetection() ||
            configManager.getEnableFallDetection()
        ) {
            uniffi.tracelet_core.ImpactDetector(
                uniffi.tracelet_core.ImpactConfig(
                    enableCrash = configManager.getEnableCrashDetection(),
                    enableFall = configManager.getEnableFallDetection(),
                    crashGThreshold = configManager.getCrashGThreshold(),
                    crashMinSpeedKmh = configManager.getCrashMinSpeedKmh(),
                    fallGThreshold = configManager.getFallGThreshold(),
                    confirmWindowMs = configManager.getConfirmWindowMs(),
                    minConfidence = configManager.getMinImpactConfidence(),
                ),
            )
        } else {
            null
        }

        // Crash/fall impulses peak in ~50-150 ms, far faster than the ~5 Hz
        // SENSOR_DELAY_NORMAL used for motion detection. When impact detection is
        // active, sample the accelerometer at a higher rate so the peak is
        // actually captured (battery cost is accepted because the feature is
        // opt-in). Falls back to the normal rate otherwise.
        if (::motionDetector.isInitialized) {
            motionDetector.impactHighRate = impactDetector != null
            // Gyroscope corroboration (#179) — only sample gyro when crash/fall is on.
            motionDetector.gyroEnabled = impactDetector != null
            // Barometer cue (#173) — only sample pressure when crash/fall is on.
            motionDetector.baroEnabled = impactDetector != null
        }

        // #183: opt-in ML crash model. Download/decrypt happen off the main thread;
        // until (or unless) it loads, the rule engine is used. Any failure → null
        // (rule-engine fallback). The model is only fetched when crash detection is
        // on AND a model URL (or a licensing unlock endpoint) is configured.
        crashModel = null
        val crashUrl = configManager.getCrashModelUrl()
        val unlockUrl = configManager.getCrashModelUnlockUrl()
        val licenseKey = configManager.getCrashModelLicenseKey()
        if (configManager.getEnableCrashDetection() && (crashUrl != null || unlockUrl != null)) {
            Thread {
                val loader = com.ikolvi.tracelet.sdk.crash.CrashModelLoader
                // If a licensing endpoint is configured, exchange the license for the
                // decryption key + model URL/sha at runtime; else use the static key
                // + configured URL (host-injected). Either path → rule-engine fallback.
                var modelUrl = crashUrl
                var modelSha = configManager.getCrashModelSha256()
                if (unlockUrl != null && licenseKey != null) {
                    emitCrashModelStatus("unlocking")
                    val integrityToken = loader.integrityTokenProvider?.invoke()
                    val unlocked = loader.unlock(
                        unlockUrl, licenseKey, integrityToken,
                    ) { msg -> logger.debug(msg) }
                    if (unlocked != null) {
                        modelUrl = unlocked.url
                        modelSha = unlocked.sha256 ?: modelSha
                    } else {
                        emitCrashModelStatus("failed", "license unlock failed")
                    }
                }
                if (modelUrl != null) {
                    emitCrashModelStatus("downloading")
                    val m = loader.load(context, modelUrl, modelSha) { msg -> logger.debug(msg) }
                    if (m != null) {
                        crashModel = m
                        logger.info("Crash ML model active.")
                        emitCrashModelStatus("ready", "${m.treeCount()} trees")
                    } else {
                        emitCrashModelStatus("failed", "model download or decrypt failed")
                    }
                }
            }.apply { isDaemon = true }.start()
        }
    }

    /** Forwards an ML crash-model lifecycle status to the host (best-effort). */
    private fun emitCrashModelStatus(status: String, detail: String? = null) {
        if (!::eventSender.isInitialized) return
        try {
            eventSender.sendCrashModelStatus(
                mapOf("status" to status, "detail" to detail),
            )
        } catch (_: Throwable) {
            // Never let status reporting affect model loading.
        }
    }

    /** Feeds an accepted location fix to the telematics engine and emits events. */
    private fun processTelematics(location: Map<String, Any?>) {
        @Suppress("UNCHECKED_CAST")
        val coords = location["coords"] as? Map<String, Any?> ?: return
        val speed = (coords["speed"] as? Number)?.toDouble() ?: 0.0
        val heading = (coords["heading"] as? Number)?.toDouble() ?: -1.0
        val lat = (coords["latitude"] as? Number)?.toDouble() ?: 0.0
        val lng = (coords["longitude"] as? Number)?.toDouble() ?: 0.0
        // Capture speed/position for impact gating + the ML speed-history window
        // unconditionally — crash detection can run without driving events.
        lastSpeedMps = speed
        lastLat = lat
        lastLng = lng
        recordSpeedSample(speed)
        val engine = telematicsEngine ?: return
        val events = try {
            engine.processFix(speed, heading, lat, lng, System.currentTimeMillis())
        } catch (e: Exception) {
            logger.error("telematics processFix failed: ${e.message}")
            return
        }
        for (e in events) {
            eventSender.sendDrivingEvent(
                mapOf(
                    "kind" to e.kind,
                    "severity" to e.severity,
                    "speed" to e.speed,
                    "value" to e.value,
                    "latitude" to e.latitude,
                    "longitude" to e.longitude,
                    "timestampMs" to e.timestampMs,
                ),
            )
            // Persist to the telematics DB so getTelematicsEvents() returns the
            // real history (not just Doctor-simulated events).
            try {
                // #367: `speed` and `value` are the magnitudes behind the
                // normalized severity — persist them, or stored history and every
                // synced payload keeps only the flag.
                rustDatabase?.insertTelematicsEvent(e.kind, e.severity, e.speed, e.value, e.latitude, e.longitude)
            } catch (ex: Exception) {
                logger.error("Failed to persist driving event: ${ex.message}")
            }
        }
    }

    /**
     * Re-aligns the location processor's thresholds with the classifier's
     * committed transport mode (#301).
     *
     * Auto-tuning only ever fires on a *committed mode change*, which makes it
     * blind to everything else that can move the two out of step:
     *
     * - `setConfig()` rebuilds the processor for a location-key change, resetting
     *   it to the configured thresholds while the committed mode stays put — so
     *   a user who never changes activity keeps the base thresholds forever.
     * - Turning `autoTuneFromTransportMode` off leaves the last applied tuning in
     *   force, since the next commit returns early before it can restore.
     * - Turning `enableFusedClassifier` off destroys the classifier, so no
     *   further commit ever arrives to undo the tuning.
     *
     * Calling this after any reconfiguration closes all three: with auto-tuning
     * off it restores the host's own values, and with it on it re-applies the
     * mode currently committed (`unknown` also restores).
     *
     * #303: this path changes the four thresholds without any `modeChange` event
     * — the mode did not change, so synthesising one would corrupt the event
     * stream for consumers that count commits. It is logged instead, at INFO for
     * the same reason the geofence decision trace is: the symptom (filters not
     * behaving as configured) is reported days later from a bug report, and DEBUG
     * is not on in production.
     */
    private fun syncTransportModeTuning() {
        if (!::locationEngine.isInitialized) return
        if (!configManager.getAutoTuneFromTransportMode()) {
            locationEngine.restoreBaseTuning()
            logger.info(
                "auto-tune: off — reconfiguration restored the configured thresholds " +
                    "(${locationEngine.currentTuningDescription()})"
            )
            return
        }
        val mode = transportClassifier?.currentMode()?.name?.lowercase() ?: "unknown"
        locationEngine.applyTransportModeTuning(mode)
        logger.info(
            "auto-tune: reconfiguration re-aligned thresholds with committed mode " +
                "'$mode' (${locationEngine.currentTuningDescription()})"
        )
    }

    /** Starts the ~1 Hz accel-window loop (classifier + impact) if a consumer is active. */
    private fun startBehaviorSampling() {
        stopBehaviorSampling()
        if (transportClassifier == null && impactDetector == null) return

        accelBuffer.clear()
        gyroBuffer.clear()
        rawAccelBuffer.clear()
        baroBuffer.clear()
        // #310: don't carry a previous session's feature window into a new one.
        synchronized(crashFeatureHistory) { crashFeatureHistory.clear() }
        accelWindowRunnable = object : Runnable {
            override fun run() {
                if (!stateManager.enabled) return
                processAccelWindow()
                mainHandler.postDelayed(this, accelWindowMs)
            }
        }
        mainHandler.postDelayed(accelWindowRunnable!!, accelWindowMs)
    }

    private fun stopBehaviorSampling() {
        accelWindowRunnable?.let { mainHandler.removeCallbacks(it) }
        accelWindowRunnable = null
        accelBuffer.clear()
        gyroBuffer.clear()
        rawAccelBuffer.clear()
        baroBuffer.clear()
        synchronized(crashFeatureHistory) { crashFeatureHistory.clear() }
        // NOTE: the impact confirmation loop is intentionally NOT stopped here.
        // A crash typically ends in the vehicle stopping, which disables tracking
        // (stopTimeout) and would otherwise abandon a pending `potential_crash`
        // before its countdown elapses — so the confirmed `crash` would never
        // fire. The confirmation loop runs independently and self-terminates once
        // no candidates remain (see [ensureImpactConfirmLoop]).
    }

    /**
     * Ensures the impact confirmation poll is running. Unlike accel sampling,
     * this loop is decoupled from `stateManager.enabled`: once a candidate is
     * pending it keeps polling — across a tracking stop — until every candidate
     * has confirmed (deadline elapsed), been confirmed explicitly, or cancelled.
     * It self-terminates when nothing is pending.
     */
    private fun ensureImpactConfirmLoop() {
        if (impactConfirmRunnable != null) return
        val runnable = object : Runnable {
            override fun run() {
                val detector = impactDetector
                if (detector == null) {
                    impactConfirmRunnable = null
                    return
                }
                detector.checkConfirmations(System.currentTimeMillis()).forEach(::emitImpact)
                if (detector.pendingCount() > 0u) {
                    mainHandler.postDelayed(this, impactConfirmPollMs)
                } else {
                    impactConfirmRunnable = null
                }
            }
        }
        impactConfirmRunnable = runnable
        mainHandler.postDelayed(runnable, impactConfirmPollMs)
    }

    /**
     * Post-impact stillness — the third phase of the canonical fall signature
     * (#180): free-fall → impact peak → the body coming to rest. From this
     * window's total-acceleration trace (g), finds the impact peak and checks
     * that the samples after it settle back near 1 g with little movement.
     */
    private fun isPostImpactStill(rawTotalG: List<Double>): Boolean {
        if (rawTotalG.size < 6) return false
        var peakIdx = 0
        var peakDev = 0.0
        for (i in rawTotalG.indices) {
            val dev = kotlin.math.abs(rawTotalG[i] - 1.0)
            if (dev > peakDev) {
                peakDev = dev
                peakIdx = i
            }
        }
        // Need a genuine impact and a few settling samples after it.
        if (peakDev < 0.5 || peakIdx + 3 >= rawTotalG.size) return false
        val tail = rawTotalG.subList(peakIdx + 1, rawTotalG.size)
        return tail.all { kotlin.math.abs(it - 1.0) < 0.3 }
    }

    /**
     * Schedules a one-shot post-impact GPS speed read ~[crashDvDelayMs] after a
     * crash candidate and folds it into the core's Δv corroboration (#181). A
     * sharp speed collapse (e.g. 60 → 0 km/h) raises the candidate's confidence;
     * a maintained speed leaves it unchanged (never suppressed).
     */
    private fun scheduleDvCorroboration() {
        mainHandler.postDelayed({
            val detector = impactDetector ?: return@postDelayed
            try {
                if (detector.corroborateDv(lastSpeedMps, System.currentTimeMillis())) {
                    logger.debug("crash Δv: post-impact speed collapse corroborated (#181)")
                }
            } catch (e: Exception) {
                logger.error("crash Δv corroboration failed: ${e.message}")
            }
        }, crashDvDelayMs)
    }

    /**
     * Records one GPS speed sample (m/s) into the rolling crash speed-history
     * window, evicting samples older than [crashSpeedWindowMs]. Feeds the ML
     * model's `speed_max` / `dv` features (#183).
     */
    private fun recordSpeedSample(speedMps: Double) {
        val now = System.currentTimeMillis()
        synchronized(speedHistory) {
            speedHistory.addLast(now to speedMps)
            val cutoff = now - crashSpeedWindowMs
            while (speedHistory.isNotEmpty() && speedHistory.first().first < cutoff) {
                speedHistory.removeFirst()
            }
        }
    }

    /**
     * The speed (m/s) the device was carrying into an impact (#312).
     *
     * The maximum GPS speed over the last [crashPreImpactWindowMs], falling back
     * to the latest fix when no history has accumulated yet. Using the *latest*
     * fix directly is what the crash gate used to do, and it loses real crashes:
     * a collision collapses speed within 1–2 s, so a post-impact fix can land
     * before the window containing the impact is scored, dropping the reported
     * speed under `crashMinSpeedKmh` and failing the gate both the rule and the
     * ML path sit behind.
     */
    private fun preImpactSpeedMps(nowMs: Long): Double {
        val recentMax: Double?
        synchronized(speedHistory) {
            val cutoff = nowMs - crashPreImpactWindowMs
            recentMax = speedHistory.filter { it.first >= cutoff }.maxOfOrNull { it.second }
        }
        return maxOf(recentMax ?: 0.0, lastSpeedMps)
    }

    /**
     * Records one processed accel window's features into the rolling ~16 s
     * history, evicting entries older than [crashSpeedWindowMs] (#310).
     */
    private fun recordCrashFeatureWindow(
        nowMs: Long,
        window: uniffi.tracelet_core.AccelWindow,
        gyroPeakDps: Double,
    ) {
        synchronized(crashFeatureHistory) {
            crashFeatureHistory.addLast(
                AccelWindowFeatures(nowMs, window.peakG, window.meanG, gyroPeakDps),
            )
            val cutoff = nowMs - crashSpeedWindowMs
            while (crashFeatureHistory.isNotEmpty() &&
                crashFeatureHistory.first().timestampMs < cutoff
            ) {
                crashFeatureHistory.removeFirst()
            }
        }
    }

    /**
     * Builds the crash model's feature vector, ordered to match
     * [CrashModel.featureNames]. Features (training units): `peak_g` and
     * `mean_g` in g, `gyro_peak_dps` in deg/s, `speed_max` and `dv` (pre-impact
     * speed drop) in **km/h** (#183).
     *
     * Every feature is aggregated over the same ~16 s window the model was
     * trained on (#310) — `peak_g`/`gyro_peak_dps` as the maximum across the
     * window's 1 s slices, `mean_g` as their mean, `speed_max`/`dv` from the GPS
     * speed history. Detection still runs once a second; only the *features* are
     * widened, so a spike is scored in the context the model expects rather than
     * against a 1 s slice it never saw in training.
     *
     * Call [recordCrashFeatureWindow] for the current window first, so it is
     * included here.
     */
    private fun crashFeatureVector(model: uniffi.tracelet_core.CrashModel): List<Double> {
        val speedsKmh: List<Double>
        synchronized(speedHistory) {
            speedsKmh = speedHistory.map { it.second * 3.6 }
        }
        val speedMax = speedsKmh.maxOrNull() ?: (lastSpeedMps * 3.6)
        val speedMin = speedsKmh.minOrNull() ?: (lastSpeedMps * 3.6)
        val dv = speedMax - speedMin

        val windows: List<AccelWindowFeatures>
        synchronized(crashFeatureHistory) {
            windows = ArrayList(crashFeatureHistory)
        }
        val peakG = windows.maxOfOrNull { it.peakG } ?: 0.0
        val meanG = if (windows.isEmpty()) 0.0 else windows.sumOf { it.meanG } / windows.size
        val gyroPeak = windows.maxOfOrNull { it.gyroPeakDps } ?: 0.0

        val byName = mapOf(
            "peak_g" to peakG,
            "mean_g" to meanG,
            "gyro_peak_dps" to gyroPeak,
            "speed_max" to speedMax,
            "dv" to dv,
        )
        // Order by the model's declared feature names. Every name is guaranteed
        // to be present: the Rust core rejects a model declaring anything outside
        // its supported set at load (#309), so a miss here is unreachable.
        return model.featureNames().map { byName[it] ?: 0.0 }
    }

    /** Snapshots the accel buffer into one window and feeds classifier + impact. */
    private fun processAccelWindow() {
        val samples: List<Double>
        synchronized(accelBuffer) {
            if (accelBuffer.isEmpty()) return
            samples = ArrayList(accelBuffer)
            accelBuffer.clear()
        }
        val now = System.currentTimeMillis()
        val window = try {
            uniffi.tracelet_core.computeAccelWindow(samples, accelWindowMs)
        } catch (e: Exception) {
            logger.error("computeAccelWindow failed: ${e.message}")
            return
        }

        transportClassifier?.let { classifier ->
            val result = classifier.classify(window, lastRawSpeedMps, now)
            // #214 pt3: keep the engine's fused mode fresh every window so it can be
            // persisted into the location's activity column when authoritative — this
            // is what survives termination / syncs historically.
            if (::locationEngine.isInitialized) {
                locationEngine.fusedTransportMode = result.mode.name.lowercase()
                locationEngine.fusedTransportModeConfidence = result.confidence
            }
            if (result.changed) {
                val mode = result.mode.name.lowercase()
                // #299: retune the location filters for the newly committed mode.
                // Only on a *commit* — confidence-gated and dwell-debounced — so the
                // thresholds cannot chatter with per-window classification noise.
                val tuning = if (::locationEngine.isInitialized) {
                    locationEngine.applyTransportModeTuning(mode)
                } else {
                    null
                }
                val payload = mutableMapOf<String, Any?>(
                    "mode" to mode,
                    "confidence" to result.confidence,
                )
                // Report the applied thresholds so an auto-tune is visible to the
                // host rather than being a silent config mutation.
                if (tuning != null) {
                    payload["appliedTuning"] = mapOf(
                        "distanceFilter" to tuning.distanceFilter,
                        "trackingAccuracyThreshold" to tuning.trackingAccuracyThreshold,
                        "odometerAccuracyThreshold" to tuning.odometerAccuracyThreshold,
                        "maxImpliedSpeed" to tuning.maxImpliedSpeed,
                    )
                }
                eventSender.sendModeChange(payload)
            }
        }

        impactDetector?.let { detector ->
            // #312: the speed carried into the impact, not the latest fix — which
            // by now may already be the post-crash one. Drives both the speed gate
            // and the on-foot fall context so the two stay coherent.
            val speedBeforeMps = preImpactSpeedMps(now)
            val onFoot = speedBeforeMps * 3.6 < configManager.getCrashMinSpeedKmh()
            // Peak rotation (deg/s) over this window — crash corroboration (#179).
            val gyroPeak: Double
            synchronized(gyroBuffer) {
                gyroPeak = gyroBuffer.maxOrNull() ?: 0.0
                gyroBuffer.clear()
            }
            // Free-fall preceding the impact — fall corroboration (#180). Total
            // acceleration dipping below ~0.5 g indicates the device was falling.
            // Also derive the third phase of the canonical fall signature —
            // post-impact stillness (the body coming to rest) — from the same
            // window's total-acceleration trace.
            val wasInFreeFall: Boolean
            val postImpactStill: Boolean
            synchronized(rawAccelBuffer) {
                val raw = ArrayList(rawAccelBuffer)
                val minTotalG = raw.minOrNull()
                wasInFreeFall = minTotalG != null && minTotalG < 0.5
                postImpactStill = isPostImpactStill(raw)
                rawAccelBuffer.clear()
            }
            // Cabin-pressure swing (hPa) over this window — crash corroboration
            // (#173). peak−trough of the buffered barometer samples; 0 when the
            // device has no pressure sensor (buffer stays empty), so the cue is
            // strictly best-effort and never suppresses.
            val baroDelta: Double
            synchronized(baroBuffer) {
                val baro = baroBuffer
                baroDelta = if (baro.size >= 2) (baro.max() - baro.min()) else 0.0
                baroBuffer.clear()
            }
            // #310: fold this window into the rolling ~16 s feature history so the
            // model is scored over the window it was trained on.
            recordCrashFeatureWindow(now, window, gyroPeak)
            // #183 ML gating (Replace mode): when the opt-in model is loaded, run
            // inference for this window and let its probability decide the crash
            // (still speed-gated in the core). `crashProba < 0` ⇒ no model ⇒ the
            // g-threshold rule is used instead.
            val crashProba = crashModel?.let { model ->
                try {
                    model.predictProba(crashFeatureVector(model))
                } catch (e: Exception) {
                    logger.error("crash model inference failed: ${e.message}")
                    -1.0
                }
            } ?: -1.0
            // Observability (#183): surface each real model inference so the
            // model path can be verified on-device. Only logged when the model
            // actually ran (crashProba >= 0) and the window has a notable peak,
            // to avoid spamming the ~1 Hz idle loop.
            if (crashProba >= 0.0 && window.peakG > 1.5) {
                val thr = configManager.getCrashModelThreshold()
                val verdict = if (crashProba >= thr) "CRASH" else "below-threshold"
                logger.debug(
                    "crash model: proba=%.3f peak=%.2fg speed=%.1fkm/h thr=%.3f → %s".format(
                        crashProba,
                        window.peakG,
                        speedBeforeMps * 3.6,
                        thr,
                        verdict,
                    ),
                )
            }
            val candidate = detector.onImpactWindow(
                window.peakG,
                speedBeforeMps,
                gyroPeak,
                wasInFreeFall,
                postImpactStill,
                onFoot,
                lastLat,
                lastLng,
                now,
                crashProba,
                configManager.getCrashModelThreshold(),
            )
            if (candidate != null) {
                emitImpact(candidate)
                // Keep the countdown alive even if tracking stops right after the
                // crash (vehicle comes to rest → stopTimeout disables tracking).
                ensureImpactConfirmLoop()
                // #181: a real crash collapses the vehicle's speed within ~1–2 s.
                // Sample the post-impact GPS speed shortly after to corroborate.
                if (candidate.kind == "potential_crash") {
                    scheduleDvCorroboration()
                    // #173: a severe collision / airbag deployment spikes cabin
                    // pressure. The transient is concurrent with the impact, so
                    // fold this window's pressure swing in immediately. A flat or
                    // absent barometer leaves confidence unchanged.
                    if (baroDelta > 0.0) {
                        try {
                            if (detector.corroborateBarometric(baroDelta, now)) {
                                logger.debug("crash barometer: cabin-pressure spike corroborated (#173)")
                            }
                        } catch (e: Exception) {
                            logger.error("crash barometer corroboration failed: ${e.message}")
                        }
                    }
                }
                // #182: persist the candidate and arm a process-death safety-net
                // alarm so the confirmation still fires if the OS kills the app
                // before its in-process countdown elapses.
                if (candidate.kind.startsWith("potential_")) {
                    scheduleProcessDeathSafeConfirm(candidate)
                }
            }
        }
    }

    /**
     * Persists a pending crash/fall candidate and schedules an exact wake-up
     * alarm just past its confirmation deadline (#182). If the process is killed
     * during the countdown — common after a violent impact — the
     * [CrashConfirmReceiver] re-emits the confirmed event from a fresh process.
     */
    private fun scheduleProcessDeathSafeConfirm(candidate: uniffi.tracelet_core.ImpactEvent) {
        try {
            val p = PendingImpact(
                id = candidate.id,
                kind = candidate.kind,
                confidence = candidate.confidence,
                peakG = candidate.peakG,
                speedBefore = candidate.speedBefore,
                latitude = candidate.latitude,
                longitude = candidate.longitude,
                timestampMs = candidate.timestampMs,
                confirmDeadlineMs = candidate.confirmDeadlineMs,
            )
            CrashConfirmStore(context).put(p)
            CrashConfirmReceiver.schedule(context, p)
        } catch (e: Exception) {
            logger.error("Failed to arm crash-confirm safety net: ${e.message}")
        }
    }

    private fun emitImpact(e: uniffi.tracelet_core.ImpactEvent) {
        eventSender.sendImpact(
            mapOf(
                "kind" to e.kind,
                "id" to e.id,
                "confidence" to e.confidence,
                "peakG" to e.peakG,
                "speedBefore" to e.speedBefore,
                "latitude" to e.latitude,
                "longitude" to e.longitude,
                "timestampMs" to e.timestampMs,
                "confirmDeadlineMs" to e.confirmDeadlineMs,
            ),
        )
        // Persist confirmed impacts (not transient potential_* candidates, which
        // may still be cancelled) to the telematics DB for history/retrieval.
        if (e.kind == "crash" || e.kind == "fall") {
            try {
                // #367: peak g and the speed going in are an impact's magnitudes,
                // the same role speed/value play for a driving event.
                rustDatabase?.insertTelematicsEvent(
                    e.kind, e.confidence, e.speedBefore, e.peakG, e.latitude, e.longitude,
                )
            } catch (ex: Exception) {
                logger.error("Failed to persist impact event: ${ex.message}")
            }
            // #182: an in-process confirmation just delivered this event — drop
            // the persisted candidate and cancel its safety-net alarm so the
            // wake-up receiver never re-emits a duplicate.
            try {
                CrashConfirmStore(context).remove(e.id)
                CrashConfirmReceiver.cancel(context, e.id)
            } catch (ex: Exception) {
                logger.error("Failed to clear crash-confirm safety net: ${ex.message}")
            }
        }
    }

    /**
     * Re-emits a confirmed crash/fall from a persisted candidate (#182). Called
     * by [CrashConfirmReceiver] when the app was killed during the confirmation
     * countdown, so the host's escalation/SOS flow still runs. Mirrors the
     * confirmed-event side of [emitImpact] without touching the (now-gone)
     * in-memory Rust detector.
     */
    internal fun deliverConfirmedImpact(p: PendingImpact) {
        eventSender.sendImpact(
            mapOf(
                "kind" to p.confirmedKind,
                "id" to p.id,
                "confidence" to p.confidence,
                "peakG" to p.peakG,
                "speedBefore" to p.speedBefore,
                "latitude" to p.latitude,
                "longitude" to p.longitude,
                "timestampMs" to p.timestampMs,
                "confirmDeadlineMs" to p.confirmDeadlineMs,
            ),
        )
        try {
            // #367: as above — peak g and entry speed are the impact's magnitudes.
            rustDatabase?.insertTelematicsEvent(
                p.confirmedKind, p.confidence, p.speedBefore, p.peakG, p.latitude, p.longitude,
            )
        } catch (ex: Exception) {
            logger.error("Failed to persist confirmed impact event: ${ex.message}")
        }
    }

    /** Confirms a pending impact candidate (called from the Pigeon host API). */
    fun confirmImpact(id: Long): Boolean {
        val confirmed = impactDetector?.confirm(id, System.currentTimeMillis()) ?: return false
        emitImpact(confirmed)
        return true
    }

    /** Cancels a pending impact candidate (called from the Pigeon host API). */
    fun cancelImpact(id: Long): Boolean {
        // #182: drop the persisted candidate and disarm its safety-net alarm so
        // a cancelled candidate is never re-confirmed after a process restart.
        try {
            CrashConfirmStore(context).remove(id)
            CrashConfirmReceiver.cancel(context, id)
        } catch (e: Exception) {
            logger.error("Failed to clear crash-confirm safety net on cancel: ${e.message}")
        }
        return impactDetector?.cancel(id) ?: false
    }

    /**
     * Debug (#183): runs one synthetic high-g window through the REAL crash
     * pipeline — the loaded ML model and the live [impactDetector] — so the
     * model path can be verified without a physical impact. Requires crash
     * detection to be enabled. Returns proba/threshold/fired so callers can
     * prove the model (not the rule engine) made the call.
     */
    fun debugRunCrashModelInference(peakG: Double, speedKmh: Double, crashLike: Boolean = true): Map<String, Any?> {
        val detector = impactDetector ?: return mapOf(
            "modelRan" to false,
            "fired" to false,
            "error" to "crash detection not enabled — toggle it on and start tracking first",
        )
        val speedMps = speedKmh / 3.6
        // Synthesize a window: baseline ~1 g with a single spike at peakG.
        val samples = ArrayList<Double>(50).apply {
            repeat(49) { add(1.0) }
            add(peakG)
        }
        val window = try {
            uniffi.tracelet_core.computeAccelWindow(samples, accelWindowMs)
        } catch (e: Exception) {
            return mapOf(
                "modelRan" to false,
                "fired" to false,
                "error" to "computeAccelWindow failed: ${e.message}",
            )
        }
        // Crash-like corroboration: high rotation + a full speed drop (dv) at the
        // given speed. Benign: no rotation, no speed drop (model should reject).
        val gyroPeak = if (crashLike) 250.0 else 0.0
        val speedMax = speedKmh
        val dv = if (crashLike) speedKmh else 0.0
        val now = System.currentTimeMillis()
        val crashProba = crashModel?.let { model ->
            try {
                val byName = mapOf(
                    "peak_g" to window.peakG,
                    "mean_g" to window.meanG,
                    "gyro_peak_dps" to gyroPeak,
                    "speed_max" to speedMax,
                    "dv" to dv,
                )
                model.predictProba(model.featureNames().map { byName[it] ?: 0.0 })
            } catch (e: Exception) {
                logger.error("crash model inference failed: ${e.message}")
                -1.0
            }
        } ?: -1.0
        val threshold = configManager.getCrashModelThreshold()
        val modelRan = crashProba >= 0.0
        logger.debug(
            "crash model (debug): proba=%.3f peak=%.2fg gyro=%.0f speed=%.1fkm/h dv=%.1f thr=%.3f modelRan=%b".format(
                crashProba,
                window.peakG,
                gyroPeak,
                speedKmh,
                dv,
                threshold,
                modelRan,
            ),
        )
        val candidate = detector.onImpactWindow(
            window.peakG,
            speedMps,
            gyroPeak,
            false,
            false,
            speedKmh < configManager.getCrashMinSpeedKmh(),
            lastLat,
            lastLng,
            now,
            crashProba,
            threshold,
        )
        if (candidate != null) {
            emitImpact(candidate)
            ensureImpactConfirmLoop()
        }
        return mapOf(
            "modelRan" to modelRan,
            "proba" to crashProba,
            "threshold" to threshold,
            "peakG" to window.peakG,
            "fired" to (candidate != null),
            "kind" to candidate?.kind,
        )
    }

    /**
     * (Re)builds the battery-budget engine from the current config.
     *
     * A non-zero `batteryBudgetPerHour` creates the engine seeded with the
     * current distance filter / accuracy; a zero (or negative) value disables
     * it. Called both at [ready] and from [setConfig] so the budget can be
     * turned on/off/retargeted at runtime — e.g. via remote config — instead of
     * only taking effect on the next cold start.
     */
    private fun applyBatteryBudgetConfig() {
        val budgetPerHour = configManager.getBatteryBudgetPerHour()
        batteryBudgetEngine = if (budgetPerHour > 0) {
            BatteryBudgetEngine(
                targetBudgetPerHour = budgetPerHour,
                initialDistanceFilter = configManager.getDistanceFilter(),
                initialAccuracyIndex = configManager.getDesiredAccuracy(),
                initialPeriodicInterval = configManager.getPeriodicLocationInterval(),
            )
        } else {
            // Turning the budget off must lift whatever it had imposed, or the
            // last overlay would outlive the engine that justified it (#396).
            locationEngine.applyBudgetOverlay(
                distanceFilter = null,
                desiredAccuracy = null,
                cadenceMultiplier = 1.0,
                trackingAccuracyFloor = 0,
            )
            null
        }
    }

    /**
     * Re-seeds the ladder's floor after the app changes its own tracking
     * parameters, so an overlay in force is recomputed against the new
     * configuration rather than against the one it was built with (#396).
     */
    private fun syncBatteryBudgetConfigured() {
        val engine = batteryBudgetEngine ?: return
        engine.updateConfigured(
            distanceFilter = configManager.getDistanceFilter(),
            accuracyIndex = configManager.getDesiredAccuracy(),
            periodicInterval = configManager.getPeriodicLocationInterval(),
        )
        val throttle = engine.throttleState
        if (throttle.level == 0) return
        locationEngine.applyBudgetOverlay(
            distanceFilter = throttle.distanceFilter,
            desiredAccuracy = throttle.desiredAccuracy,
            cadenceMultiplier = throttle.cadenceMultiplier,
            trackingAccuracyFloor = throttle.trackingAccuracyFloor,
        )
    }

    private fun startBatteryBudgetSampling() {
        stopBatteryBudgetSampling()
        val engine = batteryBudgetEngine ?: return

        batteryBudgetRunnable = object : Runnable {
            override fun run() {
                if (!stateManager.enabled) return

                // On external power the ladder comes all the way down. Skipping
                // the sample instead — as this did — left a throttle picked up
                // during a discharge in force for the rest of the session (#396).
                val event = if (BatteryUtils.isCharging(context)) {
                    engine.noteCharging()
                } else {
                    engine.processSample(BatteryUtils.getBatteryLevel(context))
                }
                if (event != null) {
                    applyBudgetThrottle(engine, event)
                }
                mainHandler.postDelayed(this, BATTERY_SAMPLE_INTERVAL_MS)
            }
        }
        mainHandler.postDelayed(batteryBudgetRunnable!!, BATTERY_SAMPLE_INTERVAL_MS)
    }

    private fun stopBatteryBudgetSampling() {
        batteryBudgetRunnable?.let { mainHandler.removeCallbacks(it) }
        batteryBudgetRunnable = null
    }

    /**
     * Puts a ladder movement into force as an overlay on the location engine.
     *
     * The pre-ladder version wrote the throttled values into [ConfigManager] and
     * restarted the engine. That is what made the throttle permanent and
     * invisible at once: `distanceFilter: 0` — the documented "record every fix"
     * opt-out — was clamped to 10 and written over the app's own value, so the
     * processor's protection for a configured zero no longer had anything to
     * protect, and `activeConfig` began reporting a configuration the app had
     * never set. The restart was the other half: it rebuilt the processor with
     * the throttled numbers as its *base* tuning (#393).
     *
     * The overlay does neither. The app's configuration is untouched, the engine
     * keeps running, and the whole thing lifts by passing nulls.
     */
    private fun applyBudgetThrottle(engine: BatteryBudgetEngine, event: BudgetAdjustmentEvent) {
        val throttle = engine.throttleState
        val throttled = throttle.level > 0

        locationEngine.applyBudgetOverlay(
            distanceFilter = if (throttled) throttle.distanceFilter else null,
            desiredAccuracy = if (throttled) throttle.desiredAccuracy else null,
            cadenceMultiplier = if (throttled) throttle.cadenceMultiplier else 1.0,
            trackingAccuracyFloor = throttle.trackingAccuracyFloor,
        )

        eventSender.sendBudgetAdjustment(
            mapOf(
                "currentBatteryDrain" to event.currentBatteryDrain,
                "targetBudget" to event.targetBudget,
                "newDistanceFilter" to event.newDistanceFilter,
                "newDesiredAccuracy" to event.newDesiredAccuracy,
                "newPeriodicInterval" to event.newPeriodicInterval,
                "throttleLevel" to throttle.level,
            )
        )

        // Lifecycle, not info: a throttle that silently changes how a session
        // behaves for the rest of its life is exactly the class of event a
        // released app has to be able to report (#397). It fires a handful of
        // times a session at most.
        TraceletLog.lifecycle(
            "battery budget: throttle level ${throttle.level} — " +
                "drain ${"%.1f".format(throttle.lastDrain)}%/hr vs " +
                "budget ${"%.1f".format(event.targetBudget)}%/hr " +
                "(measured over ${"%.0f".format(throttle.lastMeasurementSeconds)}s, " +
                "±${"%.1f".format(throttle.lastMeasurementResolution)}%/hr); " +
                "overlay df=${"%.1f".format(throttle.distanceFilter)}m " +
                "acc=${throttle.desiredAccuracy} " +
                "floor=${throttle.trackingAccuracyFloor}m " +
                "cadence=×${"%.2f".format(throttle.cadenceMultiplier)}",
        )
    }

    private fun startStopAfterElapsedTimer() {
        cancelStopAfterElapsedTimer()
        val minutes = configManager.getStopAfterElapsedMinutes()
        if (minutes <= 0) return

        stopAfterElapsedRunnable = Runnable {
            logger.info("stopAfterElapsedMinutes ($minutes min) — auto-stopping")
            stateManager.enabled = false
            stateManager.isMoving = false
            locationEngine.stop()
            motionDetector.stop()
            stopHeartbeat()
            if (configManager.isForegroundServiceEnabled()) {
                LocationService.stop(context)
            }
            eventSender.sendEnabledChange(false)
        }
        mainHandler.postDelayed(stopAfterElapsedRunnable!!, minutes * 60 * 1000L)
    }

    private fun cancelStopAfterElapsedTimer() {
        stopAfterElapsedRunnable?.let { mainHandler.removeCallbacks(it) }
        stopAfterElapsedRunnable = null
    }

    private fun updateBootReceiverState() {
        val enabled = configManager.getStartOnBoot() && !configManager.getStopOnTerminate()
        val componentName = ComponentName(context, BootReceiver::class.java)
        val newState = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        try {
            context.packageManager.setComponentEnabledSetting(
                componentName, newState, PackageManager.DONT_KILL_APP
            )
        } catch (e: Exception) {
            logger.warning("Failed to update BootReceiver state: ${e.message}")
        }
    }

    private fun carbonFactorForMode(mode: String): Double {
        return when (mode) {
            "in_vehicle" -> 192.0
            "on_bicycle", "walking", "running", "on_foot" -> 0.0
            else -> 96.0
        }
    }

    private fun haversineDistance(
        lat1: Double, lng1: Double,
        lat2: Double, lng2: Double,
    ): Double {
        val r = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
            Math.sin(dLng / 2) * Math.sin(dLng / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return r * c
    }

    // =========================================================================
    // Cleanup
    // =========================================================================

    fun destroyAll() {
        // When stopOnTerminate=false and tracking is active,
        // LocationService.onTaskRemoved() bootstraps native tracking
        // independently. Tearing down subsystems here races against that
        // bootstrap and kills background tracking — the bug reported in
        // issues #63 and #65.
        //
        // Only tear down when stopOnTerminate=true OR tracking is not active.
        val keepAlive = !configManager.getStopOnTerminate() && stateManager.enabled

        // LocationEngine — keep alive for continuous (0) and geofence (1) modes.
        // Periodic mode (2) has its own WorkManager/AlarmManager lifecycle.
        //
        // All subsystems are `lateinit` and are only constructed by initialize().
        // destroyAll() can run in a process/engine where initialize() never
        // executed — e.g. a secondary/headless Flutter engine that is the last to
        // detach (see TraceletAndroidPlugin.onDetachedFromEngine). Touching an
        // uninitialized lateinit here throws UninitializedPropertyAccessException,
        // which — being dispatched during engine/activity teardown — surfaces as
        // a fatal "Unable to destroy activity" (#227). Guard every access.
        if (!(keepAlive && stateManager.trackingMode != TrackingMode.PERIODIC)) {
            if (::locationEngine.isInitialized) locationEngine.destroy()
        }
        if (::motionDetector.isInitialized) motionDetector.stop()

        // GeofenceManager — geofences are a standalone feature: addGeofence()/
        // addGeofences() never require trackingMode == GEOFENCES, which is only
        // the dedicated geofence-only *session* started by startGeofences().
        // Geofences must therefore survive task removal on the same `keepAlive`
        // terms as everything else in this function, regardless of which
        // tracking mode is active.
        //
        // This was previously additionally gated on `trackingMode == GEOFENCES`,
        // so a `start()` (continuous) session with geofences added via
        // addGeofences() — a fully supported, documented combination — had
        // every geofence unregistered from Play Services on the very first
        // task removal, and nothing ever re-registered them afterwards
        // (LocationService.startBootTracking() had the matching GEOFENCES-only
        // gate on reRegisterAll(), fixed alongside this). Continuous tracking
        // itself kept working, which is why the geofence feature could die
        // silently and go unnoticed (#353).
        val keepGeofencesAlive = keepAlive
        if (!keepGeofencesAlive) {
            if (::geofenceManager.isInitialized) {
                // #353: the destroy/unregister path had no logging at all, so a
                // release-mode Doctor bug report could not show that this ran —
                // only that geofences had mysteriously stopped firing.
                TraceletLog.lifecycle(
                    "geofences: unregistering ${geofenceManager.getGeofences().size} " +
                        "geofence(s) on destroyAll() — mode=${stateManager.trackingMode} " +
                        "stopOnTerminate=${configManager.getStopOnTerminate()} " +
                        "enabled=${stateManager.enabled} (#353)"
                )
                geofenceManager.destroy()
            }
        }

        // HttpSyncManager — MUST survive for location uploads after task
        // removal. LocationService.onTaskRemoved() creates a boot-mode
        // HttpSyncManager, but the plugin's instance must not be torn down
        // before that bootstrap completes (#65).
        if (!keepAlive) {
            // TODO: Port to Rust
        // httpSyncManager.stop()
        }

        // ScheduleManager & heartbeat — keep alive for continuity.
        if (!keepAlive) {
            if (::scheduleManager.isInitialized) scheduleManager.stop()
            stopHeartbeat()
        }

        // Sound is safe to stop unconditionally — no background impact.
        if (::soundManager.isInitialized) soundManager.stop()

        // PeriodicLocationWorker — keep alive only in periodic mode (2).
        val keepPeriodicAlive = keepAlive && stateManager.trackingMode == TrackingMode.PERIODIC
        if (!keepPeriodicAlive) {
            PeriodicLocationWorker.cancel(context)
        }
        if (!keepPeriodicAlive) {
            PeriodicLocationWorker.eventSender = null
            // TODO: Port to Rust
        // PeriodicLocationWorker.httpSyncManager = null
        }
        if (!keepGeofencesAlive) {
            GeofenceBroadcastReceiver.geofenceManager = null
        }
    }

    /**
     * Synchronizes the active platform configuration stored in [configManager] 
     * to the underlying Rust Core [rustEngineState] instance.
     * 
     * This method maps every individual geolocation, motion, network, geofencing,
     * persistence, audit, database encryption, and device attestation property 
     * from the native Android ConfigManager directly into a UniFFI-exported 
     * [uniffi.tracelet_core.EngineConfig] record, ensuring the Rust core 
     * engine maintains perfect configuration parity with the platform layer.
     */
    private fun syncConfigToRustFlat() {
        val state = rustEngineState ?: return
        try {
            val newConfig = uniffi.tracelet_core.EngineConfig(
                geo = uniffi.tracelet_core.GeoConfig(
                    desiredAccuracy = configManager.getDesiredAccuracy(),
                    distanceFilter = configManager.getDistanceFilter(),
                    stationaryRadius = configManager.getStationaryRadius(),
                    locationTimeout = configManager.getLocationTimeout(),
                    disableElasticity = configManager.getDisableElasticity(),
                    elasticityMultiplier = configManager.getElasticityMultiplier(),
                    enableAdaptiveMode = configManager.getEnableAdaptiveMode(),
                    enableTimestampMeta = configManager.getEnableTimestampMeta(),
                    enableSparseUpdates = configManager.getEnableSparseUpdates(),
                    sparseDistanceThreshold = configManager.getSparseDistanceThreshold(),
                    stopAfterElapsedMinutes = configManager.getStopAfterElapsedMinutes(),
                    maxMonitoredGeofences = configManager.getMaxMonitoredGeofences(),
                    periodicLocationInterval = configManager.getPeriodicLocationInterval(),
                    periodicDesiredAccuracy = configManager.getPeriodicDesiredAccuracy(),
                    sparseMaxIdleSeconds = configManager.getSparseMaxIdleSeconds(),
                    batteryBudgetPerHour = configManager.getBatteryBudgetPerHour(),
                    enableDeadReckoning = configManager.getEnableDeadReckoning(),
                    deadReckoningActivationDelay = configManager.getDeadReckoningActivationDelay(),
                    deadReckoningMaxDuration = configManager.getDeadReckoningMaxDuration(),
                    resolveAddress = configManager.getResolveAddress()
                ),
                motion = uniffi.tracelet_core.MotionConfig(
                    stopTimeout = configManager.getStopTimeout(),
                    motionTriggerDelay = configManager.getMotionTriggerDelay(),
                    disableMotionActivityUpdates = configManager.isMotionActivityUpdatesDisabled(),
                    disableStopDetection = configManager.getDisableStopDetection(),
                    shakeThreshold = configManager.getShakeThreshold(),
                    isMoving = configManager.getIsMoving(),
                    activityRecognitionInterval = configManager.getActivityRecognitionInterval(),
                    minimumActivityRecognitionConfidence = configManager.getMinimumActivityRecognitionConfidence(),
                    stopDetectionDelay = configManager.getStopDetectionDelay(),
                    stopOnStationary = configManager.getStopOnStationary(),
                    stationaryRadius = configManager.getStationaryRadius(),
                    useSignificantChangesOnly = false,
                    stillThreshold = configManager.getStillThreshold(),
                    stillSampleCount = configManager.getStillSampleCount(),
                    motionDetectionMode = configManager.getMotionDetectionMode().value,
                    speedMovingThreshold = configManager.getSpeedMovingThreshold(),
                    speedStationaryThreshold = configManager.getSpeedStationaryThreshold(),
                    speedStationaryDelay = configManager.getSpeedStationaryDelay(),
                    stationaryTrackingMode = configManager.getStationaryTrackingMode().value,
                    stationaryPeriodicInterval = configManager.getStationaryPeriodicInterval(),
                    stationaryPeriodicAccuracy = configManager.getStationaryPeriodicAccuracy(),
                    speedWakeConfirmCount = configManager.getSpeedWakeConfirmCount()
                ),
                http = uniffi.tracelet_core.HttpConfig(
                    url = configManager.getHttpUrl(),
                    method = configManager.getHttpMethod(),
                    headers = HashMap(configManager.getMergedHttpHeaders()),
                    batchSync = configManager.getBatchSync(),
                    maxBatchSize = configManager.getMaxBatchSize(),
                    autoSync = configManager.getAutoSync(),
                    maxRetries = configManager.getMaxRetries(),
                    retryBackoffBase = configManager.getRetryBackoffBase(),
                    retryBackoffCap = configManager.getRetryBackoffCap(),
                    autoSyncDelay = configManager.getAutoSyncDelay(),
                    sslPinningCertificates = configManager.getSslPinningCertificates().takeIf { it.isNotEmpty() },
                    sslPinningFingerprints = configManager.getSslPinningFingerprints().takeIf { it.isNotEmpty() },
                    httpRootProperty = configManager.getHttpRootProperty(),
                    params = HashMap(configManager.getHttpParams().filterValues { it != null }.mapValues { it.value.toString() }),
                    extras = HashMap(configManager.getHttpExtras().filterValues { it != null }.mapValues { it.value.toString() }),
                    disableAutoSyncOnCellular = configManager.getDisableAutoSyncOnCellular(),
                    enableDeltaCompression = configManager.getEnableDeltaCompression(),
                    deltaCoordinatePrecision = configManager.getDeltaCoordinatePrecision(),
                    locationsOrderDirection = configManager.getLocationsOrderDirection(),
                    autoSyncThreshold = configManager.getAutoSyncThreshold(),
                    httpTimeout = configManager.getHttpTimeout(),
                    syncInterval = configManager.getSyncInterval(),
                    syncTelematics = configManager.getSyncTelematics(),
                    telematicsUrl = configManager.getTelematicsUrl()
                ),
                geofence = uniffi.tracelet_core.GeofenceConfig(
                    geofenceInitialTrigger = configManager.getGeofenceInitialTrigger(),
                    geofenceInitialTriggerEntry = configManager.getGeofenceInitialTriggerEntry(),
                    geofenceProximityRadius = configManager.getGeofenceProximityRadius()
                ),
                persistence = uniffi.tracelet_core.PersistenceConfig(
                    maxDaysToPersist = configManager.getMaxDaysToPersist(),
                    maxRecordsToPersist = configManager.getMaxRecordsToPersist()
                ),
                audit = uniffi.tracelet_core.AuditConfig(
                    enabled = configManager.getAuditEnabled()
                ),
                security = uniffi.tracelet_core.SecurityConfig(
                    encryptDatabase = configManager.getEncryptDatabase()
                ),
                attestation = uniffi.tracelet_core.AttestationConfig(
                    enabled = configManager.getAttestationEnabled()
                )
            )
            state.updateConfig(newConfig)
            logger.info("Successfully synchronized ConfigManager state to Rust Core.")
        } catch (e: Exception) {
            logger.error("Failed to sync config to Rust Core: ${e.message}")
        }
    }
}
