import CoreLocation
import Foundation

/// Manages geofence monitoring using CLLocationManager region monitoring.
///
/// iOS limits region monitoring to 20 regions. This manager persists all
/// geofences in SQLite and registers up to 20 with the system based on
/// proximity to the user's current location.
final class GeofenceManager: NSObject, CLLocationManagerDelegate {
    private let locationManager: CLLocationManager
    private let configManager: ConfigManager
    private let eventDispatcher: EventDispatcher
    private let database: TraceletDatabase

    /// Maximum number of monitored regions (iOS limit).
    private static let maxRegions = 20

    /// High-accuracy mode: track which geofences the device is currently inside.
    private var insideGeofenceIds = Set<String>()

    init(configManager: ConfigManager,
         eventDispatcher: EventDispatcher,
         database: TraceletDatabase) {
        self.configManager = configManager
        self.eventDispatcher = eventDispatcher
        self.database = database
        self.locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Add / Remove geofences

    func addGeofence(_ data: [String: Any]) -> Bool {
        let _ = database.insertGeofence(data)
        // Polygon geofences are evaluated in Dart — skip system registration
        let vertices = data["vertices"] as? [[Double]]
        if vertices == nil || (vertices?.count ?? 0) < 3 {
            registerWithSystem(data)
        }
        return true
    }

    func addGeofences(_ geofences: [[String: Any]]) -> Bool {
        for g in geofences {
            let _ = database.insertGeofence(g)
            let vertices = g["vertices"] as? [[Double]]
            if vertices == nil || (vertices?.count ?? 0) < 3 {
                registerWithSystem(g)
            }
        }
        return true
    }

    func removeGeofence(_ identifier: String) -> Bool {
        let _ = database.deleteGeofence(identifier)
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 1,
            identifier: identifier
        )
        locationManager.stopMonitoring(for: region)
        return true
    }

    func removeGeofences() -> Bool {
        let _ = database.deleteAllGeofences()
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        return true
    }

    func getGeofences() -> [[String: Any]] {
        return database.getGeofences()
    }

    func getGeofence(_ identifier: String) -> [String: Any]? {
        return database.getGeofence(identifier)
    }

    func geofenceExists(_ identifier: String) -> Bool {
        return database.geofenceExists(identifier)
    }

    // MARK: - Re-register all (on boot or restart)

    func reRegisterAll() {
        let geofences = database.getGeofences()
        for g in geofences {
            // Polygon geofences are evaluated in Dart — skip system registration
            let vertices = g["vertices"] as? [[Double]]
            if vertices != nil && (vertices?.count ?? 0) >= 3 { continue }
            registerWithSystem(g)
        }
    }

    // MARK: - High-accuracy proximity evaluation

    /// High-accuracy geofence evaluation is now handled by shared Dart code
    /// (GeofenceEvaluator in tracelet_platform_interface). This method is kept
    /// as a no-op stub for call-site compatibility.
    func evaluateHighAccuracyProximity(latitude: Double, longitude: Double) {
        // Proximity evaluation moved to shared Dart GeofenceEvaluator.
        // This method is intentionally empty — Dart handles all ENTER/EXIT
        // transitions via GeofenceEvaluator.evaluateProximity() in the
        // onLocation stream pipeline.
    }

    /// Clear high-accuracy tracking state.
    func clearHighAccuracyState() {
        insideGeofenceIds.removeAll()
    }

    func destroy() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        insideGeofenceIds.removeAll()
    }

    // MARK: - System registration

    private func registerWithSystem(_ data: [String: Any]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            NSLog("[Tracelet] Geofence monitoring not available")
            return
        }

        let identifier = data["identifier"] as? String ?? UUID().uuidString
        let latitude = data["latitude"] as? Double ?? 0
        let longitude = data["longitude"] as? Double ?? 0
        let radius = min(data["radius"] as? Double ?? 100, locationManager.maximumRegionMonitoringDistance)

        // Guard against invalid radius (e.g. polygon geofences with radius=0)
        guard radius > 0 else {
            NSLog("[Tracelet] Skipping geofence \(identifier): invalid radius \(radius)")
            return
        }

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(center: center, radius: radius, identifier: identifier)

        region.notifyOnEntry = data["notifyOnEntry"] as? Bool ?? true
        region.notifyOnExit = data["notifyOnExit"] as? Bool ?? true

        locationManager.startMonitoring(for: region)

        // Request state for initial trigger
        if configManager.getGeofenceInitialTriggerEntry() {
            locationManager.requestState(for: region)
        }
    }

    // MARK: - CLLocationManagerDelegate — Geofence events

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circular = region as? CLCircularRegion else { return }
        handleTransition(region: circular, action: "ENTER")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circular = region as? CLCircularRegion else { return }
        handleTransition(region: circular, action: "EXIT")

        // KnockOut mode: auto-remove after EXIT
        if configManager.getGeofenceModeKnockOut() {
            let _ = removeGeofence(circular.identifier)
        }
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard let circular = region as? CLCircularRegion else { return }
        if state == .inside && configManager.getGeofenceInitialTriggerEntry() {
            handleTransition(region: circular, action: "ENTER")
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        NSLog("[Tracelet] Geofence monitoring failed for \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
    }

    // MARK: - Transition handling

    private func handleTransition(region: CLCircularRegion, action: String) {
        // When high-accuracy mode is active, evaluateHighAccuracyProximity()
        // handles transitions in-app. Skip OS-level events to avoid duplicates.
        if configManager.getGeofenceModeHighAccuracy() { return }

        let geofenceData = database.getGeofence(region.identifier)
        let location = locationManager.location

        var eventData: [String: Any] = [
            "identifier": region.identifier,
            "action": action,
            "location": [
                "coords": [
                    "latitude": location?.coordinate.latitude ?? region.center.latitude,
                    "longitude": location?.coordinate.longitude ?? region.center.longitude,
                ],
            ],
            "extras": geofenceData?["extras"] ?? [:] as [String: Any],
        ]

        if let g = geofenceData {
            eventData["geofence"] = g
        }

        eventDispatcher.sendGeofence(eventData)

        // Also fire geofencesChange with correct on/off arrays
        let geofence = geofenceData ?? ["identifier": region.identifier]
        let on: [[String: Any]]  = action == "ENTER" ? [geofence] : []
        let off: [[String: Any]] = action == "EXIT"  ? [geofence] : []
        eventDispatcher.sendGeofencesChange(["on": on, "off": off])
    }

}
