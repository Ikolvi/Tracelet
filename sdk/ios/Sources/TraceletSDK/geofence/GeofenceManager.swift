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

    /// Invoked when CoreLocation reports a transition for a fence the in-app
    /// evaluator owns — the wake-up that `wakeupRadiusMeters`' inflated region
    /// exists to produce (#356).
    ///
    /// The transition itself is discarded (it describes the 100 m wake-up
    /// boundary, not the fence), but its *arrival* is information: the device is
    /// near a fence only this SDK can decide, and deciding it needs the location
    /// stream. Hosts wire this to resume continuous tracking, so a relaunch that
    /// came up in a low-power posture still evaluates the true radius.
    public var onEvaluatorWakeup: (() -> Void)?
    
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    /// Maximum number of monitored regions (iOS limit).
    private static let maxRegions = 20

    /// Category prefix for geofence log lines.
    ///
    /// Must stay identical to the Android constant: the Doctor bug report lifts
    /// geofence activity into its own section by filtering on this literal, so a
    /// divergence here would silently make that section Android-only.
    private static let logTag = "[geofence]"

    /// Mirror of `GEOFENCE_EXIT_HYSTERESIS_FRACTION` in the Rust core's
    /// `geofence_evaluator.rs`. Used for logging only — the Rust evaluator
    /// remains the single source of truth for the actual decision.
    private static let exitHysteresisFraction = 0.1

    /// Mirror of `GEOFENCE_MIN_EXIT_HYSTERESIS_METERS` in the Rust core.
    private static let minExitHysteresisMeters = 20.0

    /// Mirror of `GEOFENCE_ABS_MIN_EXIT_HYSTERESIS_METERS` in the Rust core.
    private static let absMinExitHysteresisMeters = 3.0

    /// Smallest radius CoreLocation can decide for itself, in metres.
    ///
    /// Below this the fence is smaller than the error of the fixes it is
    /// compared against, so region monitoring never becomes confident enough to
    /// report a crossing: entering a region the device is already inside reports
    /// state immediately — which looks like it works — and then nothing, ever
    /// (#355).
    ///
    /// Small fences are *not* rejected. They are decided in-app instead, against
    /// the true radius and with a hysteresis band scaled to the measured fix
    /// accuracy rather than a flat 20 m (#356). See `isEvaluatorOwned`.
    private static let osMinResolvableRadiusMeters = 100.0

    /// High-accuracy mode: track which geofences the device is currently inside.
    private var insideGeofenceIds = Set<String>()

    /// UserDefaults key for the persisted high-accuracy inside-set (#292).
    private static let knownInsideDefaultsKey = "com.tracelet.geofence.knownInsideIds"

    /// Geofences the device is inside per the last *emitted* high-accuracy
    /// transition, persisted across process death.
    ///
    /// The Rust evaluator's own inside-set is in-memory only and is wiped on
    /// every resume/boot by `clearHighAccuracyState()` (via `startGeofences()` on
    /// each `ready()`/takeover). A stationary device inside a fence therefore
    /// re-satisfies `entered && !was_inside` after each wipe and the evaluator
    /// re-emits ENTER — a false attendance punch-in on the backend (#292).
    ///
    /// This set survives those resets, so `evaluateHighAccuracyProximity`
    /// suppresses an ENTER for a fence it already reported and an EXIT for a
    /// fence it never reported entering. Cleared only by
    /// `resetHighAccuracyInsideState()` (fresh start) and `destroy()`.
    private lazy var knownInsideIds: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: GeofenceManager.knownInsideDefaultsKey) ?? [])

    /// Flushes `knownInsideIds` to disk.
    private func persistKnownInside() {
        UserDefaults.standard.set(Array(knownInsideIds), forKey: GeofenceManager.knownInsideDefaultsKey)
    }

    /// True once the freshly-constructed evaluator has been reconciled with the
    /// persisted `knownInsideIds` for this manager lifetime.
    private var evaluatorSeeded = false

    /// Reconcile the newly-constructed (empty) evaluator with the persisted
    /// `knownInsideIds` by replaying one synthetic in-fence fix per known-inside
    /// geofence, so the evaluator — not a side table — stays the single source of
    /// truth across process death (#292):
    ///
    ///  - a device still inside a fence produces no ENTER (already known), and
    ///  - a device that left a fence *while the process was dead* produces a real
    ///    EXIT on the first outside fix, instead of the inside-state getting
    ///    stuck and suppressing the next genuine ENTER.
    ///
    /// The synthetic ENTERs are discarded — `knownInsideIds` already reflects
    /// them. Runs once per manager lifetime, before the first real evaluation.
    private func seedEvaluatorFromKnownInside(_ byId: [String: [String: Any]]) {
        if evaluatorSeeded { return }
        evaluatorSeeded = true
        if knownInsideIds.isEmpty { return }
        for id in knownInsideIds {
            guard let gf = byId[id], let point = insidePoint(gf) else { continue }
            // Discard the synthetic ENTER; we only want the adopted inside-state.
            _ = geofenceEvaluator.evaluateProximity(
                latitude: point.0,
                longitude: point.1,
                accuracy: 0.0,
                geofences: [mapToCoreGeofence(gf)]
            )
        }
    }

    /// A point guaranteed inside `gf` used to seed the evaluator: the centre for
    /// a circle, the vertex centroid for a polygon (inside for convex polygons;
    /// a concave polygon whose centroid falls outside simply is not seeded and
    /// falls back to the persisted-set dedup).
    private func insidePoint(_ gf: [String: Any]) -> (Double, Double)? {
        if let vertices = gf["vertices"] as? [[Any]], vertices.count >= 3 {
            var sumLat = 0.0
            var sumLng = 0.0
            var n = 0
            for v in vertices where v.count >= 2 {
                if let vLat = (v[0] as? NSNumber)?.doubleValue,
                   let vLng = (v[1] as? NSNumber)?.doubleValue {
                    sumLat += vLat
                    sumLng += vLng
                    n += 1
                }
            }
            if n == 0 { return nil }
            return (sumLat / Double(n), sumLng / Double(n))
        }
        guard let lat = (gf["latitude"] as? NSNumber)?.doubleValue,
              let lng = (gf["longitude"] as? NSNumber)?.doubleValue else { return nil }
        return (lat, lng)
    }

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

            // Warned at add time, not registration time: this is the moment the
            // caller chose the radius, and it fires once per fence rather than
            // on every proximity re-registration (#355).
            let isPolygonShape = (data["vertices"] as? [[Double]])?.count ?? 0 >= 3
            if !isPolygonShape { noteSmallRadiusHandling(identifier, radius) }
            
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
                try rustDatabase?.insertGeofence(
                    identifier: identifier, lat: lat, lng: lng, radius: radius,
                    vertices: vertices, extras: extrasStr,
                    notifyOnEntry: data["notifyOnEntry"] as? Bool ?? true,
                    notifyOnExit: data["notifyOnExit"] as? Bool ?? true,
                    notifyOnDwell: data["notifyOnDwell"] as? Bool ?? false,
                    loiteringDelay: Int32(data["loiteringDelay"] as? Int ?? 0))
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
                    try rustDatabase?.insertGeofence(
                        identifier: identifier, lat: lat, lng: lng, radius: radius,
                        vertices: vertices, extras: extrasStr,
                        notifyOnEntry: g["notifyOnEntry"] as? Bool ?? true,
                        notifyOnExit: g["notifyOnExit"] as? Bool ?? true,
                        notifyOnDwell: g["notifyOnDwell"] as? Bool ?? false,
                        loiteringDelay: Int32(g["loiteringDelay"] as? Int ?? 0))
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

        // Forget any inside-state for this fence so a later re-add — or an id
        // reused for a different location — starts clean instead of having its
        // ENTER suppressed by stale persisted state (#292).
        if knownInsideIds.remove(identifier) != nil { persistKnownInside() }
        geofenceEvaluator.removeGeofence(identifier: identifier)

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
        // No fences means the device is inside nothing — forget all inside-state
        // so a subsequent add/enter is reported cleanly (#292).
        if !knownInsideIds.isEmpty {
            knownInsideIds.removeAll()
            persistKnownInside()
        }
        geofenceEvaluator.clear()
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
            "vertices": verticesArray,
            // #355: these four were absent here, so every fence rebuilt from the
            // database — on each proximity change, relaunch and reboot — was
            // re-registered with notifyOnDwell=false and loiteringDelay=0,
            // silently killing DWELL for the rest of the install.
            "notifyOnEntry": gf.notifyOnEntry,
            "notifyOnExit": gf.notifyOnExit,
            "notifyOnDwell": gf.notifyOnDwell,
            "loiteringDelay": gf.loiteringDelay,
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

    /// One-decimal formatter that avoids locale-dependent decimal separators.
    private func fmt1(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Exit-hysteresis band the Rust evaluator applies for `radius` at a fix
    /// accuracy of `accuracy`. Mirrors `exit_hysteresis_meters` in the core so
    /// the decision trace reports the threshold actually used. Logging only.
    private func exitHysteresisMeters(_ radius: Double, _ accuracy: Double) -> Double {
        let jitter = accuracy > 0
            ? Swift.min(Swift.max(accuracy, GeofenceManager.absMinExitHysteresisMeters),
                        GeofenceManager.minExitHysteresisMeters)
            : GeofenceManager.minExitHysteresisMeters
        return Swift.max(radius * GeofenceManager.exitHysteresisFraction, jitter)
    }

    /// Whether the in-app evaluator — not CoreLocation — decides this fence's
    /// transitions.
    ///
    /// Three cases, and each is one region monitoring cannot serve:
    ///
    ///  - **Polygons.** CoreLocation only monitors circular regions, so a
    ///    polygon is never registered with it and has always been ours.
    ///  - **Sub-`osMinResolvableRadiusMeters` circles.** Monitored only as a
    ///    coarse wake-up (see `wakeupRadiusMeters`); at that inflated radius the
    ///    OS's transitions describe the wrong boundary, so they are discarded
    ///    and the true radius is applied in-app (#356).
    ///  - **`geofenceModeHighAccuracy`.** The caller asked for in-app
    ///    evaluation of everything.
    ///
    /// Ownership is per fence, not global: a 20 m fence and a 500 m fence in the
    /// same config are decided by whichever component can actually resolve them.
    private func isEvaluatorOwned(_ geofence: [String: Any]) -> Bool {
        if let vertices = geofence["vertices"] as? [Any], vertices.count >= 3 { return true }
        if configManager.getGeofenceModeHighAccuracy() { return true }
        guard let radius = geofence["radius"] as? Double else { return false }
        return radius > 0 && radius < GeofenceManager.osMinResolvableRadiusMeters
    }

    /// The radius a circular fence is monitored with at the OS level.
    ///
    /// A sub-resolvable fence is inflated to `osMinResolvableRadiusMeters`
    /// because at its true radius CoreLocation will not reliably fire at all —
    /// and firing is the entire point of the OS registration for these fences.
    /// It exists to wake the process when the device comes near, not to judge
    /// the boundary; the evaluator does that, at the true radius.
    private func wakeupRadiusMeters(_ radius: Double) -> Double {
        radius > 0 && radius < GeofenceManager.osMinResolvableRadiusMeters
            ? GeofenceManager.osMinResolvableRadiusMeters
            : radius
    }

    /// Whether any stored fence needs the uninterrupted fix stream that in-app
    /// evaluation runs on.
    public func hasEvaluatorOwnedGeofences() -> Bool {
        configManager.getGeofenceModeHighAccuracy() || getGeofences().contains { isEvaluatorOwned($0) }
    }

    /// Records that a sub-resolvable fence has been handed to the in-app
    /// evaluator (#356).
    ///
    /// On the always-on lifecycle channel: which component owns a fence is the
    /// first thing a "geofences stopped firing" report needs to establish, and
    /// such a report arrives from a release build whose `logLevel` may be `off`.
    private func noteSmallRadiusHandling(_ identifier: String, _ radius: Double) {
        guard radius > 0, radius < GeofenceManager.osMinResolvableRadiusMeters else { return }
        let floor = fmt1(GeofenceManager.osMinResolvableRadiusMeters)
        TraceletLog.lifecycle(
            "\(GeofenceManager.logTag) \(identifier) radius=\(fmt1(radius))m is below the "
            + "\(floor)m CoreLocation can resolve — transitions will be evaluated in-app at "
            + "the true radius, and the monitored region is registered at \(floor)m as a "
            + "wake-up only. Requires location updates to be running (#356)")
    }

    /// Builds the `[geofence]`-tagged decision trace logged alongside every
    /// transition. Mirrors the Android implementation field-for-field so a bug
    /// report reads identically on both platforms and the Doctor section's
    /// `[geofence]` filter works cross-platform.
    ///
    /// Carries every input to the accuracy-aware EXIT test (#274/#276) so a
    /// drift-induced EXIT can be told apart from a genuine one without a
    /// reproduction. Deliberately excludes absolute coordinates.
    private func transitionTrace(
        action: String,
        identifier: String,
        gfMap: [String: Any]?,
        latitude: Double,
        longitude: Double,
        accuracyRaw: Double,
        accuracyEffective: Double
    ) -> String {
        var parts = ["\(GeofenceManager.logTag) \(action) \(identifier)"]

        let vertices = gfMap?["vertices"] as? [[Double]]
        let isPolygon = (vertices?.count ?? 0) >= 3

        if isPolygon {
            // Polygon membership is a point-in-polygon test; radius, hysteresis
            // and accuracy gating do not participate.
            parts.append("shape=polygon vertices=\(vertices?.count ?? 0)")
        } else if let gfLat = gfMap?["latitude"] as? Double,
                  let gfLng = gfMap?["longitude"] as? Double,
                  let radius = gfMap?["radius"] as? Double, radius > 0 {
            // Same Rust haversine the evaluator uses, so the logged distance
            // cannot disagree with the decision.
            let distance = haversine(lat1: latitude, lon1: longitude, lat2: gfLat, lon2: gfLng)
            let buffer = exitHysteresisMeters(radius, accuracyEffective)
            let threshold = radius + buffer
            parts.append("dist=\(fmt1(distance))")
            parts.append("radius=\(fmt1(radius))")
            parts.append("buffer=\(fmt1(buffer))")
            parts.append("thr=\(fmt1(threshold))")
            parts.append("margin=\(fmt1(distance - accuracyEffective - threshold))")
        }

        parts.append("accRaw=\(fmt1(accuracyRaw))")
        parts.append("accEff=\(fmt1(accuracyEffective))")
        parts.append("exitAccuracyMax=\(configManager.getGeofenceExitAccuracyMax())")

        if accuracyRaw <= 0 {
            // CoreLocation reports a negative horizontalAccuracy when the fix
            // has no valid accuracy, and the evaluator maps any non-positive
            // value to "gating disabled". Unknown uncertainty therefore behaves
            // as zero uncertainty — flag it, because it makes a false EXIT far
            // more likely and is invisible otherwise.
            parts.append("accuracyInvalid=true gatingDisabled=true")
        } else if accuracyEffective < accuracyRaw {
            // The #276 clamp bound on this fix, weakening drift immunity
            // relative to the -1 default.
            parts.append("clampApplied=true")
        }
        return parts.joined(separator: " ")
    }

    public func evaluateHighAccuracyProximity(latitude: Double, longitude: Double, accuracy: Double = 0.0) {
        // Only the fences this path owns (see `isEvaluatorOwned`). Feeding the
        // evaluator a fence CoreLocation is also reporting would double-fire it,
        // so ownership is exclusive on both sides of the split.
        let allGeofences = getCachedGeofences().filter { isEvaluatorOwned($0) }
        if allGeofences.isEmpty { return }

        let geofenceMapById = Dictionary(uniqueKeysWithValues: allGeofences.compactMap {
            if let id = $0["identifier"] as? String { return (id, $0) } else { return nil }
        })
        // Reconcile a cold-started evaluator with the persisted inside-set before
        // the first real fix, so a leave-while-dead is caught (#292).
        seedEvaluatorFromKnownInside(geofenceMapById)

        let effectiveAccuracy = effectiveExitAccuracy(accuracy)
        let coreGeofences = allGeofences.map { mapToCoreGeofence($0) }
        let transitions = geofenceEvaluator.evaluateProximity(
            latitude: latitude,
            longitude: longitude,
            accuracy: effectiveAccuracy,
            geofences: coreGeofences
        )
        if transitions.isEmpty {
            if effectiveAccuracy < accuracy {
                // No transition, but the clamp bound on this fix. Surfaces a
                // mis-set geofenceExitAccuracyMax without waiting for a crossing.
                TraceletLog.debug(
                    "\(GeofenceManager.logTag) no transition — accRaw=\(fmt1(accuracy)) " +
                    "accEff=\(fmt1(effectiveAccuracy)) clampApplied=true " +
                    "exitAccuracyMax=\(configManager.getGeofenceExitAccuracyMax())"
                )
            }
            return
        }

        var on: [[String: Any]] = []
        var off: [[String: Any]] = []

        for t in transitions {
            // Persisted-state dedup (#292). The evaluator's in-memory inside-set
            // is wiped on every resume/boot, so a stationary device inside a
            // fence re-produces an ENTER the app already emitted. knownInsideIds
            // survives that reset: suppress an ENTER for a fence we already
            // reported inside, and an EXIT for a fence we never reported
            // entering. Genuine crossings still pass through and flip the set.
            let alreadyInside = knownInsideIds.contains(t.identifier)
            if t.action == "ENTER" && alreadyInside {
                TraceletLog.debug(
                    "\(GeofenceManager.logTag) suppressed duplicate ENTER \(t.identifier) " +
                    "— already inside per persisted state (resume/boot re-entry)"
                )
                continue
            }
            if t.action == "EXIT" && !alreadyInside {
                TraceletLog.debug(
                    "\(GeofenceManager.logTag) suppressed EXIT \(t.identifier) " +
                    "— not inside per persisted state"
                )
                continue
            }
            if t.action == "ENTER" {
                knownInsideIds.insert(t.identifier)
            } else if t.action == "EXIT" {
                knownInsideIds.remove(t.identifier)
            }
            persistKnownInside()

            let gfMap = geofenceMapById[t.identifier]

            // On the always-on lifecycle channel (#318), not INFO or DEBUG: a
            // false EXIT is reported days later by an end user, from a release
            // build whose logLevel may be `error` or `off` — which dropped even
            // the INFO line, so the bug report that was supposed to explain the
            // crossing contained no trace of it. Volume is a handful of lines
            // per day, and the line carries no coordinates (#352).
            TraceletLog.lifecycle(
                transitionTrace(
                    action: t.action,
                    identifier: t.identifier,
                    gfMap: gfMap,
                    latitude: latitude,
                    longitude: longitude,
                    accuracyRaw: accuracy,
                    accuracyEffective: effectiveAccuracy
                )
            )

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

        // Note for triage: this emits geofencesChange on/off for *monitoring*
        // scope, not ENTER/EXIT. An `off` here means the region left the
        // geofenceProximityRadius window and was unregistered — it is not a
        // boundary crossing and is deliberately not accuracy-gated. Apps that
        // treat geofencesChange.off as an exit will see spurious "exits" from a
        // single far-drifting fix, so make the distinction explicit.
        TraceletLog.debug(
            "\(GeofenceManager.logTag) proximity scope update (not ENTER/EXIT): " +
            "\(activeGeofenceIds.count) active, +\(toAdd.count)/-\(toRemove.count), " +
            "proximityRadius=\(proximityRadius)m"
        )
    }

    /// Clear the *in-memory* high-accuracy evaluator state.
    ///
    /// Deliberately does NOT touch the persisted `knownInsideIds`: this is called
    /// on every resume/boot, and the persisted set is exactly what lets
    /// `evaluateHighAccuracyProximity` suppress the re-ENTER a freshly-reset
    /// evaluator would otherwise produce for a stationary device (#292). Use
    /// `resetHighAccuracyInsideState()` for a full reset that forgets crossings.
    public func clearHighAccuracyState() {
        insideGeofenceIds.removeAll()
        geofenceEvaluator.clear()
    }

    /// Full reset of high-accuracy inside-state — the in-memory evaluator AND the
    /// persisted `knownInsideIds`.
    ///
    /// Called only on a *fresh* `startGeofences()` (not a resume/boot) and on
    /// `destroy()`, so a genuine fresh start re-emits the initial-entry ENTER
    /// once while a resume/boot preserves the persisted set (#292).
    public func resetHighAccuracyInsideState() {
        knownInsideIds.removeAll()
        persistKnownInside()
        clearHighAccuracyState()
    }

    public func destroy() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        insideGeofenceIds.removeAll()
        geofenceEvaluator.clear()
        knownInsideIds.removeAll()
        persistKnownInside()
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
        // Inflated for sub-resolvable fences: at their true radius CoreLocation
        // fires nothing, and this registration exists to wake us near the fence,
        // not to judge it (#356).
        let region = CLCircularRegion(
            center: center, radius: wakeupRadiusMeters(radius), identifier: identifier)

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
        // Dropped for fences the in-app evaluator owns (see `isEvaluatorOwned`):
        // under `geofenceModeHighAccuracy` that is every fence, and otherwise the
        // small ones, whose monitored region is inflated to a wake-up radius and
        // whose OS transitions therefore describe the wrong boundary.
        // `evaluateHighAccuracyProximity` reports those instead (#356).
        if let stored = getGeofence(region.identifier), isEvaluatorOwned(stored) {
            TraceletLog.debug(
                "\(GeofenceManager.logTag) ignoring OS transition for \(region.identifier) "
                + "— evaluated in-app at its true radius (#356)")
            // The discarded transition still did its job: it says we are near a
            // fence only the evaluator can decide. Claim the wake-up before
            // returning, or the inflated region is pure cost (#356).
            TraceletLog.lifecycle(
                "\(GeofenceManager.logTag) wake-up from the OS near an in-app fence — "
                + "resuming the location stream so its true radius can be evaluated (#356)")
            onEvaluatorWakeup?()
            return
        }

        let geofenceData = getGeofence(region.identifier)
        let location = locationManager.location

        // The OS region-monitoring path has no accuracy gating — CoreLocation
        // owns the debouncing. Log it distinctly so a bug report makes clear
        // which path produced the transition.
        // On the always-on lifecycle channel (#318), not INFO — see the
        // high-accuracy path above: a release build may run logLevel `off` and
        // a crossing is exactly what the later bug report needs (#352).
        TraceletLog.lifecycle(
            "\(GeofenceManager.logTag) \(action) \(region.identifier) source=os " +
            "radius=\(fmt1(region.radius)) (no accuracy gating on this path)"
        )

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
        return CoreGeofence(
            identifier: identifier, latitude: latitude, longitude: longitude,
            radius: radius, vertices: vertices, extras: extrasStr,
            // Same defaulting as the registration and persistence paths (#355).
            notifyOnEntry: gf["notifyOnEntry"] as? Bool ?? true,
            notifyOnExit: gf["notifyOnExit"] as? Bool ?? true,
            notifyOnDwell: gf["notifyOnDwell"] as? Bool ?? false,
            loiteringDelay: Int32(gf["loiteringDelay"] as? Int ?? 0))
    }
}
