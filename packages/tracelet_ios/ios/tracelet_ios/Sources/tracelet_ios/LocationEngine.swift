import CoreLocation
import Foundation

/// CLLocationManager wrapper providing continuous location tracking,
/// one-shot position, watch position, significant location changes,
/// and odometer computation.
final class LocationEngine: NSObject, CLLocationManagerDelegate {
    private let locationManager: CLLocationManager
    private let configManager: ConfigManager
    private let stateManager: StateManager
    private let eventDispatcher: EventDispatcher
    private let database: TraceletDatabase

    private var lastLocation: CLLocation?
    private var oneShots: [((CLLocation?) -> Void)] = []
    private var watchCallbacks: [Int: Bool] = [:]
    private var nextWatchId = 0
    private var isTracking = false

    /// Optional callback invoked on every accepted location (for geofenceModeHighAccuracy).
    var onLocationUpdate: ((Double, Double) -> Void)?

    init(configManager: ConfigManager,
         stateManager: StateManager,
         eventDispatcher: EventDispatcher,
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

    func start() {
        guard !isTracking else { return }
        isTracking = true

        configureLocationManager()

        // Always register for significant-location changes as a fallback
        // wake-up mechanism. If iOS terminates the app, significant-location
        // changes will relaunch it so tracking can resume.
        locationManager.startMonitoringSignificantLocationChanges()

        if !configManager.getUseSignificantChangesOnly() {
            locationManager.startUpdatingLocation()
        }
    }

    func stop() {
        guard isTracking else { return }
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    func destroy() {
        stop()
        lastLocation = nil
        oneShots.removeAll()
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
        locationManager.distanceFilter = distanceFilter > 0 ? distanceFilter : kCLDistanceFilterNone

        if #available(iOS 14.0, *) {
            locationManager.desiredAccuracy = locationManager.desiredAccuracy
        }

        locationManager.activityType = .otherNavigation
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
    func getCurrentPosition(options: [String: Any], callback: @escaping ([String: Any]?) -> Void) {
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
                if persist { let _ = database.insertLocation(locationMap) }
                callback(locationMap)
                return
            }
        }

        if samples > 1 {
            collectSamples(count: samples, persist: persist, extras: extras, callback: callback)
            return
        }

        oneShots.append { [weak self] location in
            guard let self = self, let location = location else {
                callback(nil)
                return
            }
            var locationMap = self.buildLocationMap(location)
            if !extras.isEmpty { locationMap["extras"] = extras }
            if persist { let _ = self.database.insertLocation(locationMap) }
            callback(locationMap)
        }

        // Ensure the location manager is configured for one-shot delivery.
        // requestLocation() requires desiredAccuracy to be set and
        // will silently fail if the manager isn't properly configured.
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestLocation()
    }

    /// Returns the last known location without activating any provider.
    ///
    /// This is a zero-battery-cost operation. Returns nil if no cached
    /// location is available.
    ///
    /// Supported keys in `options`:
    /// - `persist` (Bool): Whether to persist to DB (default false).
    /// - `extras` ([String: Any]): Extra data to attach.
    func getLastKnownLocation(options: [String: Any], callback: ([String: Any]?) -> Void) {
        let persist = options["persist"] as? Bool ?? false
        let extras = options["extras"] as? [String: Any] ?? [:]

        guard let location = lastLocation ?? locationManager.location else {
            callback(nil)
            return
        }

        var locationMap = buildLocationMap(location)
        if !extras.isEmpty { locationMap["extras"] = extras }
        locationMap["event"] = "getLastKnownLocation"
        if persist { let _ = database.insertLocation(locationMap) }
        callback(locationMap)
    }

    // MARK: - Watch position

    func watchPosition(options: [String: Any]) -> Int {
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

    func stopWatchPosition(_ watchId: Int) -> Bool {
        watchCallbacks.removeValue(forKey: watchId)
        return true
    }

    // MARK: - Pace control

    func changePace(_ isMoving: Bool) -> Bool {
        stateManager.isMoving = isMoving
        if isMoving {
            start()
        } else {
            stop()
        }
        return true
    }

    // MARK: - Odometer

    func getOdometer() -> Double {
        return stateManager.odometer
    }

    func setOdometer(_ value: Double) -> [String: Any] {
        stateManager.odometer = value
        if let loc = lastLocation {
            return buildLocationMap(loc)
        }
        return ["odometer": value]
    }

    func getLastLocation() -> CLLocation? {
        return lastLocation
    }

    // MARK: - Provider state

    func buildProviderState() -> [String: Any] {
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

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Feed multi-sample collection if active
        let consumedBySampler = feedSample(location)

        // --- Compute speed from distance/time as fallback ---
        // CLLocation.speed can be -1 (invalid) or 0 when walking slowly,
        // during cold GPS starts, or with low-accuracy modes. We compute
        // speed ourselves from consecutive location pairs.
        var computedSpeed: Double = 0.0

        // --- Elasticity: dynamically scale distanceFilter based on speed ---
        let baseDistance = configManager.getDistanceFilter()

        // Distance filter check (using elasticity-adjusted value)
        if let last = lastLocation {
            let distance = location.distance(from: last)
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp) // seconds
            computedSpeed = (distance > 0 && timeDelta > 0) ? distance / timeDelta : 0.0

            // Use platform speed if available, otherwise use computed speed
            let effectiveSpeed = (location.speed > 0) ? location.speed : computedSpeed

            let effectiveDistance: Double
            if !configManager.getDisableElasticity() && effectiveSpeed > 0 {
                let multiplier = max(configManager.getElasticityMultiplier(), 0.1)
                // Scale: faster speed → larger distance filter
                let speedFactor = min(max(effectiveSpeed / 10.0, 1.0), 10.0)
                effectiveDistance = baseDistance * speedFactor * multiplier
            } else {
                effectiveDistance = baseDistance
            }

            if effectiveDistance > 0 && distance < effectiveDistance && !configManager.getAllowIdenticalLocations() {
                // Fire one-shots regardless of distance
                fireOneShots(location)
                return
            }

            // --- Location Filtering / Denoising ---
            let trackingAccuracyThreshold = configManager.getTrackingAccuracyThreshold()
            if trackingAccuracyThreshold > 0 && location.horizontalAccuracy > Double(trackingAccuracyThreshold) {
                let policy = configManager.getFilterPolicy() // 0=adjust, 1=ignore, 2=discard
                switch policy {
                case 2: // discard: drop + emit error event
                    eventDispatcher.sendLocation(["error": "ACCURACY_FILTER", "message": "Location accuracy \(location.horizontalAccuracy)m exceeds threshold \(trackingAccuracyThreshold)m"])
                    fireOneShots(location)
                    return
                case 1: // ignore: drop silently
                    fireOneShots(location)
                    return
                default: // adjust: skip inaccurate point
                    fireOneShots(location)
                    return
                }
            }

            let maxImpliedSpeed = configManager.getMaxImpliedSpeed()
            if maxImpliedSpeed > 0 {
                if timeDelta > 0 {
                    let impliedSpeed = distance / timeDelta // m/s
                    if impliedSpeed > Double(maxImpliedSpeed) {
                        let policy = configManager.getFilterPolicy()
                        switch policy {
                        case 2:
                            eventDispatcher.sendLocation(["error": "SPEED_FILTER", "message": "Implied speed \(impliedSpeed)m/s exceeds max \(maxImpliedSpeed)m/s"])
                            fireOneShots(location)
                            return
                        default: // ignore or adjust: reject impossible speed
                            fireOneShots(location)
                            return
                        }
                    }
                }
            }

            // Odometer accuracy check
            let odometerAccuracyThreshold = configManager.getOdometerAccuracyThreshold()
            let addToOdometer = odometerAccuracyThreshold <= 0 || location.horizontalAccuracy <= Double(odometerAccuracyThreshold)
            if addToOdometer {
                stateManager.odometer += distance
            }
        }

        // Resolve effective speed: platform speed if available, otherwise computed
        let effectiveSpeed = (location.speed > 0) ? location.speed : computedSpeed

        lastLocation = location
        stateManager.lastLocationTime = Date().timeIntervalSince1970 * 1000

        let locationMap = buildLocationMap(location, speed: effectiveSpeed)

        // Fire one-shot callbacks
        fireOneShots(location)

        // If consumed exclusively by sampler, don't dispatch as tracking event
        if consumedBySampler && !isTracking { return }

        // Fire watch position events
        if !watchCallbacks.isEmpty {
            eventDispatcher.sendWatchPosition(locationMap)
        }

        // Persist and dispatch (respecting persistMode)
        persistLocationIfAllowed(locationMap, event: "motionchange")
        eventDispatcher.sendLocation(locationMap)

        // Notify geofenceModeHighAccuracy listener (if active)
        onLocationUpdate?(location.coordinate.latitude, location.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[Tracelet] Location error: \(error.localizedDescription)")

        // Fail all one-shots
        for callback in oneShots {
            callback(nil)
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
            } else {
                state.callback(nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
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
        locationManager.activityType = .otherNavigation

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
        if persist { let _ = database.insertLocation(locationMap) }
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
    ///   - speed: Pre-computed effective speed (m/s). Uses platform speed if
    ///            available, otherwise distance/time from consecutive locations.
    ///            Pass `nil` to fall back to platform speed.
    private func buildLocationMap(_ location: CLLocation, speed: Double? = nil) -> [String: Any] {
        // Use provided effective speed, or fall back to platform speed.
        let effectiveSpeed = speed ?? max(location.speed, -1)

        var coords: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "speed": effectiveSpeed,
            "heading": max(location.course, -1),
            "accuracy": location.horizontalAccuracy,
            "altitude_accuracy": location.verticalAccuracy,
        ]

        if #available(iOS 13.4, *) {
            coords["speed_accuracy"] = location.speedAccuracy
            coords["heading_accuracy"] = location.courseAccuracy
        }

        if let floor = location.floor {
            coords["floor"] = floor.level
        }

        let battery = BatteryUtils.getBatteryInfo()

        var result: [String: Any] = [
            "uuid": UUID().uuidString,
            "timestamp": iso8601String(from: location.timestamp),
            "coords": coords,
            "is_moving": stateManager.isMoving,
            "odometer": stateManager.odometer,
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

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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

        let _ = database.insertLocation(location)

        // Enforce retention limits
        let maxDays = configManager.getMaxDaysToPersist()
        if maxDays > 0 { database.pruneOldLocations(maxDays: maxDays) }
        let maxRecords = configManager.getMaxRecordsToPersist()
        if maxRecords > 0 { database.enforceMaxRecords(maxRecords: maxRecords) }
    }
}
