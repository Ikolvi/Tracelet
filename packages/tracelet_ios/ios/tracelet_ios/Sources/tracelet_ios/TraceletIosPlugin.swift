import Flutter
import UIKit

/// TraceletIosPlugin — Full iOS implementation of the Tracelet plugin.
///
/// Wires together all subsystems:
/// - ConfigManager / StateManager (persistence)
/// - LocationEngine (CLLocationManager)
/// - MotionDetector (CMMotionActivityManager + CMPedometer)
/// - GeofenceManager (CLCircularRegion monitoring)
/// - TraceletDatabase (SQLite3)
/// - HttpSyncManager (URLSession)
/// - HeadlessRunner (background Dart execution)
/// - ScheduleManager (BGTaskScheduler)
/// - TraceletLogger / SoundManager / PermissionManager
/// - EventDispatcher (15 EventChannels → Dart)
public class TraceletIosPlugin: NSObject, FlutterPlugin {

    private var channel: FlutterMethodChannel!

    // Core subsystems
    private var configManager: ConfigManager!
    private var stateManager: StateManager!
    private var eventDispatcher: EventDispatcher!
    private var database: TraceletDatabase!
    private var locationEngine: LocationEngine!
    private var motionDetector: MotionDetector!
    private var geofenceManager: GeofenceManager!
    private var httpSyncManager: HttpSyncManager!
    private var headlessRunner: HeadlessRunner!
    private var scheduleManager: ScheduleManager!
    private var logger: TraceletLogger!
    private var soundManager: SoundManager!
    private var permissionManager: PermissionManager!
    private var preventSuspendManager: PreventSuspendManager!
    private var backgroundActivitySessionManager: BackgroundActivitySessionManager!
    private var serviceSessionManager: ServiceSessionManager!
    private var periodicRefreshScheduler: PeriodicRefreshScheduler!

    private var heartbeatTimer: Timer?
    private var stopAfterElapsedTimer: Timer?
    private var isReady = false

    /// [Enterprise] Tamper-proof audit trail manager.
    private var auditTrailManager: AuditTrailManager!

    /// [Enterprise] Privacy zone manager.
    private var privacyZoneManager: PrivacyZoneManager!

    // MARK: - FlutterPlugin registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.tracelet/methods",
            binaryMessenger: registrar.messenger()
        )
        let instance = TraceletIosPlugin()
        instance.channel = channel

        // EventChannels
        instance.eventDispatcher = EventDispatcher()
        instance.eventDispatcher.register(messenger: registrar.messenger())

        // Register bootstrap factories so core engines can construct
        // event senders and headless dispatchers after killed-state relaunch.
        TraceletBootstrapIOS.eventSenderFactory = { EventDispatcher() }
        TraceletBootstrapIOS.headlessDispatcherFactory = { HeadlessRunner() }

        // Persistence
        instance.configManager = ConfigManager()
        instance.stateManager = StateManager()
        instance.database = TraceletDatabase.shared

        // Battery monitoring — enable once at setup
        BatteryUtils.initialize()

        // Logger
        instance.logger = TraceletLogger(
            configManager: instance.configManager,
            database: instance.database
        )

        // Location
        instance.locationEngine = LocationEngine(
            configManager: instance.configManager,
            stateManager: instance.stateManager,
            eventDispatcher: instance.eventDispatcher,
            database: instance.database
        )

        // [Enterprise] Audit Trail
        instance.auditTrailManager = AuditTrailManager(
            database: instance.database,
            configManager: instance.configManager
        )
        // Wire location persistence → HTTP auto-sync trigger
        instance.locationEngine.onLocationPersisted = { [weak instance] in
            instance?.httpSyncManager.onLocationInserted()
        }

        instance.locationEngine.auditTrailManager = instance.auditTrailManager

        // [Enterprise] Privacy Zones
        instance.privacyZoneManager = PrivacyZoneManager(
            database: instance.database,
            configManager: instance.configManager
        )
        instance.locationEngine.privacyZoneManager = instance.privacyZoneManager

        // Trip detection is now handled in Dart

        // Motion
        instance.motionDetector = MotionDetector(
            configManager: instance.configManager,
            stateManager: instance.stateManager,
            eventDispatcher: instance.eventDispatcher
        )
        instance.motionDetector.onMotionStateChanged = { [weak instance] isMoving in
            instance?.handleMotionStateChange(isMoving)
        }
        instance.motionDetector.onStopRequested = { [weak instance] in
            guard let instance = instance else { return }
            // Protect teardown — state writes + event dispatch.
            BackgroundTaskHelper.shared.run("stopOnStationary") {
                // stopOnStationary: fully stop tracking
                instance.stateManager.enabled = false
                instance.stateManager.isMoving = false
                instance.locationEngine.stop()
                instance.motionDetector.stop()
                instance.stopHeartbeat()
                instance.periodicRefreshScheduler.stop()
                instance.preventSuspendManager.stop()
                instance.backgroundActivitySessionManager.stop()
                instance.serviceSessionManager.stop()
                instance.eventDispatcher.sendEnabledChange(false)
                instance.logger.info("stopOnStationary — tracking stopped by motion detector")
            }
        }

        // Geofencing
        instance.geofenceManager = GeofenceManager(
            configManager: instance.configManager,
            eventDispatcher: instance.eventDispatcher,
            database: instance.database
        )

        // HTTP
        instance.httpSyncManager = HttpSyncManager(
            configManager: instance.configManager,
            eventDispatcher: instance.eventDispatcher,
            database: instance.database
        )

        // Headless
        instance.headlessRunner = HeadlessRunner()

        // Wire headless fallback — when no Dart UI listener exists for an event,
        // EventDispatcher routes it to HeadlessRunner.
        instance.eventDispatcher.headlessFallback = { [weak instance] eventName, eventData in
            guard let runner = instance?.headlessRunner else { return }
            let event: [String: Any] = [
                "name": eventName,
                "event": eventData,
            ]
            runner.dispatchEvent(event)
        }

        // Schedule
        instance.scheduleManager = ScheduleManager(
            configManager: instance.configManager,
            stateManager: instance.stateManager,
            eventDispatcher: instance.eventDispatcher
        )
        instance.scheduleManager.onScheduleStart = { [weak instance] in
            instance?.handleScheduleStart()
        }
        instance.scheduleManager.onScheduleStop = { [weak instance] in
            instance?.handleScheduleStop()
        }

        // Sound
        instance.soundManager = SoundManager(configManager: instance.configManager)

        // Prevent Suspend
        instance.preventSuspendManager = PreventSuspendManager(configManager: instance.configManager)

        // iOS 17+ background session managers
        instance.backgroundActivitySessionManager = BackgroundActivitySessionManager()
        instance.serviceSessionManager = ServiceSessionManager()

        // Periodic refresh (BGAppRefreshTask)
        instance.periodicRefreshScheduler = PeriodicRefreshScheduler()
        instance.periodicRefreshScheduler.registerTask()
        instance.periodicRefreshScheduler.onWakeUp = { [weak instance] in
            guard let instance = instance,
                  instance.stateManager.enabled,
                  instance.stateManager.trackingMode == 2 else { return }
            instance.locationEngine.performPeriodicFix()
            // Restart the in-memory periodic timer. After iOS suspends the
            // app, the Timer dies. When BGAppRefreshTask wakes the app,
            // restarting the timer ensures fixes continue if the app stays
            // alive (e.g., user came back to foreground).
            instance.locationEngine.restartPeriodicTimerIfNeeded()
        }

        // Permissions
        instance.permissionManager = PermissionManager()

        registrar.addMethodCallDelegate(instance, channel: channel)

        // Register as application delegate so we receive
        // application(_:didFinishLaunchingWithOptions:) for
        // significant-location-change relaunches from killed state.
        registrar.addApplicationDelegate(instance)
    }

    // MARK: - UIApplicationDelegate (killed-state relaunch)

    /// Called when the app is launched — including when iOS relaunches
    /// it in the background due to a significant location change.
    ///
    /// If `LaunchOptionsKey.location` is present, it means iOS killed
    /// the app and then relaunched it because a significant location
    /// change was detected. We check persisted state and auto-resume
    /// the previous tracking mode.
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]? = nil
    ) -> Bool {
        let launchedForLocation = (launchOptions?[UIApplication.LaunchOptionsKey.location] as? Bool) == true

        if launchedForLocation {
            stateManager.didLaunchInBackground = true
            NSLog("[Tracelet] App relaunched by significant location change — checking auto-resume")
            autoResumeTracking()
        }
        return true
    }

    // MARK: - MethodCallHandler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // Lifecycle
        case "ready":
            handleReady(call, result: result)
        case "start":
            handleStart(result: result)
        case "stop":
            handleStop(result: result)
        case "startPeriodic":
            handleStartPeriodic(result: result)
        case "startGeofences":
            handleStartGeofences(result: result)
        case "getState":
            result(stateManager.toMap(configManager.getConfig()))
        case "setConfig":
            handleSetConfig(call, result: result)
        case "reset":
            handleReset(call, result: result)

        // Location
        case "getCurrentPosition":
            handleGetCurrentPosition(call, result: result)
        case "getLastKnownLocation":
            handleGetLastKnownLocation(call, result: result)
        case "watchPosition":
            handleWatchPosition(call, result: result)
        case "stopWatchPosition":
            let watchId = call.arguments as? Int ?? -1
            result(locationEngine.stopWatchPosition(watchId))
        case "changePace":
            let isMoving = call.arguments as? Bool ?? false
            let changePaceResult = locationEngine.changePace(isMoving)

            // Feed trip manager so manual pace changes trigger trip start/end
            let locationMap: [String: Any]
            if let last = locationEngine.getLastLocation() {
                var map = locationEngine.buildLocationMap(last, speed: locationEngine.lastEffectiveSpeed)
                map["isMoving"] = isMoving
                map["event"] = "motionchange"
                locationMap = map
            } else {
                locationMap = ["isMoving": isMoving]
            }
            result(changePaceResult)
        case "getOdometer":
            result(locationEngine.getOdometer())
        case "setOdometer":
            let value = (call.arguments as? NSNumber)?.doubleValue ?? 0.0
            result(locationEngine.setOdometer(value))

        // Geofencing
        case "addGeofence":
            let geofence = call.arguments as? [String: Any] ?? [:]
            result(geofenceManager.addGeofence(geofence))
        case "addGeofences":
            let geofences = call.arguments as? [[String: Any]] ?? []
            result(geofenceManager.addGeofences(geofences))
        case "removeGeofence":
            let id = call.arguments as? String ?? ""
            result(geofenceManager.removeGeofence(id))
        case "removeGeofences":
            result(geofenceManager.removeGeofences())
        case "getGeofences":
            result(geofenceManager.getGeofences())
        case "getGeofence":
            let id = call.arguments as? String ?? ""
            result(geofenceManager.getGeofence(id) as Any)
        case "geofenceExists":
            let id = call.arguments as? String ?? ""
            result(geofenceManager.geofenceExists(id))

        // Persistence
        case "getLocations":
            handleGetLocations(call, result: result)
        case "getCount":
            let countQuery = call.arguments as? [String: Any]
            let countStart = (countQuery?["start"] as? NSNumber)?.int64Value
            let countEnd = (countQuery?["end"] as? NSNumber)?.int64Value
            result(database.getLocationCount(startTime: countStart, endTime: countEnd))
        case "destroyLocations":
            result(database.deleteAllLocations())
        case "destroyLocation":
            let uuid = call.arguments as? String ?? ""
            result(database.deleteLocation(uuid))
        case "insertLocation":
            let params = call.arguments as? [String: Any] ?? [:]
            let uuid = database.insertLocation(params)
            httpSyncManager.onLocationInserted()
            result(uuid)

        // HTTP Sync
        case "sync":
            httpSyncManager.sync { synced in
                result(synced)
            }

        // Utility
        case "isPowerSaveMode":
            result(permissionManager.isPowerSaveMode())
        case "getPermissionStatus":
            result(permissionManager.getAuthorizationStatus())
        case "requestPermission":
            permissionManager.requestPermission(result: result)
        case "getNotificationPermissionStatus":
            result(3) // iOS: not needed for foreground location — always "granted"
        case "requestNotificationPermission":
            result(3) // iOS: not needed for foreground location — always "granted"
        case "canScheduleExactAlarms":
            result(true) // iOS has no exact alarm permission — BGAppRefreshTask is used instead
        case "openExactAlarmSettings":
            result(false) // No-op on iOS — no exact alarm settings page
        case "getMotionPermissionStatus":
            result(motionDetector.getMotionAuthorizationStatus())
        case "requestMotionPermission":
            motionDetector.requestMotionPermission { status in
                result(status)
            }
        case "requestTemporaryFullAccuracy":
            let purposeKey = call.arguments as? String ?? "default"
            result(permissionManager.requestTemporaryFullAccuracy(purposeKey: purposeKey))
        case "getProviderState":
            result(locationEngine.buildProviderState())
        case "getSensors":
            result(motionDetector.getSensors())
        case "getDeviceInfo":
            result(getDeviceInfo())
        case "playSound":
            let name = call.arguments as? String ?? ""
            result(soundManager.playSound(name))
        case "isIgnoringBatteryOptimizations":
            result(true) // iOS doesn't have battery optimization settings like Android
        case "requestSettings":
            let action = call.arguments as? String ?? ""
            result(handleRequestSettings(action))
        case "showSettings":
            let action = call.arguments as? String ?? ""
            result(handleShowSettings(action))

        // OEM Compatibility (iOS has no aggressive OEM power management)
        case "getSettingsHealth":
            let device = UIDevice.current
            result([
                "manufacturer": "Apple",
                "model": device.model,
                "isAggressiveOem": false,
                "aggressionRating": 0,
                "isIgnoringBatteryOptimizations": true,
                "autostartAvailable": false,
                "oemSettingsScreens": [] as [[String: String]],
            ] as [String: Any])
        case "openOemSettings":
            result(false) // No OEM settings on iOS

        // Background Tasks
        case "startBackgroundTask":
            let taskId = BackgroundTaskHelper.shared.begin("dartBackground")
            result(taskId?.rawValue ?? UIBackgroundTaskIdentifier.invalid.rawValue)
        case "stopBackgroundTask":
            let rawId = (call.arguments as? NSNumber)?.intValue ?? 0
            BackgroundTaskHelper.shared.end(UIBackgroundTaskIdentifier(rawValue: rawId))
            result(rawId)

        // Logging
        case "getLog":
            let query = call.arguments as? [String: Any]
            let logs = logger.getLog(query: query)
            let lines = logs.map { entry -> String in
                let ts = entry["timestamp"] as? String ?? ""
                let level = entry["level"] as? String ?? ""
                let msg = entry["message"] as? String ?? ""
                return "[\(ts)] \(level): \(msg)"
            }
            result(lines.joined(separator: "\n"))
        case "destroyLog":
            result(logger.destroyLog())
        case "emailLog":
            handleEmailLog(call, result: result)
        case "log":
            let args = call.arguments as? [Any]
            let level = args?.first as? String ?? "INFO"
            let message = args?.last as? String ?? ""
            logger.log(levelString: level, message: message)
            result(true)

        // Scheduling
        case "startSchedule":
            scheduleManager.start()
            result(stateManager.toMap(configManager.getConfig()))
        case "stopSchedule":
            scheduleManager.stop()
            result(stateManager.toMap(configManager.getConfig()))

        // Headless
        case "registerHeadlessTask":
            handleRegisterHeadlessTask(call, result: result)

        // [Enterprise] Audit Trail
        case "verifyAuditTrail":
            result(auditTrailManager.verifyChain())
        case "getAuditProof":
            let uuid = call.arguments as? String ?? ""
            result(auditTrailManager.getProof(uuid: uuid))

        // [Enterprise] Privacy Zones
        case "addPrivacyZone":
            let zone = call.arguments as? [String: Any] ?? [:]
            result(privacyZoneManager.addZone(zone))
        case "addPrivacyZones":
            let zones = call.arguments as? [[String: Any]] ?? []
            result(privacyZoneManager.addZones(zones))
        case "removePrivacyZone":
            let identifier = call.arguments as? String ?? ""
            result(privacyZoneManager.removeZone(identifier))
        case "removePrivacyZones":
            result(privacyZoneManager.removeAllZones())
        case "getPrivacyZones":
            result(privacyZoneManager.getZones())

        // Legacy
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Lifecycle handlers

    private func handleReady(_ call: FlutterMethodCall, result: FlutterResult) {
        let configMap = call.arguments as? [String: Any] ?? [:]
        let merged = configManager.setConfig(configMap)

        if configManager.isDebug() { soundManager.start() }
        httpSyncManager.start()
        logger.pruneOldLogs()

        isReady = true
        logger.info("ready() called")
        result(stateManager.toMap(merged))
    }

    private func handleStart(result: FlutterResult) {
        guard isReady else {
            result(FlutterError(code: "NOT_READY", message: "Call ready() before start()", details: nil))
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 0
        stateManager.isMoving = false

        // Stop any active periodic tracking before switching to continuous mode.
        locationEngine.stopPeriodic()
        periodicRefreshScheduler.stop()

        locationEngine.start()

        // Wire proximity-based geofence monitoring so geofences are
        // automatically loaded/unloaded as the device moves.
        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
        }

        motionDetector.start()
        startHeartbeat()
        startStopAfterElapsedTimer()
        preventSuspendManager.start()
        backgroundActivitySessionManager.start()
        serviceSessionManager.start()

        eventDispatcher.sendEnabledChange(true)
        logger.info("start() — tracking started")
        result(stateManager.toMap(configManager.getConfig()))
    }

    private func handleStop(result: FlutterResult) {
        // Protect shutdown sequence with a background task so iOS doesn't
        // suspend us before state is fully persisted.
        BackgroundTaskHelper.shared.run("stop") {
            stateManager.enabled = false
            stateManager.isMoving = false

            locationEngine.stop()
            locationEngine.onLocationUpdate = nil // clear high-accuracy geofence listener
            motionDetector.stop()
            stopHeartbeat()
            cancelStopAfterElapsedTimer()
            periodicRefreshScheduler.stop()
            preventSuspendManager.stop()
            backgroundActivitySessionManager.stop()
            serviceSessionManager.stop()

            eventDispatcher.sendEnabledChange(false)
            logger.info("stop() — tracking stopped")
        }
        result(stateManager.toMap(configManager.getConfig()))
    }

    private func handleStartPeriodic(result: FlutterResult) {
        guard isReady else {
            result(FlutterError(code: "NOT_READY", message: "Call ready() before startPeriodic()", details: nil))
            return
        }

        // Stop any active continuous tracking before switching to periodic mode.
        // Without this, startUpdatingLocation() remains active and the blue
        // arrow stays permanently visible in the status bar.
        locationEngine.stop()
        motionDetector.stop()

        stateManager.enabled = true
        stateManager.trackingMode = 2 // Periodic
        stateManager.isMoving = false

        locationEngine.startPeriodic()

        // Wire proximity-based geofence monitoring
        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
        }

        // Do NOT start the heartbeat timer in periodic mode. The heartbeat
        // calls getCurrentPosition() → requestLocation() on every tick
        // (default: every 60 s), which activates GPS and causes the location
        // icon to appear nearly continuously. The periodic timer already
        // provides location fixes at the configured periodicLocationInterval.
        // startHeartbeat() — intentionally omitted for periodic mode.
        startStopAfterElapsedTimer()

        // Schedule BGAppRefreshTask as a supplementary wake-up mechanism.
        // When iOS suspends the app, the in-memory Timer dies. This ensures
        // the app gets woken up periodically (best-effort) to capture a fix.
        let interval = TimeInterval(configManager.getPeriodicLocationInterval())
        periodicRefreshScheduler.start(interval: interval)

        // Do NOT start preventSuspendManager by default for periodic mode.
        // Users can explicitly enable it via AppConfig.preventSuspend for
        // guaranteed timer execution while backgrounded.
        if configManager.getPreventSuspend() {
            preventSuspendManager.start()
        }

        // iOS 18+: Start CLServiceSession to preserve authorization across
        // suspension/termination. Choose the correct authorization level
        // based on what the user granted.
        startServiceSessionForCurrentAuth()

        eventDispatcher.sendEnabledChange(true)
        logger.info("startPeriodic() — periodic tracking started (interval=\(configManager.getPeriodicLocationInterval())s)")
        result(stateManager.toMap(configManager.getConfig()))
    }

    // MARK: - Auto-resume from killed state

    /// Automatically resumes tracking after the app is relaunched from a
    /// killed state by a significant location change.
    ///
    /// Checks persisted state (`enabled`, `trackingMode`) and restarts the
    /// appropriate tracking mode. Events are dispatched via the headless
    /// runner since the Flutter UI isn't active yet.
    private func autoResumeTracking() {
        guard stateManager.enabled else {
            NSLog("[Tracelet] Auto-resume skipped — tracking was not enabled")
            return
        }

        // Guard: killed-state relaunch requires "Always" authorization.
        // If the user only granted "When In Use" or revoked permission,
        // do NOT resume tracking — it would run without valid authorization
        // and violate platform policy.
        let authStatus = locationEngine.getAuthorizationStatus()
        guard authStatus == 3 else { // 3 = authorizedAlways
            NSLog("[Tracelet] Auto-resume skipped — authorization is \(authStatus) (not Always), disabling tracking state")
            stateManager.enabled = false
            return
        }
        NSLog("[Tracelet] Auto-resume — authorization is Always, proceeding with killed-state resume")

        // The plugin was registered by Flutter, so subsystems are initialized.
        // However, ready() hasn't been called from Dart yet (no UI).
        // We can directly start native engines since config is persisted.

        let trackingMode = stateManager.trackingMode
        NSLog("[Tracelet] Auto-resume — restoring trackingMode=\(trackingMode)")

        switch trackingMode {
        case 0:
            // Continuous location tracking
            locationEngine.start()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
            }
            motionDetector.start()
            startHeartbeat()
            preventSuspendManager.start()
            backgroundActivitySessionManager.start()
            serviceSessionManager.start()
            logger.info("Auto-resumed continuous tracking from killed state")

        case 1:
            // Geofence-only
            geofenceManager.reRegisterAll()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
            }
            locationEngine.start()
            preventSuspendManager.start()
            backgroundActivitySessionManager.start()
            serviceSessionManager.start()
            logger.info("Auto-resumed geofence tracking from killed state")

        case 2:
            // Periodic one-shot
            locationEngine.startPeriodic()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
            }
            startHeartbeat()
            let interval = TimeInterval(configManager.getPeriodicLocationInterval())
            periodicRefreshScheduler.start(interval: interval)
            if configManager.getPreventSuspend() {
                preventSuspendManager.start()
            }
            startServiceSessionForCurrentAuth()
            logger.info("Auto-resumed periodic tracking from killed state (interval=\(configManager.getPeriodicLocationInterval())s)")

        default:
            NSLog("[Tracelet] Auto-resume — unknown trackingMode \(trackingMode), skipping")
        }
    }

    /// Starts a `CLServiceSession` (iOS 18+) with the authorization level
    /// matching the user's current permission grant.
    ///
    /// - **Always** → `serviceSessionManager.start()` (preserves full auth
    ///   across termination, enabling killed-state relaunches).
    /// - **When In Use** → `serviceSessionManager.startWhenInUse()` (preserves
    ///   foreground authorization context while backgrounded).
    private func startServiceSessionForCurrentAuth() {
        let status = locationEngine.getAuthorizationStatus()
        switch status {
        case 3: // authorizedAlways
            serviceSessionManager.start()
        case 2: // authorizedWhenInUse
            serviceSessionManager.startWhenInUse()
        default:
            // Not authorized — no session needed
            break
        }
    }

    private func handleStartGeofences(result: FlutterResult) {
        guard isReady else {
            result(FlutterError(code: "NOT_READY", message: "Call ready() before startGeofences()", details: nil))
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 1

        geofenceManager.reRegisterAll()

        // Wire proximity-based geofence monitoring so geofences are
        // automatically loaded/unloaded as the device moves.
        // Also handles high-accuracy mode (Dart evaluates transitions).
        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
        }

        // geofenceModeHighAccuracy: also start GPS tracking and compute
        // transitions in-app for more precise enter/exit detection.
        if configManager.getGeofenceModeHighAccuracy() {
            geofenceManager.clearHighAccuracyState()
            locationEngine.start()
        } else {
            // Start location engine for proximity updates
            locationEngine.start()
        }

        preventSuspendManager.start()
        backgroundActivitySessionManager.start()
        serviceSessionManager.start()

        eventDispatcher.sendEnabledChange(true)
        logger.info("startGeofences() — geofence-only mode (highAccuracy=\(configManager.getGeofenceModeHighAccuracy()))")
        result(stateManager.toMap(configManager.getConfig()))
    }

    private func handleSetConfig(_ call: FlutterMethodCall, result: FlutterResult) {
        let wasPreventing = configManager.getPreventSuspend()
        let configMap = call.arguments as? [String: Any] ?? [:]
        let merged = configManager.setConfig(configMap)

        if stateManager.enabled {
            if stateManager.trackingMode == 2 {
                // Periodic mode — restart periodic tracking, not continuous.
                locationEngine.stopPeriodic()
                locationEngine.startPeriodic()
                // Re-schedule the BGAppRefreshTask with possibly updated interval
                periodicRefreshScheduler.stop()
                periodicRefreshScheduler.start(
                    interval: TimeInterval(configManager.getPeriodicLocationInterval())
                )
            } else {
                locationEngine.stop()
                locationEngine.start()
            }

            // Toggle preventSuspend if it changed mid-session
            let nowPreventing = configManager.getPreventSuspend()
            if nowPreventing && !wasPreventing {
                preventSuspendManager.start()
            } else if !nowPreventing && wasPreventing {
                preventSuspendManager.stop()
            }
        }

        result(stateManager.toMap(merged))
    }

    private func handleReset(_ call: FlutterMethodCall, result: FlutterResult) {
        // Protect teardown with a background task — DB deletes + state writes.
        BackgroundTaskHelper.shared.run("reset") {
            locationEngine.destroy()
            motionDetector.stop()
            stopHeartbeat()
            cancelStopAfterElapsedTimer()
            periodicRefreshScheduler.stop()

            // Only destroy geofences if stopOnTerminate is true or geofence mode
            // is not active. When stopOnTerminate is false and geofence mode is
            // active, CLLocationManager region registrations must survive so the
            // OS can still deliver transition events after app termination.
            let keepGeofencesAlive = !configManager.getStopOnTerminate()
                && stateManager.enabled
                && stateManager.trackingMode == 1
            if !keepGeofencesAlive {
                geofenceManager.destroy()
            }

            preventSuspendManager.stop()
            backgroundActivitySessionManager.stop()
            serviceSessionManager.stop()

            stateManager.reset()
            let newConfig = call.arguments as? [String: Any]
            configManager.reset(newConfig)

            isReady = false
            logger.info("reset() — all subsystems reset")
        }
        result(stateManager.toMap(configManager.getConfig()))
    }

    // MARK: - Location handlers

    private func handleGetCurrentPosition(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let options = call.arguments as? [String: Any] ?? [:]
        locationEngine.getCurrentPosition(options: options) { location in
            if let location = location {
                result(location)
            } else {
                result(FlutterError(code: "LOCATION_UNAVAILABLE", message: "Could not get current position", details: nil))
            }
        }
    }

    private func handleGetLastKnownLocation(_ call: FlutterMethodCall, result: FlutterResult) {
        let options = call.arguments as? [String: Any] ?? [:]
        locationEngine.getLastKnownLocation(options: options) { location in
            if let location = location {
                result(location)
            } else {
                // Return empty dict — nil means "no cached location"
                result([String: Any]())
            }
        }
    }

    private func handleWatchPosition(_ call: FlutterMethodCall, result: FlutterResult) {
        let options = call.arguments as? [String: Any] ?? [:]
        let watchId = locationEngine.watchPosition(options: options)
        result(watchId)
    }

    // MARK: - Persistence handlers

    private func handleGetLocations(_ call: FlutterMethodCall, result: FlutterResult) {
        let query = call.arguments as? [String: Any]
        let limit = (query?["limit"] as? NSNumber)?.intValue ?? -1
        let offset = (query?["offset"] as? NSNumber)?.intValue ?? 0
        let orderAsc = (query?["order"] as? NSNumber)?.intValue != 1
        let startTime = (query?["start"] as? NSNumber)?.int64Value
        let endTime = (query?["end"] as? NSNumber)?.int64Value
        result(database.getLocations(limit: limit, offset: offset, orderAsc: orderAsc, startTime: startTime, endTime: endTime))
    }

    // MARK: - Utility handlers

    private func getDeviceInfo() -> [String: Any] {
        return [
            "model": UIDevice.current.model,
            "manufacturer": "Apple",
            "version": UIDevice.current.systemVersion,
            "platform": "ios",
            "framework": "flutter",
        ]
    }

    private func handleRequestSettings(_ action: String) -> Bool {
        switch action {
        case "location":
            return permissionManager.showLocationSettings()
        default:
            return false
        }
    }

    private func handleShowSettings(_ action: String) -> Bool {
        switch action {
        case "location":
            return permissionManager.showLocationSettings()
        case "app":
            return permissionManager.showAppSettings()
        default:
            return false
        }
    }

    private func handleEmailLog(_ call: FlutterMethodCall, result: FlutterResult) {
        let email = call.arguments as? String ?? ""
        let logContent = logger.getLogForEmail()

        // Note: UIActivityViewController requires a presenting view controller.
        // In Flutter context, we use the root VC.
        guard let rootVC = UIApplication.shared.keyWindow?.rootViewController else {
            result(false)
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: ["Tracelet Log\n\n\(logContent)"],
            applicationActivities: nil
        )
        rootVC.present(activityVC, animated: true)
        result(true)
    }

    // MARK: - Headless task handler

    private func handleRegisterHeadlessTask(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let callbackIds = call.arguments as? [Any],
              let registrationId = (callbackIds.first as? NSNumber)?.int64Value,
              let dispatchId = (callbackIds.last as? NSNumber)?.int64Value else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected list of callback IDs", details: nil))
            return
        }
        headlessRunner.registerCallbacks(registrationId, dispatchId)
        result(true)
    }

    // MARK: - Motion state handling

    private func handleMotionStateChange(_ isMoving: Bool) {
        logger.debug("Motion state changed: isMoving=\(isMoving)")
        stateManager.isMoving = isMoving

        if isMoving {
            locationEngine.start()
            soundManager.playMotionChange(isMoving: true)
        } else {
            locationEngine.stop()
            soundManager.playMotionChange(isMoving: false)
        }

        let locationMap: [String: Any]
        if let last = locationEngine.getLastLocation() {
            var map = locationEngine.buildLocationMap(last, speed: locationEngine.lastEffectiveSpeed)
            map["isMoving"] = isMoving
            map["event"] = "motionchange"
            locationMap = map
        } else {
            locationMap = ["isMoving": isMoving]
        }

        eventDispatcher.sendMotionChange(locationMap)
    }

    // MARK: - Schedule callbacks

    private func handleScheduleStart() {
        stateManager.enabled = true
        locationEngine.start()
        motionDetector.start()
        startHeartbeat()
        backgroundActivitySessionManager.start()
        serviceSessionManager.start()
        eventDispatcher.sendEnabledChange(true)
    }

    private func handleScheduleStop() {
        // Protect teardown — state writes + event dispatch.
        BackgroundTaskHelper.shared.run("scheduleStop") {
            stateManager.enabled = false
            locationEngine.stop()
            motionDetector.stop()
            stopHeartbeat()
            periodicRefreshScheduler.stop()
            preventSuspendManager.stop()
            backgroundActivitySessionManager.stop()
            serviceSessionManager.stop()
            eventDispatcher.sendEnabledChange(false)
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        let interval = configManager.getHeartbeatInterval()
        guard interval > 0 else { return }

        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(interval),
            repeats: true
        ) { [weak self] _ in
            guard let self = self, self.stateManager.enabled else { return }
            self.locationEngine.getCurrentPosition(options: [:]) { location in
                // Use fresh fix; fall back to last known location enriched as a map
                let locationData: [String: Any]
                if let loc = location {
                    locationData = loc
                } else if let lastLoc = self.locationEngine.getLastLocation() {
                    locationData = self.locationEngine.buildLocationMap(lastLoc)
                } else {
                    locationData = [:]
                }
                // Wrap in {"location": ...} to match HeartbeatEvent.fromMap
                self.eventDispatcher.sendHeartbeat(["location": locationData])
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - stopAfterElapsedMinutes

    private func startStopAfterElapsedTimer() {
        cancelStopAfterElapsedTimer()
        let minutes = configManager.getStopAfterElapsedMinutes()
        guard minutes > 0 else { return }

        stopAfterElapsedTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(minutes * 60),
            repeats: false
        ) { [weak self] _ in
            guard let self = self else { return }
            // Protect teardown — state writes + event dispatch.
            BackgroundTaskHelper.shared.run("stopAfterElapsed") {
                self.logger.info("stopAfterElapsedMinutes (\(minutes) min) — auto-stopping")
                self.stateManager.enabled = false
                self.stateManager.isMoving = false
                self.locationEngine.stop()
                self.motionDetector.stop()
                self.stopHeartbeat()
                self.periodicRefreshScheduler.stop()
                self.preventSuspendManager.stop()
                self.backgroundActivitySessionManager.stop()
                self.serviceSessionManager.stop()
                self.eventDispatcher.sendEnabledChange(false)
            }
        }
    }

    private func cancelStopAfterElapsedTimer() {
        stopAfterElapsedTimer?.invalidate()
        stopAfterElapsedTimer = nil
    }
}

