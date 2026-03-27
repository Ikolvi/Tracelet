import Foundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

/// Main entry point for the Tracelet Background Geolocation SDK.
///
/// Usage (Swift):
/// ```swift
/// let sdk = TraceletSdk.shared
/// sdk.delegate = self
/// sdk.ready(config: ["geo": ["distanceFilter": 10]])
/// sdk.start()
/// ```
///
/// Usage (Objective-C):
/// ```objc
/// TraceletSdk *sdk = [TraceletSdk shared];
/// sdk.delegate = self;
/// [sdk readyWithConfig:@{@"geo": @{@"distanceFilter": @10}}];
/// [sdk start];
/// ```
///
/// This class orchestrates all subsystems: location engine, motion detector,
/// geofence manager, HTTP sync, database, and scheduling. It is
/// framework-agnostic and can be used from Flutter, React Native, Capacitor,
/// or native iOS apps.
///
/// The API surface mirrors the Dart `Tracelet` class so developers switching
/// between Flutter and native iOS have a familiar interface.
public final class TraceletSdk {

    // MARK: - Singleton

    /// The shared singleton instance.
    public static let shared = TraceletSdk()

    // MARK: - Delegate

    /// Delegate that receives all tracking events (location, motion, geofence, etc.).
    ///
    /// Set this before calling ``ready(config:)`` to receive all events.
    public weak var delegate: TraceletDelegate? {
        didSet { delegateEventSender.delegate = delegate }
    }

    // MARK: - Subsystems

    public private(set) var configManager: ConfigManager!
    public private(set) var stateManager: StateManager!
    public private(set) var database: TraceletDatabase!
    public private(set) var locationEngine: LocationEngine!
    public private(set) var motionDetector: MotionDetector!
    public private(set) var geofenceManager: GeofenceManager!
    public private(set) var httpSyncManager: HttpSyncManager!
    public private(set) var scheduleManager: ScheduleManager!
    public private(set) var logger: TraceletLogger!
    public private(set) var soundManager: SoundManager!
    public private(set) var permissionManager: TraceletPermissionManager = TraceletPermissionManager()
    public private(set) var auditTrailManager: AuditTrailManager!
    public private(set) var privacyZoneManager: PrivacyZoneManager!
    public private(set) var deviceAttestor: DeviceAttestor!
    public private(set) var preventSuspendManager: PreventSuspendManager!
    public private(set) var backgroundActivitySessionManager: BackgroundActivitySessionManager!
    public private(set) var serviceSessionManager: ServiceSessionManager!
    public private(set) var periodicRefreshScheduler: PeriodicRefreshScheduler!

    private let delegateEventSender = DelegateEventSender()
    private var eventSender: TraceletEventSending
    private var heartbeatTimer: Timer?
    private var stopAfterElapsedTimer: Timer?
    private var isReady = false

    // Algorithms
    public private(set) var tripManager: TripManager!
    private var batteryBudgetEngine: BatteryBudgetEngine?
    private var batteryBudgetTimer: Timer?

    /// Battery budget sampling interval: 5 minutes.
    private static let batterySampleInterval: TimeInterval = 5 * 60

    /// Whether ``ready(config:)`` has been called.
    public var isReadyState: Bool { isReady }

    private init() {
        eventSender = delegateEventSender
        delegateEventSender.sdk = self
    }

    // MARK: - Event Sender (for framework bridges)

    /// Returns the internal ``TraceletEventSending`` for use by framework bridges.
    ///
    /// Flutter, React Native, and other bridges provide their own event sender
    /// implementation via this accessor, bypassing the delegate pattern.
    public func getEventSender() -> TraceletEventSending {
        return eventSender
    }

    /// Replace the default delegate-based event sender with a custom one.
    ///
    /// Framework bridges (Flutter, React Native) call this **before** ``ready(config:)``
    /// to inject their own event-channel implementation.
    ///
    /// - Parameter sender: A ``TraceletEventSending`` implementation.
    public func setEventSender(_ sender: TraceletEventSending) {
        precondition(!isReady, "setEventSender() must be called before ready()")
        self.eventSender = sender
    }

    /// Sets a headless dispatcher for background event delivery.
    ///
    /// Used by framework bridges (Flutter, React Native) to forward events
    /// to their respective background runtimes.
    public func setHeadlessDispatcher(_ dispatcher: HeadlessDispatching?) {
        delegateEventSender.headlessDispatcher = dispatcher
    }

    // =========================================================================
    // MARK: - Lifecycle
    // =========================================================================

    /// Initialize all subsystems with a typed configuration.
    ///
    /// Type-safe overload matching the Dart API:
    ///
    /// ```swift
    /// sdk.ready(config: TraceletConfig(
    ///     geo: .init(desiredAccuracy: .high, distanceFilter: 10.0),
    ///     app: .init(stopOnTerminate: false, startOnBoot: true)
    /// ))
    /// ```
    ///
    /// - Parameter config: Typed configuration.
    /// - Returns: Current state as a dictionary.
    @discardableResult
    public func ready(config: TraceletConfig) -> [String: Any] {
        return ready(config: config.toMap())
    }

    /// Initialize the SDK using an Objective-C compatible config wrapper.
    ///
    /// - Parameter objcConfig: ``TraceletConfigObjC`` instance.
    /// - Returns: Current state as a dictionary.
    @objc(readyWithObjCConfig:)
    @discardableResult
    public func ready(objcConfig: TraceletConfigObjC) -> [String: Any] {
        return ready(config: objcConfig.toMap())
    }

    /// Initialize all subsystems with the given configuration.
    ///
    /// **Must be called before any other method.** Returns the current state.
    ///
    /// - Parameter config: Configuration dictionary matching Dart `Config.toMap()` format.
    /// - Returns: Current state as a dictionary.
    @discardableResult
    public func ready(config: [String: Any]) -> [String: Any] {
        if configManager == nil {
            initialize()
        }

        let merged = configManager.setConfig(config)

        if configManager.isDebug() { soundManager.start() }
        httpSyncManager.start()
        logger.pruneOldLogs()

        // [Enterprise] Auto-encrypt database if configured.
        if configManager.getEncryptDatabase() && !database.isDatabaseEncrypted() {
            let _ = database.encryptDatabase()
        }

        // [Enterprise] Start attestation refresh if configured.
        if configManager.getAttestationEnabled() {
            deviceAttestor.startRefresh(intervalSeconds: configManager.getAttestationRefreshInterval())
        }

        // [Enterprise] Fetch remote config if configured.
        if let remoteUrl = configManager.getRemoteConfigUrl() {
            httpSyncManager.fetchRemoteConfig(
                url: remoteUrl,
                headers: configManager.getRemoteConfigHeaders(),
                timeoutMs: configManager.getRemoteConfigTimeout()
            ) { [weak self] remoteConfig in
                if let config = remoteConfig {
                    self?.eventSender.sendRemoteConfigEvent([
                        "config": config,
                        "source": "remote",
                    ])
                }
            }
        }

        // Initialize battery budget engine from config
        let budgetPerHour = configManager.getBatteryBudgetPerHour()
        if budgetPerHour > 0 {
            batteryBudgetEngine = BatteryBudgetEngine(
                targetBudgetPerHour: budgetPerHour,
                initialDistanceFilter: configManager.getDistanceFilter(),
                initialAccuracyIndex: configManager.getDesiredAccuracy()
            )
        } else {
            batteryBudgetEngine = nil
        }

        isReady = true
        return stateManager.toMap(merged)
    }

    /// Start continuous location tracking.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func start() -> [String: Any] {
        precondition(isReady, "TraceletSdk.ready() must be called before start()")

        stateManager.enabled = true
        stateManager.trackingMode = 0
        stateManager.isMoving = false

        // Stop any periodic tracking before switching to continuous mode.
        locationEngine.stopPeriodic()
        periodicRefreshScheduler.stop()

        locationEngine.start()

        // Wire proximity-based geofence monitoring + trip waypoints.
        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
            if self?.configManager.getGeofenceModeHighAccuracy() == true {
                self?.geofenceManager.evaluateHighAccuracyProximity(latitude: lat, longitude: lng)
            }
            self?.tripManager.onLocationReceived(
                latitude: lat,
                longitude: lng,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }

        motionDetector.start()
        startHeartbeat()
        startStopAfterElapsedTimer()
        startBatteryBudgetSampling()
        preventSuspendManager.start()
        backgroundActivitySessionManager.start()
        serviceSessionManager.start()

        eventSender.sendEnabledChange(true)

        return stateManager.toMap(configManager.getConfig())
    }

    /// Stop all tracking.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func stop() -> [String: Any] {
        BackgroundTaskHelper.shared.run("stop") { [self] in
            stateManager.enabled = false
            stateManager.isMoving = false

            locationEngine.stop()
            locationEngine.onLocationUpdate = nil
            motionDetector.stop()
            geofenceManager.destroy()
            stopHeartbeat()
            cancelStopAfterElapsedTimer()
            locationEngine.stopPeriodic()
            periodicRefreshScheduler.stop()
            preventSuspendManager.stop()
            backgroundActivitySessionManager.stop()
            serviceSessionManager.stop()

            scheduleManager.stop()
            tripManager.reset()
            stopBatteryBudgetSampling()
            batteryBudgetEngine?.reset()
            eventSender.sendEnabledChange(false)
        }

        return stateManager.toMap(configManager.getConfig())
    }

    /// Start geofence-only tracking mode.
    ///
    /// The SDK will only monitor geofences without continuous location
    /// tracking, saving significant battery.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func startGeofences() -> [String: Any] {
        precondition(isReady, "TraceletSdk.ready() must be called before startGeofences()")

        stateManager.enabled = true
        stateManager.trackingMode = 1

        locationEngine.stop()
        motionDetector.stop()

        geofenceManager.reRegisterAll()

        // Wire proximity-based geofence monitoring.
        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
            if self?.configManager.getGeofenceModeHighAccuracy() == true {
                self?.geofenceManager.evaluateHighAccuracyProximity(latitude: lat, longitude: lng)
            }
        }

        // geofenceModeHighAccuracy: start GPS for in-app transition detection.
        if configManager.getGeofenceModeHighAccuracy() {
            geofenceManager.clearHighAccuracyState()
            locationEngine.start()
        } else {
            locationEngine.start()
        }

        preventSuspendManager.start()
        backgroundActivitySessionManager.start()
        serviceSessionManager.start()

        eventSender.sendEnabledChange(true)

        return stateManager.toMap(configManager.getConfig())
    }

    /// Start periodic one-shot location tracking mode.
    ///
    /// Instead of continuous GPS updates, this mode wakes at the configured
    /// interval, performs a single location fix, dispatches the result, and
    /// immediately turns the location provider off.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func startPeriodic() -> [String: Any] {
        precondition(isReady, "TraceletSdk.ready() must be called before startPeriodic()")

        // Stop continuous tracking before switching to periodic mode.
        locationEngine.stop()
        motionDetector.stop()

        stateManager.enabled = true
        stateManager.trackingMode = 2
        stateManager.isMoving = false

        locationEngine.startPeriodic()

        // Wire proximity-based geofence monitoring.
        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
            if self?.configManager.getGeofenceModeHighAccuracy() == true {
                self?.geofenceManager.evaluateHighAccuracyProximity(latitude: lat, longitude: lng)
            }
        }

        startStopAfterElapsedTimer()

        // Schedule BGAppRefreshTask as a supplementary wake-up mechanism.
        let interval = TimeInterval(configManager.getPeriodicLocationInterval())
        periodicRefreshScheduler.start(interval: interval)

        // Only start preventSuspend in periodic mode when explicitly enabled.
        if configManager.getPreventSuspend() {
            preventSuspendManager.start()
        }

        // Do NOT start CLBackgroundActivitySession for periodic mode.
        // It causes a persistent blue location indicator in the status bar,
        // which is misleading — periodic mode only uses GPS briefly during
        // each fix. Background execution is already handled by:
        //   - BackgroundTaskHelper around each periodic fix
        //   - Temporarily enabling allowsBackgroundLocationUpdates per fix
        //   - significantLocationChanges as a wake-up mechanism
        //   - BGAppRefreshTask via PeriodicRefreshScheduler

        // iOS 18+: Preserve authorization across suspension/termination.
        // This does NOT show the location indicator.
        startServiceSessionForCurrentAuth()

        eventSender.sendEnabledChange(true)

        return stateManager.toMap(configManager.getConfig())
    }

    /// Get the current SDK state.
    ///
    /// - Returns: State as a dictionary.
    public func getState() -> [String: Any] {
        return stateManager.toMap(configManager.getConfig())
    }

    /// Update the SDK configuration.
    ///
    /// - Parameter config: Configuration dictionary.
    /// - Returns: Updated state as a dictionary.
    /// Update the SDK configuration using a typed ``TraceletConfig``.
    ///
    /// - Parameter config: Typed configuration struct.
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func setConfig(_ config: TraceletConfig) -> [String: Any] {
        return setConfig(config.toMap())
    }

    /// Update the SDK configuration using an Objective-C compatible config wrapper.
    ///
    /// - Parameter objcConfig: ``TraceletConfigObjC`` instance.
    /// - Returns: Updated state as a dictionary.
    @objc(setConfigWithObjC:)
    @discardableResult
    public func setConfig(objcConfig: TraceletConfigObjC) -> [String: Any] {
        return setConfig(objcConfig.toMap())
    }

    @discardableResult
    public func setConfig(_ config: [String: Any]) -> [String: Any] {
        let wasPreventing = configManager.getPreventSuspend()
        configManager.setConfig(config)

        if stateManager.enabled {
            if stateManager.trackingMode == 2 {
                // Periodic mode — restart periodic tracking.
                locationEngine.stopPeriodic()
                locationEngine.startPeriodic()
                periodicRefreshScheduler.stop()
                periodicRefreshScheduler.start(
                    interval: TimeInterval(configManager.getPeriodicLocationInterval())
                )
            } else {
                locationEngine.stop()
                locationEngine.start()
            }

            // Toggle preventSuspend if it changed mid-session.
            let nowPreventing = configManager.getPreventSuspend()
            if nowPreventing && !wasPreventing {
                preventSuspendManager.start()
            } else if !nowPreventing && wasPreventing {
                preventSuspendManager.stop()
            }
        }

        return stateManager.toMap(configManager.getConfig())
    }

    /// Reset all state and optionally apply new configuration.
    ///
    /// - Parameter config: Optional new configuration to apply after reset.
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func reset(_ config: [String: Any]? = nil) -> [String: Any] {
        BackgroundTaskHelper.shared.run("reset") { [self] in
            locationEngine.destroy()
            locationEngine.onLocationUpdate = nil
            motionDetector.stop()
            stopHeartbeat()
            cancelStopAfterElapsedTimer()
            periodicRefreshScheduler.stop()

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
            configManager.reset(config)
            isReady = false
        }

        return stateManager.toMap(configManager.getConfig())
    }

    // =========================================================================
    // MARK: - Location
    // =========================================================================

    /// Get the current position as a one-shot request.
    ///
    /// - Parameters:
    ///   - options: Options dictionary (desiredAccuracy, timeout, maximumAge, persist, samples, extras).
    ///   - completion: Called with the location dictionary, or nil on failure.
    public func getCurrentPosition(options: [String: Any] = [:],
                                   completion: @escaping ([String: Any]?) -> Void) {
        locationEngine.getCurrentPosition(options: options, callback: completion)
    }

    /// Get the last known location without requesting a new fix.
    ///
    /// - Parameter options: Options dictionary (persist, extras).
    /// - Returns: Location dictionary, or nil if no cached location is available.
    public func getLastKnownLocation(options: [String: Any] = [:]) -> [String: Any]? {
        var result: [String: Any]?
        locationEngine.getLastKnownLocation(options: options) { result = $0 }
        return result
    }

    /// Start watching position at a high-frequency interval.
    ///
    /// - Parameter options: Options dictionary (interval, desiredAccuracy, extras).
    /// - Returns: Watch ID that can be used to stop the watch via ``stopWatchPosition(_:)``.
    public func watchPosition(options: [String: Any] = [:]) -> Int {
        return locationEngine.watchPosition(options: options)
    }

    /// Stop a watch started by ``watchPosition(options:)``.
    ///
    /// - Parameter watchId: The watch ID returned by ``watchPosition(options:)``.
    /// - Returns: `true` if the watcher was found and stopped.
    @discardableResult
    public func stopWatchPosition(_ watchId: Int) -> Bool {
        return locationEngine.stopWatchPosition(watchId)
    }

    /// Toggle the motion state.
    ///
    /// `isMoving: true` forces moving mode (high-frequency updates).
    /// `isMoving: false` forces stationary mode.
    ///
    /// - Parameter isMoving: The desired motion state.
    /// - Returns: `true` if the pace was changed.
    @discardableResult
    public func changePace(_ isMoving: Bool) -> Bool {
        return locationEngine.changePace(isMoving)
    }

    /// Get the current odometer value in meters.
    public func getOdometer() -> Double {
        return locationEngine.getOdometer()
    }

    /// Set the odometer value.
    ///
    /// - Parameter value: New odometer value in meters.
    /// - Returns: Location dictionary at the reset point.
    @discardableResult
    public func setOdometer(_ value: Double) -> [String: Any] {
        return locationEngine.setOdometer(value)
    }

    // =========================================================================
    // MARK: - Geofencing
    // =========================================================================

    /// Add a single geofence to the monitoring list.
    ///
    /// - Parameter geofence: Geofence dictionary (identifier, latitude, longitude, radius, etc.).
    /// - Returns: `true` if the geofence was added.
    @discardableResult
    public func addGeofence(_ geofence: [String: Any]) -> Bool {
        return geofenceManager.addGeofence(geofence)
    }

    /// Add a single geofence using a typed ``TraceletGeofence`` model.
    ///
    /// - Parameter geofence: Typed geofence model.
    /// - Returns: `true` if the geofence was added.
    @discardableResult
    public func addGeofence(_ geofence: TraceletGeofence) -> Bool {
        return addGeofence(geofence.toMap() as [String: Any])
    }

    /// Add multiple geofences at once.
    ///
    /// - Parameter geofences: Array of geofence dictionaries.
    /// - Returns: `true` if all geofences were added.
    @discardableResult
    public func addGeofences(_ geofences: [[String: Any]]) -> Bool {
        return geofenceManager.addGeofences(geofences)
    }

    /// Add multiple geofences using typed ``TraceletGeofence`` models.
    ///
    /// - Parameter geofences: Array of typed geofence models.
    /// - Returns: `true` if all geofences were added.
    @discardableResult
    public func addGeofences(_ geofences: [TraceletGeofence]) -> Bool {
        return addGeofences(geofences.map { $0.toMap() as [String: Any] })
    }

    /// Remove a geofence by its identifier.
    ///
    /// - Parameter identifier: The geofence identifier.
    /// - Returns: `true` if the geofence was removed.
    @discardableResult
    public func removeGeofence(_ identifier: String) -> Bool {
        return geofenceManager.removeGeofence(identifier)
    }

    /// Remove all geofences.
    ///
    /// - Returns: `true` if geofences were removed.
    @discardableResult
    public func removeGeofences() -> Bool {
        return geofenceManager.removeGeofences()
    }

    /// Get all registered geofences.
    ///
    /// - Returns: Array of geofence dictionaries.
    public func getGeofences() -> [[String: Any]] {
        return geofenceManager.getGeofences()
    }

    /// Get a single geofence by identifier.
    ///
    /// - Parameter identifier: The geofence identifier.
    /// - Returns: Geofence dictionary, or nil if not found.
    public func getGeofence(_ identifier: String) -> [String: Any]? {
        return geofenceManager.getGeofence(identifier)
    }

    /// Check whether a geofence with the given identifier exists.
    ///
    /// - Parameter identifier: The geofence identifier.
    /// - Returns: `true` if the geofence exists.
    public func geofenceExists(_ identifier: String) -> Bool {
        return geofenceManager.geofenceExists(identifier)
    }

    // =========================================================================
    // MARK: - Persistence
    // =========================================================================

    /// Get stored locations from the local database.
    ///
    /// - Parameter query: Optional query parameters (limit, offset, order, start, end).
    /// - Returns: Array of location dictionaries.
    public func getLocations(query: [String: Any]? = nil) -> [[String: Any]] {
        let limit = query?["limit"] as? Int ?? -1
        let offset = query?["offset"] as? Int ?? 0
        let orderAsc = (query?["order"] as? Int ?? 0) == 0
        let start = query?["start"] as? Int64
        let end = query?["end"] as? Int64
        return database.getLocations(limit: limit, offset: offset, orderAsc: orderAsc,
                                     startTime: start, endTime: end)
    }

    /// Get the count of stored locations.
    ///
    /// - Parameter query: Optional query parameters (start, end).
    /// - Returns: Number of locations.
    public func getCount(query: [String: Any]? = nil) -> Int {
        let start = query?["start"] as? Int64
        let end = query?["end"] as? Int64
        return database.getLocationCount(startTime: start, endTime: end)
    }

    /// Destroy all stored locations.
    ///
    /// - Returns: `true` if locations were destroyed.
    @discardableResult
    public func destroyLocations() -> Bool {
        return database.deleteAllLocations()
    }

    /// Destroy only locations that have been successfully synced.
    ///
    /// - Returns: Number of synced locations deleted.
    @discardableResult
    public func destroySyncedLocations() -> Int {
        return database.deleteSyncedLocations()
    }

    /// Destroy a single location by UUID.
    ///
    /// - Parameter uuid: The location UUID.
    /// - Returns: `true` if the location was destroyed.
    @discardableResult
    public func destroyLocation(_ uuid: String) -> Bool {
        return database.deleteLocation(uuid)
    }

    /// Insert a custom location into the store.
    ///
    /// - Parameter params: Location data dictionary.
    /// - Returns: The UUID of the inserted location.
    public func insertLocation(_ params: [String: Any]) -> String {
        let uuid = database.insertLocation(params)
        httpSyncManager.onLocationInserted()
        return uuid
    }

    // =========================================================================
    // MARK: - HTTP Sync
    // =========================================================================

    /// Manually trigger HTTP synchronization of pending locations.
    ///
    /// - Parameter completion: Called with the list of synced location dictionaries.
    public func sync(completion: (([[String: Any]]) -> Void)? = nil) {
        httpSyncManager.sync(completion: completion)
    }

    /// Update dynamic HTTP headers on the native side.
    ///
    /// Dynamic headers are merged with the static headers at sync time.
    /// Dynamic headers take precedence when keys overlap.
    ///
    /// - Parameter headers: Header key-value pairs.
    public func setDynamicHeaders(_ headers: [String: String]) {
        configManager.setDynamicHeaders(headers)
    }

    // =========================================================================
    // MARK: - Route Context
    // =========================================================================

    /// Set the route context that will be persisted with every subsequent location.
    ///
    /// - Parameter context: Route context dictionary (taskId, driverId, etc.).
    public func setRouteContext(_ context: [String: Any]) {
        configManager.setRouteContext(context)
    }

    /// Clear the current route context.
    public func clearRouteContext() {
        configManager.clearRouteContext()
    }

    // =========================================================================
    // MARK: - Utility
    // =========================================================================

    /// Whether the device is currently in power-save (battery saver) mode.
    public var isPowerSaveMode: Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Get the current location permission status.
    ///
    /// - Returns: Authorization status code (0=notDetermined, 2=whenInUse, 3=always, 4=denied).
    public func getPermissionStatus() -> Int {
        return permissionManager.getAuthorizationStatus()
    }

    /// Whether the app has background ("Always") location permission.
    public var hasBackgroundPermission: Bool {
        return getPermissionStatus() == 3
    }

    /// Get the current location provider state.
    ///
    /// - Returns: Provider state dictionary.
    public func getProviderState() -> [String: Any] {
        let status = permissionManager.getAuthorizationStatus()
        let enabled = CLLocationManager.locationServicesEnabled()
        return [
            "enabled": enabled,
            "status": status,
            "gps": enabled,
            "network": enabled,
        ]
    }

    /// Get information about available device sensors.
    ///
    /// - Returns: Sensors dictionary.
    public func getSensors() -> [String: Any] {
        return [
            "accelerometer": true,
            "gyroscope": true,
            "magnetometer": true,
            "significantMotion": true,
            "motionActivity": !configManager.getDisableMotionActivityUpdates(),
        ]
    }

    /// Get information about the device.
    ///
    /// - Returns: Device info dictionary.
    public func getDeviceInfo() -> [String: Any] {
        #if canImport(UIKit)
        let device = UIDevice.current
        return [
            "manufacturer": "Apple",
            "model": device.model,
            "platform": "ios",
            "version": device.systemVersion,
            "framework": "native",
        ]
        #else
        return [
            "manufacturer": "Apple",
            "model": "unknown",
            "platform": "ios",
            "version": ProcessInfo.processInfo.operatingSystemVersionString,
            "framework": "native",
        ]
        #endif
    }

    /// Play a debug sound effect.
    ///
    /// - Parameter name: Sound identifier.
    /// - Returns: `true` if the sound was played.
    @discardableResult
    public func playSound(_ name: String) -> Bool {
        let _ = soundManager.playSound(name)
        return true
    }

    // =========================================================================
    // MARK: - Logging
    // =========================================================================

    /// Get the plugin log as a string.
    ///
    /// - Parameter query: Optional query parameters.
    /// - Returns: Formatted log string.
    public func getLog(query: [String: Any]? = nil) -> String {
        return database.getLogForEmail()
    }

    /// Destroy all log entries.
    ///
    /// - Returns: `true` if logs were destroyed.
    @discardableResult
    public func destroyLog() -> Bool {
        return database.deleteAllLogs()
    }

    /// Write a custom log entry.
    ///
    /// - Parameters:
    ///   - level: Log level ("error", "warn", "info", "debug", "verbose").
    ///   - message: Log message.
    public func log(_ level: String, _ message: String) {
        database.insertLog(level: level, message: message, source: "app")
    }

    // =========================================================================
    // MARK: - Scheduling
    // =========================================================================

    /// Start the scheduler (uses the `schedule` array in config).
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func startSchedule() -> [String: Any] {
        scheduleManager.start()
        return stateManager.toMap(configManager.getConfig())
    }

    /// Stop the scheduler.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func stopSchedule() -> [String: Any] {
        scheduleManager.stop()
        return stateManager.toMap(configManager.getConfig())
    }

    // =========================================================================
    // MARK: - Enterprise: Audit Trail
    // =========================================================================

    /// Verify the integrity of the tamper-proof audit trail.
    ///
    /// - Returns: Verification result dictionary.
    public func verifyAuditTrail() -> [String: Any] {
        return auditTrailManager.verifyChain()
    }

    /// Get the audit proof for a specific location record.
    ///
    /// - Parameter uuid: The location UUID.
    /// - Returns: Audit proof dictionary, or nil if not found.
    public func getAuditProof(_ uuid: String) -> [String: Any]? {
        return auditTrailManager.getProof(uuid: uuid)
    }

    // =========================================================================
    // MARK: - Enterprise: Privacy Zones
    // =========================================================================

    /// Add a single privacy zone.
    ///
    /// - Parameter zone: Privacy zone dictionary (identifier, latitude, longitude, radius, action).
    /// - Returns: `true` if the zone was added.
    @discardableResult
    public func addPrivacyZone(_ zone: [String: Any]) -> Bool {
        return privacyZoneManager.addZone(zone)
    }

    /// Add a single privacy zone using a typed ``TraceletPrivacyZone`` model.
    ///
    /// - Parameter zone: Typed privacy zone model.
    /// - Returns: `true` if the zone was added.
    @discardableResult
    public func addPrivacyZone(_ zone: TraceletPrivacyZone) -> Bool {
        return addPrivacyZone(zone.toMap())
    }

    /// Add multiple privacy zones at once.
    ///
    /// - Parameter zones: Array of privacy zone dictionaries.
    /// - Returns: `true` if all zones were added.
    @discardableResult
    public func addPrivacyZones(_ zones: [[String: Any]]) -> Bool {
        return privacyZoneManager.addZones(zones)
    }

    /// Add multiple privacy zones using typed ``TraceletPrivacyZone`` models.
    ///
    /// - Parameter zones: Array of typed privacy zone models.
    /// - Returns: `true` if all zones were added.
    @discardableResult
    public func addPrivacyZones(_ zones: [TraceletPrivacyZone]) -> Bool {
        return addPrivacyZones(zones.map { $0.toMap() })
    }

    /// Remove a privacy zone by its identifier.
    ///
    /// - Parameter identifier: The zone identifier.
    /// - Returns: `true` if the zone was removed.
    @discardableResult
    public func removePrivacyZone(_ identifier: String) -> Bool {
        return privacyZoneManager.removeZone(identifier)
    }

    /// Remove all privacy zones.
    ///
    /// - Returns: `true` if zones were removed.
    @discardableResult
    public func removePrivacyZones() -> Bool {
        return privacyZoneManager.removeAllZones()
    }

    /// Get all registered privacy zones.
    ///
    /// - Returns: Array of privacy zone dictionaries.
    public func getPrivacyZones() -> [[String: Any]] {
        return privacyZoneManager.getZones()
    }

    // =========================================================================
    // MARK: - Enterprise: Device Attestation
    // =========================================================================

    /// Request a fresh device attestation token.
    ///
    /// - Parameter completion: Called with the attestation token dictionary, or nil.
    public func getAttestationToken(completion: @escaping ([String: Any]?) -> Void) {
        deviceAttestor.requestToken(completion: completion)
    }

    // =========================================================================
    // MARK: - Enterprise: Dead Reckoning
    // =========================================================================

    /// Get the current dead reckoning state.
    ///
    /// - Returns: DR state dictionary, or nil if DR is disabled or GPS is available.
    public func getDeadReckoningState() -> [String: Any]? {
        // DR state is managed internally by LocationEngine — expose if active.
        return nil // TODO: Wire up when DeadReckoningEngine exposes state
    }

    // =========================================================================
    // MARK: - Private: Initialization
    // =========================================================================

    private func initialize() {
        // Register bootstrap factory for headless/background restarts
        TraceletBootstrapIOS.eventSenderFactory = { [weak self] in
            self?.getEventSender() ?? DelegateEventSender()
        }

        // Persistence
        // Note: iOS does not need a separate DatabaseEncryptionManager.
        // Android uses SQLCipher (application-level AES-256 encryption)
        // managed by DatabaseEncryptionManager, whereas iOS uses
        // NSFileProtectionComplete (hardware-level, OS-managed encryption).
        // Auto-encryption is triggered in ready() if encryptDatabase=true.
        configManager = ConfigManager()
        stateManager = StateManager()
        database = TraceletDatabase.shared

        // Logger
        logger = TraceletLogger(configManager: configManager, database: database)

        // Enterprise features
        auditTrailManager = AuditTrailManager(database: database, configManager: configManager)
        privacyZoneManager = PrivacyZoneManager(database: database, configManager: configManager)
        deviceAttestor = DeviceAttestor()

        // Location engine
        locationEngine = LocationEngine(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: eventSender,
            database: database
        )
        locationEngine.auditTrailManager = auditTrailManager
        locationEngine.privacyZoneManager = privacyZoneManager
        locationEngine.onLocationPersisted = { [weak self] in
            self?.httpSyncManager.onLocationInserted()
        }

        // Trip manager
        tripManager = TripManager()
        tripManager.onTripEnd = { [weak self] data in
            self?.eventSender.sendTrip(data)
        }

        // Motion detector
        motionDetector = MotionDetector(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: eventSender
        )
        motionDetector.onMotionStateChanged = { [weak self] isMoving in
            self?.handleMotionStateChange(isMoving)
        }

        // Geofencing
        geofenceManager = GeofenceManager(
            configManager: configManager,
            eventDispatcher: eventSender,
            database: database
        )

        // HTTP sync
        httpSyncManager = HttpSyncManager(
            configManager: configManager,
            eventDispatcher: eventSender,
            database: database
        )

        // Scheduling
        scheduleManager = ScheduleManager(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: eventSender
        )
        scheduleManager.onScheduleStart = { [weak self] in self?.handleScheduleStart() }
        scheduleManager.onScheduleStop = { [weak self] in self?.handleScheduleStop() }

        // Utilities
        soundManager = SoundManager(configManager: configManager)

        // Battery monitoring
        BatteryUtils.initialize()

        // Background keep-alive managers
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
    }

    // MARK: - Private: Motion State

    private func handleMotionStateChange(_ isMoving: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stateManager.isMoving = isMoving
            self.locationEngine.changePace(isMoving)

            // Feed TripManager with motion state change
            let lastLoc = self.locationEngine.getLastLocation()
            self.tripManager.onMotionStateChanged(
                isMoving: isMoving,
                latitude: lastLoc?.coordinate.latitude,
                longitude: lastLoc?.coordinate.longitude,
                timestamp: lastLoc.map { ISO8601DateFormatter().string(from: $0.timestamp) }
            )
        }
    }

    // MARK: - Private: Schedule

    private func handleScheduleStart() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.stateManager.enabled else { return }
            self.start()
        }
    }

    private func handleScheduleStop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.stateManager.enabled else { return }
            self.stop()
        }
    }

    // MARK: - Private: Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        let interval = configManager.getHeartbeatInterval()
        guard interval > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(interval),
                repeats: true
            ) { [weak self] _ in
                guard let self = self else { return }
                NSLog("[Tracelet] Heartbeat fired")
                guard let location = self.locationEngine.getLastGpsLocation() else {
                    NSLog("[Tracelet] Heartbeat: no cached location, skipping")
                    return
                }
                // Build a fully enriched location map with UUID, battery, etc.
                var locationMap = self.locationEngine.buildLocationMap(location)
                locationMap["event"] = "heartbeat"

                // Persist to database so it syncs via HTTP automatically.
                let _ = self.database.insertLocation(locationMap)
                self.locationEngine.onLocationPersisted?()

                let data: [String: Any] = ["location": locationMap]
                self.eventSender.sendHeartbeat(data)
                NSLog("[Tracelet] Heartbeat: lat=%.6f, lon=%.6f, accuracy=%.1fm",
                      location.coordinate.latitude, location.coordinate.longitude,
                      location.horizontalAccuracy)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Private: Battery Budget Sampling

    private func startBatteryBudgetSampling() {
        stopBatteryBudgetSampling()
        guard let engine = batteryBudgetEngine else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.batteryBudgetTimer = Timer.scheduledTimer(
                withTimeInterval: Self.batterySampleInterval,
                repeats: true
            ) { [weak self] _ in
                guard let self = self, self.stateManager.enabled else { return }
                let level = Double(BatteryUtils.getBatteryLevel())
                if let event = engine.processSample(level) {
                    self.eventSender.sendBudgetAdjustment([
                        "currentBatteryDrain": event.currentBatteryDrain,
                        "targetBudget": event.targetBudget,
                        "newDistanceFilter": event.newDistanceFilter,
                        "newDesiredAccuracy": event.newDesiredAccuracy,
                        "newPeriodicInterval": event.newPeriodicInterval as Any,
                    ])
                    self.logger.info(
                        "BatteryBudget adjusted: df=\(event.newDistanceFilter), " +
                        "acc=\(event.newDesiredAccuracy), drain=\(event.currentBatteryDrain)%/hr"
                    )
                }
            }
        }
    }

    private func stopBatteryBudgetSampling() {
        batteryBudgetTimer?.invalidate()
        batteryBudgetTimer = nil
    }

    // MARK: - Private: stopAfterElapsedMinutes

    private func startStopAfterElapsedTimer() {
        cancelStopAfterElapsedTimer()
        let minutes = configManager.getStopAfterElapsedMinutes()
        guard minutes > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            self?.stopAfterElapsedTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(minutes * 60),
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                BackgroundTaskHelper.shared.run("stopAfterElapsed") {
                    self.stateManager.enabled = false
                    self.stateManager.isMoving = false
                    self.locationEngine.stop()
                    self.motionDetector.stop()
                    self.stopHeartbeat()
                    self.periodicRefreshScheduler.stop()
                    self.preventSuspendManager.stop()
                    self.backgroundActivitySessionManager.stop()
                    self.serviceSessionManager.stop()
                    self.eventSender.sendEnabledChange(false)
                }
            }
        }
    }

    private func cancelStopAfterElapsedTimer() {
        stopAfterElapsedTimer?.invalidate()
        stopAfterElapsedTimer = nil
    }

    // MARK: - Private: Service Session

    /// Starts a `CLServiceSession` (iOS 18+) matching the user's permission.
    private func startServiceSessionForCurrentAuth() {
        let status = locationEngine.getAuthorizationStatus()
        switch status {
        case 3: // authorizedAlways
            serviceSessionManager.start()
        case 2: // authorizedWhenInUse
            serviceSessionManager.startWhenInUse()
        default:
            break
        }
    }

    // MARK: - Public: App Termination

    /// Called when the app is about to be terminated.
    ///
    /// Ensures significant location monitoring is registered so iOS will
    /// relaunch the app on the next cell-tower change. Also creates a
    /// fresh `CLLocationManager` to survive the teardown and explicitly
    /// starts significant location monitoring on it.
    ///
    /// **Important:** This does NOT survive user force-quit on iOS (swipe
    /// up from app switcher). Apple explicitly kills all location services
    /// in that scenario. This handles system-initiated termination only
    /// (memory pressure, OS updates, etc.).
    public func onAppWillTerminate() {
        guard stateManager != nil, stateManager.enabled else { return }
        guard configManager != nil, !configManager.getStopOnTerminate() else { return }

        NSLog("[Tracelet] onAppWillTerminate: stopOnTerminate=false, ensuring significant location monitoring")

        // Create a standalone CLLocationManager that outlives the current
        // singleton teardown. By starting significant location monitoring
        // on a fresh manager, we guarantee iOS has an active registration
        // that will trigger a relaunch.
        let terminationManager = CLLocationManager()
        terminationManager.startMonitoringSignificantLocationChanges()
        // Store in a static to prevent deallocation before the process ends.
        TraceletSdk._terminationLocationManager = terminationManager

        NSLog("[Tracelet] onAppWillTerminate: significant location monitoring registered on termination manager")
    }

    /// Holds a reference to the CLLocationManager created at termination
    /// time so it isn't deallocated before the process exits.
    private static var _terminationLocationManager: CLLocationManager?

    // MARK: - Public: Auto-Resume from killed state

    /// Automatically resumes tracking after the app is relaunched from a
    /// killed state by a significant location change.
    ///
    /// Call this from `application(_:didFinishLaunchingWithOptions:)` when
    /// `LaunchOptionsKey.location` is present.
    public func autoResumeTracking() {
        NSLog("[Tracelet] autoResumeTracking: starting")
        if configManager == nil {
            NSLog("[Tracelet] autoResumeTracking: configManager nil, calling initialize()")
            initialize()
        }

        // Guard: stopOnTerminate means we should NOT resume after kill.
        if configManager.getStopOnTerminate() {
            NSLog("[Tracelet] autoResumeTracking: stopOnTerminate=true, aborting")
            stateManager.enabled = false
            return
        }

        guard stateManager.enabled else {
            NSLog("[Tracelet] autoResumeTracking: stateManager.enabled=false, aborting")
            return
        }

        let authStatus = locationEngine.getAuthorizationStatus()
        guard authStatus == 3 else { // authorizedAlways
            NSLog("[Tracelet] autoResumeTracking: authStatus=\(authStatus), need 3 (Always), disabling")
            stateManager.enabled = false
            return
        }

        stateManager.didLaunchInBackground = true
        let trackingMode = stateManager.trackingMode
        NSLog("[Tracelet] autoResumeTracking: trackingMode=\(trackingMode), resuming")

        // Start HTTP sync so killed-state locations are synced to server
        httpSyncManager.start()
        NSLog("[Tracelet] autoResumeTracking: httpSyncManager started")

        // Wire onLocationPersisted so persisted locations trigger HTTP auto-sync.
        // Without this, locations accumulate in SQLite but never sync.
        locationEngine.onLocationPersisted = { [weak self] in
            self?.httpSyncManager.onLocationInserted()
        }

        switch trackingMode {
        case 0:
            locationEngine.start()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
                if self?.configManager.getGeofenceModeHighAccuracy() == true {
                    self?.geofenceManager.evaluateHighAccuracyProximity(latitude: lat, longitude: lng)
                }
            }
            motionDetector.start()
            startHeartbeat()
            preventSuspendManager.start()
            backgroundActivitySessionManager.start()
            serviceSessionManager.start()

        case 1:
            geofenceManager.reRegisterAll()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
                if self?.configManager.getGeofenceModeHighAccuracy() == true {
                    self?.geofenceManager.evaluateHighAccuracyProximity(latitude: lat, longitude: lng)
                }
            }
            locationEngine.start()
            preventSuspendManager.start()
            backgroundActivitySessionManager.start()
            serviceSessionManager.start()

        case 2:
            locationEngine.startPeriodic()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
                if self?.configManager.getGeofenceModeHighAccuracy() == true {
                    self?.geofenceManager.evaluateHighAccuracyProximity(latitude: lat, longitude: lng)
                }
            }
            let interval = TimeInterval(configManager.getPeriodicLocationInterval())
            periodicRefreshScheduler.start(interval: interval)
            if configManager.getPreventSuspend() {
                preventSuspendManager.start()
            }
            // Do NOT start CLBackgroundActivitySession for periodic mode —
            // it causes a persistent location indicator in the status bar.
            startServiceSessionForCurrentAuth()

        default:
            break
        }
    }

    // MARK: - Enterprise: Carbon Report

    /// Generate a carbon emissions report for a time range.
    ///
    /// - Parameter query: Query parameters (startTime, endTime, transportMode).
    /// - Returns: Carbon report dictionary.
    public func getCarbonReport(query: [String: Any]? = nil) -> [String: Any] {
        let startTime = (query?["startTime"] as? NSNumber)?.int64Value
        let endTime = (query?["endTime"] as? NSNumber)?.int64Value
        let locations = database.getLocations(
            limit: -1, offset: 0, orderAsc: true,
            startTime: startTime, endTime: endTime
        )

        var totalDistanceKm = 0.0
        var previousLat: Double?
        var previousLng: Double?

        for location in locations {
            let coords = location["coords"] as? [String: Any]
            let lat = coords?["latitude"] as? Double ?? location["latitude"] as? Double ?? 0
            let lng = coords?["longitude"] as? Double ?? location["longitude"] as? Double ?? 0

            if let prevLat = previousLat, let prevLng = previousLng {
                totalDistanceKm += GeoUtils.haversine(
                    prevLat, prevLng, lat, lng
                ) / 1000.0
            }
            previousLat = lat
            previousLng = lng
        }

        let mode = query?["transportMode"] as? String ?? "car"
        let factorGPerKm = carbonFactorForMode(mode)
        let totalCO2Grams = totalDistanceKm * factorGPerKm

        return [
            "totalDistanceKm": totalDistanceKm,
            "totalCO2Grams": totalCO2Grams,
            "totalCO2Kg": totalCO2Grams / 1000.0,
            "transportMode": mode,
            "emissionFactorGPerKm": factorGPerKm,
            "locationCount": locations.count,
            "startTime": startTime as Any? ?? NSNull(),
            "endTime": endTime as Any? ?? NSNull(),
        ]
    }

    private func carbonFactorForMode(_ mode: String) -> Double {
        switch mode {
        case "car": return 192.0
        case "bus": return 89.0
        case "train": return 41.0
        case "bicycle", "bike": return 0.0
        case "walking", "walk", "on_foot": return 0.0
        case "e-scooter", "scooter": return 35.0
        case "motorcycle": return 113.0
        case "plane", "flight": return 255.0
        default: return 192.0
        }
    }
}
