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

    func setOdometer(_ value: Double) -> Double {
        stateManager.odometer = value
        return value
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

        // Distance filter check
        if let last = lastLocation {
            let distance = location.distance(from: last)
            let minDistance = configManager.getDistanceFilter()
            if minDistance > 0 && distance < minDistance && !configManager.getAllowIdenticalLocations() {
                // Fire one-shots regardless of distance
                fireOneShots(location)
                return
            }

            // Update odometer
            stateManager.odometer += distance
        }

        lastLocation = location
        stateManager.lastLocationTime = Date().timeIntervalSince1970 * 1000

        let locationMap = buildLocationMap(location)

        // Fire one-shot callbacks
        fireOneShots(location)

        // If consumed exclusively by sampler, don't dispatch as tracking event
        if consumedBySampler && !isTracking { return }

        // Fire watch position events
        if !watchCallbacks.isEmpty {
            eventDispatcher.sendWatchPosition(locationMap)
        }

        // Persist and dispatch
        let _ = database.insertLocation(locationMap)
        eventDispatcher.sendLocation(locationMap)
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

    private func buildLocationMap(_ location: CLLocation) -> [String: Any] {
        var coords: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "speed": max(location.speed, -1),
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

        return [
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
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
