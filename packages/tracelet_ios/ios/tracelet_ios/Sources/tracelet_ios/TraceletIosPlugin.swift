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

    private var heartbeatTimer: Timer?
    private var stopAfterElapsedTimer: Timer?
    private var isReady = false

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

        // Persistence
        instance.configManager = ConfigManager()
        instance.stateManager = StateManager()
        instance.database = TraceletDatabase.shared

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
            // stopOnStationary: fully stop tracking
            instance.stateManager.enabled = false
            instance.stateManager.isMoving = false
            instance.locationEngine.stop()
            instance.motionDetector.stop()
            instance.stopHeartbeat()
            instance.eventDispatcher.sendEnabledChange(false)
            instance.logger.info("stopOnStationary — tracking stopped by motion detector")
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

        // Permissions
        instance.permissionManager = PermissionManager()

        registrar.addMethodCallDelegate(instance, channel: channel)
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
            result(locationEngine.changePace(isMoving))
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
            result(database.getLocationCount())
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

        // Background Tasks
        case "startBackgroundTask":
            let taskId = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            result(taskId.rawValue)
        case "stopBackgroundTask":
            let rawId = (call.arguments as? NSNumber)?.intValue ?? 0
            UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: rawId))
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

        locationEngine.start()
        motionDetector.start()
        startHeartbeat()
        startStopAfterElapsedTimer()
        preventSuspendManager.start()

        eventDispatcher.sendEnabledChange(true)
        logger.info("start() — tracking started")
        result(stateManager.toMap(configManager.getConfig()))
    }

    private func handleStop(result: FlutterResult) {
        stateManager.enabled = false
        stateManager.isMoving = false

        locationEngine.stop()
        locationEngine.onLocationUpdate = nil // clear high-accuracy geofence listener
        motionDetector.stop()
        stopHeartbeat()
        cancelStopAfterElapsedTimer()
        preventSuspendManager.stop()

        eventDispatcher.sendEnabledChange(false)
        logger.info("stop() — tracking stopped")
        result(stateManager.toMap(configManager.getConfig()))
    }

    private func handleStartGeofences(result: FlutterResult) {
        guard isReady else {
            result(FlutterError(code: "NOT_READY", message: "Call ready() before startGeofences()", details: nil))
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 1

        geofenceManager.reRegisterAll()

        // geofenceModeHighAccuracy: also start GPS tracking and compute
        // transitions in-app for more precise enter/exit detection.
        if configManager.getGeofenceModeHighAccuracy() {
            geofenceManager.clearHighAccuracyState()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.evaluateHighAccuracyProximity(latitude: lat, longitude: lng)
            }
            locationEngine.start()
        }

        eventDispatcher.sendEnabledChange(true)
        logger.info("startGeofences() — geofence-only mode (highAccuracy=\(configManager.getGeofenceModeHighAccuracy()))")
        result(stateManager.toMap(configManager.getConfig()))
    }

    private func handleSetConfig(_ call: FlutterMethodCall, result: FlutterResult) {
        let configMap = call.arguments as? [String: Any] ?? [:]
        let merged = configManager.setConfig(configMap)

        if stateManager.enabled {
            locationEngine.stop()
            locationEngine.start()
        }

        result(stateManager.toMap(merged))
    }

    private func handleReset(_ call: FlutterMethodCall, result: FlutterResult) {
        locationEngine.destroy()
        motionDetector.stop()
        stopHeartbeat()
        geofenceManager.destroy()

        stateManager.reset()
        let newConfig = call.arguments as? [String: Any]
        configManager.reset(newConfig)

        isReady = false
        logger.info("reset() — all subsystems reset")
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
        result(database.getLocations(limit: limit, offset: offset, orderAsc: orderAsc))
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
        eventDispatcher.sendEnabledChange(true)
    }

    private func handleScheduleStop() {
        stateManager.enabled = false
        locationEngine.stop()
        motionDetector.stop()
        stopHeartbeat()
        eventDispatcher.sendEnabledChange(false)
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
            self.logger.info("stopAfterElapsedMinutes (\(minutes) min) — auto-stopping")
            self.stateManager.enabled = false
            self.stateManager.isMoving = false
            self.locationEngine.stop()
            self.motionDetector.stop()
            self.stopHeartbeat()
            self.eventDispatcher.sendEnabledChange(false)
        }
    }

    private func cancelStopAfterElapsedTimer() {
        stopAfterElapsedTimer?.invalidate()
        stopAfterElapsedTimer = nil
    }
}

