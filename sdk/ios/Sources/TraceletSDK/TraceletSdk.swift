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
    public private(set) var permissionManager: TraceletPermissionManager!
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

        // Wire proximity-based geofence monitoring.
        locationEngine.onLocationUpdate = { [weak self] lat, lng in
            self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
        }

        motionDetector.start()
        startHeartbeat()
        startStopAfterElapsedTimer()
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
        }

        startStopAfterElapsedTimer()

        // Schedule BGAppRefreshTask as a supplementary wake-up mechanism.
        let interval = TimeInterval(configManager.getPeriodicLocationInterval())
        periodicRefreshScheduler.start(interval: interval)

        // Only start preventSuspend in periodic mode when explicitly enabled.
        if configManager.getPreventSuspend() {
            preventSuspendManager.start()
        }

        // iOS 18+: Preserve authorization across suspension/termination.
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

    /// Add multiple geofences at once.
    ///
    /// - Parameter geofences: Array of geofence dictionaries.
    /// - Returns: `true` if all geofences were added.
    @discardableResult
    public func addGeofences(_ geofences: [[String: Any]]) -> Bool {
        return geofenceManager.addGeofences(geofences)
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

    /// Add multiple privacy zones at once.
    ///
    /// - Parameter zones: Array of privacy zone dictionaries.
    /// - Returns: `true` if all zones were added.
    @discardableResult
    public func addPrivacyZones(_ zones: [[String: Any]]) -> Bool {
        return privacyZoneManager.addZones(zones)
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
        permissionManager = TraceletPermissionManager()

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
                if let location = self.locationEngine.getLastLocation() {
                    let data: [String: Any] = [
                        "location": [
                            "coords": [
                                "latitude": location.coordinate.latitude,
                                "longitude": location.coordinate.longitude,
                                "accuracy": location.horizontalAccuracy,
                                "altitude": location.altitude,
                                "speed": location.speed,
                                "heading": location.course,
                            ],
                            "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
                        ]
                    ]
                    self.eventSender.sendHeartbeat(data)
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
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

    // MARK: - Public: Auto-Resume from killed state

    /// Automatically resumes tracking after the app is relaunched from a
    /// killed state by a significant location change.
    ///
    /// Call this from `application(_:didFinishLaunchingWithOptions:)` when
    /// `LaunchOptionsKey.location` is present.
    public func autoResumeTracking() {
        guard configManager != nil else {
            initialize()
            return
        }
        guard stateManager.enabled else { return }

        let authStatus = locationEngine.getAuthorizationStatus()
        guard authStatus == 3 else { // authorizedAlways
            stateManager.enabled = false
            return
        }

        stateManager.didLaunchInBackground = true
        let trackingMode = stateManager.trackingMode

        switch trackingMode {
        case 0:
            locationEngine.start()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
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
            }
            locationEngine.start()
            preventSuspendManager.start()
            backgroundActivitySessionManager.start()
            serviceSessionManager.start()

        case 2:
            locationEngine.startPeriodic()
            locationEngine.onLocationUpdate = { [weak self] lat, lng in
                self?.geofenceManager.updateProximity(latitude: lat, longitude: lng)
            }
            let interval = TimeInterval(configManager.getPeriodicLocationInterval())
            periodicRefreshScheduler.start(interval: interval)
            if configManager.getPreventSuspend() {
                preventSuspendManager.start()
            }
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
