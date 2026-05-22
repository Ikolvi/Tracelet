import Flutter
import UIKit
import CoreMotion
import TraceletSDK

/// Pigeon-backed implementation of ``TraceletHostApi``.
///
/// Delegates every call to ``TraceletSdk`` and converts between Pigeon typed
/// objects (``TlState``, ``TlLocation``, etc.) and the SDK's raw dictionary format.
class TraceletHostApiImpl: TraceletHostApi {

    private let headlessRunner: HeadlessRunner
    private var sdk: TraceletSdk { TraceletSdk.shared }

    init(headlessRunner: HeadlessRunner) {
        self.headlessRunner = headlessRunner
    }

    // MARK: - Mappers: Pigeon → SDK Dictionary

    private func tlConfigToDict(_ c: TlConfig) -> [String: Any] {
        var dict: [String: Any] = [:]

        // Geo
        dict["desiredAccuracy"] = c.geo.desiredAccuracy.rawValue
        dict["distanceFilter"] = c.geo.distanceFilter
        dict["stationaryRadius"] = c.geo.stationaryRadius
        dict["locationTimeout"] = c.geo.locationTimeout
        dict["disableElasticity"] = c.geo.disableElasticity
        dict["elasticityMultiplier"] = c.geo.elasticityMultiplier
        dict["stopAfterElapsedMinutes"] = c.geo.stopAfterElapsedMinutes
        dict["maxMonitoredGeofences"] = c.geo.maxMonitoredGeofences
        dict["enableTimestampMeta"] = c.geo.enableTimestampMeta
        dict["enableAdaptiveMode"] = c.geo.enableAdaptiveMode
        dict["periodicLocationInterval"] = c.geo.periodicLocationInterval
        dict["periodicDesiredAccuracy"] = c.geo.periodicDesiredAccuracy.rawValue
        dict["enableSparseUpdates"] = c.geo.enableSparseUpdates
        dict["sparseDistanceThreshold"] = c.geo.sparseDistanceThreshold
        dict["sparseMaxIdleSeconds"] = c.geo.sparseMaxIdleSeconds
        dict["batteryBudgetPerHour"] = c.geo.batteryBudgetPerHour
        dict["enableDeadReckoning"] = c.geo.enableDeadReckoning
        dict["deadReckoningActivationDelay"] = c.geo.deadReckoningActivationDelay
        dict["deadReckoningMaxDuration"] = c.geo.deadReckoningMaxDuration

        // App
        dict["stopOnTerminate"] = c.app.stopOnTerminate
        dict["startOnBoot"] = c.app.startOnBoot
        dict["heartbeatInterval"] = c.app.heartbeatInterval
        dict["schedule"] = c.app.schedule
        if let remoteConfigUrl = c.app.remoteConfigUrl { dict["remoteConfigUrl"] = remoteConfigUrl }
        if let remoteConfigHeaders = c.app.remoteConfigHeaders { dict["remoteConfigHeaders"] = remoteConfigHeaders.compactMapValues { $0 } }
        dict["remoteConfigTimeout"] = c.app.remoteConfigTimeout
        dict["remoteConfigRefreshInterval"] = c.app.remoteConfigRefreshInterval

        // Android (ignored on iOS but kept for parity in dictionary)
        dict["locationUpdateInterval"] = c.android.locationUpdateInterval
        dict["fastestLocationUpdateInterval"] = c.android.fastestLocationUpdateInterval
        dict["deferTime"] = c.android.deferTime
        dict["allowIdenticalLocations"] = c.android.allowIdenticalLocations
        dict["geofenceModeHighAccuracy"] = c.android.geofenceModeHighAccuracy
        dict["periodicUseForegroundService"] = c.android.periodicUseForegroundService
        dict["periodicUseExactAlarms"] = c.android.periodicUseExactAlarms
        dict["scheduleUseAlarmManager"] = c.android.scheduleUseAlarmManager

        // iOS
        dict["activityType"] = c.ios.activityType.rawValue
        dict["useSignificantChangesOnly"] = c.ios.useSignificantChangesOnly
        dict["showsBackgroundLocationIndicator"] = c.ios.showsBackgroundLocationIndicator
        dict["pausesLocationUpdatesAutomatically"] = c.ios.pausesLocationUpdatesAutomatically
        dict["locationAuthorizationRequest"] = c.ios.locationAuthorizationRequest == .always ? "Always" : "WhenInUse"
        dict["disableLocationAuthorizationAlert"] = c.ios.disableLocationAuthorizationAlert
        dict["preventSuspend"] = c.ios.preventSuspend

        // HTTP
        if let url = c.http.url { dict["url"] = url }
        dict["method"] = c.http.method.rawValue
        if let headers = c.http.headers { dict["headers"] = headers.compactMapValues { $0 } }
        if let params = c.http.params { dict["params"] = params.compactMapValues { $0 } }
        dict["autoSync"] = c.http.autoSync
        dict["batchSync"] = c.http.batchSync
        dict["maxBatchSize"] = c.http.maxBatchSize
        dict["autoSyncThreshold"] = c.http.autoSyncThreshold
        dict["httpTimeout"] = c.http.httpTimeout
        dict["locationsOrderDirection"] = c.http.locationsOrderDirection.rawValue
        dict["disableAutoSyncOnCellular"] = c.http.disableAutoSyncOnCellular
        dict["maxRetries"] = c.http.maxRetries
        dict["retryBackoffBase"] = c.http.retryBackoffBase
        dict["retryBackoffCap"] = c.http.retryBackoffCap
        dict["enableDeltaCompression"] = c.http.enableDeltaCompression
        dict["deltaCoordinatePrecision"] = c.http.deltaCoordinatePrecision

        // Logger
        dict["logLevel"] = c.logger.logLevel.rawValue
        dict["logMaxDays"] = c.logger.logMaxDays
        dict["debug"] = c.logger.debug

        // Motion
        dict["stopTimeout"] = c.motion.stopTimeout
        dict["motionTriggerDelay"] = c.motion.motionTriggerDelay
        dict["disableMotionActivityUpdates"] = c.motion.disableMotionActivityUpdates
        dict["isMoving"] = c.motion.isMoving
        dict["activityRecognitionInterval"] = c.motion.activityRecognitionInterval
        dict["minimumActivityRecognitionConfidence"] = c.motion.minimumActivityRecognitionConfidence
        dict["disableStopDetection"] = c.motion.disableStopDetection
        dict["stopDetectionDelay"] = c.motion.stopDetectionDelay
        dict["stopOnStationary"] = c.motion.stopOnStationary
        dict["stationaryRadius"] = c.motion.stationaryRadius
        dict["useSignificantChangesOnly"] = c.motion.useSignificantChangesOnly
        dict["shakeThreshold"] = c.motion.shakeThreshold
        dict["stillThreshold"] = c.motion.stillThreshold
        dict["stillSampleCount"] = c.motion.stillSampleCount

        // Geofence
        dict["geofenceModeHighAccuracy"] = c.geofence.geofenceModeHighAccuracy
        dict["geofenceInitialTriggerEntry"] = c.geofence.geofenceInitialTriggerEntry
        dict["geofenceProximityRadius"] = c.geofence.geofenceProximityRadius
        dict["geofenceInitialTrigger"] = c.geofence.geofenceInitialTrigger

        // Persistence
        dict["persistMode"] = c.persistence.persistMode.rawValue
        dict["maxDaysToPersist"] = c.persistence.maxDaysToPersist
        dict["maxRecordsToPersist"] = c.persistence.maxRecordsToPersist
        dict["disableProviderChangeRecord"] = c.persistence.disableProviderChangeRecord

        // Security
        dict["encryptDatabase"] = c.security.encryptDatabase

        // Audit
        dict["auditEnabled"] = c.audit.enabled
        dict["auditHashAlgorithm"] = c.audit.hashAlgorithm.rawValue

        // Privacy Zone
        dict["privacyZoneEnabled"] = c.privacyZone.enabled

        // Attestation
        dict["attestationEnabled"] = c.attestation.enabled
        dict["attestationRefreshInterval"] = c.attestation.refreshInterval

        return dict
    }

    // MARK: - Converters: SDK Dictionary → Pigeon types

    private func dictToTlState(_ d: [String: Any]) -> TlState {
        let modeInt = d["trackingMode"] as? Int ?? 0
        return TlState(
            enabled: d["enabled"] as? Bool ?? false,
            isMoving: d["isMoving"] as? Bool ?? false,
            trackingMode: TlTrackingMode(rawValue: modeInt) ?? .location,
            schedulerEnabled: d["schedulerEnabled"] as? Bool ?? false,
            odometer: d["odometer"] as? Double ?? 0.0,
            lastLocationTimestamp: d["lastLocationTimestamp"] as? String
        )
    }

    private func dictToTlLocation(_ d: [String: Any]) -> TlLocation {
        let coords = d["coords"] as? [String: Any] ?? [:]
        let battery = d["battery"] as? [String: Any] ?? [:]
        let activity = d["activity"] as? [String: Any]

        return TlLocation(
            coords: TlCoords(
                latitude: coords["latitude"] as? Double ?? 0.0,
                longitude: coords["longitude"] as? Double ?? 0.0,
                accuracy: coords["accuracy"] as? Double ?? 0.0,
                speed: coords["speed"] as? Double ?? -1.0,
                heading: coords["heading"] as? Double ?? -1.0,
                altitude: coords["altitude"] as? Double ?? 0.0,
                altitudeAccuracy: coords["altitudeAccuracy"] as? Double ?? 0.0,
                speedAccuracy: coords["speedAccuracy"] as? Double ?? 0.0,
                headingAccuracy: coords["headingAccuracy"] as? Double ?? 0.0,
                ellipsoidalAltitude: coords["ellipsoidalAltitude"] as? Double,
                floor: (coords["floor"] as? Int).map { Int64($0) }
            ),
            battery: TlBattery(
                level: battery["level"] as? Double ?? -1.0,
                isCharging: battery["isCharging"] as? Bool ?? false
            ),
            timestamp: d["timestamp"] as? String ?? "",
            uuid: d["uuid"] as? String ?? "",
            isMoving: d["isMoving"] as? Bool ?? false,
            odometer: d["odometer"] as? Double ?? 0.0,
            event: d["event"] as? String,
            activity: activity.map {
                TlActivity(
                    type: $0["type"] as? String ?? "unknown",
                    confidence: Int64($0["confidence"] as? Int ?? 0)
                )
            },
            extras: d["extras"] as? [String?: Any?]
        )
    }

    private func dictToTlGeofence(_ d: [String: Any]) -> TlGeofence {
        TlGeofence(
            identifier: d["identifier"] as? String ?? "",
            latitude: d["latitude"] as? Double ?? 0.0,
            longitude: d["longitude"] as? Double ?? 0.0,
            radius: d["radius"] as? Double ?? 0.0,
            notifyOnEntry: d["notifyOnEntry"] as? Bool ?? true,
            notifyOnExit: d["notifyOnExit"] as? Bool ?? true,
            notifyOnDwell: d["notifyOnDwell"] as? Bool ?? false,
            loiteringDelay: Int64(d["loiteringDelay"] as? Int ?? 0),
            extras: d["extras"] as? [String?: Any?],
            vertices: (d["vertices"] as? [[Double?]?])
        )
    }

    private func tlGeofenceToDict(_ g: TlGeofence) -> [String: Any] {
        var d: [String: Any] = [
            "identifier": g.identifier,
            "latitude": g.latitude,
            "longitude": g.longitude,
            "radius": g.radius,
            "notifyOnEntry": g.notifyOnEntry,
            "notifyOnExit": g.notifyOnExit,
            "notifyOnDwell": g.notifyOnDwell,
            "loiteringDelay": g.loiteringDelay,
        ]
        if let extras = g.extras { d["extras"] = extras.compactMapValues { $0 } }
        if let vertices = g.vertices { d["vertices"] = vertices }
        return d
    }

    private func optionsToDict(_ o: TlCurrentPositionOptions) -> [String: Any] {
        var d: [String: Any] = [
            "timeout": o.timeout,
            "maximumAge": o.maximumAge,
            "persist": o.persist,
            "samples": o.samples,
        ]
        if let accuracy = o.desiredAccuracy { d["desiredAccuracy"] = accuracy.rawValue }
        if let extras = o.extras { d["extras"] = extras.compactMapValues { $0 } }
        return d
    }

    private func dictToTlProviderState(_ d: [String: Any]) -> TlProviderChangeEvent {
        TlProviderChangeEvent(
            enabled: d["enabled"] as? Bool ?? false,
            gps: d["gps"] as? Bool ?? false,
            network: d["network"] as? Bool ?? false,
            status: Int64(d["status"] as? Int ?? 0),
            accuracyAuthorization: (d["accuracyAuthorization"] as? Int).map { Int64($0) }
        )
    }

    func intToAuthStatus(_ value: Int) -> TlAuthorizationStatus {
        return TlAuthorizationStatus(rawValue: value) ?? .notDetermined
    }

    // MARK: - Lifecycle

    func ready(config: TlConfig, completion: @escaping (Result<TlState, Error>) -> Void) {
        let state = sdk.ready(config: tlConfigToDict(config))
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func start(completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before start()", details: nil)))
            return
        }
        let state = sdk.start()
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func stop(completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before stop()", details: nil)))
            return
        }
        let state = sdk.stop()
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func startGeofences(completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before startGeofences()", details: nil)))
            return
        }
        let state = sdk.startGeofences()
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func startPeriodic(completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before startPeriodic()", details: nil)))
            return
        }
        let state = sdk.startPeriodic()
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func getState(completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.success(TlState(
                enabled: false, isMoving: false, trackingMode: .location,
                schedulerEnabled: false, odometer: 0.0, lastLocationTimestamp: nil)))
            return
        }
        let state = sdk.getState()
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func setConfig(config: TlConfig, completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before setConfig()", details: nil)))
            return
        }
        let state = sdk.setConfig(tlConfigToDict(config))
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func reset(config: TlConfig?, completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before reset()", details: nil)))
            return
        }
        let dict = config.map { tlConfigToDict($0) }
        let state = sdk.reset(dict)
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    // MARK: - Location

    func getCurrentPosition(options: TlCurrentPositionOptions, completion: @escaping (Result<TlLocation, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before getCurrentPosition()", details: nil)))
            return
        }
        sdk.getCurrentPosition(options: optionsToDict(options)) { location in
            if let loc = location as? [String: Any] {
                completion(.success(self.dictToTlLocation(loc)))
            } else {
                completion(.failure(PigeonError(code: "LOCATION_UNAVAILABLE", message: "Could not get current position", details: nil)))
            }
        }
    }

    func getLastKnownLocation(options: TlCurrentPositionOptions?, completion: @escaping (Result<TlLocation?, Error>) -> Void) {
        let opts = options.map { optionsToDict($0) } ?? [:]
        let loc = sdk.getLastKnownLocation(options: opts as [String: Any])
        if let loc = loc as? [String: Any] {
            completion(.success(dictToTlLocation(loc)))
        } else {
            completion(.success(nil))
        }
    }

    func watchPosition(options: TlCurrentPositionOptions, completion: @escaping (Result<Int64, Error>) -> Void) {
        let watchId = sdk.watchPosition(options: optionsToDict(options))
        completion(.success(Int64(watchId)))
    }

    func stopWatchPosition(watchId: Int64, completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.stopWatchPosition(Int(watchId))
        completion(.success(result))
    }

    func changePace(isMoving: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before changePace()", details: nil)))
            return
        }
        let result = sdk.changePace(isMoving)
        completion(.success(result))
    }

    func getOdometer(completion: @escaping (Result<Double, Error>) -> Void) {
        completion(.success(sdk.getOdometer()))
    }

    func setOdometer(value: Double, completion: @escaping (Result<TlLocation, Error>) -> Void) {
        let loc = sdk.setOdometer(value)
        completion(.success(dictToTlLocation(loc)))
    }

    // MARK: - Geofencing

    func addGeofence(geofence: TlGeofence, completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.addGeofence(tlGeofenceToDict(geofence))
        completion(.success(result))
    }

    func addGeofences(geofences: [TlGeofence], completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.addGeofences(geofences.map(tlGeofenceToDict))
        completion(.success(result))
    }

    func removeGeofence(identifier: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.removeGeofence(identifier)
        completion(.success(result))
    }

    func removeGeofences(completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.removeGeofences()
        completion(.success(result))
    }

    func getGeofences(completion: @escaping (Result<[TlGeofence?], Error>) -> Void) {
        let raw = sdk.getGeofences()
        completion(.success(raw.map(dictToTlGeofence)))
    }

    func getGeofence(identifier: String, completion: @escaping (Result<TlGeofence?, Error>) -> Void) {
        let raw = sdk.getGeofence(identifier)
        completion(.success(raw.map(dictToTlGeofence)))
    }

    func geofenceExists(identifier: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.geofenceExists(identifier)))
    }

    // MARK: - Persistence

    func getLocations(query: [String?: Any?]?, completion: @escaping (Result<[TlLocation?], Error>) -> Void) {
        let q = (query as? [String: Any?])?.compactMapValues { $0 }
        let raw = sdk.getLocations(query: q as? [String: Any])
        completion(.success(raw.map(dictToTlLocation)))
    }

    func getCount(query: [String?: Any?]?, completion: @escaping (Result<Int64, Error>) -> Void) {
        let q = (query as? [String: Any?])?.compactMapValues { $0 }
        completion(.success(Int64(sdk.getCount(query: q as? [String: Any]))))
    }

    func destroyLocations(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.destroyLocations()))
    }

    func destroySyncedLocations(completion: @escaping (Result<Int64, Error>) -> Void) {
        completion(.success(Int64(sdk.destroySyncedLocations())))
    }

    func destroyLocation(uuid: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.destroyLocation(uuid)))
    }

    func insertLocation(params: [String?: Any?], completion: @escaping (Result<String, Error>) -> Void) {
        let p = (params as? [String: Any?])?.compactMapValues { $0 } ?? [:]
        completion(.success(sdk.insertLocation(p as [String: Any])))
    }

    // MARK: - HTTP Sync

    func sync(completion: @escaping (Result<[TlLocation?], Error>) -> Void) {
        sdk.sync { synced in
            let list = synced
            completion(.success(list.map { self.dictToTlLocation($0) }))
        }
    }

    func setDynamicHeaders(headers: [String?: String?], completion: @escaping (Result<Bool, Error>) -> Void) {
        sdk.setDynamicHeaders((headers as? [String: String?])?.compactMapValues { $0 } ?? [:])
        completion(.success(true))
    }

    func setRouteContext(context: [String?: Any?], completion: @escaping (Result<Bool, Error>) -> Void) {
        let c = (context as? [String: Any?])?.compactMapValues { $0 } ?? [:]
        sdk.setRouteContext(c as [String: Any])
        completion(.success(true))
    }

    func clearRouteContext(completion: @escaping (Result<Bool, Error>) -> Void) {
        sdk.clearRouteContext()
        completion(.success(true))
    }

    // MARK: - Permissions

    func getPermissionStatus(completion: @escaping (Result<TlAuthorizationStatus, Error>) -> Void) {
        let status = sdk.getPermissionStatus()
        completion(.success(intToAuthStatus(status)))
    }

    func requestPermission(completion: @escaping (Result<TlAuthorizationStatus, Error>) -> Void) {
        NSLog("[Tracelet] requestPermission called")
        DispatchQueue.main.async {
            self.sdk.permissionManager.requestPermission { status in
                let s = status as? Int ?? 0
                let result = self.intToAuthStatus(s)
                NSLog("[Tracelet] requestPermission result: \(s) -> \(result)")
                completion(.success(result))
            }
        }
    }

    func getNotificationPermissionStatus(completion: @escaping (Result<TlNotificationAuthorizationStatus, Error>) -> Void) {
        completion(.success(.authorized)) // Always granted on iOS
    }

    func requestNotificationPermission(completion: @escaping (Result<TlNotificationAuthorizationStatus, Error>) -> Void) {
        completion(.success(.authorized)) // Always granted on iOS
    }

    func canScheduleExactAlarms(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(true)) // No restriction on iOS
    }

    func openExactAlarmSettings(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false)) // N/A on iOS
    }

    private func intToMotionStatus(_ code: Int) -> TlMotionAuthorizationStatus {
        switch code {
        case 0: return .notDetermined
        case 1: return .restricted
        case 2: return .denied
        case 3: return .authorized
        case 4: return .deniedForever
        default: return .notDetermined
        }
    }

    func getMotionPermissionStatus(completion: @escaping (Result<TlMotionAuthorizationStatus, Error>) -> Void) {
        if let detector = sdk.motionDetector {
            completion(.success(intToMotionStatus(detector.getMotionAuthorizationStatus())))
        } else {
            // Pre-ready: fall back to static CMMotionActivityManager check
            let status = CMMotionActivityManager.authorizationStatus()
            let tlStatus: TlMotionAuthorizationStatus
            switch status {
            case .notDetermined: tlStatus = .notDetermined
            case .restricted:    tlStatus = .restricted
            case .denied:        tlStatus = .denied
            case .authorized:    tlStatus = .authorized
            @unknown default:    tlStatus = .notDetermined
            }
            completion(.success(tlStatus))
        }
    }

    func requestMotionPermission(completion: @escaping (Result<TlMotionAuthorizationStatus, Error>) -> Void) {
        guard let detector = sdk.motionDetector else {
            // Pre-ready: can't request without motionDetector
            completion(.success(.notDetermined))
            return
        }
        NSLog("[Tracelet] requestMotionPermission called")
        DispatchQueue.main.async {
            detector.requestMotionPermission { status in
                NSLog("[Tracelet] requestMotionPermission result: \(status)")
                completion(.success(self.intToMotionStatus(status)))
            }
        }
    }

    func requestTemporaryFullAccuracy(purpose: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        NSLog("[Tracelet] requestTemporaryFullAccuracy called for purpose: \(purpose)")
        DispatchQueue.main.async {
            let result = self.sdk.permissionManager.requestTemporaryFullAccuracy(purposeKey: purpose)
            let resInt = result as? Int ?? 0
            NSLog("[Tracelet] requestTemporaryFullAccuracy result: \(resInt)")
            completion(.success(Int64(resInt)))
        }
    }

    // MARK: - Utility

    func isPowerSaveMode(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.isPowerSaveMode))
    }

    func getProviderState(completion: @escaping (Result<TlProviderChangeEvent, Error>) -> Void) {
        let state = sdk.getProviderState()
        completion(.success(dictToTlProviderState(state)))
    }

    func getDeviceInfo(completion: @escaping (Result<[String?: Any?], Error>) -> Void) {
        var info = sdk.getDeviceInfo()
        info["framework"] = "flutter"
        completion(.success(info))
    }

    func getSensors(completion: @escaping (Result<[String?: Any?], Error>) -> Void) {
        completion(.success(sdk.getSensors()))
    }

    func playSound(name: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.playSound(name)))
    }

    func isIgnoringBatteryOptimizations(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(true)) // Always true on iOS
    }

    func requestSettings(action: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        DispatchQueue.main.async {
            completion(.success(self.sdk.permissionManager.showLocationSettings()))
        }
    }

    func showSettings(action: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        DispatchQueue.main.async {
            let result = action == "app"
                ? self.sdk.permissionManager.showAppSettings()
                : self.sdk.permissionManager.showLocationSettings()
            completion(.success(result))
        }
    }

    func getSettingsHealth(completion: @escaping (Result<[String?: Any?], Error>) -> Void) {
        completion(.success([
            "manufacturer": "Apple",
            "model": UIDevice.current.model,
            "isAggressiveOem": false,
            "aggressionRating": 0,
            "isIgnoringBatteryOptimizations": true,
            "autostartAvailable": false,
            "oemSettingsScreens": [[String: String]](),
        ]))
    }

    func openOemSettings(label: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false)) // N/A on iOS
    }

    // MARK: - Logging

    func getLog(query: [String?: Any?]?, completion: @escaping (Result<String, Error>) -> Void) {
        let q = (query as? [String: Any?])?.compactMapValues { $0 }
        completion(.success(sdk.getLog(query: q as? [String: Any])))
    }

    func destroyLog(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.destroyLog()))
    }

    func emailLog(email: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let logContent = sdk.getLog()
        guard let rootVC = UIApplication.shared.keyWindow?.rootViewController else {
            completion(.success(false))
            return
        }
        let activityVC = UIActivityViewController(
            activityItems: ["Tracelet Log\n\n\(logContent)"],
            applicationActivities: nil
        )
        rootVC.present(activityVC, animated: true)
        completion(.success(true))
    }

    func log(level: String, message: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        sdk.log(level, message)
        completion(.success(true))
    }

    // MARK: - Scheduling

    func startSchedule(completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before startSchedule()", details: nil)))
            return
        }
        let state = sdk.startSchedule()
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func stopSchedule(completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before stopSchedule()", details: nil)))
            return
        }
        let state = sdk.stopSchedule()
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    // MARK: - Background Tasks

    func startBackgroundTask(completion: @escaping (Result<Int64, Error>) -> Void) {
        let taskId = BackgroundTaskHelper.shared.begin("dartBackground")
        completion(.success(Int64(taskId?.rawValue ?? UIBackgroundTaskIdentifier.invalid.rawValue)))
    }

    func stopBackgroundTask(taskId: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
        BackgroundTaskHelper.shared.end(UIBackgroundTaskIdentifier(rawValue: Int(taskId)))
        completion(.success(taskId))
    }

    // MARK: - Headless

    func registerHeadlessTask(callbackIds: [Int64?], completion: @escaping (Result<Bool, Error>) -> Void) {
        let validIds = callbackIds.compactMap { $0 }
        let registrationId = validIds.first ?? -1
        let dispatchId = validIds.last ?? -1
        headlessRunner.registerCallbacks(registrationId, dispatchId)
        completion(.success(true))
    }

    func registerHeadlessHeadersCallback(callbackIds: [Int64?], completion: @escaping (Result<Bool, Error>) -> Void) {
        storeHeadlessCallback(callbackIds.compactMap { $0 }, key: "headlessHeaders")
        completion(.success(true))
    }

    func registerHeadlessSyncBodyBuilder(callbackIds: [Int64?], completion: @escaping (Result<Bool, Error>) -> Void) {
        storeHeadlessCallback(callbackIds.compactMap { $0 }, key: "headlessSyncBody")
        completion(.success(true))
    }

    private func storeHeadlessCallback(_ callbackIds: [Int64], key: String) {
        let validIds = callbackIds.compactMap { $0 }
        let registrationId = validIds.first ?? -1
        let dispatchId = validIds.last ?? -1
        let defaults = UserDefaults.standard
        defaults.set(registrationId, forKey: "com.tracelet.headless.\(key)_registrationId")
        defaults.set(dispatchId, forKey: "com.tracelet.headless.\(key)_dispatchId")
    }

    // MARK: - Enterprise: Audit Trail

    func verifyAuditTrail(completion: @escaping (Result<[String?: Any?], Error>) -> Void) {
        completion(.success(sdk.verifyAuditTrail()))
    }

    func getAuditProof(uuid: String, completion: @escaping (Result<[String?: Any?]?, Error>) -> Void) {
        completion(.success(sdk.getAuditProof(uuid)))
    }

    // MARK: - Enterprise: Privacy Zones

    func addPrivacyZone(zone: [String?: Any?], completion: @escaping (Result<Bool, Error>) -> Void) {
        let z = (zone as? [String: Any?])?.compactMapValues { $0 } ?? [:]
        completion(.success(sdk.addPrivacyZone(z as [String: Any])))
    }

    func addPrivacyZones(zones: [[String?: Any?]?], completion: @escaping (Result<Bool, Error>) -> Void) {
        let zs = zones.compactMap { $0 as? [String: Any?] }.map { $0.compactMapValues { $0 } }
        completion(.success(sdk.addPrivacyZones(zs as [[String: Any]])))
    }

    func removePrivacyZone(identifier: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.removePrivacyZone(identifier)))
    }

    func removePrivacyZones(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.removePrivacyZones()))
    }

    func getPrivacyZones(completion: @escaping (Result<[[String?: Any?]?], Error>) -> Void) {
        completion(.success(sdk.getPrivacyZones()))
    }

    // MARK: - Enterprise: Encrypted Database

    func isDatabaseEncrypted(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.database.isDatabaseEncrypted()))
    }

    func encryptDatabase(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.database.encryptDatabase()))
    }

    // MARK: - Enterprise: Device Attestation

    func getAttestationToken(completion: @escaping (Result<[String?: Any?]?, Error>) -> Void) {
        sdk.getAttestationToken { token in
            DispatchQueue.main.async {
                completion(.success(token))
            }
        }
    }

    // MARK: - Enterprise: Carbon Estimator

    func getCarbonReport(query: [String?: Any?]?, completion: @escaping (Result<[String?: Any?], Error>) -> Void) {
        let q = (query as? [String: Any?])?.compactMapValues { $0 }
        completion(.success(sdk.getCarbonReport(query: q as? [String: Any])))
    }

    // MARK: - Enterprise: Dead Reckoning

    func getDeadReckoningState(completion: @escaping (Result<[String?: Any?]?, Error>) -> Void) {
        completion(.success(sdk.getDeadReckoningState()))
    }
}
