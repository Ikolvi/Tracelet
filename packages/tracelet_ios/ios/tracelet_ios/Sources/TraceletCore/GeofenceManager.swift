import CoreLocation
import Foundation

/// Manages geofence monitoring using CLLocationManager region monitoring.
///
/// iOS limits region monitoring to 20 regions. This manager persists all
/// geofences in SQLite and registers up to 20 with the system based on
/// proximity to the user's current location.
public final class GeofenceManager: NSObject, CLLocationManagerDelegate {
    private let locationManager: CLLocationManager
    private let configManager: ConfigManager
    private let eventDispatcher: TraceletEventSending
    private let database: TraceletDatabase

    /// Maximum number of monitored regions (iOS limit).
    private static let maxRegions = 20

    /// High-accuracy mode: track which geofences the device is currently inside.
    private var insideGeofenceIds = Set<String>()

    /// Identifiers of geofences currently registered with CLLocationManager.
    private var activeGeofenceIds = Set<String>()

    /// Last known device location for proximity filtering.
    private var lastLatitude: Double?
    private var lastLongitude: Double?

    /// In-memory cache of geofences — avoids DB query on every proximity update (I-M8).
    private var cachedGeofences: [[String: Any]]?

    public init(configManager: ConfigManager,
         eventDispatcher: TraceletEventSending,
         database: TraceletDatabase) {
        self.configManager = configManager
        self.eventDispatcher = eventDispatcher
        self.database = database
        self.locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Add / Remove geofences

    public func addGeofence(_ data: [String: Any]) -> Bool {
        let _ = database.insertGeofence(data)
        cachedGeofences = nil
        // Polygon geofences are evaluated in Dart — no system registration needed
        let vertices = data["vertices"] as? [[Double]]
        if vertices != nil && (vertices?.count ?? 0) >= 3 { return true }

        // If we have a known device location, use proximity-based registration
        if let lat = lastLatitude, let lng = lastLongitude {
            updateProximity(latitude: lat, longitude: lng)
            return true
        }
        // No known location — register directly (will be proximity-filtered later)
        registerWithSystem(data)
        return true
    }

    public func addGeofences(_ geofences: [[String: Any]]) -> Bool {
        // Use batch insert with a single transaction (I-H3).
        let _ = database.insertGeofencesBatch(geofences)
        cachedGeofences = nil
        // Re-evaluate proximity for all geofences at once
        if let lat = lastLatitude, let lng = lastLongitude {
            updateProximity(latitude: lat, longitude: lng)
        } else {
            // No known location — register circular ones directly
            for g in geofences {
                let vertices = g["vertices"] as? [[Double]]
                if vertices == nil || (vertices?.count ?? 0) < 3 {
                    registerWithSystem(g)
                }
            }
        }
        return true
    }

    public func removeGeofence(_ identifier: String) -> Bool {
        let _ = database.deleteGeofence(identifier)
        cachedGeofences = nil
        // Find the actual monitored region by identifier instead of creating
        // a dummy region with fake coordinates (I-M5).
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager.stopMonitoring(for: region)
        }
        return true
    }

    public func removeGeofences() -> Bool {
        let _ = database.deleteAllGeofences()
        cachedGeofences = nil
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        return true
    }

    public func getGeofences() -> [[String: Any]] {
        return database.getGeofences()
    }

    public func getGeofence(_ identifier: String) -> [String: Any]? {
        return database.getGeofence(identifier)
    }

    public func geofenceExists(_ identifier: String) -> Bool {
        return database.geofenceExists(identifier)
    }

    // MARK: - Re-register all (on boot or restart)

    /// Re-registers persisted geofences with CLLocationManager.
    /// Uses proximity filtering when a device location is available;
    /// otherwise registers all (up to platform max).
    public func reRegisterAll() {
        if let lat = lastLatitude, let lng = lastLongitude {
            updateProximity(latitude: lat, longitude: lng)
            return
        }
        // No known location — register all circular geofences (capped at max)
        let maxMonitored = resolveMaxMonitored()
        var count = 0
        let geofences = database.getGeofences()
        for g in geofences {
            if count >= maxMonitored { break }
            let vertices = g["vertices"] as? [[Double]]
            if vertices != nil && (vertices?.count ?? 0) >= 3 { continue }
            let radius = g["radius"] as? Double ?? 0
            if radius <= 0 { continue }
            registerWithSystem(g)
            count += 1
        }
    }

    // MARK: - High-accuracy proximity evaluation

    /// High-accuracy geofence evaluation is now handled by shared Dart code
    /// (GeofenceEvaluator in tracelet_platform_interface). This method is kept
    /// as a no-op stub for call-site compatibility.
    public func evaluateHighAccuracyProximity(latitude: Double, longitude: Double) {
        // Proximity evaluation moved to shared Dart GeofenceEvaluator.
    }

    /// Update proximity-based geofence monitoring.
    ///
    /// Evaluates which stored geofences are within `geofenceProximityRadius`
    /// of the given device location, sorts them by distance, and registers only
    /// the closest N geofences with iOS (where N = min(maxMonitoredGeofences, 20)).
    ///
    /// Geofences that move out of proximity are unregistered. Geofences that
    /// move into proximity are registered. A `geofencesChange` event is fired
    /// for any changes.
    ///
    /// This enables monitoring thousands of geofences despite iOS's 20-region limit.
    public func updateProximity(latitude: Double, longitude: Double) {
        lastLatitude = latitude
        lastLongitude = longitude

        let proximityRadius = Double(configManager.getGeofenceProximityRadius())
        let maxMonitored = resolveMaxMonitored()

        // Use cached geofences to avoid DB query on every proximity update (I-M8).
        let allGeofences: [[String: Any]]
        if let cached = cachedGeofences {
            allGeofences = cached
        } else {
            allGeofences = database.getGeofences()
            cachedGeofences = allGeofences
        }
        let candidates: [(geofence: [String: Any], distance: Double)] = allGeofences
            .filter { gf in
                let vertices = gf["vertices"] as? [[Double]]
                return vertices == nil || (vertices?.count ?? 0) < 3
            }
            .filter { gf in
                let radius = gf["radius"] as? Double ?? 0
                return radius > 0
            }
            .map { gf in
                let lat = gf["latitude"] as? Double ?? 0
                let lng = gf["longitude"] as? Double ?? 0
                let distance = haversineDistanceMetres(lat1: latitude, lng1: longitude, lat2: lat, lng2: lng)
                return (geofence: gf, distance: distance)
            }
            .filter { $0.distance <= proximityRadius }
            .sorted { $0.distance < $1.distance }
            .prefix(maxMonitored)
            .map { $0 }

        let newActiveIds = Set(candidates.compactMap { $0.geofence["identifier"] as? String })
        let toRemove = activeGeofenceIds.subtracting(newActiveIds)
        let toAdd = newActiveIds.subtracting(activeGeofenceIds)

        if toRemove.isEmpty && toAdd.isEmpty { return }

        // Unregister geofences that left the proximity zone
        for id in toRemove {
            unregisterFromSystem(id)
        }

        // Register geofences that entered the proximity zone
        let candidateMap = Dictionary(
            candidates.compactMap { c -> (String, [String: Any])? in
                guard let id = c.geofence["identifier"] as? String else { return nil }
                return (id, c.geofence)
            },
            uniquingKeysWith: { first, _ in first }
        )
        for id in toAdd {
            if let gf = candidateMap[id] {
                registerWithSystem(gf)
            }
        }

        // Fire geofencesChange event (on = activated, off = deactivated)
        let on: [[String: Any]] = toAdd.compactMap { candidateMap[$0] }
        let off: [[String: Any]] = toRemove.map { id in
            database.getGeofence(id) ?? ["identifier": id]
        }
        if !on.isEmpty || !off.isEmpty {
            eventDispatcher.sendGeofencesChange(["on": on, "off": off])
        }

        NSLog("[Tracelet] Proximity update: \(activeGeofenceIds.count) active, +\(toAdd.count)/-\(toRemove.count)")
    }

    /// Clear high-accuracy tracking state.
    public func clearHighAccuracyState() {
        insideGeofenceIds.removeAll()
    }

    public func destroy() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        insideGeofenceIds.removeAll()
    }

    // MARK: - System registration / unregistration

    /// Unregister a single geofence from CLLocationManager by identifier.
    private func unregisterFromSystem(_ identifier: String) {
        for region in locationManager.monitoredRegions {
            if region.identifier == identifier {
                locationManager.stopMonitoring(for: region)
                activeGeofenceIds.remove(identifier)
                return
            }
        }
        // Region not found in monitoredRegions — just clean up our tracking set
        activeGeofenceIds.remove(identifier)
    }

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
        activeGeofenceIds.insert(identifier)

        // Request state for initial trigger
        if configManager.getGeofenceInitialTriggerEntry() {
            locationManager.requestState(for: region)
        }
    }

    // MARK: - CLLocationManagerDelegate — Geofence events

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circular = region as? CLCircularRegion else { return }
        handleTransition(region: circular, action: "ENTER")
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circular = region as? CLCircularRegion else { return }
        handleTransition(region: circular, action: "EXIT")

        // KnockOut mode: auto-remove after EXIT
        if configManager.getGeofenceModeKnockOut() {
            let _ = removeGeofence(circular.identifier)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard let circular = region as? CLCircularRegion else { return }
        if state == .inside && configManager.getGeofenceInitialTriggerEntry() {
            handleTransition(region: circular, action: "ENTER")
        }
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
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

    // MARK: - Helpers

    /// Resolve the effective maximum number of simultaneously monitored geofences.
    /// Uses `maxMonitoredGeofences` if set (> 0), otherwise falls back to
    /// the platform maximum (20 for iOS).
    private func resolveMaxMonitored() -> Int {
        let configured = configManager.getMaxMonitoredGeofences()
        return configured > 0 ? min(configured, GeofenceManager.maxRegions) : GeofenceManager.maxRegions
    }
}
