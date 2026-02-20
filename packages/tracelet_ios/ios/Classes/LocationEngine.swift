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
    private var oneShots: [(([String: Any]?) -> Void)] = []
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

        if configManager.getUseSignificantChangesOnly() {
            locationManager.startMonitoringSignificantLocationChanges()
        } else {
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

    func getCurrentPosition(options: [String: Any], callback: @escaping ([String: Any]?) -> Void) {
        oneShots.append(callback)
        locationManager.requestLocation()
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
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        let providerState = buildProviderState()
        eventDispatcher.sendProviderChange(providerState)
    }

    // MARK: - Helpers

    private func fireOneShots(_ location: CLLocation) {
        guard !oneShots.isEmpty else { return }
        let map = buildLocationMap(location)
        for callback in oneShots {
            callback(map)
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
