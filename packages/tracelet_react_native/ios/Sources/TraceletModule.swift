import Foundation
import TraceletCore
import UIKit

/// React Native TurboModule bridge for Tracelet.
///
/// Wires together all TraceletCore subsystems and routes events to JS
/// via RCTEventEmitter. Mirrors the Flutter adapter (TraceletIosPlugin)
/// but uses React Native promise/event patterns instead of MethodChannel.
@objc(TraceletReactNative)
class TraceletModule: RCTEventEmitter, TraceletEventSending {

    // Core subsystems
    private var configManager: ConfigManager!
    private var stateManager: StateManager!
    private var database: TraceletDatabase!
    private var locationEngine: LocationEngine!
    private var motionDetector: MotionDetector!
    private var geofenceManager: GeofenceManager!
    private var httpSyncManager: HttpSyncManager!
    private var logger: TraceletLogger!
    private var soundManager: SoundManager!
    private var permissionManager: PermissionManager!
    private var auditTrailManager: AuditTrailManager!
    private var privacyZoneManager: PrivacyZoneManager!
    private var preventSuspendManager: PreventSuspendManager!
    private var backgroundActivitySessionManager: BackgroundActivitySessionManager!
    private var serviceSessionManager: ServiceSessionManager!
    private var periodicRefreshScheduler: PeriodicRefreshScheduler!

    private var heartbeatTimer: Timer?
    private var isReady = false
    private var hasListeners = false

    override init() {
        super.init()
        initSubsystems()
    }

    @objc override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    /// Initialize all TraceletCore subsystems — mirrors TraceletIosPlugin.register().
    private func initSubsystems() {
        configManager = ConfigManager()
        stateManager = StateManager()
        database = TraceletDatabase.shared

        BatteryUtils.initialize()

        logger = TraceletLogger(
            configManager: configManager,
            database: database
        )

        locationEngine = LocationEngine(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: self,
            database: database
        )

        auditTrailManager = AuditTrailManager(
            database: database,
            configManager: configManager
        )
        locationEngine.auditTrailManager = auditTrailManager

        privacyZoneManager = PrivacyZoneManager(
            database: database,
            configManager: configManager
        )
        locationEngine.privacyZoneManager = privacyZoneManager

        motionDetector = MotionDetector(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: self
        )
        motionDetector.onMotionStateChanged = { [weak self] isMoving in
            self?.handleMotionStateChange(isMoving)
        }
        motionDetector.onStopRequested = { [weak self] in
            guard let self = self else { return }
            BackgroundTaskHelper.shared.run("stopOnStationary") {
                self.stateManager.enabled = false
                self.stateManager.isMoving = false
                self.locationEngine.stop()
                self.motionDetector.stop()
                self.stopHeartbeat()
                self.periodicRefreshScheduler.stop()
                self.preventSuspendManager.stop()
                self.backgroundActivitySessionManager.stop()
                self.serviceSessionManager.stop()
                self.sendEnabledChange(false)
                self.logger.info("stopOnStationary — tracking stopped by motion detector")
            }
        }

        geofenceManager = GeofenceManager(
            configManager: configManager,
            eventDispatcher: self,
            database: database
        )

        httpSyncManager = HttpSyncManager(
            configManager: configManager,
            eventDispatcher: self,
            database: database
        )

        locationEngine.onLocationPersisted = { [weak self] in
            self?.httpSyncManager.onLocationInserted()
        }

        soundManager = SoundManager(configManager: configManager)
        preventSuspendManager = PreventSuspendManager(configManager: configManager)
        backgroundActivitySessionManager = BackgroundActivitySessionManager()
        serviceSessionManager = ServiceSessionManager()

        periodicRefreshScheduler = PeriodicRefreshScheduler()
        periodicRefreshScheduler.registerTask()
        periodicRefreshScheduler.onWakeUp = { [weak self] in
            guard let self = self,
                  self.stateManager.enabled,
                  self.stateManager.trackingMode == 2 else { return }
            self.locationEngine.performPeriodicFix()
            self.locationEngine.restartPeriodicTimerIfNeeded()
        }

        permissionManager = PermissionManager()
    }

    // MARK: - RCTEventEmitter

    override func supportedEvents() -> [String] {
        return [
            "onLocation",
            "onMotionChange",
            "onActivityChange",
            "onProviderChange",
            "onGeofence",
            "onGeofencesChange",
            "onHeartbeat",
            "onHttp",
            "onSchedule",
            "onPowerSaveChange",
            "onConnectivityChange",
            "onEnabledChange",
            "onNotificationAction",
            "onAuthorization",
            "onWatchPosition",
        ]
    }

    override func startObserving() {
        hasListeners = true
    }

    override func stopObserving() {
        hasListeners = false
    }

    // MARK: - TraceletEventSending

    func sendLocation(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onLocation", body: data) }
    }

    func sendMotionChange(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onMotionChange", body: data) }
    }

    func sendActivityChange(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onActivityChange", body: data) }
    }

    func sendProviderChange(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onProviderChange", body: data) }
    }

    func sendGeofence(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onGeofence", body: data) }
    }

    func sendGeofencesChange(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onGeofencesChange", body: data) }
    }

    func sendHeartbeat(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onHeartbeat", body: data) }
    }

    func sendHttp(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onHttp", body: data) }
    }

    func sendSchedule(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onSchedule", body: data) }
    }

    func sendPowerSaveChange(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onPowerSaveChange", body: data) }
    }

    func sendConnectivityChange(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onConnectivityChange", body: data) }
    }

    func sendEnabledChange(_ enabled: Bool) {
        if hasListeners { sendEvent(withName: "onEnabledChange", body: enabled) }
    }

    func sendEnabledChange(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onEnabledChange", body: data) }
    }

    func sendAuthorization(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onAuthorization", body: data) }
    }

    func sendWatchPosition(_ data: [String: Any]) {
        if hasListeners { sendEvent(withName: "onWatchPosition", body: data) }
    }

    func hasListener(eventName: String) -> Bool {
        return hasListeners
    }

    // MARK: - Lifecycle

    @objc func ready(
        _ config: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let configMap = config as? [String: Any] ?? [:]
        let merged = configManager.setConfig(configMap)

        if configManager.isDebug() { soundManager.start() }
        httpSyncManager.start()
        logger.pruneOldLogs()

        isReady = true
        logger.info("ready() called (React Native)")
        resolve(stateManager.toMap(merged))
    }

    @objc func start(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard isReady else {
            reject("ERR_NOT_READY", "Call ready() before start()", nil)
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 0
        stateManager.isMoving = false

        locationEngine.stopPeriodic()
        periodicRefreshScheduler.stop()
        locationEngine.start()

        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
        }

        motionDetector.start()
        startHeartbeat()
        preventSuspendManager.start()
        backgroundActivitySessionManager.start()
        serviceSessionManager.start()

        sendEnabledChange(true)
        logger.info("start() — tracking started (React Native)")
        resolve(stateManager.toMap(configManager.getConfig()))
    }

    @objc func stop(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        BackgroundTaskHelper.shared.run("stop") {
            stateManager.enabled = false
            stateManager.isMoving = false

            locationEngine.stop()
            locationEngine.onLocationUpdate = nil
            motionDetector.stop()
            stopHeartbeat()
            periodicRefreshScheduler.stop()
            preventSuspendManager.stop()
            backgroundActivitySessionManager.stop()
            serviceSessionManager.stop()

            sendEnabledChange(false)
            logger.info("stop() — tracking stopped (React Native)")
        }
        resolve(stateManager.toMap(configManager.getConfig()))
    }

    @objc func startGeofences(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard isReady else {
            reject("ERR_NOT_READY", "Call ready() before startGeofences()", nil)
            return
        }

        stateManager.enabled = true
        stateManager.trackingMode = 1
        stateManager.isMoving = false

        geofenceManager.reRegisterAll()
        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
        }
        locationEngine.start()
        preventSuspendManager.start()
        backgroundActivitySessionManager.start()
        serviceSessionManager.start()

        sendEnabledChange(true)
        logger.info("startGeofences() — geofence tracking started (React Native)")
        resolve(stateManager.toMap(configManager.getConfig()))
    }

    @objc func startPeriodic(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard isReady else {
            reject("ERR_NOT_READY", "Call ready() before startPeriodic()", nil)
            return
        }

        locationEngine.stop()
        motionDetector.stop()

        stateManager.enabled = true
        stateManager.trackingMode = 2
        stateManager.isMoving = false

        locationEngine.startPeriodic()

        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
        }

        let interval = TimeInterval(configManager.getPeriodicLocationInterval())
        periodicRefreshScheduler.start(interval: interval)

        if configManager.getPreventSuspend() {
            preventSuspendManager.start()
        }

        let status = locationEngine.getAuthorizationStatus()
        switch status {
        case 3: serviceSessionManager.start()
        case 2: serviceSessionManager.startWhenInUse()
        default: break
        }

        sendEnabledChange(true)
        logger.info("startPeriodic() — periodic tracking started (React Native)")
        resolve(stateManager.toMap(configManager.getConfig()))
    }

    @objc func getState(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(stateManager.toMap(configManager.getConfig()))
    }

    @objc func setConfig(
        _ config: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let configMap = config as? [String: Any] ?? [:]
        let merged = configManager.setConfig(configMap)
        resolve(stateManager.toMap(merged))
    }

    @objc func reset(
        _ config: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // Stop everything
        stateManager.enabled = false
        stateManager.isMoving = false
        locationEngine.stop()
        locationEngine.onLocationUpdate = nil
        motionDetector.stop()
        stopHeartbeat()
        periodicRefreshScheduler.stop()
        preventSuspendManager.stop()
        backgroundActivitySessionManager.stop()
        serviceSessionManager.stop()

        // Reset config
        let configMap = (config as? [String: Any]) ?? [:]
        configManager.reset()
        let merged = configManager.setConfig(configMap)

        // Clear persistence
        database.deleteAllLocations()

        sendEnabledChange(false)
        isReady = false
        logger.info("reset() — plugin reset (React Native)")
        resolve(stateManager.toMap(merged))
    }

    // MARK: - Location

    @objc func getCurrentPosition(
        _ options: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let opts = options as? [String: Any] ?? [:]
        locationEngine.getCurrentPosition(opts) { location in
            resolve(location)
        } onError: { error in
            reject("ERR_LOCATION", error, nil)
        }
    }

    @objc func getLastKnownLocation(
        _ options: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        guard let last = locationEngine.getLastLocation() else {
            resolve(nil)
            return
        }
        let map = locationEngine.buildLocationMap(last, speed: locationEngine.lastEffectiveSpeed)
        resolve(map)
    }

    @objc func watchPosition(
        _ options: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let opts = options as? [String: Any] ?? [:]
        let watchId = locationEngine.watchPosition(opts)
        resolve(watchId)
    }

    @objc func stopWatchPosition(
        _ watchId: Double,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let result = locationEngine.stopWatchPosition(Int(watchId))
        resolve(result)
    }

    @objc func changePace(
        _ isMoving: Bool,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let result = locationEngine.changePace(isMoving)
        resolve(result)
    }

    @objc func getOdometer(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(locationEngine.getOdometer())
    }

    @objc func setOdometer(
        _ value: Double,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(locationEngine.setOdometer(value))
    }

    // MARK: - Geofencing

    @objc func addGeofence(
        _ geofence: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let g = geofence as? [String: Any] ?? [:]
        resolve(geofenceManager.addGeofence(g))
    }

    @objc func addGeofences(
        _ geofences: NSArray,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let gArr = geofences as? [[String: Any]] ?? []
        resolve(geofenceManager.addGeofences(gArr))
    }

    @objc func removeGeofence(
        _ identifier: NSString,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(geofenceManager.removeGeofence(identifier as String))
    }

    @objc func removeGeofences(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(geofenceManager.removeGeofences())
    }

    @objc func getGeofences(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(geofenceManager.getGeofences())
    }

    @objc func getGeofence(
        _ identifier: NSString,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(geofenceManager.getGeofence(identifier as String) as Any)
    }

    @objc func geofenceExists(
        _ identifier: NSString,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(geofenceManager.geofenceExists(identifier as String))
    }

    // MARK: - Persistence

    @objc func getLocations(
        _ query: NSDictionary?,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let q = query as? [String: Any]
        let limit = q?["limit"] as? Int ?? -1
        let order = q?["order"] as? Int ?? 0
        let locations = database.getLocations(limit: limit, order: order)
        resolve(locations)
    }

    @objc func getCount(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(database.getLocationCount())
    }

    @objc func destroyLocations(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(database.deleteAllLocations())
    }

    @objc func destroyLocation(
        _ uuid: NSString,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(database.deleteLocation(uuid as String))
    }

    @objc func insertLocation(
        _ location: NSDictionary,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let params = location as? [String: Any] ?? [:]
        let uuid = database.insertLocation(params)
        httpSyncManager.onLocationInserted()
        resolve(uuid)
    }

    // MARK: - HTTP Sync

    @objc func sync(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        httpSyncManager.sync { synced in
            resolve(synced)
        }
    }

    // MARK: - Permissions

    @objc func requestPermission(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        permissionManager.requestPermission { status in
            resolve(status)
        }
    }

    @objc func getPermissionStatus(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(permissionManager.getAuthorizationStatus())
    }

    @objc func requestNotificationPermission(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // iOS: no notification permission needed for location — always granted
        resolve(3)
    }

    @objc func getNotificationPermissionStatus(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // iOS: not needed for foreground location — always "granted"
        resolve(3)
    }

    @objc func requestMotionPermission(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        motionDetector.requestMotionPermission { status in
            resolve(status)
        }
    }

    @objc func getMotionPermissionStatus(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(motionDetector.getMotionAuthorizationStatus())
    }

    @objc func requestTemporaryFullAccuracy(
        _ purposeKey: NSString,
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(permissionManager.requestTemporaryFullAccuracy(purposeKey: purposeKey as String))
    }

    @objc func canScheduleExactAlarms(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        // iOS has no exact alarm permission — BGAppRefreshTask is used instead
        resolve(true)
    }

    // MARK: - Utilities

    @objc func isPowerSaveMode(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(permissionManager.isPowerSaveMode())
    }

    @objc func getProviderState(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(locationEngine.buildProviderState())
    }

    @objc func getSensors(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(motionDetector.getSensors())
    }

    @objc func getDeviceInfo(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        let device = UIDevice.current
        resolve([
            "manufacturer": "Apple",
            "model": device.model,
            "version": device.systemVersion,
            "platform": "ios",
            "framework": "react-native",
        ] as [String: Any])
    }

    // MARK: - Motion state handling

    private func handleMotionStateChange(_ isMoving: Bool) {
        stateManager.isMoving = isMoving
        if isMoving {
            locationEngine.start()
            if configManager.isDebug() { soundManager.playSound("motionchange_true") }
        } else {
            locationEngine.stop()
            if configManager.isDebug() { soundManager.playSound("motionchange_false") }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        let interval = TimeInterval(configManager.getHeartbeatInterval())
        guard interval > 0 else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.locationEngine.getCurrentPosition([:]) { location in
                self.sendHeartbeat(location)
            } onError: { _ in }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
}
