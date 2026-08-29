import Flutter
import UIKit
import CoreMotion
#if canImport(TraceletSDK)
import TraceletSDK
#endif

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
        dict["desiredAccuracy"] = c.geo.desiredAccuracy?.rawValue
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
        dict["periodicDesiredAccuracy"] = c.geo.periodicDesiredAccuracy?.rawValue
        dict["enableSparseUpdates"] = c.geo.enableSparseUpdates
        dict["sparseDistanceThreshold"] = c.geo.sparseDistanceThreshold
        dict["sparseMaxIdleSeconds"] = c.geo.sparseMaxIdleSeconds
        dict["batteryBudgetPerHour"] = c.geo.batteryBudgetPerHour
        dict["enableDeadReckoning"] = c.geo.enableDeadReckoning
        dict["deadReckoningActivationDelay"] = c.geo.deadReckoningActivationDelay
        dict["deadReckoningMaxDuration"] = c.geo.deadReckoningMaxDuration
        dict["resolveAddress"] = c.geo.resolveAddress

        var filterDict = [String: Any]()
        filterDict["trackingAccuracyThreshold"] = c.geo.filter?.trackingAccuracyThreshold
        filterDict["maxImpliedSpeed"] = c.geo.filter?.maxImpliedSpeed
        filterDict["odometerAccuracyThreshold"] = c.geo.filter?.odometerAccuracyThreshold
        filterDict["policy"] = c.geo.filter?.policy?.rawValue
        filterDict["rejectMockLocations"] = c.geo.filter?.rejectMockLocations
        filterDict["mockDetectionLevel"] = c.geo.filter?.mockDetectionLevel
        filterDict["useKalmanFilter"] = c.geo.filter?.useKalmanFilter
        dict["filter"] = filterDict

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
        // NOTE: the legacy Android-only `c.android.geofenceModeHighAccuracy` is no
        // longer read directly on iOS (that leak caused the always-on indicator —
        // Issue #210). High-accuracy geofencing is now driven by the cross-platform
        // GeofenceConfig flag, handled in the Geofence section below.
        dict["periodicUseForegroundService"] = c.android.periodicUseForegroundService
        dict["periodicUseExactAlarms"] = c.android.periodicUseExactAlarms
        dict["scheduleUseAlarmManager"] = c.android.scheduleUseAlarmManager

        // iOS
        dict["activityType"] = c.ios.activityType?.rawValue
        dict["useSignificantChangesOnly"] = c.ios.useSignificantChangesOnly
        dict["showsBackgroundLocationIndicator"] = c.ios.showsBackgroundLocationIndicator
        dict["pausesLocationUpdatesAutomatically"] = c.ios.pausesLocationUpdatesAutomatically
        // nil means the caller never set it, so the key is omitted and the
        // persisted value survives the merge (#321).
        dict["locationAuthorizationRequest"] = c.ios.locationAuthorizationRequest
            .map { $0 == .always ? "Always" : "WhenInUse" }
        dict["disableLocationAuthorizationAlert"] = c.ios.disableLocationAuthorizationAlert
        dict["preventSuspend"] = c.ios.preventSuspend
        dict["useBackgroundActivitySession"] = c.ios.useBackgroundActivitySession
        if let liveConfig = c.ios.liveActivityConfig {
            var liveActivityDict: [String: Any] = [:]
            if let title = liveConfig.title {
                liveActivityDict["title"] = title
            }
            if let body = liveConfig.body {
                liveActivityDict["body"] = body
            }
            if let startedAt = liveConfig.startedAt {
                liveActivityDict["startedAt"] = startedAt
            }
            if let showTimer = liveConfig.showTimer {
                liveActivityDict["showTimer"] = showTimer
            }
            dict["liveActivityConfig"] = liveActivityDict
        }

        // HTTP
        if let url = c.http.url { dict["url"] = url }
        dict["method"] = c.http.method?.rawValue
        if let headers = c.http.headers { dict["headers"] = headers.compactMapValues { $0 } }
        if let params = c.http.params { dict["params"] = params.compactMapValues { $0 } }
        if let extras = c.http.extras { dict["extras"] = extras.compactMapValues { $0 } }
        if let rootProp = c.http.httpRootProperty { dict["httpRootProperty"] = rootProp }
        if let sslFingerprints = c.http.sslPinningFingerprints { dict["sslPinningFingerprints"] = sslFingerprints.compactMap { $0 } }
        if let sslCertificates = c.http.sslPinningCertificates { dict["sslPinningCertificates"] = sslCertificates.compactMap { $0 } }
        dict["autoSync"] = c.http.autoSync
        dict["batchSync"] = c.http.batchSync
        dict["maxBatchSize"] = c.http.maxBatchSize
        dict["autoSyncThreshold"] = c.http.autoSyncThreshold
        if let autoSyncDelay = c.http.autoSyncDelay { dict["autoSyncDelay"] = autoSyncDelay }
        dict["syncInterval"] = c.http.syncInterval
        dict["httpTimeout"] = c.http.httpTimeout
        dict["locationsOrderDirection"] = c.http.locationsOrderDirection?.rawValue
        dict["disableAutoSyncOnCellular"] = c.http.disableAutoSyncOnCellular
        dict["maxRetries"] = c.http.maxRetries
        dict["retryBackoffBase"] = c.http.retryBackoffBase
        dict["retryBackoffCap"] = c.http.retryBackoffCap
        dict["enableDeltaCompression"] = c.http.enableDeltaCompression
        dict["deltaCoordinatePrecision"] = c.http.deltaCoordinatePrecision
        dict["syncTelematics"] = c.http.syncTelematics
        if let telematicsUrl = c.http.telematicsUrl { dict["telematicsUrl"] = telematicsUrl }

        // Logger
        dict["logLevel"] = c.logger.logLevel?.rawValue
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
        if let activityTypes = c.motion.activityTypes { dict["activityTypes"] = activityTypes.compactMap { $0?.rawValue } }
        dict["stationaryRadius"] = c.motion.stationaryRadius
        // #261: `useSignificantChangesOnly` is defined on BOTH IosConfig and
        // MotionConfig, and both flatten to this same native key. The iOS
        // section already wrote `c.ios.useSignificantChangesOnly` above; writing
        // the motion value here unconditionally CLOBBERED it, so a user-set
        // `ios: IosConfig(useSignificantChangesOnly: true)` was overwritten by a
        // default-false MotionConfig. Combine them so a `true` from either
        // source is honored (the native SDK exposes a single flag).
        // #321: emit only when at least one side was actually supplied, so an
        // untouched flag is not rewritten with a default-derived `false`.
        if c.ios.useSignificantChangesOnly != nil || c.motion.useSignificantChangesOnly != nil {
            dict["useSignificantChangesOnly"] =
                (c.ios.useSignificantChangesOnly ?? false)
                    || (c.motion.useSignificantChangesOnly ?? false)
        }
        // Sensor thresholds are only forwarded when the app set them. Sending them
        // unconditionally overrode the iOS-tuned defaults with Dart's (Android)
        // values: 0.4 m/s² became 0.04 g, roughly four times stricter than the
        // 0.15 g iOS default. Absent key ⇒ ConfigManager's own default applies.
        if let shakeThreshold = c.motion.shakeThreshold {
            dict["shakeThreshold"] = shakeThreshold
        }
        if let stillThreshold = c.motion.stillThreshold {
            dict["stillThreshold"] = stillThreshold
        }
        if let stillSampleCount = c.motion.stillSampleCount {
            dict["stillSampleCount"] = stillSampleCount
        }
        dict["motionDetectionMode"] = c.motion.motionDetectionMode?.rawValue
        dict["speedMovingThreshold"] = c.motion.speedMovingThreshold
        dict["speedStationaryDelay"] = c.motion.speedStationaryDelay
        dict["stationaryTrackingMode"] = c.motion.stationaryTrackingMode?.rawValue
        dict["stationaryPeriodicInterval"] = c.motion.stationaryPeriodicInterval
        dict["stationaryPeriodicAccuracy"] = c.motion.stationaryPeriodicAccuracy?.rawValue
        dict["speedWakeConfirmCount"] = c.motion.speedWakeConfirmCount

        // Geofence
        dict["geofenceInitialTriggerEntry"] = c.geofence.geofenceInitialTriggerEntry
        dict["geofenceProximityRadius"] = c.geofence.geofenceProximityRadius
        dict["geofenceInitialTrigger"] = c.geofence.geofenceInitialTrigger
        // Tunes the accuracy-aware EXIT gating (#274/#276): -1 full gating
        // (default), 0 disabled, N>0 clamp accuracy to N meters.
        dict["geofenceExitAccuracyMax"] = c.geofence.geofenceExitAccuracyMax
        // High-accuracy geofencing: cross-platform GeofenceConfig flag, OR'd with
        // the deprecated Android-only flag for backward compatibility. When true,
        // iOS evaluates transitions from continuous GPS (reliable tight radii /
        // EXIT) and the system location indicator is expected (Issue #210).
        dict["geofenceModeHighAccuracy"] =
            (c.geofence.geofenceModeHighAccuracy ?? false) || (c.android.geofenceModeHighAccuracy ?? false)

        // Persistence
        dict["persistMode"] = c.persistence.persistMode?.rawValue
        dict["maxDaysToPersist"] = c.persistence.maxDaysToPersist
        dict["maxRecordsToPersist"] = c.persistence.maxRecordsToPersist
        dict["disableProviderChangeRecord"] = c.persistence.disableProviderChangeRecord

        // Security
        dict["encryptDatabase"] = c.security.encryptDatabase

        // Audit
        dict["auditEnabled"] = c.audit.enabled
        dict["auditHashAlgorithm"] = c.audit.hashAlgorithm?.rawValue

        // Privacy Zone
        dict["privacyZoneEnabled"] = c.privacyZone.enabled

        // Attestation
        dict["attestationEnabled"] = c.attestation.enabled
        dict["attestationRefreshInterval"] = c.attestation.refreshInterval

        // Impact / crash & fall detection (#183). Flattened so the iOS
        // ConfigManager + ImpactDetector pick these up (parity with Android).
        dict["enableCrashDetection"] = c.impact.enableCrashDetection
        dict["enableFallDetection"] = c.impact.enableFallDetection
        dict["crashGThreshold"] = c.impact.crashGThreshold
        dict["crashMinSpeedKmh"] = c.impact.crashMinSpeedKmh
        dict["fallGThreshold"] = c.impact.fallGThreshold
        dict["confirmWindowMs"] = c.impact.confirmWindowMs
        dict["minImpactConfidence"] = c.impact.minImpactConfidence
        dict["crashModelUrl"] = c.impact.crashModelUrl
        dict["crashModelSha256"] = c.impact.crashModelSha256
        dict["crashModelThreshold"] = c.impact.crashModelThreshold
        dict["crashModelUnlockUrl"] = c.impact.crashModelUnlockUrl
        dict["crashModelLicenseKey"] = c.impact.crashModelLicenseKey

        // Transport-mode classifier. Flattened so the iOS ConfigManager picks
        // these up (parity with Android). This section was previously dropped
        // entirely, which made `enableFusedClassifier` undeliverable from
        // Flutter on iOS — and with it `autoTuneFromTransportMode` (#299).
        dict["enableFusedClassifier"] = c.classifier.enableFusedClassifier
        dict["fusedClassifierAuthoritative"] = c.classifier.fusedClassifierAuthoritative
        dict["modeSwitchDwellMs"] = c.classifier.modeSwitchDwellMs
        dict["minModeConfidence"] = c.classifier.minModeConfidence
        dict["autoTuneFromTransportMode"] = c.classifier.autoTuneFromTransportMode

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

    // `internal` (not private) so the regression tests can verify the native-map
    // → Pigeon field contract directly (#175).
    func dictToTlLocation(_ d: [String: Any]) -> TlLocation {
        let coords = d["coords"] as? [String: Any] ?? [:]
        let battery = d["battery"] as? [String: Any] ?? [:]
        let activity = d["activity"] as? [String: Any]

        // #280: TlLocation has no locationSource/reducedAccuracy fields, so carry
        // them through `extras` — the same transport the live onLocation path
        // uses (EventDispatcher.mapToTlLocation) and that Location.fromMap
        // unpacks. Without this, getLocations()/sync drop the DB-restored
        // classification and report the "unknown"/false defaults.
        var extras = d["extras"] as? [String?: Any?] ?? [:]
        if let source = d["locationSource"] as? String {
            extras["locationSource"] = source
        }
        if let reduced = d["reducedAccuracy"] as? Bool {
            extras["reducedAccuracy"] = reduced
        }

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
                // Native emits snake_case `is_charging`; accept both for safety.
                isCharging: (battery["is_charging"] ?? battery["isCharging"]) as? Bool ?? false
            ),
            timestamp: d["timestamp"] as? String ?? "",
            uuid: d["uuid"] as? String ?? "",
            // Native emits snake_case `is_moving`; accept both for safety.
            isMoving: (d["is_moving"] ?? d["isMoving"]) as? Bool ?? false,
            odometer: d["odometer"] as? Double ?? 0.0,
            event: d["event"] as? String,
            activity: activity.map {
                TlActivity(
                    type: $0["type"] as? String ?? "unknown",
                    confidence: Int64($0["confidence"] as? Int ?? 0)
                )
            },
            extras: extras.isEmpty ? nil : extras,
            address: (d["address"] as? [String: Any]).map { addr in
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

    // internal (not private) so completeness guards in tests can call it (#206).
    func tlGeofenceToDict(_ g: TlGeofence) -> [String: Any] {
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

    // internal (not private) so completeness guards in tests can call it (#206).
    func optionsToDict(_ o: TlCurrentPositionOptions) -> [String: Any] {
        var d: [String: Any] = [
            "timeout": o.timeout,
            "maximumAge": o.maximumAge,
            "persist": o.persist,
            "samples": o.samples,
        ]
        if let accuracy = o.desiredAccuracy { d["desiredAccuracy"] = accuracy.rawValue }
        if let target = o.accuracyTarget { d["accuracyTarget"] = target }
        if let requestId = o.requestId { d["requestId"] = requestId }
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
        switch value {
        case 0: return .notDetermined
        case 2: return .whenInUse
        case 3: return .always
        case 4: return .deniedForever
        default: return .notDetermined
        }
    }

    // MARK: - Lifecycle

    func requestStateFlush() throws {
        sdk.requestStateFlush()
    }

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
        // No isReadyState guard — stop() must work before ready() so the user
        // can halt tracking that was auto-resumed after a killed-state relaunch.
        // The SDK is initialize()d at plugin registration, so this is safe.
        // (Matches Android: TraceletHostApiImpl.stop has no readiness guard.)
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
        // No isReadyState guard — getState() must report the real persisted
        // state before ready() so a relaunched app can restore its UI
        // (see killed-state restart support; matches Android behavior).
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

    func updateNotification(completion: @escaping (Result<Void, Error>) -> Void) {
        // #257: iOS has no foreground-service notification. Its analogue is the
        // optional Live Activity: if the developer opted into one via
        // liveActivityConfig and it is currently running, refresh its content
        // from the latest config. Otherwise this is a safe no-op. Never restarts
        // tracking. No isReadyState guard so it degrades to a no-op rather than
        // throwing when called before ready().
        sdk.updateNotification()
        completion(.success(()))
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

    func cancelCurrentPosition(requestId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.cancelCurrentPosition(requestId)))
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

    func updateLocationProviderOptions(
        desiredAccuracy: TlDesiredAccuracy?,
        distanceFilter: Double?,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard sdk.isReadyState else {
            completion(.failure(PigeonError(code: "NOT_READY", message: "Call ready() before updateLocationProviderOptions()", details: nil)))
            return
        }
        let result = sdk.updateLocationProviderOptions(
            desiredAccuracy: desiredAccuracy.flatMap {
                TraceletDesiredAccuracy(rawValue: $0.rawValue)
            },
            distanceFilter: distanceFilter
        )
        completion(.success(result))
    }

    func confirmImpact(id: Int64) throws -> Bool {
        return sdk.isReadyState ? sdk.confirmImpact(id) : false
    }

    func cancelImpact(id: Int64) throws -> Bool {
        return sdk.isReadyState ? sdk.cancelImpact(id) : false
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
        TraceletSdk.shared.logger.debug("requestPermission called")
        DispatchQueue.main.async {
            let requestAlways = self.sdk.configManager.getLocationAuthorizationRequest() == "Always"
            self.sdk.permissionManager.requestPermission(requestAlways: requestAlways) { status in
                let statusInt = status as? Int ?? 0
                let result = self.intToAuthStatus(statusInt)
                TraceletSdk.shared.logger.debug("requestPermission result: \(statusInt) -> \(result)")
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
        TraceletSdk.shared.logger.debug("requestMotionPermission called")
        DispatchQueue.main.async {
            detector.requestMotionPermission { status in
                TraceletSdk.shared.logger.debug("requestMotionPermission result: \(status)")
                completion(.success(self.intToMotionStatus(status)))
            }
        }
    }

    func requestTemporaryFullAccuracy(purpose: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        TraceletSdk.shared.logger.debug("requestTemporaryFullAccuracy called for purpose: \(purpose)")
        DispatchQueue.main.async {
            let result = self.sdk.permissionManager.requestTemporaryFullAccuracy(purposeKey: purpose)
            let resInt = result as? Int ?? 0
            TraceletSdk.shared.logger.debug("requestTemporaryFullAccuracy result: \(resInt)")
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

    func getForegroundServiceHealth(completion: @escaping (Result<[String?: Any?], Error>) -> Void) {
        // iOS has no foreground service — there is no promotion that can fail
        // after the fact (see #253/#254). Report the desired state alongside
        // whether location tracking is actually active, so cross-platform code
        // can consume the same shape. `serviceForeground` and the promotion
        // fields are always null/false on iOS.
        let state = sdk.getState()
        completion(.success([
            "desiredEnabled": state["enabled"] as? Bool ?? false,
            "foregroundServiceEnabled": false,
            "serviceRunning": state["enabled"] as? Bool ?? false,
            "serviceForeground": false,
            "foregroundNotificationId": nil,
            "lastForegroundPromotionResult": nil,
            "lastForegroundPromotionFailureClass": nil,
            "lastForegroundPromotionFailureMessage": nil,
            "lastForegroundTransitionAt": nil,
            "platform": "ios",
        ]))
    }

    /// Reports the thresholds actually in force in the Rust processor (#303).
    ///
    /// Read back from the processor rather than from ConfigManager: those two
    /// could silently disagree, which is the whole bug #303 fixed, so a getter
    /// that answered from config would be unable to detect a regression. Nil
    /// before a processor exists, and while a transport-mode auto-tune is in
    /// force these are the tuned values, not the configured ones.
    func getCurrentLocationTuning(
        completion: @escaping (Result<TlLocationTuning?, Error>) -> Void
    ) {
        guard let t = sdk.getCurrentLocationTuning() else {
            return completion(.success(nil))
        }
        completion(.success(TlLocationTuning(
            distanceFilter: t.distanceFilter,
            trackingAccuracyThreshold: Int64(t.trackingAccuracyThreshold),
            odometerAccuracyThreshold: Int64(t.odometerAccuracyThreshold),
            maxImpliedSpeed: Int64(t.maxImpliedSpeed)
        )))
    }

    func openOemSettings(label: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false)) // N/A on iOS
    }

    func showPowerManager(completion: @escaping (Result<Bool, Error>) -> Void) {
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

    // MARK: - Telematics

    func getTelematicsEvents(limit: Int64, completion: @escaping (Result<[TlTelematicsRecord?], Error>) -> Void) {
        let events = sdk.getTelematicsEvents(limit: Int(limit))
        let mapped = events.map { e in
            TlTelematicsRecord(
                id: e.id,
                eventType: e.eventType,
                severity: e.severity,
                // #367: the magnitudes behind the normalized severity.
                speed: e.speed,
                value: e.value,
                latitude: e.latitude,
                longitude: e.longitude,
                timestamp: e.timestamp,
                synced: e.synced,
                // #402: the trip this event was recorded during.
                tripId: e.tripId
            )
        }
        completion(.success(mapped))
    }

    func destroyTelematicsEvents(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.destroyTelematicsEvents()))
    }

    func simulateTelematicsEvent(eventType: String, severity: Double, latitude: Double, longitude: Double, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.simulateTelematicsEvent(eventType: eventType, severity: severity, latitude: latitude, longitude: longitude)))
    }

    func debugRunCrashModelInference(peakG: Double, speedKmh: Double, crashLike: Bool, completion: @escaping (Result<[String: Any?], Error>) -> Void) {
        completion(.success(sdk.debugRunCrashModelInference(peakG, speedKmh, crashLike)))
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
        headlessRunner.registerCallbacks(type: .main, registrationId, dispatchId)
        completion(.success(true))
    }

    func registerHeadlessHeadersCallback(callbackIds: [Int64?], completion: @escaping (Result<Bool, Error>) -> Void) {
        let validIds = callbackIds.compactMap { $0 }
        let registrationId = validIds.first ?? -1
        let dispatchId = validIds.last ?? -1
        headlessRunner.registerCallbacks(type: .headers, registrationId, dispatchId)
        completion(.success(true))
    }

    func registerHeadlessSyncBodyBuilder(callbackIds: [Int64?], completion: @escaping (Result<Bool, Error>) -> Void) {
        let validIds = callbackIds.compactMap { $0 }
        let registrationId = validIds.first ?? -1
        let dispatchId = validIds.last ?? -1
        headlessRunner.registerCallbacks(type: .syncBody, registrationId, dispatchId)
        completion(.success(true))
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

    func getPrivacyZones(completion: @escaping (Result<[Any?], Error>) -> Void) {
        completion(.success(sdk.getPrivacyZones()))
    }

    // MARK: - Enterprise: Encrypted Database

    func isDatabaseEncrypted(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.isDatabaseEncrypted()))
    }

    func encryptDatabase(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(sdk.encryptDatabase()))
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

    func getCarbonReport(query: [String: Any?]?, completion: @escaping (Result<[String: Any?], Error>) -> Void) {
        do {
            let nonOptionalQuery = query?.reduce(into: [String: Any]()) { result, pair in
                if let value = pair.value {
                    result[pair.key] = value
                }
            }
            let report = try sdk.getCarbonReport(query: nonOptionalQuery)
            let resultReport = report.reduce(into: [String: Any?]()) { result, pair in
                result[pair.key] = pair.value
            }
            completion(.success(resultReport))
        } catch {
            completion(.failure(error))
        }
    }

    func getLogs(limit: Int64, completion: @escaping (Result<[TlLogEntry?], Error>) -> Void) {
        let records = sdk.getLogs(limit: Int(limit))
        let mapped = records.map { r in
            TlLogEntry(
                id: Int64(r.id),
                level: r.level,
                message: r.message,
                timestamp: r.timestamp
            )
        }
        completion(.success(mapped))
    }

    func clearLogs(completion: @escaping (Result<Void, Error>) -> Void) {
        sdk.clearLogs()
        completion(.success(()))
    } 

    // MARK: - Enterprise: Dead Reckoning

    func getDeadReckoningState(completion: @escaping (Result<[String?: Any?]?, Error>) -> Void) {
        completion(.success(sdk.getDeadReckoningState()))
    }
}
