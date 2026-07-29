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
    public var onGeofenceEvent: (([String: Any]) -> Void)?
    
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    /// Maximum number of monitored regions (iOS limit).
    private static let maxRegions = 20

    /// High-accuracy mode: track which geofences the device is currently inside.
    private var insideGeofenceIds = Set<String>()

    /// High-accuracy geofence evaluator (polygon + circular).
    private let geofenceEvaluator = GeofenceEvaluator()

    /// Identifiers of geofences currently registered with CLLocationManager.
    private var activeGeofenceIds = Set<String>()

    /// Last known device location for proximity filtering.
    private var lastLatitude: Double?
    private var lastLongitude: Double?

    /// In-memory cache of active geofences to avoid querying the SQLite database on every GPS location update.
    private var cachedGeofences: [[String: Any]]?
    private let rustDatabase: DatabaseManager?

    private func getCachedGeofences() -> [[String: Any]] {
        if let cached = cachedGeofences {
            return cached
        }
        // Retrieve geofences from the shared Rust Core SQLite engine
        let loaded = (try? rustDatabase?.getGeofences()) ?? []
        let mapped = loaded.map { mapFromCoreGeofence($0) }
        cachedGeofences = mapped
        return mapped
    }

    public init(configManager: ConfigManager,
         eventSender: TraceletEventSending,
         rustDatabase: DatabaseManager? = nil) {
        self.configManager = configManager
        self.eventDispatcher = eventSender
        self.rustDatabase = rustDatabase ?? (try? DatabaseManager(dbPath: ":memory:"))
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
    }

    // MARK: - Add / Remove geofences

    /// Registers a single geofence. Persists to both the native Swift database (for background OS region monitoring)
    /// and the Rust Core SQLite engine, and evaluates local proximity.
    public func addGeofence(_ data: [String: Any]) -> Bool {
        // We removed native DB double-persist
        
        // Write to the shared Rust Core SQLite engine
        if let identifier = data["identifier"] as? String {
            let lat = data["latitude"] as? Double ?? 0.0
            let lng = data["longitude"] as? Double ?? 0.0
            let radius = data["radius"] as? Double ?? 100.0
            
            var vertices: [Coordinate]? = nil
            if let verticesRaw = data["vertices"] as? [[Double]] {
                vertices = verticesRaw.filter { $0.count >= 2 }.map { Coordinate(lat: $0[0], lng: $0[1]) }
            }
            
            var extrasStr: String? = nil
            if let extrasRaw = data["extras"] as? [String: Any],
               let jsonData = try? JSONSerialization.data(withJSONObject: extrasRaw, options: []),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                extrasStr = jsonStr
            }
            
            do {
                try rustDatabase?.insertGeofence(identifier: identifier, lat: lat, lng: lng, radius: radius, vertices: vertices, extras: extrasStr)
            } catch {
                TraceletLog.error("GeofenceManager: Failed to write geofence to Rust Core DB: \(error)")
            }
        }

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

    /// Registers multiple geofences in a single batch transaction.
    public func addGeofences(_ geofences: [[String: Any]]) -> Bool {
        // We removed native DB double-persist
        
        // Write to the shared Rust Core SQLite engine
        for g in geofences {
            if let identifier = g["identifier"] as? String {
                let lat = g["latitude"] as? Double ?? 0.0
                let lng = g["longitude"] as? Double ?? 0.0
                let radius = g["radius"] as? Double ?? 100.0
                
                var vertices: [Coordinate]? = nil
                if let verticesRaw = g["vertices"] as? [[Double]] {
                    vertices = verticesRaw.filter { $0.count >= 2 }.map { Coordinate(lat: $0[0], lng: $0[1]) }
                }
                
                var extrasStr: String? = nil
                if let extrasRaw = g["extras"] as? [String: Any],
                   let jsonData = try? JSONSerialization.data(withJSONObject: extrasRaw, options: []),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    extrasStr = jsonStr
                }
                
                do {
                    try rustDatabase?.insertGeofence(identifier: identifier, lat: lat, lng: lng, radius: radius, vertices: vertices, extras: extrasStr)
                } catch {
                    TraceletLog.error("GeofenceManager: Failed to write batch geofence to Rust Core DB: \(error)")
                }
            }
        }

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

    /// Deletes a specific geofence from both native iOS and shared Rust databases,
    /// and stops monitoring the active region.
    public func removeGeofence(_ identifier: String) -> Bool {
        do {
            try rustDatabase?.deleteGeofence(identifier: identifier)
        } catch {
            TraceletLog.error("GeofenceManager: Failed to delete geofence from Rust Core DB: \(error)")
        }

        cachedGeofences = nil

        // Find the actual monitored region by identifier instead of creating
        // a dummy region with fake coordinates (I-M5).
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager.stopMonitoring(for: region)
        }
        return true
    }

    /// Deletes all registered geofences.
    public func removeGeofences() -> Bool {
        do {
            try rustDatabase?.clearGeofences()
        } catch {
            TraceletLog.error("GeofenceManager: Failed to clear geofences from Rust Core DB: \(error)")
        }

        cachedGeofences = nil
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        return true
    }

    /// Retrieves all active geofences from the cached Rust database entries.
    public func getGeofences() -> [[String: Any]] {
        return getCachedGeofences()
    }

    /// Retrieves details for a specific geofence by its identifier.
    public func getGeofence(_ identifier: String) -> [String: Any]? {
        return getCachedGeofences().first(where: { $0["identifier"] as? String == identifier })
    }

    /// Checks if a specific geofence exists.
    public func geofenceExists(_ identifier: String) -> Bool {
        return getGeofence(identifier) != nil
    }

    /// Maps a Rust `CoreGeofence` structure into a bridge-compatible Swift dictionary.
    private func mapFromCoreGeofence(_ gf: CoreGeofence) -> [String: Any] {
        let verticesArray = gf.vertices.map { [$0.lat, $0.lng] }
        var result: [String: Any] = [
            "identifier": gf.identifier,
            "latitude": gf.latitude,
            "longitude": gf.longitude,
            "radius": gf.radius,
            "vertices": verticesArray
        ]
        
        if let extrasStr = gf.extras,
           let data = extrasStr.data(using: .utf8),
           let extrasDict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            result["extras"] = extrasDict
        }
        
        return result
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
        let geofences = getCachedGeofences()
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

    /// High-accuracy geofence evaluation.
    ///
    /// Uses `GeofenceEvaluator` to perform software-based ENTER/EXIT detection
    /// for both circular and polygon geofences. Dispatches transition events
    /// and geofencesChange events via `TraceletEventSending`.
    ///
    /// Called on each location update when `geofenceModeHighAccuracy` is enabled.
    /// Applies the `getGeofenceExitAccuracyMax` policy to the raw fix accuracy
    /// before it reaches the evaluator's accuracy-aware EXIT test (#274/#276):
    /// - `-1` (default): pass accuracy through unchanged (full gating).
    /// - `0`: return 0 — disables gating (fastest, drift-prone EXIT).
    /// - `N > 0`: clamp accuracy to N, bounding the worst-case EXIT delay.
    private func effectiveExitAccuracy(_ accuracy: Double) -> Double {
        let max = configManager.getGeofenceExitAccuracyMax()
        if max < 0 { return accuracy }
        if max == 0 { return 0.0 }
        return Swift.min(accuracy, Double(max))
    }

    public func evaluateHighAccuracyProximity(latitude: Double, longitude: Double, accuracy: Double = 0.0) {
        let allGeofences = getCachedGeofences()
        if allGeofences.isEmpty { return }

        let coreGeofences = allGeofences.map { mapToCoreGeofence($0) }
        let transitions = geofenceEvaluator.evaluateProximity(
            latitude: latitude,
            longitude: longitude,
            accuracy: effectiveExitAccuracy(accuracy),
            geofences: coreGeofences
        )
        if transitions.isEmpty { return }

        var on: [[String: Any]] = []
        var off: [[String: Any]] = []
        let geofenceMapById = Dictionary(uniqueKeysWithValues: allGeofences.compactMap {
            if let id = $0["identifier"] as? String { return (id, $0) } else { return nil }
        })

        for t in transitions {
            let gfMap = geofenceMapById[t.identifier]
            let eventData: [String: Any] = [
                "uuid": UUID().uuidString,
                "event": "geofence",
                "timestamp": isoFormatter.string(from: Date()),
                "coords": buildCoords(latitude: latitude, longitude: longitude),
                "battery": BatteryUtils.getBatteryInfo(),
                "geofence": [
                    "identifier": t.identifier,
                    "action": t.action,
                    "extras": gfMap?["extras"] ?? [:] as [String: Any],
                ]
            ]
            onGeofenceEvent?(eventData)
            eventDispatcher.sendGeofence(eventData)

            switch t.action {
            case "ENTER":
                if let g = gfMap { on.append(g) }
            case "EXIT":
                if let g = gfMap { off.append(g) }
                if configManager.getGeofenceModeKnockOut() {
                    let _ = removeGeofence(t.identifier)
                    geofenceEvaluator.removeGeofence(identifier: t.identifier)
                }
            default:
                break
            }
        }

        if !on.isEmpty || !off.isEmpty {
            eventDispatcher.sendGeofencesChange(["on": on, "off": off])
        }
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
        let allGeofences = getCachedGeofences()
        // Break up expression for Swift type-checker
        let circularGeofences = allGeofences.filter { gf in
            let vertices = gf["vertices"] as? [[Double]]
            return vertices == nil || (vertices?.count ?? 0) < 3
        }.filter { gf in
            let radius = gf["radius"] as? Double ?? 0
            return radius > 0
        }
        let candidates: [(geofence: [String: Any], distance: Double)] = circularGeofences
            .map { gf -> (geofence: [String: Any], distance: Double) in
                let lat = gf["latitude"] as? Double ?? 0
                let lng = gf["longitude"] as? Double ?? 0
                let distance = haversine(lat1: latitude, lon1: longitude, lat2: lat, lon2: lng)
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
            getGeofence(id) ?? ["identifier": id]
        }
        if !on.isEmpty || !off.isEmpty {
            eventDispatcher.sendGeofencesChange(["on": on, "off": off])
        }

        TraceletLog.debug("[Tracelet] Proximity update: \(activeGeofenceIds.count) active, +\(toAdd.count)/-\(toRemove.count)")
    }

    /// Clear high-accuracy tracking state.
    public func clearHighAccuracyState() {
        insideGeofenceIds.removeAll()
        geofenceEvaluator.clear()
    }

    public func destroy() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        insideGeofenceIds.removeAll()
        geofenceEvaluator.clear()
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
            TraceletLog.debug("[Tracelet] Geofence monitoring not available")
            return
        }

        let identifier = data["identifier"] as? String ?? UUID().uuidString
        let latitude = data["latitude"] as? Double ?? 0
        let longitude = data["longitude"] as? Double ?? 0
        let radius = min(data["radius"] as? Double ?? 100, locationManager.maximumRegionMonitoringDistance)

        // Guard against invalid radius (e.g. polygon geofences with radius=0)
        guard radius > 0 else {
            TraceletLog.debug("[Tracelet] Skipping geofence \(identifier): invalid radius \(radius)")
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
        TraceletLog.error("[Tracelet] Geofence monitoring failed for \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
    }

    // MARK: - Transition handling

    /// Builds the `coords` payload for a geofence transition event.
    ///
    /// The geofence boundary `latitude`/`longitude` come from the triggering
    /// event, while the remaining telemetry (accuracy, speed, heading, altitude
    /// and per-field accuracies) is sourced from the most recent GPS fix when
    /// available. Previously these were hardcoded to `0.0`, leaving backends
    /// blind to speed/heading/accuracy at the crossing (#231).
    private func buildCoords(latitude: Double, longitude: Double) -> [String: Any] {
        guard let location = locationManager.location else {
            return [
                "latitude": latitude,
                "longitude": longitude,
                "accuracy": 0.0,
                "speed": 0.0,
                "heading": 0.0,
                "altitude": 0.0,
            ]
        }

        var coords: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "altitude": location.altitude,
            "speed": location.speed >= 0 ? location.speed : 0.0,
            "heading": location.course >= 0 ? location.course : 0.0,
            "accuracy": location.horizontalAccuracy,
            "altitudeAccuracy": location.verticalAccuracy,
        ]
        if #available(iOS 13.4, *) {
            coords["speedAccuracy"] = location.speedAccuracy
            coords["headingAccuracy"] = location.courseAccuracy
        }
        return coords
    }

    private func handleTransition(region: CLCircularRegion, action: String) {
        // When high-accuracy mode is active, evaluateHighAccuracyProximity()
        // handles transitions in-app. Skip OS-level events to avoid duplicates.
        if configManager.getGeofenceModeHighAccuracy() { return }

        let geofenceData = getGeofence(region.identifier)
        let location = locationManager.location

        let lat = location?.coordinate.latitude ?? region.center.latitude
        let lng = location?.coordinate.longitude ?? region.center.longitude

        var eventData: [String: Any] = [
            "uuid": UUID().uuidString,
            "event": "geofence",
            "timestamp": isoFormatter.string(from: Date()),
            "coords": buildCoords(latitude: lat, longitude: lng),
            "battery": BatteryUtils.getBatteryInfo(),
            "geofence": [
                "identifier": region.identifier,
                "action": action,
                "extras": geofenceData?["extras"] ?? [:] as [String: Any],
            ]
        ]

        onGeofenceEvent?(eventData)
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

    private func mapToCoreGeofence(_ gf: [String: Any]) -> CoreGeofence {
        let identifier = gf["identifier"] as? String ?? ""
        let latitude = gf["latitude"] as? Double ?? 0.0
        let longitude = gf["longitude"] as? Double ?? 0.0
        let radius = gf["radius"] as? Double ?? 0.0
        var vertices: [Coordinate] = []
        if let verticesRaw = gf["vertices"] as? [[Double]] {
            for v in verticesRaw {
                if v.count >= 2 {
                    vertices.append(Coordinate(lat: v[0], lng: v[1]))
                }
            }
        }
        var extrasStr: String? = nil
        if let extrasRaw = gf["extras"] as? [String: Any],
           let jsonData = try? JSONSerialization.data(withJSONObject: extrasRaw, options: []),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            extrasStr = jsonStr
        }
        return CoreGeofence(identifier: identifier, latitude: latitude, longitude: longitude, radius: radius, vertices: vertices, extras: extrasStr)
    }
}
