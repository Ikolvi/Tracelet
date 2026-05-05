import Foundation

/// Geographic coordinates and accuracy metrics.
public struct TraceletCoords {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let speed: Double
    public let heading: Double
    public let accuracy: Double
    public let speedAccuracy: Double
    public let headingAccuracy: Double
    public let altitudeAccuracy: Double

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        speed: Double = -1,
        heading: Double = -1,
        accuracy: Double = -1,
        speedAccuracy: Double = -1,
        headingAccuracy: Double = -1,
        altitudeAccuracy: Double = -1
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.heading = heading
        self.accuracy = accuracy
        self.speedAccuracy = speedAccuracy
        self.headingAccuracy = headingAccuracy
        self.altitudeAccuracy = altitudeAccuracy
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletCoords {
        TraceletCoords(
            latitude: (map["latitude"] as? NSNumber)?.doubleValue ?? 0,
            longitude: (map["longitude"] as? NSNumber)?.doubleValue ?? 0,
            altitude: (map["altitude"] as? NSNumber)?.doubleValue ?? 0,
            speed: (map["speed"] as? NSNumber)?.doubleValue ?? -1,
            heading: (map["heading"] as? NSNumber)?.doubleValue ?? -1,
            accuracy: (map["accuracy"] as? NSNumber)?.doubleValue ?? -1,
            speedAccuracy: (map["speedAccuracy"] as? NSNumber)?.doubleValue ?? -1,
            headingAccuracy: (map["headingAccuracy"] as? NSNumber)?.doubleValue ?? -1,
            altitudeAccuracy: (map["altitudeAccuracy"] as? NSNumber)?.doubleValue ?? -1
        )
    }

    public func toMap() -> [String: Any?] {
        [
            "latitude": latitude,
            "longitude": longitude,
            "altitude": altitude,
            "speed": speed,
            "heading": heading,
            "accuracy": accuracy,
            "speedAccuracy": speedAccuracy,
            "headingAccuracy": headingAccuracy,
            "altitudeAccuracy": altitudeAccuracy,
        ]
    }
}

/// Activity recognition data.
public struct TraceletActivityData {
    public let type: String
    public let confidence: Int

    public init(type: String = "unknown", confidence: Int = -1) {
        self.type = type
        self.confidence = confidence
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletActivityData {
        TraceletActivityData(
            type: map["type"] as? String ?? "unknown",
            confidence: (map["confidence"] as? NSNumber)?.intValue ?? -1
        )
    }

    public func toMap() -> [String: Any?] {
        ["type": type, "confidence": confidence]
    }
}

/// Battery state data.
public struct TraceletBattery {
    public let isCharging: Bool
    public let level: Double

    public init(isCharging: Bool = false, level: Double = -1) {
        self.isCharging = isCharging
        self.level = level
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletBattery {
        TraceletBattery(
            isCharging: map["is_charging"] as? Bool ?? false,
            level: (map["level"] as? NSNumber)?.doubleValue ?? -1
        )
    }

    public func toMap() -> [String: Any?] {
        ["is_charging": isCharging, "level": level]
    }
}

/// A recorded location from the Tracelet SDK.
public struct TraceletLocation {
    public let coords: TraceletCoords
    public let timestamp: String
    public let isMoving: Bool
    public let uuid: String
    public let odometer: Double
    public let locationSource: String
    public let reducedAccuracy: Bool
    public let isMock: Bool
    public let mockHeuristics: [String: Any?]?
    public let activity: TraceletActivityData
    public let battery: TraceletBattery
    public let event: String?
    public let extras: [String: Any?]

    public init(
        coords: TraceletCoords,
        timestamp: String,
        isMoving: Bool,
        uuid: String,
        odometer: Double = 0,
        locationSource: String = "unknown",
        reducedAccuracy: Bool = false,
        isMock: Bool = false,
        mockHeuristics: [String: Any?]? = nil,
        activity: TraceletActivityData = TraceletActivityData(),
        battery: TraceletBattery = TraceletBattery(),
        event: String? = nil,
        extras: [String: Any?] = [:]
    ) {
        self.coords = coords
        self.timestamp = timestamp
        self.isMoving = isMoving
        self.uuid = uuid
        self.odometer = odometer
        self.locationSource = locationSource
        self.reducedAccuracy = reducedAccuracy
        self.isMock = isMock
        self.mockHeuristics = mockHeuristics
        self.activity = activity
        self.battery = battery
        self.event = event
        self.extras = extras
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletLocation {
        let coordsMap = map["coords"] as? [String: Any?] ?? [:]
        let actMap = map["activity"] as? [String: Any?] ?? [:]
        let batMap = map["battery"] as? [String: Any?] ?? [:]

        return TraceletLocation(
            coords: TraceletCoords.fromMap(coordsMap),
            timestamp: map["timestamp"] as? String ?? "",
            isMoving: map["is_moving"] as? Bool ?? false,
            uuid: map["uuid"] as? String ?? "",
            odometer: (map["odometer"] as? NSNumber)?.doubleValue ?? 0,
            locationSource: map["locationSource"] as? String ?? "unknown",
            reducedAccuracy: map["reducedAccuracy"] as? Bool ?? false,
            isMock: map["mock"] as? Bool ?? false,
            mockHeuristics: map["mockHeuristics"] as? [String: Any?],
            activity: TraceletActivityData.fromMap(actMap),
            battery: TraceletBattery.fromMap(batMap),
            event: map["event"] as? String,
            extras: map["extras"] as? [String: Any?] ?? [:]
        )
    }

    public func toMap() -> [String: Any?] {
        var result: [String: Any?] = [
            "coords": coords.toMap(),
            "timestamp": timestamp,
            "is_moving": isMoving,
            "uuid": uuid,
            "odometer": odometer,
            "locationSource": locationSource,
            "reducedAccuracy": reducedAccuracy,
            "mock": isMock,
            "activity": activity.toMap(),
            "battery": battery.toMap(),
        ]
        if let mh = mockHeuristics { result["mockHeuristics"] = mh }
        if let ev = event { result["event"] = ev }
        if !extras.isEmpty { result["extras"] = extras }
        return result
    }
}

/// Geofence event data.
public struct TraceletGeofenceEvent {
    public let identifier: String
    public let action: String
    public let location: TraceletLocation?
    public let extras: [String: Any?]

    public init(
        identifier: String,
        action: String,
        location: TraceletLocation? = nil,
        extras: [String: Any?] = [:]
    ) {
        self.identifier = identifier
        self.action = action
        self.location = location
        self.extras = extras
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletGeofenceEvent {
        let locMap = map["location"] as? [String: Any?]
        return TraceletGeofenceEvent(
            identifier: map["identifier"] as? String ?? "",
            action: map["action"] as? String ?? "",
            location: locMap.map { TraceletLocation.fromMap($0) },
            extras: map["extras"] as? [String: Any?] ?? [:]
        )
    }

    public func toMap() -> [String: Any?] {
        var result: [String: Any?] = [
            "identifier": identifier,
            "action": action,
        ]
        if let loc = location { result["location"] = loc.toMap() }
        if !extras.isEmpty { result["extras"] = extras }
        return result
    }
}

// MARK: - TraceletGeofence (definition)

/// Geofence definition for registration.
public struct TraceletGeofence {
    public let identifier: String
    public let latitude: Double
    public let longitude: Double
    public let radius: Double
    public let notifyOnEntry: Bool
    public let notifyOnExit: Bool
    public let notifyOnDwell: Bool
    public let loiteringDelay: Int
    public let extras: [String: Any?]
    public let vertices: [[Double]]

    public init(
        identifier: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        notifyOnEntry: Bool = true,
        notifyOnExit: Bool = true,
        notifyOnDwell: Bool = false,
        loiteringDelay: Int = 0,
        extras: [String: Any?] = [:],
        vertices: [[Double]] = []
    ) {
        self.identifier = identifier
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.notifyOnDwell = notifyOnDwell
        self.loiteringDelay = loiteringDelay
        self.extras = extras
        self.vertices = vertices
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletGeofence {
        let verticesRaw = map["vertices"] as? [[Any]] ?? []
        let verticesList = verticesRaw.compactMap { v -> [Double]? in
            let doubles = v.compactMap { ($0 as? NSNumber)?.doubleValue }
            return doubles.count >= 2 ? doubles : nil
        }
        return TraceletGeofence(
            identifier: map["identifier"] as? String ?? "",
            latitude: (map["latitude"] as? NSNumber)?.doubleValue ?? 0,
            longitude: (map["longitude"] as? NSNumber)?.doubleValue ?? 0,
            radius: (map["radius"] as? NSNumber)?.doubleValue ?? 0,
            notifyOnEntry: map["notifyOnEntry"] as? Bool ?? true,
            notifyOnExit: map["notifyOnExit"] as? Bool ?? true,
            notifyOnDwell: map["notifyOnDwell"] as? Bool ?? false,
            loiteringDelay: (map["loiteringDelay"] as? NSNumber)?.intValue ?? 0,
            extras: map["extras"] as? [String: Any?] ?? [:],
            vertices: verticesList
        )
    }

    public func toMap() -> [String: Any?] {
        [
            "identifier": identifier,
            "latitude": latitude,
            "longitude": longitude,
            "radius": radius,
            "notifyOnEntry": notifyOnEntry,
            "notifyOnExit": notifyOnExit,
            "notifyOnDwell": notifyOnDwell,
            "loiteringDelay": loiteringDelay,
            "extras": extras,
            "vertices": vertices,
        ]
    }
}

// MARK: - TrackingMode

/// Tracking modes supported by the SDK.
@objc public enum TrackingMode: Int {
    /// Continuous location tracking with motion detection.
    case continuous = 0
    /// Passive geofence-only monitoring (saves maximum battery).
    case geofences = 1
    /// Periodic location fixes at fixed intervals.
    case periodic = 2

    /// Returns a variant from an integer value, defaulting to `.continuous` on unknown values.
    public static func fromInt(_ value: Int) -> TrackingMode {
        return TrackingMode(rawValue: value) ?? .continuous
    }
}

// MARK: - TraceletState

/// Current state of the Tracelet SDK.
public struct TraceletState {
    public let enabled: Bool
    public let trackingMode: TrackingMode
    public let isMoving: Bool
    public let schedulerEnabled: Bool
    public let odometer: Double
    public let didLaunchInBackground: Bool
    public let didDeviceReboot: Bool

    public init(
        enabled: Bool,
        trackingMode: TrackingMode = .continuous,
        isMoving: Bool = false,
        schedulerEnabled: Bool = false,
        odometer: Double = 0,
        didLaunchInBackground: Bool = false,
        didDeviceReboot: Bool = false
    ) {
        self.enabled = enabled
        self.trackingMode = trackingMode
        self.isMoving = isMoving
        self.schedulerEnabled = schedulerEnabled
        self.odometer = odometer
        self.didLaunchInBackground = didLaunchInBackground
        self.didDeviceReboot = didDeviceReboot
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletState {
        let modeInt = (map["trackingMode"] as? NSNumber)?.intValue ?? 0
        return TraceletState(
            enabled: map["enabled"] as? Bool ?? false,
            trackingMode: TrackingMode.fromInt(modeInt),
            isMoving: (map["isMoving"] ?? map["is_moving"]) as? Bool ?? false,
            schedulerEnabled: map["schedulerEnabled"] as? Bool ?? false,
            odometer: (map["odometer"] as? NSNumber)?.doubleValue ?? 0,
            didLaunchInBackground: map["didLaunchInBackground"] as? Bool ?? false,
            didDeviceReboot: map["didDeviceReboot"] as? Bool ?? false
        )
    }

    public func toMap() -> [String: Any?] {
        [
            "enabled": enabled,
            "trackingMode": trackingMode.rawValue,
            "isMoving": isMoving,
            "schedulerEnabled": schedulerEnabled,
            "odometer": odometer,
            "didLaunchInBackground": didLaunchInBackground,
            "didDeviceReboot": didDeviceReboot,
        ]
    }
}

// MARK: - TraceletProviderChangeEvent

/// Provider change event — location services state change.
public struct TraceletProviderChangeEvent {
    public let enabled: Bool
    public let status: Int
    public let gps: Bool
    public let network: Bool
    public let accuracyAuthorization: Int
    public let mockLocationsDetected: Bool
    public let gpsFallback: Bool

    public init(
        enabled: Bool,
        status: Int = 0,
        gps: Bool = false,
        network: Bool = false,
        accuracyAuthorization: Int = 0,
        mockLocationsDetected: Bool = false,
        gpsFallback: Bool = false
    ) {
        self.enabled = enabled
        self.status = status
        self.gps = gps
        self.network = network
        self.accuracyAuthorization = accuracyAuthorization
        self.mockLocationsDetected = mockLocationsDetected
        self.gpsFallback = gpsFallback
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletProviderChangeEvent {
        TraceletProviderChangeEvent(
            enabled: map["enabled"] as? Bool ?? false,
            status: (map["status"] as? NSNumber)?.intValue ?? 0,
            gps: map["gps"] as? Bool ?? false,
            network: map["network"] as? Bool ?? false,
            accuracyAuthorization: (map["accuracyAuthorization"] as? NSNumber)?.intValue ?? 0,
            mockLocationsDetected: map["mockLocationsDetected"] as? Bool ?? false,
            gpsFallback: map["gpsFallback"] as? Bool ?? false
        )
    }

    public func toMap() -> [String: Any?] {
        [
            "enabled": enabled,
            "status": status,
            "gps": gps,
            "network": network,
            "accuracyAuthorization": accuracyAuthorization,
            "mockLocationsDetected": mockLocationsDetected,
            "gpsFallback": gpsFallback,
        ]
    }
}

// MARK: - TraceletHeartbeatEvent

/// Heartbeat event — periodic status pulse with latest location.
public struct TraceletHeartbeatEvent {
    public let location: TraceletLocation

    public init(location: TraceletLocation) {
        self.location = location
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletHeartbeatEvent {
        let locMap = map["location"] as? [String: Any?] ?? [:]
        return TraceletHeartbeatEvent(location: TraceletLocation.fromMap(locMap))
    }

    public func toMap() -> [String: Any?] {
        ["location": location.toMap()]
    }
}

// MARK: - TraceletHttpEvent

/// HTTP sync event result.
public struct TraceletHttpEvent {
    public let success: Bool
    public let status: Int
    public let responseText: String
    public let isRetry: Bool
    public let retryCount: Int

    public init(
        success: Bool,
        status: Int,
        responseText: String = "",
        isRetry: Bool = false,
        retryCount: Int = 0
    ) {
        self.success = success
        self.status = status
        self.responseText = responseText
        self.isRetry = isRetry
        self.retryCount = retryCount
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletHttpEvent {
        TraceletHttpEvent(
            success: map["success"] as? Bool ?? false,
            status: (map["status"] as? NSNumber)?.intValue ?? 0,
            responseText: map["responseText"] as? String ?? "",
            isRetry: map["isRetry"] as? Bool ?? false,
            retryCount: (map["retryCount"] as? NSNumber)?.intValue ?? 0
        )
    }

    public func toMap() -> [String: Any?] {
        [
            "success": success,
            "status": status,
            "responseText": responseText,
            "isRetry": isRetry,
            "retryCount": retryCount,
        ]
    }
}

// MARK: - TraceletConnectivityChangeEvent

/// Connectivity change event.
public struct TraceletConnectivityChangeEvent {
    public let connected: Bool

    public init(connected: Bool) {
        self.connected = connected
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletConnectivityChangeEvent {
        TraceletConnectivityChangeEvent(connected: map["connected"] as? Bool ?? false)
    }

    public func toMap() -> [String: Any?] {
        ["connected": connected]
    }
}

// MARK: - TraceletAuthorizationEvent

/// Authorization event — OAuth token exchange result.
public struct TraceletAuthorizationEvent {
    public let success: Bool
    public let status: Int
    public let response: String

    public init(success: Bool, status: Int, response: String = "") {
        self.success = success
        self.status = status
        self.response = response
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletAuthorizationEvent {
        TraceletAuthorizationEvent(
            success: map["success"] as? Bool ?? false,
            status: (map["status"] as? NSNumber)?.intValue ?? 0,
            response: map["response"] as? String ?? ""
        )
    }

    public func toMap() -> [String: Any?] {
        ["success": success, "status": status, "response": response]
    }
}

// MARK: - TraceletActivityChangeEvent

/// Activity change event — detected device activity.
public struct TraceletActivityChangeEvent {
    public let activity: String
    public let confidence: Int

    public init(activity: String = "unknown", confidence: Int = -1) {
        self.activity = activity
        self.confidence = confidence
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletActivityChangeEvent {
        TraceletActivityChangeEvent(
            activity: map["activity"] as? String ?? "unknown",
            confidence: (map["confidence"] as? NSNumber)?.intValue ?? -1
        )
    }

    public func toMap() -> [String: Any?] {
        ["activity": activity, "confidence": confidence]
    }
}

// MARK: - TraceletMotionChangeEvent

/// Motion change event — moving/stationary transition.
public struct TraceletMotionChangeEvent {
    public let isMoving: Bool
    public let location: TraceletLocation

    public init(isMoving: Bool, location: TraceletLocation) {
        self.isMoving = isMoving
        self.location = location
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletMotionChangeEvent {
        let locMap = map["location"] as? [String: Any?] ?? [:]
        return TraceletMotionChangeEvent(
            isMoving: (map["isMoving"] ?? map["is_moving"]) as? Bool ?? false,
            location: TraceletLocation.fromMap(locMap)
        )
    }

    public func toMap() -> [String: Any?] {
        ["isMoving": isMoving, "location": location.toMap()]
    }
}

// MARK: - TraceletTripEvent

/// Trip event — detected trip (start → stop).
public struct TraceletTripEvent {
    public let isMoving: Bool
    public let distance: Double
    public let duration: Double
    public let startLocation: TraceletLocation
    public let stopLocation: TraceletLocation
    public let waypoints: [TraceletLocation]

    public var averageSpeed: Double {
        duration > 0 ? distance / duration : 0
    }

    public init(
        isMoving: Bool,
        distance: Double = 0,
        duration: Double = 0,
        startLocation: TraceletLocation,
        stopLocation: TraceletLocation,
        waypoints: [TraceletLocation] = []
    ) {
        self.isMoving = isMoving
        self.distance = distance
        self.duration = duration
        self.startLocation = startLocation
        self.stopLocation = stopLocation
        self.waypoints = waypoints
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletTripEvent {
        let startMap = map["startLocation"] as? [String: Any?] ?? [:]
        let stopMap = map["stopLocation"] as? [String: Any?] ?? [:]
        let waypointsList = (map["waypoints"] as? [[String: Any?]])?.map {
            TraceletLocation.fromMap($0)
        } ?? []

        return TraceletTripEvent(
            isMoving: map["isMoving"] as? Bool ?? false,
            distance: (map["distance"] as? NSNumber)?.doubleValue ?? 0,
            duration: (map["duration"] as? NSNumber)?.doubleValue ?? 0,
            startLocation: TraceletLocation.fromMap(startMap),
            stopLocation: TraceletLocation.fromMap(stopMap),
            waypoints: waypointsList
        )
    }

    public func toMap() -> [String: Any?] {
        [
            "isMoving": isMoving,
            "distance": distance,
            "duration": duration,
            "startLocation": startLocation.toMap(),
            "stopLocation": stopLocation.toMap(),
            "waypoints": waypoints.map { $0.toMap() },
        ]
    }
}

// MARK: - TraceletPrivacyZone (definition)

/// Privacy zone definition.
///
/// Actions:
/// - `0` (exclude): Drop location entirely — not persisted, not dispatched.
/// - `1` (degrade): Snap coordinates to a grid at ``degradedAccuracyMeters`` resolution.
/// - `2` (eventOnly): Dispatch to listeners but do not persist to database.
public struct TraceletPrivacyZone {
    /// Action: drop location entirely.
    public static let actionExclude = 0
    /// Action: degrade coordinate precision.
    public static let actionDegrade = 1
    /// Action: dispatch to listeners but skip persistence.
    public static let actionEventOnly = 2

    public let identifier: String
    public let latitude: Double
    public let longitude: Double
    public let radius: Double
    /// 0 = exclude, 1 = degrade, 2 = eventOnly
    public let action: Int
    public let degradedAccuracyMeters: Double

    public init(
        identifier: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        action: Int = 0,
        degradedAccuracyMeters: Double = 1000.0
    ) {
        self.identifier = identifier
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.action = action
        self.degradedAccuracyMeters = degradedAccuracyMeters
    }

    public static func fromMap(_ map: [String: Any?]) -> TraceletPrivacyZone {
        TraceletPrivacyZone(
            identifier: map["identifier"] as? String ?? "",
            latitude: (map["latitude"] as? NSNumber)?.doubleValue ?? 0,
            longitude: (map["longitude"] as? NSNumber)?.doubleValue ?? 0,
            radius: (map["radius"] as? NSNumber)?.doubleValue ?? 0,
            action: (map["action"] as? NSNumber)?.intValue ?? 0,
            degradedAccuracyMeters: (map["degradedAccuracyMeters"] as? NSNumber)?.doubleValue ?? 1000.0
        )
    }

    public func toMap() -> [String: Any] {
        [
            "identifier": identifier,
            "latitude": latitude,
            "longitude": longitude,
            "radius": radius,
            "action": action,
            "degradedAccuracyMeters": degradedAccuracyMeters,
        ]
    }
}
