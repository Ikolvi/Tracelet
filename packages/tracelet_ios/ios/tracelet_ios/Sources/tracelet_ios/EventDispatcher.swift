import Flutter
import Foundation
import TraceletSDK

/// Flutter-specific event dispatcher using Pigeon FlutterApi.
///
/// Converts SDK dictionary data to Pigeon typed objects and sends via
/// `TraceletEventApi`. All event dispatch is marshalled to the main thread.
///
/// When no Flutter engine is attached, the dispatcher falls back to
/// `headlessFallback` (if set) so events can be routed to a background
/// Dart isolate via HeadlessRunner.
final class EventDispatcher: NSObject, TraceletEventSending {
    private var eventApi: TraceletEventApi?

    /// Optional headless fallback. When no Flutter engine is attached,
    /// the dispatcher calls this closure so the event can be forwarded to
    /// HeadlessRunner.
    var headlessFallback: ((_ eventName: String, _ data: [String: Any]) -> Void)?

    func register(messenger: FlutterBinaryMessenger) {
        eventApi = TraceletEventApi(binaryMessenger: messenger)
    }

    func unregister() {
        eventApi = nil
    }

    // MARK: - TraceletEventSending

    func sendLocation(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("location", data) }
        let location = mapToTlLocation(data)
        DispatchQueue.main.async { api.onLocation(location: location) { _ in } }
    }

    func sendMotionChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("motionchange", data) }
        let location = mapToTlLocation(data)
        DispatchQueue.main.async { api.onMotionChange(location: location) { _ in } }
    }

    func sendSpeedMotionEvent(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("speedmotion", data) }
        let event = TlSpeedMotionEvent(
            state: data["state"] as? String ?? "",
            previousState: data["previousState"] as? String ?? "",
            trackingMode: data["trackingMode"] as? String ?? ""
        )
        DispatchQueue.main.async { api.onSpeedMotion(event: event) { _ in } }
    }

    func sendActivityChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("activitychange", data) }
        let event = TlActivityChangeEvent(
            activity: data["activity"] as? String ?? "unknown",
            confidence: Int64(data["confidence"] as? Int ?? -1)
        )
        DispatchQueue.main.async { api.onActivityChange(event: event) { _ in } }
    }

    func sendProviderChange(_ data: [String: Any]) {
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

    func sendGeofence(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("geofence", data) }
        let locMap = data["location"] as? [String: Any] ?? [:]
        let actionStr = (data["action"] as? String ?? "ENTER").uppercased()
        let action: TlGeofenceAction
        switch actionStr {
        case "EXIT": action = .exit
        case "DWELL": action = .dwell
        default: action = .enter
        }
        let event = TlGeofenceEvent(
            identifier: data["identifier"] as? String ?? "",
            action: action,
            location: mapToTlLocation(locMap),
            extras: data["extras"] as? [String?: Any?]
        )
        DispatchQueue.main.async { api.onGeofence(event: event) { _ in } }
    }

    func sendGeofencesChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("geofenceschange", data) }
        let onList = (data["on"] as? [[String: Any]])?.map { mapToTlGeofence($0) }
        let offList = (data["off"] as? [[String: Any]])?.map { mapToTlGeofence($0) }
        let event = TlGeofencesChangeEvent(on: onList, off: offList)
        DispatchQueue.main.async { api.onGeofencesChange(event: event) { _ in } }
    }

    func sendHeartbeat(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("heartbeat", data) }
        let locMap = data["location"] as? [String: Any] ?? [:]
        let event = TlHeartbeatEvent(location: mapToTlLocation(locMap))
        DispatchQueue.main.async { api.onHeartbeat(event: event) { _ in } }
    }

    func sendHttp(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("http", data) }
        let event = TlHttpEvent(
            isSuccess: data["success"] as? Bool ?? false,
            status: Int64(data["status"] as? Int ?? 0),
            responseText: data["responseText"] as? String ?? ""
        )
        DispatchQueue.main.async { api.onHttp(event: event) { _ in } }
    }

    func sendSchedule(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("schedule", data) }
        let state = mapToTlState(data)
        DispatchQueue.main.async { api.onSchedule(state: state) { _ in } }
    }

    func sendPowerSaveChange(_ isPowerSave: Bool) {
        guard let api = eventApi else { return fallback("powersavechange", ["value": isPowerSave]) }
        DispatchQueue.main.async { api.onPowerSaveChange(isPowerSaveMode: isPowerSave) { _ in } }
    }

    func sendConnectivityChange(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("connectivitychange", data) }
        let event = TlConnectivityChangeEvent(connected: data["connected"] as? Bool ?? false)
        DispatchQueue.main.async { api.onConnectivityChange(event: event) { _ in } }
    }

    func sendEnabledChange(_ enabled: Bool) {
        guard let api = eventApi else { return fallback("enabledchange", ["value": enabled]) }
        DispatchQueue.main.async { api.onEnabledChange(enabled: enabled) { _ in } }
    }

    func sendNotificationAction(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("notificationaction", data) }
        let action = data["action"] as? String ?? ""
        DispatchQueue.main.async { api.onNotificationAction(action: action) { _ in } }
    }

    func sendAuthorization(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("authorization", data) }
        let event = TlAuthorizationEvent(
            success: data["success"] as? Bool ?? false,
            status: Int64(data["status"] as? Int ?? 0),
            response: data["response"] as? String ?? ""
        )
        DispatchQueue.main.async { api.onAuthorization(event: event) { _ in } }
    }

    func sendWatchPosition(_ data: [String: Any]) {
        guard let api = eventApi else { return fallback("watchposition", data) }
        let location = mapToTlLocation(data)
        DispatchQueue.main.async { api.onWatchPosition(location: location) { _ in } }
    }

    func sendRemoteConfigEvent(_ data: [String: Any]) {
        fallback("remoteconfig", data)
    }

    func sendTrip(_ data: [String: Any]) {
        fallback("trip", data)
    }

    func sendBudgetAdjustment(_ data: [String: Any]) {
        fallback("budgetadjustment", data)
    }

    func hasListener(eventName: String) -> Bool {
        return eventApi != nil
    }

    // MARK: - Map → Pigeon type converters

    private func mapToTlLocation(_ data: [String: Any]) -> TlLocation {
        let coordsMap = data["coords"] as? [String: Any] ?? [:]
        let batteryMap = data["battery"] as? [String: Any] ?? [:]
        let activityMap = data["activity"] as? [String: Any]

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
            extras: data["extras"] as? [String?: Any?]
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
        let modeInt = data["trackingMode"] as? Int ?? TrackingMode.continuous.rawValue
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
