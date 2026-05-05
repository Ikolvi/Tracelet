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

    // MARK: - Converters: SDK Dictionary → Pigeon types

    private func dictToTlState(_ d: [String: Any]) -> TlState {
        let modeInt = d["trackingMode"] as? Int ?? TrackingMode.continuous.rawValue
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
            vertices: (d["vertices"] as? [[Any]]).map { $0.map { inner in inner.map { $0 as? Double } } }
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
        if let extras = g.extras { d["extras"] = extras }
        if let vertices = g.vertices { d["vertices"] = vertices }
        return d
    }

    private func optionsToDict(_ o: TlCurrentPositionOptions) -> [String: Any] {
        [
            "timeout": o.timeout,
            "maximumAge": o.maximumAge,
            "persist": o.persist,
            "samples": o.samples,
        ]
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

    private func intToAuthStatus(_ value: Int) -> TlAuthorizationStatus {
        TlAuthorizationStatus(rawValue: value) ?? .notDetermined
    }

    // MARK: - Lifecycle

    func ready(config: [String: Any?], completion: @escaping (Result<TlState, Error>) -> Void) {
        let c = config.compactMapValues { $0 }
        let state = sdk.ready(config: c)
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

    func setConfig(config: [String: Any?], completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before setConfig()", details: nil)))
            return
        }
        let c = config.compactMapValues { $0 }
        let state = sdk.setConfig(c)
        completion(.success(dictToTlState(state as? [String: Any] ?? [:])))
    }

    func reset(config: [String: Any?]?, completion: @escaping (Result<TlState, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before reset()", details: nil)))
            return
        }
        let c = config?.compactMapValues { $0 }
        let state = sdk.reset(c)
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

    func getLastKnownLocation(options: [String: Any?]?, completion: @escaping (Result<TlLocation?, Error>) -> Void) {
        let opts = (options ?? [:]).compactMapValues { $0 }
        let loc = sdk.getLastKnownLocation(options: opts)
        if let loc = loc as? [String: Any] {
            completion(.success(dictToTlLocation(loc)))
        } else {
            completion(.success(nil))
        }
    }

    func watchPosition(options: [String: Any?], completion: @escaping (Result<Int64, Error>) -> Void) {
        let opts = options.compactMapValues { $0 }
        let watchId = sdk.watchPosition(options: opts)
        completion(.success(Int64(watchId as? Int ?? -1)))
    }

    func stopWatchPosition(watchId: Int64, completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.stopWatchPosition(Int(watchId))
        completion(.success(result as? Bool ?? true))
    }

    func changePace(isMoving: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before changePace()", details: nil)))
            return
        }
        let result = sdk.changePace(isMoving)
        completion(.success(result as? Bool ?? true))
    }

    func getOdometer(completion: @escaping (Result<Double, Error>) -> Void) {
        completion(.success(sdk.getOdometer() as? Double ?? 0.0))
    }

    func setOdometer(value: Double, completion: @escaping (Result<TlLocation, Error>) -> Void) {
        let loc = sdk.setOdometer(value) as? [String: Any] ?? [:]
        completion(.success(dictToTlLocation(loc)))
    }

    // MARK: - Geofencing

    func addGeofence(geofence: TlGeofence, completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.addGeofence(tlGeofenceToDict(geofence))
        completion(.success(result as? Bool ?? true))
    }

    func addGeofences(geofences: [TlGeofence], completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.addGeofences(geofences.map(tlGeofenceToDict))
        completion(.success(result as? Bool ?? true))
    }

    func removeGeofence(identifier: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.removeGeofence(identifier)
        completion(.success(result as? Bool ?? true))
    }

    func removeGeofences(completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = sdk.removeGeofences()
        completion(.success(result as? Bool ?? true))
    }

    func getGeofences(completion: @escaping (Result<[TlGeofence], Error>) -> Void) {
        let raw = sdk.getGeofences() as? [[String: Any]] ?? []
        completion(.success(raw.map(dictToTlGeofence)))
    }

    func getGeofence(identifier: String, completion: @escaping (Result<TlGeofence?, Error>) -> Void) {
        let raw = sdk.getGeofence(identifier) as? [String: Any]
        completion(.success(raw.map(dictToTlGeofence)))
    }

    func geofenceExists(identifier: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.geofenceExists(identifier) as? Bool ?? false))
    }

    // MARK: - Persistence

    func getLocations(query: [String: Any?]?, completion: @escaping (Result<[TlLocation], Error>) -> Void) {
        let q = query?.compactMapValues { $0 }
        let raw = sdk.getLocations(query: q) as? [[String: Any]] ?? []
        completion(.success(raw.map(dictToTlLocation)))
    }

    func getCount(query: [String: Any?]?, completion: @escaping (Result<Int64, Error>) -> Void) {
        let q = query?.compactMapValues { $0 }
        completion(.success(Int64(sdk.getCount(query: q) as? Int ?? 0)))
    }

    func destroyLocations(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.destroyLocations() as? Bool ?? true))
    }

    func destroySyncedLocations(completion: @escaping (Result<Int64, Error>) -> Void) {
        completion(.success(Int64(sdk.destroySyncedLocations())))
    }

    func destroyLocation(uuid: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.destroyLocation(uuid) as? Bool ?? true))
    }

    func insertLocation(params: [String: Any?], completion: @escaping (Result<String, Error>) -> Void) {
        let p = params.compactMapValues { $0 }
        completion(.success(sdk.insertLocation(p) as? String ?? ""))
    }

    // MARK: - HTTP Sync

    func sync(completion: @escaping (Result<[TlLocation], Error>) -> Void) {
        sdk.sync { synced in
            let list = synced as? [[String: Any]] ?? []
            completion(.success(list.map { self.dictToTlLocation($0) }))
        }
    }

    func setDynamicHeaders(headers: [String: String], completion: @escaping (Result<Bool, Error>) -> Void) {
        sdk.setDynamicHeaders(headers)
        completion(.success(true))
    }

    func setRouteContext(context: [String: Any?], completion: @escaping (Result<Bool, Error>) -> Void) {
        let c = context.compactMapValues { $0 }
        sdk.setRouteContext(c)
        completion(.success(true))
    }

    func clearRouteContext(completion: @escaping (Result<Bool, Error>) -> Void) {
        sdk.clearRouteContext()
        completion(.success(true))
    }

    // MARK: - Permissions

    func getPermissionStatus(completion: @escaping (Result<TlAuthorizationStatus, Error>) -> Void) {
        let status = sdk.getPermissionStatus() as? Int ?? 0
        completion(.success(intToAuthStatus(status)))
    }

    func requestPermission(completion: @escaping (Result<TlAuthorizationStatus, Error>) -> Void) {
        sdk.permissionManager.requestPermission { status in
            let s = status as? Int ?? 0
            completion(.success(self.intToAuthStatus(s)))
        }
    }

    func getNotificationPermissionStatus(completion: @escaping (Result<Int64, Error>) -> Void) {
        completion(.success(3)) // Always granted on iOS
    }

    func requestNotificationPermission(completion: @escaping (Result<Int64, Error>) -> Void) {
        completion(.success(3)) // Always granted on iOS
    }

    func canScheduleExactAlarms(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(true)) // No restriction on iOS
    }

    func openExactAlarmSettings(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false)) // N/A on iOS
    }

    func getMotionPermissionStatus(completion: @escaping (Result<Int64, Error>) -> Void) {
        if let detector = sdk.motionDetector {
            completion(.success(Int64(detector.getMotionAuthorizationStatus())))
        } else {
            // Pre-ready: fall back to static CMMotionActivityManager check
            let status = CMMotionActivityManager.authorizationStatus()
            let code: Int64
            switch status {
            case .notDetermined: code = 0
            case .restricted:    code = 4
            case .denied:        code = 4
            case .authorized:    code = 3
            @unknown default:    code = 0
            }
            completion(.success(code))
        }
    }

    func requestMotionPermission(completion: @escaping (Result<Int64, Error>) -> Void) {
        guard let detector = sdk.motionDetector else {
            // Pre-ready: can't request without motionDetector
            completion(.success(0))
            return
        }
        detector.requestMotionPermission { status in
            completion(.success(Int64(status)))
        }
    }

    func requestTemporaryFullAccuracy(purpose: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        let result = sdk.permissionManager.requestTemporaryFullAccuracy(purposeKey: purpose)
        completion(.success(Int64(result as? Int ?? 0)))
    }

    // MARK: - Utility

    func isPowerSaveMode(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.isPowerSaveMode))
    }

    func getProviderState(completion: @escaping (Result<TlProviderChangeEvent, Error>) -> Void) {
        let state = sdk.getProviderState() as? [String: Any] ?? [:]
        completion(.success(dictToTlProviderState(state)))
    }

    func getDeviceInfo(completion: @escaping (Result<[String: Any?], Error>) -> Void) {
        var info = sdk.getDeviceInfo()
        info["framework"] = "flutter"
        completion(.success(info))
    }

    func getSensors(completion: @escaping (Result<[String: Any?], Error>) -> Void) {
        completion(.success(sdk.getSensors() as? [String: Any] ?? [:]))
    }

    func playSound(name: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.playSound(name) as? Bool ?? true))
    }

    func isIgnoringBatteryOptimizations(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(true)) // Always true on iOS
    }

    func requestSettings(action: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.permissionManager.showLocationSettings() as? Bool ?? false))
    }

    func showSettings(action: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let result = action == "app"
            ? sdk.permissionManager.showAppSettings()
            : sdk.permissionManager.showLocationSettings()
        completion(.success(result as? Bool ?? false))
    }

    func getSettingsHealth(completion: @escaping (Result<[String: Any?], Error>) -> Void) {
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

    func getLog(query: [String: Any?]?, completion: @escaping (Result<String, Error>) -> Void) {
        let q = query?.compactMapValues { $0 }
        completion(.success(sdk.getLog(query: q)))
    }

    func destroyLog(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.destroyLog() as? Bool ?? true))
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

    func registerHeadlessTask(callbackIds: [Int64], completion: @escaping (Result<Bool, Error>) -> Void) {
        let registrationId = callbackIds.first ?? -1
        let dispatchId = callbackIds.last ?? -1
        headlessRunner.registerCallbacks(registrationId, dispatchId)
        completion(.success(true))
    }

    func registerHeadlessHeadersCallback(callbackIds: [Int64], completion: @escaping (Result<Bool, Error>) -> Void) {
        storeHeadlessCallback(callbackIds, key: "headlessHeaders")
        completion(.success(true))
    }

    func registerHeadlessSyncBodyBuilder(callbackIds: [Int64], completion: @escaping (Result<Bool, Error>) -> Void) {
        storeHeadlessCallback(callbackIds, key: "headlessSyncBody")
        completion(.success(true))
    }

    private func storeHeadlessCallback(_ callbackIds: [Int64], key: String) {
        let registrationId = callbackIds.first ?? -1
        let dispatchId = callbackIds.last ?? -1
        let defaults = UserDefaults.standard
        defaults.set(registrationId, forKey: "com.tracelet.headless.\(key)_registrationId")
        defaults.set(dispatchId, forKey: "com.tracelet.headless.\(key)_dispatchId")
    }

    // MARK: - Enterprise: Audit Trail

    func verifyAuditTrail(completion: @escaping (Result<[String: Any?], Error>) -> Void) {
        completion(.success(sdk.verifyAuditTrail() as? [String: Any] ?? [:]))
    }

    func getAuditProof(uuid: String, completion: @escaping (Result<[String: Any?]?, Error>) -> Void) {
        completion(.success(sdk.getAuditProof(uuid) as? [String: Any]))
    }

    // MARK: - Enterprise: Privacy Zones

    func addPrivacyZone(zone: [String: Any?], completion: @escaping (Result<Bool, Error>) -> Void) {
        let z = zone.compactMapValues { $0 }
        completion(.success(sdk.addPrivacyZone(z) as? Bool ?? true))
    }

    func addPrivacyZones(zones: [[String: Any?]], completion: @escaping (Result<Bool, Error>) -> Void) {
        let zs = zones.map { $0.compactMapValues { $0 } }
        completion(.success(sdk.addPrivacyZones(zs) as? Bool ?? true))
    }

    func removePrivacyZone(identifier: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.removePrivacyZone(identifier) as? Bool ?? true))
    }

    func removePrivacyZones(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.removePrivacyZones() as? Bool ?? true))
    }

    func getPrivacyZones(completion: @escaping (Result<[[String: Any?]], Error>) -> Void) {
        completion(.success(sdk.getPrivacyZones() as? [[String: Any]] ?? []))
    }

    // MARK: - Enterprise: Encrypted Database

    func isDatabaseEncrypted(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.database.isDatabaseEncrypted()))
    }

    func encryptDatabase(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.database.encryptDatabase()))
    }

    // MARK: - Enterprise: Device Attestation

    func getAttestationToken(completion: @escaping (Result<[String: Any?]?, Error>) -> Void) {
        sdk.getAttestationToken { token in
            DispatchQueue.main.async {
                completion(.success(token as? [String: Any]))
            }
        }
    }

    // MARK: - Enterprise: Carbon Estimator

    func getCarbonReport(query: [String: Any?]?, completion: @escaping (Result<[String: Any?], Error>) -> Void) {
        let q = query?.compactMapValues { $0 }
        completion(.success(sdk.getCarbonReport(query: q) as? [String: Any] ?? [:]))
    }

    // MARK: - Enterprise: Dead Reckoning

    func getDeadReckoningState(completion: @escaping (Result<[String: Any?]?, Error>) -> Void) {
        completion(.success(sdk.getDeadReckoningState() as? [String: Any]))
    }
}
