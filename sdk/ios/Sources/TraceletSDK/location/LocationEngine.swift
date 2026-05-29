import CoreLocation
import Foundation
import UIKit

/// CLLocationManager wrapper providing continuous location tracking,
/// one-shot position, watch position, significant location changes,
/// and odometer computation.
public final class LocationEngine: NSObject, CLLocationManagerDelegate {
    /// Internally settable so tests can inject a CLLocationManager subclass
    /// that records calls (e.g. `requestLocation`). Production code never
    /// reassigns this after init.
    internal var locationManager: CLLocationManager
    private let configManager: ConfigManager
    private let stateManager: StateManager
    private let eventDispatcher: TraceletEventSending
    private let database: TraceletDatabase

    private var lastLocation: CLLocation?
    /// Last GPS-quality location (horizontalAccuracy ≤ 100m).
    /// Used by heartbeat to avoid returning low-accuracy significant-change fixes.
    private var lastGpsLocation: CLLocation?
    private var oneShots: [((CLLocation?) -> Void)] = []
    private var watchCallbacks: [Int: Bool] = [:]
    private var nextWatchId = 0
    private var isTracking = false

    /// Background task ID for the current periodic fix request.
    /// Ended in didUpdateLocations/didFailWithError when periodic mode is active.
    private var periodicFixBgTaskId: UIBackgroundTaskIdentifier?
    /// Cancellable timeout work item for periodic fix cleanup.
    private var periodicFixTimeoutWork: DispatchWorkItem?

    /// Last computed effective speed (m/s) from tracking location updates.
    /// Used by the plugin to provide speed in motionchange events, since the
    /// cached CLLocation.speed may be stale, 0, or -1.
    public private(set) var lastEffectiveSpeed: Double = 0.0

    /// Optional callback invoked on every accepted location (for geofenceModeHighAccuracy).
    public var onLocationUpdate: ((Double, Double) -> Void)?

    /// Optional callback invoked after a location is persisted to the database.
    /// Used by the plugin to trigger HTTP auto-sync.
    public var onLocationPersisted: (() -> Void)?

    /// Whether a mock location warning has already been fired for this session.
    private var mockLocationWarningFired = false

    /// Tracks the last known accuracy authorization to detect transitions.
    private var lastAccuracyAuthorization: Int = -1  // -1 = unknown, 0 = full, 1 = reduced

    /// Counter for throttling DB retention pruning (I-H6).
    private var insertCountSincePrune = 0
    private static let pruneEveryNInserts = 100

    // MARK: - Rust-powered location processing

    /// Rust-backed location processor for distance/accuracy/speed/mock filtering.
    private var locationProcessor: LocationProcessor?

    /// Rust-backed Kalman filter for smoothing lat/lng.
    private var kalmanFilter: KalmanLocationFilter?

    /// Rust-backed PluginEventDispatcher for DB persistence + auto HTTP sync
    public var rustPluginEventDispatcher: EventDispatcher?

    /// Build (or rebuild) the Rust LocationProcessor from current config.
    public func rebuildProcessor() {
        locationProcessor = LocationProcessor(
            distanceFilter: configManager.getDistanceFilter(),
            disableElasticity: configManager.getDisableElasticity(),
            elasticityMultiplier: configManager.getElasticityMultiplier(),
            enableAdaptiveMode: configManager.getEnableAdaptiveMode(),
            trackingAccuracyThreshold: Int32(configManager.getTrackingAccuracyThreshold()),
            filterPolicy: Int32(configManager.getFilterPolicy()),
            maxImpliedSpeed: Int32(configManager.getMaxImpliedSpeed()),
            odometerAccuracyThreshold: Int32(configManager.getOdometerAccuracyThreshold()),
            rejectMockLocations: configManager.getRejectMockLocations(),
            mockDetectionLevel: Int32(configManager.getMockDetectionLevel()),
            enableSparseUpdates: configManager.getEnableSparseUpdates(),
            sparseDistanceThreshold: configManager.getSparseDistanceThreshold(),
            sparseMaxIdleSeconds: Int32(configManager.getSparseMaxIdleSeconds())
        )
        kalmanFilter = configManager.getEnableKalmanFilter() ? KalmanLocationFilter() : nil
    }

    /// Returns the processor, building it if needed.
    private func getProcessor() -> LocationProcessor {
        if let p = locationProcessor { return p }
        rebuildProcessor()
        return locationProcessor!
    }

    /// Maximum accuracy (meters) to consider a fix as GPS-sourced.
    static let gpsAccuracyThreshold: Double = 50.0

    /// Determines if a location fix is GPS-sourced (not network/cell).
    static func isGpsFix(_ location: CLLocation) -> Bool {
        return location.horizontalAccuracy > 0 &&
            location.horizontalAccuracy <= gpsAccuracyThreshold
    }

    /// [Enterprise] Audit trail manager — set by the plugin after initialization.
    public var auditTrailManager: AuditTrailManager?

    /// [Enterprise] Privacy zone manager — set by the plugin after initialization.
    public var privacyZoneManager: PrivacyZoneManager?

    /// Optional callback invoked to feed raw speed to SpeedMotionManager.
    public var speedSink: ((Double) -> Void)?

    // Dead Reckoning
    private var deadReckoningEngine: DeadReckoningEngine?
    private var gpsLossTimer: Timer?

    /// Current activity type — set by MotionDetector for DR algorithm selection.
    public var currentActivityType: String = "unknown"

    public init(configManager: ConfigManager,
         stateManager: StateManager,
         eventDispatcher: TraceletEventSending,
         database: TraceletDatabase) {
        self.configManager = configManager
        self.stateManager = stateManager
        self.eventDispatcher = eventDispatcher
        self.database = database
        self.locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Start / Stop

    public func start() {
        // Guard: require at least WhenInUse authorization before starting.
        // Dispatch a providerChange event so the app/Flutter UI can react
        // instead of silently doing nothing.
        let authStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authStatus = locationManager.authorizationStatus
        } else {
            authStatus = CLLocationManager.authorizationStatus()
        }
        if authStatus != .authorizedWhenInUse && authStatus != .authorizedAlways {
            NSLog("[Tracelet] start() called without location authorization (status=\(authStatus.rawValue))")
            eventDispatcher.sendProviderChange(buildProviderState())
            return
        }

        guard !isTracking else { return }
        isTracking = true

        configureLocationManager()
        checkReducedAccuracy()

        // Register for significant-location changes as a fallback wake-up
        // mechanism. If iOS terminates the app, significant-location changes
        // will relaunch it so tracking can resume (autoResumeTracking guards
        // the killed-state entry point for Always-only enforcement).
        locationManager.startMonitoringSignificantLocationChanges()

        let isLowPowerGeofences = stateManager.trackingMode == .geofences && !configManager.getGeofenceModeHighAccuracy()
        let skipContinuousGps = configManager.getUseSignificantChangesOnly() || isLowPowerGeofences

        if !skipContinuousGps {
            locationManager.startUpdatingLocation()
            startGpsLossTimer()
        }
    }

    public func stop() {
        guard isTracking else { return }
        isTracking = false
        isPeriodicTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        deactivateDeadReckoning()
        cancelGpsLossTimer()
        stopPeriodicTimer()
    }

    // MARK: - Periodic one-shot tracking

    /// Whether periodic one-shot mode is active.
    public private(set) var isPeriodicTracking = false
    private var periodicTimer: Timer?

    /// Starts periodic one-shot location tracking.
    ///
    /// Instead of continuous GPS, this mode:
    /// 1. Registers for significant location changes (no blue arrow) as a
    ///    wake-up mechanism.
    /// 2. Schedules a repeating timer at `periodicLocationInterval`.
    /// 3. On each tick, calls `requestLocation()` for a single GPS fix
    ///    (~5 sec blue arrow), dispatches the result, and stops GPS.
    ///
    /// **Important:** If `preventSuspend` is `false`, iOS may suspend the app
    /// and the timer will not fire. Use `preventSuspend: true` in `AppConfig`
    /// or rely on `BGAppRefreshTask` as a supplementary wakeup mechanism.
    public func startPeriodic() {
        guard !isPeriodicTracking else { return }
        isPeriodicTracking = true
        isTracking = true // so delegate callbacks are processed

        let interval = configManager.getPeriodicLocationInterval()
        NSLog("[Tracelet] startPeriodic: interval=%ds, accuracy=%d", interval, configManager.getPeriodicDesiredAccuracy())

        configureLocationManagerForPeriodic()
        checkReducedAccuracy()

        // Significant location changes as a fallback wake-up mechanism
        // (no blue arrow, wakes on cell tower changes).
        // autoResumeTracking() guards the killed-state entry point.
        locationManager.startMonitoringSignificantLocationChanges()

        // Do NOT call startUpdatingLocation() — that's the whole point.
        // Instead, schedule periodic one-shot fixes.
        startPeriodicTimer()
    }

    /// Stops periodic one-shot tracking.
    public func stopPeriodic() {
        guard isPeriodicTracking else { return }
        isPeriodicTracking = false
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        stopPeriodicTimer()
        // Reset last periodic coordinates so the next start doesn't
        // compute distance from a stale position.
        stateManager.lastPeriodicLatitude = .nan
        stateManager.lastPeriodicLongitude = .nan
    }

    // MARK: - Speed-Mode Atomic Switching
    //
    // These methods switch between continuous and stationary tracking modes
    // WITHOUT invalidating CLServiceSession / CLBackgroundActivitySession.
    // Sessions are only torn down on a full user-initiated stop().

    /// Switch from continuous to stationary periodic one-shot tracking.
    ///
    /// Stops continuous `startUpdatingLocation()` and starts the periodic
    /// timer. Significant-location-change monitoring and background sessions
    /// remain active.
    public func switchToStationaryPeriodic() {
        NSLog("[Tracelet] switchToStationaryPeriodic: stopping continuous, starting periodic timer")
        locationManager.stopUpdatingLocation()
        cancelGpsLossTimer()
        deactivateDeadReckoning()

        isPeriodicTracking = true
        // isTracking stays true so delegate callbacks are processed
        configureLocationManagerForPeriodic()
        startPeriodicTimer()
    }

    /// Switch from continuous to stationary geofence-only mode.
    ///
    /// Stops continuous `startUpdatingLocation()` but leaves region monitoring
    /// active. Background sessions remain active.
    public func switchToStationaryGeofences() {
        NSLog("[Tracelet] switchToStationaryGeofences: stopping continuous, geofences remain active")
        locationManager.stopUpdatingLocation()
        cancelGpsLossTimer()
        deactivateDeadReckoning()
        // Region monitoring (geofences) is managed by GeofenceManager and
        // remains active. isTracking stays true for delegate callbacks.
    }

    /// Switch from stationary (periodic or geofences) back to continuous tracking.
    ///
    /// Stops the periodic timer and resumes `startUpdatingLocation()`.
    /// Background sessions remain active.
    public func switchToContinuous() {
        NSLog("[Tracelet] switchToContinuous: stopping periodic, resuming continuous")
        stopPeriodicTimer()
        isPeriodicTracking = false

        configureLocationManager()
        locationManager.startUpdatingLocation()
        startGpsLossTimer()
    }

    /// Configures CLLocationManager for periodic mode.
    ///
    /// Key difference from `configureLocationManager()`:
    /// - `allowsBackgroundLocationUpdates = false` — no persistent blue arrow
    /// - Uses `periodicDesiredAccuracy` instead of `desiredAccuracy`
    private func configureLocationManagerForPeriodic() {
        // DO NOT set allowsBackgroundLocationUpdates = true
        // This prevents the persistent blue arrow in the status bar
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.pausesLocationUpdatesAutomatically = false

        let accuracy = configManager.getPeriodicDesiredAccuracy()
        switch accuracy {
        case 0: locationManager.desiredAccuracy = kCLLocationAccuracyBest
        case 1: locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case 2: locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        case 3: locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        case 4: locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        default: locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = configManager.getActivityType()
    }

    /// Starts the periodic timer that triggers one-shot location fixes.
    private func startPeriodicTimer() {
        stopPeriodicTimer()
        let interval = TimeInterval(configManager.getPeriodicLocationInterval())

        // Fire immediately for the first fix
        performPeriodicFix()

        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.performPeriodicFix()
        }
        // Allow iOS to coalesce timer fires with other system work for
        // energy efficiency. 10% tolerance is Apple’s recommendation (I-H2).
        timer.tolerance = interval * 0.1
        periodicTimer = timer
    }

    /// Stops the periodic timer.
    private func stopPeriodicTimer() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    /// Restarts the periodic timer if it has been invalidated.
    ///
    /// When iOS suspends the app, the in-memory `Timer` is killed. If the
    /// app is woken (e.g., by `BGAppRefreshTask` or significant-location
    /// change), the timer needs to be re-created so periodic fixes resume
    /// at the configured interval.
    public func restartPeriodicTimerIfNeeded() {
        guard isPeriodicTracking else { return }
        guard periodicTimer == nil || !(periodicTimer?.isValid ?? false) else { return }
        NSLog("[Tracelet] Restarting periodic timer (was invalidated/nil)")
        let interval = TimeInterval(configManager.getPeriodicLocationInterval())
        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.performPeriodicFix()
        }
        timer.tolerance = 0
        periodicTimer = timer
    }

    /// Performs a single one-shot location fix for periodic mode.
    ///
    /// Temporarily enables `allowsBackgroundLocationUpdates` and calls
    /// `requestLocation()`. The delegate callback (`didUpdateLocations`)
    /// handles dispatching and then turns GPS back off.
    ///
    /// This method is `internal` so that `PeriodicRefreshScheduler` and
    /// the plugin can trigger a fix from a `BGAppRefreshTask` wake-up.
    public func performPeriodicFix() {
        guard isPeriodicTracking else { return }

        NSLog("[Tracelet] performPeriodicFix: requesting one-shot GPS fix")

        // Cancel any previous timeout that hasn't fired yet
        periodicFixTimeoutWork?.cancel()
        endPeriodicFixBgTask()

        periodicFixBgTaskId = BackgroundTaskHelper.shared.begin("periodicFix")

        // Temporarily enable background location for this single fix
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.requestLocation()

        // Timeout: restore state after locationTimeout seconds if no callback
        let timeout = configManager.getLocationTimeout()
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPeriodicTracking else {
                self?.endPeriodicFixBgTask()
                return
            }
            // Restore non-background state
            self.locationManager.allowsBackgroundLocationUpdates = false
            self.locationManager.stopUpdatingLocation()
            self.endPeriodicFixBgTask()
        }
        periodicFixTimeoutWork = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(timeout), execute: timeoutWork)
    }

    /// Ends the periodic fix background task if one is active.
    private func endPeriodicFixBgTask() {
        if let taskId = periodicFixBgTaskId {
            BackgroundTaskHelper.shared.end(taskId)
            periodicFixBgTaskId = nil
        }
    }

    public func destroy() {
        stop()
        lastLocation = nil
        lastGpsLocation = nil
        oneShots.removeAll()
        stopAllWatchers()
        locationProcessor = nil
        kalmanFilter = nil
    }

    /// Stops all active watch-position subscriptions.
    public func stopAllWatchers() {
        watchCallbacks.removeAll()
    }

    // MARK: - Configuration

    private func configureLocationManager() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = configManager.getShowsBackgroundLocationIndicator()
        locationManager.pausesLocationUpdatesAutomatically = configManager.getPausesLocationUpdatesAutomatically()

        let accuracy = configManager.getDesiredAccuracy()
        switch accuracy {
        case -2: locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        case -1: locationManager.desiredAccuracy = kCLLocationAccuracyBest
        case 10: locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        case 100: locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case 1000: locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        case 3000: locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        default: locationManager.desiredAccuracy = kCLLocationAccuracyBest
        }

        let distanceFilter = configManager.getDistanceFilter()
        let isSpeedMode = configManager.getMotionDetectionMode() == .speed
        locationManager.distanceFilter = (distanceFilter > 0 && !isSpeedMode) ? distanceFilter : kCLDistanceFilterNone

        locationManager.activityType = configManager.getActivityType()
    }

    /// Overrides the distance filter temporarily.
    /// Used by TraceletSdk to keep the app awake during the stop timeout by forcing continuous GPS updates.
    public func overrideDistanceFilter(forStopTimeout: Bool) {
        if forStopTimeout {
            // If preventSuspend is enabled, the app is already kept alive via 
            // audio session. Overriding the GPS to continuous is redundant 
            // and wastes battery.
            if configManager.getPreventSuspend() {
                NSLog("[Tracelet-Location] overrideDistanceFilter: skipped because preventSuspend is true")
                return
            }
            locationManager.distanceFilter = kCLDistanceFilterNone
        } else {
            let distanceFilter = configManager.getDistanceFilter()
            let isSpeedMode = configManager.getMotionDetectionMode() == .speed
            locationManager.distanceFilter = (distanceFilter > 0 && !isSpeedMode) ? distanceFilter : kCLDistanceFilterNone
        }
    }

    /// Checks for iOS 14+ reduced accuracy authorization and auto-requests
    /// temporary full accuracy if available. Logs a warning when reduced.
    private func checkReducedAccuracy() {
        if #available(iOS 14.0, *) {
            let current = locationManager.accuracyAuthorization == .fullAccuracy ? 0 : 1
            lastAccuracyAuthorization = current
            if current == 1 {
                NSLog("[Tracelet] WARNING: Reduced accuracy authorization — locations will be approximate (~5 km). desiredAccuracy is ignored by iOS in this mode.")
                // Auto-request temporary full accuracy. The purpose key must
                // match a key in the app's Info.plist
                // NSLocationTemporaryUsageDescriptionDictionary.
                locationManager.requestTemporaryFullAccuracyAuthorization(
                    withPurposeKey: "TraceletFullAccuracy"
                )
                NSLog("[Tracelet] Requested temporary full accuracy (purposeKey: TraceletFullAccuracy)")
            }
        }
    }

    /// Whether the current accuracy authorization is reduced (iOS 14+).
    private var isReducedAccuracy: Bool {
        if #available(iOS 14.0, *) {
            return locationManager.accuracyAuthorization == .reducedAccuracy
        }
        return false
    }

    // MARK: - One-shot position

    /// Fetches the current position with configurable options.
    ///
    /// Supported keys in `options`:
    /// - `desiredAccuracy` (Int): Accuracy level override.
    /// - `timeout` (Int): Timeout in seconds (default 30).
    /// - `maximumAge` (Int): Max age in ms of a cached location.
    /// - `persist` (Bool): Whether to persist to DB (default true).
    /// - `samples` (Int): Number of samples; best accuracy is returned (default 1).
    /// - `extras` ([String: Any]): Extra data to attach.
    public func getCurrentPosition(options: [String: Any], callback: @escaping ([String: Any]?) -> Void) {
        // Guard: require at least WhenInUse authorization before attempting.
        let authStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authStatus = locationManager.authorizationStatus
        } else {
            authStatus = CLLocationManager.authorizationStatus()
        }
        guard authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways else {
            NSLog("[Tracelet] getCurrentPosition called without location authorization (status=\(authStatus.rawValue)). Call requestPermission() first.")
            callback(nil)
            return
        }

        let persist = options["persist"] as? Bool ?? true
        let maximumAge = (options["maximumAge"] as? NSNumber)?.int64Value ?? 0
        let samples = max((options["samples"] as? NSNumber)?.intValue ?? 1, 1)
        let extras = options["extras"] as? [String: Any] ?? [:]

        // Check if a cached location satisfies maximumAge
        if maximumAge > 0, let cached = lastLocation {
            let ageMs = Int64(Date().timeIntervalSince(cached.timestamp) * 1000)
            if ageMs <= maximumAge {
                var locationMap = buildLocationMap(cached)
                if !extras.isEmpty { locationMap["extras"] = extras }
                if persist {
                    let _ = database.insertLocation(locationMap)
                    onLocationPersisted?()
                }
                callback(locationMap)
                return
            }
        }

        // Use collectSamples for all cases — including samples == 1.
        // CLLocationManager.requestLocation() may return a stale cached
        // location without waking the GPS hardware. collectSamples uses
        // startUpdatingLocation() which forces a fresh GPS fix with proper
        // timeout handling.
        collectSamples(count: samples, persist: persist, extras: extras, callback: callback)
    }

    /// Returns the last known location without activating any provider.
    ///
    /// This is a zero-battery-cost operation. Returns nil if no cached
    /// location is available.
    ///
    /// Supported keys in `options`:
    /// - `persist` (Bool): Whether to persist to DB (default false).
    /// - `extras` ([String: Any]): Extra data to attach.
    public func getLastKnownLocation(options: [String: Any], callback: ([String: Any]?) -> Void) {
        let persist = options["persist"] as? Bool ?? false
        let extras = options["extras"] as? [String: Any] ?? [:]

        guard let location = lastLocation ?? locationManager.location else {
            callback(nil)
            return
        }

        var locationMap = buildLocationMap(location)
        if !extras.isEmpty { locationMap["extras"] = extras }
        locationMap["event"] = "getLastKnownLocation"
        if persist {
            let _ = database.insertLocation(locationMap)
            onLocationPersisted?()
        }
        callback(locationMap)
    }

    // MARK: - Watch position

    public func watchPosition(options: [String: Any]) -> Int {
        let watchId = nextWatchId
        nextWatchId += 1
        watchCallbacks[watchId] = true

        // Start tracking if not already
        if !isTracking {
            configureLocationManager()
            locationManager.startUpdatingLocation()
            isTracking = true
        }
        return watchId
    }

    public func stopWatchPosition(_ watchId: Int) -> Bool {
        watchCallbacks.removeValue(forKey: watchId)
        return true
    }

    // MARK: - Pace control

    public func changePace(_ isMoving: Bool) -> Bool {
        let wasTracking = isTracking
        stateManager.isMoving = isMoving
        if isMoving {
            start()
            // On an actual stationary → moving transition, fire an additional
            // one-shot request so a fresh fix arrives as soon as the GPS
            // hardware is warm, without waiting for the continuous stream's
            // first delivery. iOS prioritizes requestLocation() over the
            // rate-limited updates from startUpdatingLocation(), and routes
            // the result through didUpdateLocations so the full processing
            // pipeline (filters, Kalman, persistence) still applies.
            // Skip for periodic mode (already driven by requestLocation).
            if !wasTracking && !isPeriodicTracking {
                locationManager.requestLocation()
            }
        } else {
            stop()
        }
        // Dispatch motionChange event (consistent with Android)
        let locationMap: [String: Any]
        if let loc = lastLocation {
            var map = buildLocationMap(loc, speed: lastEffectiveSpeed)
            map["isMoving"] = isMoving
            map["event"] = "motionchange"
            locationMap = map
        } else {
            locationMap = ["isMoving": isMoving]
        }
        eventDispatcher.sendMotionChange(locationMap)
        return true
    }

    // MARK: - Odometer

    public func getOdometer() -> Double {
        return stateManager.odometer
    }

    public func setOdometer(_ value: Double) -> [String: Any] {
        stateManager.odometer = value
        if let loc = lastLocation {
            return buildLocationMap(loc)
        }
        return ["odometer": value]
    }

    public func getLastLocation() -> CLLocation? {
        return lastLocation
    }

    /// Returns the best available location for heartbeat: prefers the last
    /// GPS-quality fix (≤100m accuracy) over a potentially stale significant-
    /// location-change fix. Falls back to lastLocation if no GPS fix exists.
    public func getLastGpsLocation() -> CLLocation? {
        return lastGpsLocation ?? lastLocation
    }

    // MARK: - Provider state

    public func buildProviderState() -> [String: Any] {
        var state: [String: Any] = [
            "enabled": CLLocationManager.locationServicesEnabled(),
            "gps": true,
            "network": true,
            "platform": "ios",
        ]

        if #available(iOS 14.0, *) {
            let status = locationManager.authorizationStatus
            state["status"] = authorizationStatusToInt(status)
            state["accuracyAuthorization"] = locationManager.accuracyAuthorization == .fullAccuracy ? 0 : 1
        } else {
            let status = CLLocationManager.authorizationStatus()
            state["status"] = authorizationStatusToInt(status)
        }

        return state
    }

    /// Returns the current authorization status as an integer:
    /// 0 = notDetermined, 1 = restricted/denied, 2 = whenInUse, 3 = always.
    public func getAuthorizationStatus() -> Int {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        return authorizationStatusToInt(status)
    }

    private func authorizationStatusToInt(_ status: CLAuthorizationStatus) -> Int {
        switch status {
        case .notDetermined: return 0
        case .restricted: return 1
        case .denied: return 1
        case .authorizedWhenInUse: return 2
        case .authorizedAlways: return 3
        @unknown default: return 0
        }
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Only reset DR timer on GPS-quality fixes (not cell/Wi-Fi).
        if LocationEngine.isGpsFix(location) {
            resetGpsLossTimer()
            if deadReckoningEngine?.isActive == true {
                NSLog("[Tracelet] GPS signal recovered — deactivating dead reckoning")
                deactivateDeadReckoning()
            }
        }

        // Request background execution time for the entire persist + dispatch
        // chain. Without this, iOS may suspend the app mid-flight when waking
        // from significant-location-change or background delivery.
        let bgTaskId = BackgroundTaskHelper.shared.begin("locationUpdate")
        defer { BackgroundTaskHelper.shared.end(bgTaskId) }

        // --- Mock location rejection (defense-in-depth) ---
        if configManager.getRejectMockLocations() && isLocationMock(location) {
            if !mockLocationWarningFired {
                mockLocationWarningFired = true
                var providerState = buildProviderState()
                providerState["mockLocationsDetected"] = true
                eventDispatcher.sendProviderChange(providerState)
            }
            return // Drop the mock location entirely.
        }

        // Feed multi-sample collection if active
        let consumedBySampler = feedSample(location)

        // --- Compute speed from distance/time as fallback ---
        var computedSpeed: Double = 0.0
        var distance: Double = 0.0

        if let last = lastLocation {
            distance = location.distance(from: last)
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
            computedSpeed = (distance > 0 && timeDelta > 0) ? distance / timeDelta : 0.0
        } else if isPeriodicTracking {
            // Fallback: when the app was killed and relaunched by
            // BGAppRefreshTask, lastLocation is nil. Use persisted periodic
            // coordinates so the odometer isn't lost across restarts.
            let lastLat = stateManager.lastPeriodicLatitude
            let lastLng = stateManager.lastPeriodicLongitude
            if !lastLat.isNaN && !lastLng.isNaN {
                let lastCL = CLLocation(latitude: lastLat, longitude: lastLng)
                distance = location.distance(from: lastCL)
            }
        }

        // Resolve effective speed: platform speed if available, otherwise computed
        let effectiveSpeed = (location.speed > 0) ? location.speed : computedSpeed

        // --- Rust-powered filtering (distance, accuracy, speed, mock, sparse) ---
        let mock = isLocationMock(location)
        let processor = getProcessor()
        let batteryInfo = BatteryUtils.getBatteryInfo()
        let batteryLevel = (batteryInfo["level"] as? NSNumber)?.doubleValue ?? -1.0
        let isCharging = batteryInfo["is_charging"] as? Bool ?? false

        let adaptiveCtx = AdaptiveContext(
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            activityType: mapActivityType(currentActivityType),
            activityConfidence: mapActivityConfidence(-1),
            speed: effectiveSpeed
        )
        let result = processor.process(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            speed: effectiveSpeed,
            timestampMs: Int64(location.timestamp.timeIntervalSince1970 * 1000),
            isMock: mock,
            adaptiveContext: adaptiveCtx
        )
        if !result.accepted {
            NSLog("[Tracelet] Location filtered by Rust processor: %@", result.reason ?? "unknown")
            if result.odometerDelta > 0 {
                stateManager.addOdometer(distance: result.odometerDelta)
            }
            return
        }

        // Odometer update from processor's computed delta
        if result.odometerDelta > 0 {
            stateManager.addOdometer(distance: result.odometerDelta)
        }

        // --- Kalman smoothing (optional) ---
        var smoothedLat = location.coordinate.latitude
        var smoothedLng = location.coordinate.longitude
        if let kalman = kalmanFilter {
            let smoothed = kalman.process(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                timestampMs: Int64(location.timestamp.timeIntervalSince1970 * 1000)
            )
            smoothedLat = smoothed.latitude
            smoothedLng = smoothed.longitude
        }

        lastEffectiveSpeed = result.effectiveSpeed

        // Forward speed to SpeedMotionManager when speed-based motion detection
        // is active.
        speedSink?(result.effectiveSpeed)

        // Persist last periodic coordinates for cross-restart odometer
        if isPeriodicTracking {
            stateManager.lastPeriodicLatitude = location.coordinate.latitude
            stateManager.lastPeriodicLongitude = location.coordinate.longitude
        }

        lastLocation = location
        if location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 100 {
            lastGpsLocation = location
        }
        stateManager.lastLocationTime = Date().timeIntervalSince1970 * 1000

        let locationMap = buildLocationMap(location, speed: result.effectiveSpeed, smoothedLat: smoothedLat, smoothedLng: smoothedLng)

        // Fire one-shot callbacks
        fireOneShots(location)

        // If consumed exclusively by sampler, don't dispatch as tracking event
        if consumedBySampler && !isTracking { return }

        // Fire watch position events
        if !watchCallbacks.isEmpty {
            eventDispatcher.sendWatchPosition(locationMap)
        }

        // Persist and dispatch (respecting persistMode)

        // [Enterprise] Privacy zone check — BEFORE audit + persist + send.
        if let pzm = privacyZoneManager {
            let privacyResult = pzm.processLocation(locationMap)
            switch privacyResult.action {
            case .drop:
                // Exclusion zone — drop this location entirely.
                if isPeriodicTracking {
                    locationManager.stopUpdatingLocation()
                    locationManager.allowsBackgroundLocationUpdates = false
                    periodicFixTimeoutWork?.cancel()
                    periodicFixTimeoutWork = nil
                    endPeriodicFixBgTask()
                }
                return
            case .eventOnly:
                // Dispatch to Flutter but do NOT persist or audit.
                var data = privacyResult.location ?? locationMap
                if isPeriodicTracking { data["event"] = "periodic" }
                eventDispatcher.sendLocation(data)
                onLocationUpdate?(location.coordinate.latitude, location.coordinate.longitude)
                if isPeriodicTracking {
                    locationManager.stopUpdatingLocation()
                    locationManager.allowsBackgroundLocationUpdates = false
                    periodicFixTimeoutWork?.cancel()
                    periodicFixTimeoutWork = nil
                    endPeriodicFixBgTask()
                }
                return
            case .degraded:
                // Use degraded coordinates for audit + persist + dispatch.
                var degraded = privacyResult.location ?? locationMap
                let pzEventTag = isPeriodicTracking ? "periodic" : "location"
                degraded["event"] = pzEventTag
                if let auditFields = auditTrailManager?.appendToChain(degraded) {
                    for (key, value) in auditFields {
                        degraded[key] = value
                    }
                }
                persistLocationIfAllowed(degraded, event: pzEventTag)
                eventDispatcher.sendLocation(degraded)
                onLocationUpdate?(location.coordinate.latitude, location.coordinate.longitude)
                if isPeriodicTracking {
                    locationManager.stopUpdatingLocation()
                    locationManager.allowsBackgroundLocationUpdates = false
                    periodicFixTimeoutWork?.cancel()
                    periodicFixTimeoutWork = nil
                    endPeriodicFixBgTask()
                }
                return
            case .passThrough:
                break // Fall through to normal flow
            }
        }

        // [Enterprise] Compute audit hash and merge into location map
        var dispatchMap = locationMap
        if let auditFields = auditTrailManager?.appendToChain(locationMap) {
            for (key, value) in auditFields {
                dispatchMap[key] = value
            }
        }
        // Tag periodic fixes so Dart can distinguish them from continuous-mode events
        let eventTag = isPeriodicTracking ? "periodic" : "location"
        dispatchMap["event"] = eventTag
        persistLocationIfAllowed(dispatchMap, event: eventTag)
        eventDispatcher.sendLocation(dispatchMap)

        // Notify geofenceModeHighAccuracy listener (if active)
        onLocationUpdate?(location.coordinate.latitude, location.coordinate.longitude)

        // In periodic mode, immediately stop GPS after receiving the fix
        // to minimise blue-arrow visibility.
        if isPeriodicTracking {
            NSLog("[Tracelet] Periodic fix received: lat=%.6f, lon=%.6f, accuracy=%.1fm",
                  location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy)
            locationManager.stopUpdatingLocation()
            locationManager.allowsBackgroundLocationUpdates = false
            // Cancel the timeout and end the background task now that the fix succeeded.
            periodicFixTimeoutWork?.cancel()
            periodicFixTimeoutWork = nil
            endPeriodicFixBgTask()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[Tracelet] Location error: \(error.localizedDescription)")

        // Fail all one-shots — fallback to lastLocation if available
        let fallbackLocation = lastLocation
        for callback in oneShots {
            callback(fallbackLocation)
        }
        oneShots.removeAll()

        // Fail active sample collection — don't let it hang until timeout.
        if let state = sampleState, !state.finished {
            state.finished = true
            sampleState = nil
            if !isTracking {
                locationManager.stopUpdatingLocation()
            }
            locationManager.distanceFilter = configManager.getDistanceFilter()

            if !state.collected.isEmpty {
                deliverBest(samples: state.collected, persist: state.persist, extras: state.extras, callback: state.callback)
            } else if let fallback = lastLocation {
                deliverBest(samples: [fallback], persist: state.persist, extras: state.extras, callback: state.callback)
            } else {
                state.callback(nil)
            }
        }

        // In periodic mode, ensure GPS and background updates are turned off
        // on error — mirrors the cleanup in didUpdateLocations. Without this,
        // a failed requestLocation() leaves allowsBackgroundLocationUpdates
        // enabled, keeping the location icon visible until the timeout fires.
        if isPeriodicTracking {
            locationManager.stopUpdatingLocation()
            locationManager.allowsBackgroundLocationUpdates = false
            periodicFixTimeoutWork?.cancel()
            periodicFixTimeoutWork = nil
            endPeriodicFixBgTask()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Detect accuracy authorization transitions (iOS 14+).
        if #available(iOS 14.0, *) {
            let current = manager.accuracyAuthorization == .fullAccuracy ? 0 : 1
            if lastAccuracyAuthorization >= 0 && current != lastAccuracyAuthorization {
                if current == 1 {
                    NSLog("[Tracelet] Accuracy authorization changed to REDUCED — locations will be approximate (~5 km)")
                } else {
                    NSLog("[Tracelet] Accuracy authorization restored to FULL")
                }
            }
            lastAccuracyAuthorization = current
        }

        let providerState = buildProviderState()
        eventDispatcher.sendProviderChange(providerState)
    }

    // MARK: - Multi-sample collection

    private var sampleState: SampleState?

    /// Internal state for multi-sample collection.
    private class SampleState {
        let targetCount: Int
        let persist: Bool
        let extras: [String: Any]
        let callback: ([String: Any]?) -> Void
        var collected: [CLLocation] = []
        var finished = false

        init(count: Int, persist: Bool, extras: [String: Any], callback: @escaping ([String: Any]?) -> Void) {
            self.targetCount = count
            self.persist = persist
            self.extras = extras
            self.callback = callback
        }
    }

    /// Collects `count` location samples using continuous updates and returns the
    /// most accurate one. Automatically stops after collecting enough samples
    /// or after the configured timeout, whichever comes first.
    private func collectSamples(count: Int, persist: Bool, extras: [String: Any], callback: @escaping ([String: Any]?) -> Void) {
        let state = SampleState(count: count, persist: persist, extras: extras, callback: callback)
        sampleState = state

        // Ensure CLLocationManager is fully configured before requesting updates.
        // Without this, updates may silently not fire if start() was never called.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = configManager.getShowsBackgroundLocationIndicator()
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = configManager.getActivityType()

        // Temporarily disable distance filter so we receive updates even when
        // the device is stationary — essential for multi-sample collection.
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()

        // Timeout guard — deliver whatever we have (or nil) if time runs out.
        let timeoutSec = configManager.getLocationTimeout()
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(timeoutSec)) { [weak self] in
            guard let self = self, let state = self.sampleState, !state.finished else { return }
            state.finished = true
            self.sampleState = nil

            if !self.isTracking {
                self.locationManager.stopUpdatingLocation()
            }
            // Restore configured distance filter.
            self.locationManager.distanceFilter = self.configManager.getDistanceFilter()

            if !state.collected.isEmpty {
                self.deliverBest(samples: state.collected, persist: state.persist, extras: state.extras, callback: state.callback)
            } else if let fallback = self.lastLocation {
                // Fallback to last known location (e.g. simulator with no GPS)
                self.deliverBest(samples: [fallback], persist: state.persist, extras: state.extras, callback: state.callback)
            } else {
                state.callback(nil)
            }
        }
    }

    /// Called from `didUpdateLocations` to feed samples into an active collection.
    /// Returns `true` if the location was consumed by sample collection.
    private func feedSample(_ location: CLLocation) -> Bool {
        guard let state = sampleState, !state.finished else { return false }

        state.collected.append(location)
        if state.collected.count >= state.targetCount {
            state.finished = true
            sampleState = nil

            // Stop updates if we started them only for sampling and tracking isn't active
            if !isTracking {
                locationManager.stopUpdatingLocation()
            }
            // Restore configured distance filter.
            locationManager.distanceFilter = configManager.getDistanceFilter()

            deliverBest(samples: state.collected, persist: state.persist, extras: state.extras, callback: state.callback)
        }
        return true
    }

    /// Picks the best-accuracy location from samples and delivers it.
    private func deliverBest(samples: [CLLocation], persist: Bool, extras: [String: Any], callback: ([String: Any]?) -> Void) {
        guard let best = samples.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else {
            callback(nil)
            return
        }
        var locationMap = buildLocationMap(best)
        if !extras.isEmpty { locationMap["extras"] = extras }
        if persist {
            let _ = database.insertLocation(locationMap)
            onLocationPersisted?()
        }
        callback(locationMap)
    }

    // MARK: - Helpers

    private func fireOneShots(_ location: CLLocation) {
        guard !oneShots.isEmpty else { return }
        for callback in oneShots {
            callback(location)
        }
        oneShots.removeAll()
    }

    /// Builds an enriched location map ready for Dart/DB.
    ///
    /// - Parameters:
    ///   - location: The raw CLLocation.
    ///   - speed: Pre-computed effective speed (m/s).
    ///   - smoothedLat: Kalman-smoothed latitude (nil = use raw).
    ///   - smoothedLng: Kalman-smoothed longitude (nil = use raw).
    public func buildLocationMap(_ location: CLLocation, speed: Double? = nil, smoothedLat: Double? = nil, smoothedLng: Double? = nil) -> [String: Any] {
        // Use provided effective speed, or fall back to platform speed.
        let effectiveSpeed = speed ?? max(location.speed, -1)

        var coords: [String: Any] = [
            "latitude": smoothedLat ?? location.coordinate.latitude,
            "longitude": smoothedLng ?? location.coordinate.longitude,
            "altitude": location.altitude,
            "speed": effectiveSpeed,
            "heading": max(location.course, -1),
            "accuracy": location.horizontalAccuracy,
            "altitudeAccuracy": location.verticalAccuracy,
        ]

        if #available(iOS 13.4, *) {
            coords["speedAccuracy"] = location.speedAccuracy
            coords["headingAccuracy"] = location.courseAccuracy
        }

        if let floor = location.floor {
            coords["floor"] = floor.level
        }

        let battery = BatteryUtils.getBatteryInfo()

        let mock = isLocationMock(location)

        // Always include heuristic metadata even if rejection is off
        let driftMs = Date().timeIntervalSince(location.timestamp) * 1000.0
        var heuristics: [String: Any] = [
            "timestampDriftMs": driftMs,
        ]
        if #available(iOS 15.0, *) {
            heuristics["platformFlagMock"] = location.sourceInformation?.isSimulatedBySoftware ?? false
        }
        let mockHeuristics = heuristics

        // Classify the location source based on accuracy heuristic.
        // iOS does not expose provider names; accuracy is the best signal.
        // When reduced accuracy is active, iOS returns ~5 km fixes regardless
        // of desiredAccuracy, so classify accordingly.
        let reduced = isReducedAccuracy
        let locationSource: String
        if reduced {
            locationSource = "cell"  // reduced accuracy ≈ coarse cell-level
        } else if location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 50 {
            locationSource = "gps"
        } else if location.horizontalAccuracy <= 200 {
            locationSource = "wifi"
        } else if location.horizontalAccuracy > 200 {
            locationSource = "cell"
        } else {
            locationSource = "unknown"
        }

        var result: [String: Any] = [
            "uuid": Self.generateUUID(),
            "timestamp": iso8601String(from: location.timestamp),
            "coords": coords,
            "is_moving": stateManager.isMoving,
            "odometer": stateManager.odometer,
            "locationSource": locationSource,
            "reducedAccuracy": reduced,
            "mock": mock,
            "mockHeuristics": mockHeuristics as Any,
            "activity": [
                "type": "unknown",
                "confidence": -1,
            ],
            "battery": battery,
            "event": "",
            "extras": [:] as [String: Any],
        ]

        // enableTimestampMeta: attach additional timing metadata
        if configManager.getEnableTimestampMeta() {
            result["timestampMeta"] = [
                "time": location.timestamp.timeIntervalSince1970 * 1000, // ms since epoch
                "systemTime": Date().timeIntervalSince1970 * 1000,
                "systemClockElapsedRealtime": ProcessInfo.processInfo.systemUptime * 1000,
            ]
        }

        return result
    }

    /// Generates a UUID string using C-level functions directly.
    /// Avoids Foundation UUID struct + uppercase formatting overhead.
    private static func generateUUID() -> String {
        var uuid: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutablePointer(to: &uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                uuid_generate_random($0)
            }
        }
        var cString = [CChar](repeating: 0, count: 37)
        withUnsafePointer(to: uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                uuid_unparse_lower($0, &cString)
            }
        }
        return String(cString: cString)
    }

    /// Cached ISO 8601 formatter — creating one per call is expensive.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func iso8601String(from date: Date) -> String {
        return LocationEngine.isoFormatter.string(from: date)
    }

    /// Persists a location to the database only if allowed by persistMode.
    /// Also runs retention pruning (maxDaysToPersist / maxRecordsToPersist).
    ///
    /// persistMode: 0 = all, 1 = location only, 2 = geofence only, 3 = none
    private func persistLocationIfAllowed(_ location: [String: Any], event: String) {
        let persistMode = configManager.getPersistMode()
        // Mode 3 = none, Mode 2 = geofence only → skip location inserts
        if persistMode == 3 || persistMode == 2 { return }
        // Skip provider change records if disabled
        if event == "providerchange" && configManager.getDisableProviderChangeRecord() { return }

        // Route through Rust PluginEventDispatcher for DB persistence + auto HTTP sync
        if let dispatcher = rustPluginEventDispatcher {
            let coords = location["coords"] as? [String: Any]
            let lat = coords?["latitude"] as? Double ?? 0.0
            let lng = coords?["longitude"] as? Double ?? 0.0
            let accuracy = coords?["accuracy"] as? Double ?? 0.0
            let speed = coords?["speed"] as? Double ?? 0.0
            let heading = coords?["heading"] as? Double ?? 0.0
            let altitude = coords?["altitude"] as? Double ?? 0.0
            let isMock = location["mock"] as? Bool ?? location["is_mock"] as? Bool ?? false
            
            _ = dispatcher.onLocationUpdate(
                lat: lat,
                lng: lng,
                accuracy: accuracy,
                speed: speed,
                heading: heading,
                altitude: altitude,
                isMock: isMock
            )
        }

        // Notify HTTP sync manager (if wired) so auto-sync can fire.
        onLocationPersisted?()
    }

    /// Detects whether a CLLocation was produced by a simulated/mock provider.
    ///
    /// Detection level is controlled by `mockDetectionLevel` in config:
    /// - **0 (disabled)**: Always returns `false`.
    /// - **1 (basic)**: Uses `CLLocation.sourceInformation?.isSimulatedBySoftware`
    ///   on iOS 15+. Returns `false` on older iOS versions.
    /// - **2 (heuristic)**: Basic + timestamp drift check (compare location
    ///   timestamp against current wall-clock time; large drift is suspicious).
    ///
    /// iOS has fewer heuristic signals than Android (no satellite count, no
    /// monotonic elapsed-realtime clock on locations), so heuristic mode
    /// primarily adds timestamp drift detection.
    private func isLocationMock(_ location: CLLocation) -> Bool {
        let level = configManager.getMockDetectionLevel()
        if level == 0 { return false }

        // Level 1+ (basic): Platform API flag
        if #available(iOS 15.0, *) {
            if location.sourceInformation?.isSimulatedBySoftware ?? false {
                return true
            }
        }
        if level < 2 { return false }

        // Level 2 (heuristic): Timestamp drift check
        // Real GPS locations have a timestamp very close to the current time.
        // However, unlike Android, iOS does not provide a monotonic hardware timestamp
        // (`elapsedRealtimeNanos`) on `CLLocation`. Comparing `location.timestamp`
        // against `Date()` is extremely dangerous because it will falsely flag
        // perfectly valid locations if the user's device clock is slightly out of sync
        // with network UTC time.
        // Therefore, we do not reject locations based on timestamp drift on iOS.
        
        return false
    }

    // MARK: - Dead Reckoning (Enterprise)

    /// Returns the current dead reckoning state, or nil if not active.
    func getDeadReckoningState() -> [String: Any]? {
        return deadReckoningEngine?.getState()
    }

    /// Starts the GPS-loss timer. After `deadReckoningActivationDelay` seconds
    /// without a GPS fix, dead reckoning activates automatically.
    private func startGpsLossTimer() {
        guard configManager.getEnableDeadReckoning() else { return }
        cancelGpsLossTimer()

        let delay = TimeInterval(configManager.getDeadReckoningActivationDelay())
        NSLog("[Tracelet] DR: GPS-loss timer started (\(delay)s)")
        gpsLossTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            self?.activateDeadReckoning()
        }
    }

    /// Resets the GPS-loss timer (called on each GPS fix).
    private func resetGpsLossTimer() {
        guard configManager.getEnableDeadReckoning() else { return }
        cancelGpsLossTimer()
        startGpsLossTimer()
    }

    private func cancelGpsLossTimer() {
        gpsLossTimer?.invalidate()
        gpsLossTimer = nil
    }

    /// Activates dead reckoning from the last known GPS position.
    private func activateDeadReckoning() {
        guard let last = lastLocation else {
            NSLog("[Tracelet] DR: Cannot activate — no last known location")
            // Restart timer so we try again once a location arrives.
            startGpsLossTimer()
            return
        }
        NSLog("[Tracelet] DR: GPS lost for \(configManager.getDeadReckoningActivationDelay())s — activating (last=\(last.coordinate.latitude),\(last.coordinate.longitude) acc=\(last.horizontalAccuracy))")

        let engine = DeadReckoningEngine(configManager: configManager)
        engine.onEstimatedLocation = { [weak self] drLocation in
            self?.onDrLocationEstimated(drLocation)
        }
        engine.onDeactivated = {
            NSLog("[Tracelet] Dead reckoning auto-stopped (max duration)")
        }
        engine.activate(
            lat: last.coordinate.latitude,
            lng: last.coordinate.longitude,
            altitude: last.altitude,
            heading: last.course >= 0 ? last.course : 0,
            activity: currentActivityType
        )
        deadReckoningEngine = engine
    }

    /// Deactivates dead reckoning.
    private func deactivateDeadReckoning() {
        deadReckoningEngine?.deactivate()
        deadReckoningEngine = nil
    }

    /// Processes a dead-reckoned location estimate and dispatches it.
    private func onDrLocationEstimated(_ drLocation: [String: Any]) {
        guard let lat = drLocation["latitude"] as? Double,
              let lng = drLocation["longitude"] as? Double else { return }
        let altitude = drLocation["altitude"] as? Double ?? 0
        let heading = drLocation["heading"] as? Double ?? 0
        let accuracy = drLocation["accuracy"] as? Double ?? 50
        let speed = drLocation["speed"] as? Double ?? 0

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: Date())

        let enriched: [String: Any] = [
            "uuid": UUID().uuidString,
            "timestamp": timestamp,
            "isMoving": stateManager.isMoving,
            "odometer": stateManager.odometer,
            "event": "dead_reckoning",
            "mock": false,
            "isDeadReckoned": true,
            "coords": [
                "latitude": lat,
                "longitude": lng,
                "altitude": altitude,
                "speed": speed,
                "heading": heading,
                "accuracy": accuracy,
                "speedAccuracy": -1.0,
                "headingAccuracy": -1.0,
                "altitudeAccuracy": -1.0,
            ],
            "activity": [
                "type": currentActivityType,
                "confidence": -1,
            ],
            "battery": [
                "level": -1.0,
                "is_charging": false,
            ],
        ]

        persistLocationIfAllowed(enriched, event: "dead_reckoning")
        eventDispatcher.sendLocation(enriched)
    }

    // MARK: - Activity type mapping helpers (iOS string → Rust enum)

    private func mapActivityType(_ type: String) -> ActivityType {
        switch type.lowercased() {
        case "still": return .still
        case "walking": return .walking
        case "running": return .running
        case "on_foot": return .onFoot
        case "in_vehicle", "automotive": return .inVehicle
        case "on_bicycle", "cycling": return .onBicycle
        default: return .unknown
        }
    }

    private func mapActivityConfidence(_ confidence: Int) -> ActivityConfidence {
        if confidence >= 75 { return .high }
        if confidence >= 50 { return .medium }
        return .low
    }
}
