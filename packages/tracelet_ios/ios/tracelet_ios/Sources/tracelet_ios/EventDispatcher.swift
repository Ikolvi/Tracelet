import Flutter
import Foundation
#if canImport(TraceletSDK)
import TraceletSDK
#endif

/// Flutter-specific event dispatcher using Pigeon FlutterApi.
///
/// Converts SDK dictionary data to Pigeon typed objects and sends via
/// `TraceletEventApi`. All event dispatch is marshalled to the main thread.
///
/// When no Flutter engine is attached, the dispatcher falls back to
/// `headlessFallback` (if set) so events can be routed to a background
/// Dart isolate via HeadlessRunner.
public final class PluginEventDispatcher: NSObject, TraceletEventSending {
    private var eventApi: TraceletEventApi?

    /// Optional headless fallback. When no Flutter engine is attached,
    /// the dispatcher calls this closure so the event can be forwarded to
    /// HeadlessRunner.
    var headlessFallback: ((_ eventName: String, _ data: [String: Any]) -> Void)?

    public func register(messenger: FlutterBinaryMessenger) {
        eventApi = TraceletEventApi(binaryMessenger: messenger)
    }

    public func unregister() {
        eventApi = nil
    }

    // MARK: - TraceletEventSending

    public func sendLocation(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("location", data) }
        let location = mapToTlLocation(data)
        DispatchQueue.main.async { api.onLocation(location: location) { _ in } }
    }

    public func sendMotionChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("motionchange", data) }
        let location = mapToTlLocation(data)
        DispatchQueue.main.async { api.onMotionChange(location: location) { _ in } }
    }

    public func sendSpeedMotionEvent(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("speedmotion", data) }
        let event = TlSpeedMotionEvent(
            state: TlSpeedMotionState(rawValue: data["state"] as? Int ?? 0) ?? .moving,
            previousState: TlSpeedMotionState(rawValue: data["previousState"] as? Int ?? 0) ?? .moving,
            trackingMode: TlTrackingMode(rawValue: data["trackingMode"] as? Int ?? 0) ?? .location
        )
        DispatchQueue.main.async { api.onMotionModeChange(event: event) { _ in } }
    }

    public func sendActivityChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("activitychange", data) }
        let event = TlActivityChangeEvent(
            activity: data["activity"] as? String ?? "unknown",
            confidence: Int64(data["confidence"] as? Int ?? -1)
        )
        DispatchQueue.main.async { api.onActivityChange(event: event) { _ in } }
    }

    public func sendProviderChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("providerchange", data) }
        let event = TlProviderChangeEvent(
            enabled: data["enabled"] as? Bool ?? false,
            gps: data["gps"] as? Bool ?? false,
            network: data["network"] as? Bool ?? false,
            status: Int64(data["status"] as? Int ?? 0),
            accuracyAuthorization: (data["accuracyAuthorization"] as? Int).map { Int64($0) }
        )
        DispatchQueue.main.async { api.onProviderChange(event: event) { _ in } }
    }

    public func sendGeofence(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("geofence", data) }
        let event = makeGeofenceEvent(data)
        DispatchQueue.main.async { api.onGeofence(event: event) { _ in } }
    }

    /// Maps the SDK's geofence payload to the Pigeon `TlGeofenceEvent`.
    ///
    /// The SDK emits a structured payload: identifier/action/extras nested under
    /// `"geofence"`, with the location coords at the top-level `"coords"`. The
    /// legacy flat shape (fields at the top level, location under `"location"`)
    /// is also accepted as a fallback.
    ///
    /// Exposed (internal) for testing — guards the regression where a nested
    /// `action` (e.g. `EXIT`) was read from the wrong key and silently defaulted
    /// to `ENTER`, so every transition reached Dart as `ENTER`.
    func makeGeofenceEvent(_ data: [String: Any]) -> TlGeofenceEvent {
        let gf = data["geofence"] as? [String: Any] ?? data
        let actionStr = (gf["action"] as? String ?? "ENTER").uppercased()
        let action: TlGeofenceAction
        switch actionStr {
        case "EXIT": action = .exit
        case "DWELL": action = .dwell
        default: action = .enter
        }
        // mapToTlLocation reads ["coords"]: the structured payload already has it at
        // the top level; the legacy shape wrapped it under "location".
        let locSource = data["location"] as? [String: Any] ?? data
        return TlGeofenceEvent(
            identifier: gf["identifier"] as? String ?? "",
            action: action,
            location: mapToTlLocation(locSource),
            extras: gf["extras"] as? [String?: Any?]
        )
    }

    public func sendGeofencesChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("geofenceschange", data) }
        let onList = (data["on"] as? [[String: Any]])?.map { mapToTlGeofence($0) }
        let offList = (data["off"] as? [[String: Any]])?.map { mapToTlGeofence($0) }
        let event = TlGeofencesChangeEvent(on: onList, off: offList)
        DispatchQueue.main.async { api.onGeofencesChange(event: event) { _ in } }
    }

    public func sendHeartbeat(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("heartbeat", data) }
        let locMap = data["location"] as? [String: Any] ?? [:]
        let event = TlHeartbeatEvent(location: mapToTlLocation(locMap))
        DispatchQueue.main.async { api.onHeartbeat(event: event) { _ in } }
    }

    public func sendHttp(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("http", data) }
        let event = TlHttpEvent(
            isSuccess: data["success"] as? Bool ?? false,
            status: Int64(data["status"] as? Int ?? 0),
            responseText: data["responseText"] as? String ?? ""
        )
        DispatchQueue.main.async { api.onHttp(event: event) { _ in } }
    }

    public func sendSchedule(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("schedule", data) }
        let state = mapToTlState(data)
        DispatchQueue.main.async { api.onSchedule(state: state) { _ in } }
    }

    public func sendPowerSaveChange(_ isPowerSave: Bool) {
        guard let api = eventApi else { return fallback("powersavechange", ["value": isPowerSave]) }
        DispatchQueue.main.async { api.onPowerSaveChange(isPowerSaveMode: isPowerSave) { _ in } }
    }

    public func sendConnectivityChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("connectivitychange", data) }
        let event = TlConnectivityChangeEvent(connected: data["connected"] as? Bool ?? false)
        DispatchQueue.main.async { api.onConnectivityChange(event: event) { _ in } }
    }

    public func sendEnabledChange(_ enabled: Bool) {
        guard let api = eventApi else { return fallback("enabledchange", ["value": enabled]) }
        DispatchQueue.main.async { api.onEnabledChange(enabled: enabled) { _ in } }
    }

    public func sendNotificationAction(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("notificationaction", data) }
        let action = data["action"] as? String ?? ""
        DispatchQueue.main.async { api.onNotificationAction(action: action) { _ in } }
    }

    public func sendAuthorization(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("authorization", data) }
        let event = TlAuthorizationEvent(
            success: data["success"] as? Bool ?? false,
            status: Int64(data["status"] as? Int ?? 0),
            response: data["response"] as? String ?? ""
        )
        DispatchQueue.main.async { api.onAuthorization(event: event) { _ in } }
    }

    public func sendWatchPosition(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("watchposition", data) }
        let location = mapToTlLocation(data)
        DispatchQueue.main.async { api.onWatchPosition(location: location) { _ in } }
    }

    public func sendRemoteConfigEvent(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("remoteconfig", data) }
        // Widen [String: Any] to the Pigeon [String?: Any?] map type. Nested
        // dictionaries serialize through the standard codec unchanged.
        var config: [String?: Any?] = [:]
        for (key, value) in data { config[key] = value }
        DispatchQueue.main.async { api.onRemoteConfig(config: config) { _ in } }
    }

    public func sendTrip(_ data: [String: Any]) {
        fallback("trip", data)
    }

    public func sendBudgetAdjustment(_ data: [String: Any]) {
        fallback("budgetadjustment", data)
    }

    public func sendDrivingEvent(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("drivingevent", data) }
        let event = TlDrivingEvent(
            kind: data["kind"] as? String ?? "",
            severity: num(data["severity"]),
            speed: num(data["speed"]),
            value: num(data["value"]),
            latitude: num(data["latitude"]),
            longitude: num(data["longitude"]),
            timestampMs: lng(data["timestampMs"])
        )
        DispatchQueue.main.async { api.onDrivingEvent(event: event) { _ in } }
    }

    public func sendImpact(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("impact", data) }
        let event = TlImpactEvent(
            kind: data["kind"] as? String ?? "",
            id: lng(data["id"]),
            confidence: num(data["confidence"]),
            peakG: num(data["peakG"]),
            speedBefore: num(data["speedBefore"]),
            latitude: num(data["latitude"]),
            longitude: num(data["longitude"]),
            timestampMs: lng(data["timestampMs"]),
            confirmDeadlineMs: lng(data["confirmDeadlineMs"])
        )
        DispatchQueue.main.async { api.onImpact(event: event) { _ in } }
    }

    public func sendModeChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("modechange", data) }
        let event = TlModeChangeEvent(
            mode: data["mode"] as? String ?? "unknown",
            confidence: num(data["confidence"]),
            // #301: forward the auto-tuned thresholds. Absent unless
            // autoTuneFromTransportMode is on and the mode carries a tuning.
            appliedTuning: tuningOf(data["appliedTuning"])
        )
        DispatchQueue.main.async { api.onModeChange(event: event) { _ in } }
    }

    /// Maps the SDK's `appliedTuning` payload onto the Pigeon record (#301).
    private func tuningOf(_ v: Any?) -> TlLocationTuning? {
        guard let map = v as? [String: Any] else { return nil }
        return TlLocationTuning(
            distanceFilter: num(map["distanceFilter"]),
            trackingAccuracyThreshold: lng(map["trackingAccuracyThreshold"]),
            odometerAccuracyThreshold: lng(map["odometerAccuracyThreshold"]),
            maxImpliedSpeed: lng(map["maxImpliedSpeed"])
        )
    }

    public func sendCrashModelStatus(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("crashmodelstatus", data) }
        let event = TlCrashModelStatusEvent(
            status: data["status"] as? String ?? "unknown",
            detail: data["detail"] as? String
        )
        DispatchQueue.main.async { api.onCrashModelStatus(event: event) { _ in } }
    }

    private func num(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        return 0.0
    }

    private func lng(_ v: Any?) -> Int64 {
        if let i = v as? Int64 { return i }
        if let n = v as? NSNumber { return n.int64Value }
        return 0
    }

    public func hasListener(eventName: String) -> Bool {
        return eventApi != nil
    }

    // MARK: - Map → Pigeon type converters

    private func mapToTlLocation(_ data: [String: Any]) -> TlLocation {
        let coordsMap = data["coords"] as? [String: Any] ?? [:]
        let batteryMap = data["battery"] as? [String: Any] ?? [:]
        let activityMap = data["activity"] as? [String: Any]

        let incomingExtras = data["extras"] as? [String: Any] ?? [:]
        var synthesizedExtras = incomingExtras
        synthesizedExtras["is_mock"] = data["is_mock"] as? Bool ?? false
        synthesizedExtras["locationSource"] = data["locationSource"] as? String ?? "unknown"
        synthesizedExtras["reducedAccuracy"] = data["reducedAccuracy"] as? Bool ?? false
        if let mockHeuristics = data["mockHeuristics"] as? [String: Any] {
            synthesizedExtras["mockHeuristics"] = mockHeuristics
        }
        if let auditHash = data["audit_hash"] as? String {
            synthesizedExtras["audit_hash"] = auditHash
        }
        if let auditPreviousHash = data["audit_previous_hash"] as? String {
            synthesizedExtras["audit_previous_hash"] = auditPreviousHash
        }
        if let auditChainIndex = data["audit_chain_index"] as? Int {
            synthesizedExtras["audit_chain_index"] = auditChainIndex
        }

        let coords = TlCoords(
            latitude: (coordsMap["latitude"] as? Double) ?? 0.0,
            longitude: (coordsMap["longitude"] as? Double) ?? 0.0,
            accuracy: (coordsMap["accuracy"] as? Double) ?? -1.0,
            speed: (coordsMap["speed"] as? Double) ?? -1.0,
            heading: (coordsMap["heading"] as? Double) ?? -1.0,
            altitude: (coordsMap["altitude"] as? Double) ?? 0.0,
            altitudeAccuracy: (coordsMap["altitudeAccuracy"] as? Double) ?? -1.0,
            speedAccuracy: (coordsMap["speed_accuracy"] as? Double) ?? -1.0,
            headingAccuracy: (coordsMap["heading_accuracy"] as? Double) ?? -1.0,
            ellipsoidalAltitude: coordsMap["ellipsoidal_altitude"] as? Double,
            floor: coordsMap["floor"] as? Int64
        )

        let battery = TlBattery(
            level: (batteryMap["level"] as? Double) ?? -1.0,
            isCharging: (batteryMap["is_charging"] as? Bool) ?? false
        )

        var tlActivity: TlActivity?
        if let act = activityMap {
            tlActivity = TlActivity(
                type: (act["type"] as? String) ?? "unknown",
                confidence: (act["confidence"] as? Int64) ?? -1
            )
        }

        return TlLocation(
            coords: TlCoords(
                latitude: (coordsMap["latitude"] as? NSNumber)?.doubleValue ?? 0,
                longitude: (coordsMap["longitude"] as? NSNumber)?.doubleValue ?? 0,
                accuracy: (coordsMap["accuracy"] as? NSNumber)?.doubleValue ?? -1,
                speed: (coordsMap["speed"] as? NSNumber)?.doubleValue ?? -1,
                heading: (coordsMap["heading"] as? NSNumber)?.doubleValue ?? -1,
                altitude: (coordsMap["altitude"] as? NSNumber)?.doubleValue ?? 0,
                altitudeAccuracy: (coordsMap["altitudeAccuracy"] as? NSNumber)?.doubleValue ?? -1,
                speedAccuracy: (coordsMap["speedAccuracy"] as? NSNumber)?.doubleValue ?? -1,
                headingAccuracy: (coordsMap["headingAccuracy"] as? NSNumber)?.doubleValue ?? -1
            ),
            battery: TlBattery(
                level: (batteryMap["level"] as? NSNumber)?.doubleValue ?? -1,
                isCharging: batteryMap["is_charging"] as? Bool ?? false
            ),
            timestamp: data["timestamp"] as? String ?? "",
            uuid: data["uuid"] as? String ?? "",
            isMoving: (data["is_moving"] ?? data["isMoving"]) as? Bool ?? false,
            odometer: (data["odometer"] as? NSNumber)?.doubleValue ?? 0,
            event: data["event"] as? String,
            activity: activityMap.map {
                TlActivity(
                    type: $0["type"] as? String ?? "unknown",
                    confidence: Int64($0["confidence"] as? Int ?? -1)
                )
            },
            extras: synthesizedExtras,
            address: (data["address"] as? [String: Any]).map { addr in
                TlAddress(
                    street: addr["street"] as? String,
                    city: addr["city"] as? String,
                    state: addr["state"] as? String,
                    postalCode: (addr["postalCode"] as? String) ?? (addr["postal_code"] as? String),
                    country: addr["country"] as? String
                )
            }
        )
    }

    private func mapToTlGeofence(_ data: [String: Any]) -> TlGeofence {
        let verticesRaw = data["vertices"] as? [[Any]]
        let vertices: [[Double?]?]? = verticesRaw?.map { v in
            v.map { ($0 as? NSNumber)?.doubleValue }
        }
        return TlGeofence(
            identifier: data["identifier"] as? String ?? "",
            latitude: (data["latitude"] as? NSNumber)?.doubleValue ?? 0,
            longitude: (data["longitude"] as? NSNumber)?.doubleValue ?? 0,
            radius: (data["radius"] as? NSNumber)?.doubleValue ?? 0,
            notifyOnEntry: data["notifyOnEntry"] as? Bool ?? true,
            notifyOnExit: data["notifyOnExit"] as? Bool ?? true,
            notifyOnDwell: data["notifyOnDwell"] as? Bool ?? false,
            loiteringDelay: Int64(data["loiteringDelay"] as? Int ?? 0),
            extras: data["extras"] as? [String?: Any?],
            vertices: vertices
        )
    }

    private func mapToTlState(_ data: [String: Any]) -> TlState {
        let modeInt = data["trackingMode"] as? Int ?? TraceletTrackingMode.continuous.rawValue
        return TlState(
            enabled: data["enabled"] as? Bool ?? false,
            isMoving: (data["isMoving"] ?? data["is_moving"]) as? Bool ?? false,
            trackingMode: TlTrackingMode(rawValue: modeInt) ?? .location,
            schedulerEnabled: data["schedulerEnabled"] as? Bool ?? false,
            odometer: (data["odometer"] as? NSNumber)?.doubleValue ?? 0,
            lastLocationTimestamp: data["lastLocationTimestamp"] as? String
        )
    }

    // MARK: - Private

    private func fallback(_ eventName: String, _ data: [String: Any]) {
        headlessFallback?(eventName, data)
    }
}
