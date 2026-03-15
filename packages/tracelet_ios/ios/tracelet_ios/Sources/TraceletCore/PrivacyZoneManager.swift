import CoreLocation
import Foundation

/// **[Enterprise]** Privacy zone manager.
///
/// Evaluates incoming locations against registered privacy zones and applies
/// the configured action:
///
/// - **Exclude** (`action = 0`): Location is dropped entirely — not persisted,
///   not dispatched, not audited.
/// - **Degrade** (`action = 1`): Coordinates are degraded to a configurable
///   accuracy radius (default 1 000 m) by snapping to a grid.
/// - **Event-only** (`action = 2`): Location is dispatched to Flutter
///   listeners but **not** persisted to the database.
///
/// Uses the Haversine formula for distance checks.
public final class PrivacyZoneManager {

    // Action constants — must match Dart `PrivacyZoneAction` enum indices
    public static let actionExclude  = 0
    public static let actionDegrade  = 1
    public static let actionEventOnly = 2

    /// Earth's mean radius in metres.
    private static let earthRadiusM: Double = 6_371_000.0

    private let database: TraceletDatabase
    private let configManager: ConfigManager

    /// In-memory cache of privacy zones — avoids DB query on every location (I-M7).
    private var cachedZones: [[String: Any]]?

    public init(database: TraceletDatabase, configManager: ConfigManager) {
        self.database = database
        self.configManager = configManager
    }

    /// Whether privacy zones are enabled in the configuration.
    public func isEnabled() -> Bool {
        return configManager.getPrivacyZoneEnabled()
    }

    // MARK: - Zone CRUD

    public func addZone(_ zone: [String: Any]) -> Bool {
        cachedZones = nil
        return database.insertPrivacyZone(zone)
    }

    public func addZones(_ zones: [[String: Any]]) -> Bool {
        for zone in zones {
            _ = database.insertPrivacyZone(zone)
        }
        cachedZones = nil
        return true
    }

    public func removeZone(_ identifier: String) -> Bool {
        cachedZones = nil
        return database.deletePrivacyZone(identifier)
    }

    public func removeAllZones() -> Bool {
        cachedZones = nil
        return database.deleteAllPrivacyZones()
    }

    public func getZones() -> [[String: Any]] {
        return database.getPrivacyZones()
    }

    // MARK: - Location evaluation

    /// The result of evaluating a location against all privacy zones.
    public struct EvaluationResult {
        let action: Int?
        let zone: [String: Any]?
    }

    /// Evaluates whether a location falls inside any registered privacy zone.
    ///
    /// When multiple zones overlap the **most restrictive** action wins:
    /// exclude > eventOnly > degrade.
    public func evaluate(latitude: Double, longitude: Double) -> EvaluationResult {
        guard isEnabled() else {
            return EvaluationResult(action: nil, zone: nil)
        }
        let zones = cachedZones ?? {
            let loaded = database.getPrivacyZones()
            cachedZones = loaded
            return loaded
        }()
        guard !zones.isEmpty else {
            return EvaluationResult(action: nil, zone: nil)
        }

        var matchedAction: Int?
        var matchedZone: [String: Any]?

        for zone in zones {
            guard let zLat = zone["latitude"] as? Double,
                  let zLng = zone["longitude"] as? Double,
                  let zRadius = zone["radius"] as? Double else { continue }

            let distance = haversineDistance(
                lat1: latitude, lng1: longitude,
                lat2: zLat, lng2: zLng
            )

            if distance <= zRadius {
                let action = zone["action"] as? Int ?? PrivacyZoneManager.actionExclude
                if matchedAction == nil || isActionMoreRestrictive(action, than: matchedAction!) {
                    matchedAction = action
                    matchedZone = zone
                }
            }
        }
        return EvaluationResult(action: matchedAction, zone: matchedZone)
    }

    // MARK: - Processed location

    public enum ProcessedAction {
        /// No privacy zone matched — pass through normally.
        case passThrough
        /// Location inside exclusion zone — drop entirely.
        case drop
        /// Dispatch to Flutter but do NOT persist.
        case eventOnly
        /// Coordinates degraded — persist and dispatch the degraded version.
        case degraded
    }

    public struct ProcessedLocation {
        let action: ProcessedAction
        let location: [String: Any]?
    }

    /// Processes a location map against all privacy zones.
    public func processLocation(_ locationMap: [String: Any]) -> ProcessedLocation {
        guard let coords = locationMap["coords"] as? [String: Any],
              let lat = coords["latitude"] as? Double,
              let lng = coords["longitude"] as? Double else {
            return ProcessedLocation(action: .passThrough, location: locationMap)
        }

        let result = evaluate(latitude: lat, longitude: lng)
        guard let action = result.action else {
            return ProcessedLocation(action: .passThrough, location: locationMap)
        }

        switch action {
        case PrivacyZoneManager.actionExclude:
            return ProcessedLocation(action: .drop, location: nil)

        case PrivacyZoneManager.actionEventOnly:
            return ProcessedLocation(action: .eventOnly, location: locationMap)

        case PrivacyZoneManager.actionDegrade:
            let accuracy = result.zone?["degradedAccuracyMeters"] as? Double ?? 1000.0
            let degraded = degradeLocation(locationMap, lat: lat, lng: lng, accuracyMeters: accuracy)
            return ProcessedLocation(action: .degraded, location: degraded)

        default:
            return ProcessedLocation(action: .passThrough, location: locationMap)
        }
    }

    // MARK: - Internals

    /// Degrades location precision by snapping coordinates to a grid.
    private func degradeLocation(
        _ location: [String: Any],
        lat: Double,
        lng: Double,
        accuracyMeters: Double
    ) -> [String: Any] {
        let (snappedLat, snappedLng) = degradeCoordinates(
            lat: lat, lng: lng, accuracyMeters: accuracyMeters
        )

        var modified = location
        if var coords = modified["coords"] as? [String: Any] {
            coords["latitude"] = snappedLat
            coords["longitude"] = snappedLng
            coords["accuracy"] = accuracyMeters
            modified["coords"] = coords
        }
        // Also set top-level keys used by some code paths
        modified["latitude"] = snappedLat
        modified["longitude"] = snappedLng
        modified["accuracy"] = accuracyMeters
        return modified
    }

    /// Haversine great-circle distance between two points in metres.
    private func haversineDistance(
        lat1: Double, lng1: Double,
        lat2: Double, lng2: Double
    ) -> Double {
        return haversineDistanceMetres(lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2)
    }
}

// MARK: - Module-level pure functions (extracted for unit testing)

/// Earth's mean radius in metres.
private let kEarthRadiusM: Double = 6_371_000.0

/// Haversine great-circle distance between two points in metres.
public func haversineDistanceMetres(
    lat1: Double, lng1: Double,
    lat2: Double, lng2: Double
) -> Double {
    let dLat = (lat2 - lat1) * .pi / 180.0
    let dLng = (lng2 - lng1) * .pi / 180.0
    let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
            sin(dLng / 2) * sin(dLng / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return kEarthRadiusM * c
}

/// Returns `true` if action `a` is more restrictive than action `b`.
///
/// Priority: exclude(0)=3 > eventOnly(2)=2 > degrade(1)=1.
public func isActionMoreRestrictive(_ a: Int, than b: Int) -> Bool {
    let priority: [Int: Int] = [
        PrivacyZoneManager.actionExclude: 3,
        PrivacyZoneManager.actionEventOnly: 2,
        PrivacyZoneManager.actionDegrade: 1,
    ]
    return (priority[a] ?? 0) > (priority[b] ?? 0)
}

/// Degrades coordinates by snapping to a grid of `accuracyMeters` resolution.
///
/// Returns a tuple of `(snappedLat, snappedLng)`.
public func degradeCoordinates(
    lat: Double,
    lng: Double,
    accuracyMeters: Double
) -> (Double, Double) {
    let gridDeg = accuracyMeters / 111_320.0
    let snappedLat = (lat / gridDeg).rounded() * gridDeg
    let snappedLng = (lng / gridDeg).rounded() * gridDeg
    return (snappedLat, snappedLng)
}
