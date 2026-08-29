import Foundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

/// Main entry point for the Tracelet Background Geolocation SDK.
///
/// Usage (Swift):
/// ```swift
/// let sdk = TraceletSdk.shared
/// sdk.delegate = self
/// sdk.ready(config: ["geo": ["distanceFilter": 10]])
/// sdk.start()
/// ```
///
/// Usage (Objective-C):
/// ```objc
/// TraceletSdk *sdk = [TraceletSdk shared];
/// sdk.delegate = self;
/// [sdk readyWithConfig:@{@"geo": @{@"distanceFilter": @10}}];
/// [sdk start];
/// ```
///
/// This class orchestrates all subsystems: location engine, motion detector,
/// geofence manager, HTTP sync, database, and scheduling. It is
/// framework-agnostic and can be used from Flutter, React Native, Capacitor,
/// or native iOS apps.
///
/// The API surface mirrors the Dart `Tracelet` class so developers switching
/// between Flutter and native iOS have a familiar interface.
public protocol SyncProvider {
    func syncBatchBlocking(config: HttpConfig, records: [DbLocationRecord]) throws -> UInt32
    /// Cancel any pending (debounced) auto-sync so stop() takes effect
    /// immediately (#213). Default no-op for providers without a debounce.
    func cancelPendingSync()
    /// POST `body` to `url` — the separate telematics endpoint (#368). Returns
    /// whether the server accepted it; `false` leaves the events unsynced for
    /// the next attempt.
    func postTelematicsBlocking(config: HttpConfig, url: String, body: String) throws -> Bool
}

public extension SyncProvider {
    func cancelPendingSync() {}

    /// Defaults to "not delivered" so a provider that hasn't implemented it
    /// can't settle events it never sent (#366). Only reached when
    /// `telematicsUrl` is set, so existing providers are unaffected.
    func postTelematicsBlocking(config: HttpConfig, url: String, body: String) throws -> Bool { false }
}

public final class TraceletSdk {

    // MARK: - Singleton

    /// The shared singleton instance.
    public static let shared = TraceletSdk()

    public var syncProvider: SyncProvider? = nil {
        didSet {
            // Replacing a provider must detach the old one (parity with Android's
            // registerSyncProvider, #204/#286). Without this, a superseded
            // provider — e.g. the NativeSyncProvider created during a background
            // boot, or a sink left behind by an earlier engine — stayed
            // subscribed and independently debounced + POSTed the same batch.
            if let previous = oldValue,
               (previous as AnyObject) !== (syncProvider as AnyObject?) {
                previous.cancelPendingSync()
                if let previousSink = previous as? LocationDataSink {
                    locationEngine?.unregisterSink(previousSink)
                }
            }
            if let sink = syncProvider as? LocationDataSink {
                locationEngine?.registerSink(sink)
            }
        }
    }

    public var dartSyncInterceptor: DartSyncInterceptor? = nil

    // MARK: - Delegate

    /// Delegate that receives all tracking events (location, motion, geofence, etc.).
    ///
    /// Set this before calling ``ready(config:)`` to receive all events.
    public weak var delegate: TraceletDelegate? {
        didSet { delegateEventSender.delegate = delegate }
    }

    // MARK: - Subsystems

    public private(set) var configManager: ConfigManager!
    public private(set) var stateManager: StateManager!
    
    public private(set) var locationEngine: LocationEngine!
    public private(set) var motionDetector: MotionDetector!
    public private(set) var speedMotionManager: SpeedMotionManager?
    public private(set) var geofenceManager: GeofenceManager!
    public private(set) var smartMotionCoordinator: TraceletSmartMotionCoordinator!
    public private(set) var scheduleManager: ScheduleManager!
    public private(set) var logger: TraceletLogger!
    public private(set) var soundManager: SoundManager!
    public private(set) var permissionManager: TraceletPermissionManager = TraceletPermissionManager()
    public private(set) var auditTrailManager: AuditTrailManager!
    public private(set) var privacyZoneManager: PrivacyZoneManager!
    public private(set) var deviceAttestor: DeviceAttestor!
    public private(set) var remoteConfigManager: RemoteConfigManager!
    public private(set) var preventSuspendManager: PreventSuspendManager!
    public private(set) var backgroundActivitySessionManager: BackgroundActivitySessionManager!
    public private(set) var serviceSessionManager: ServiceSessionManager!
    public private(set) var periodicRefreshScheduler: PeriodicRefreshScheduler!

    // MARK: - Rust Core subsystems
    public private(set) var rustDatabase: DatabaseManager?
    public private(set) var rustEngineState: EngineState?
    public private(set) var rustPluginEventDispatcher: EventDispatcher?

    private let delegateEventSender = DelegateEventSender()
    private var eventSender: TraceletEventSending
    private var heartbeatTimer: Timer?
    private var stopAfterElapsedTimer: Timer?
    private var syncIntervalTimer: Timer?
    private var isReady = false

    /// Running total of locations synced-and-pruned since the last
    /// `destroySyncedLocations()` call (#154).
    private let syncedLocationsLock = NSLock()
    private var syncedLocationsRemoved: Int = 0

    // Algorithms
    public private(set) var tripManager: TraceletTripManager!
    private var batteryBudgetEngine: TraceletBatteryBudgetEngine?
    private var batteryBudgetTimer: Timer?

    /// Battery budget sampling interval: 5 minutes.
    private static let batterySampleInterval: TimeInterval = 5 * 60

    // 3.3.0 behavior engines (opt-in, default off)
    private var telematicsEngine: TelematicsEngine?
    private var transportClassifier: TransportModeClassifier?
    private var impactDetector: ImpactDetector?
    private var accelBuffer: [Double] = []
    private let accelBufferLock = NSLock()
    private var gyroBuffer: [Double] = []
    private let gyroBufferLock = NSLock()
    private var rawAccelBuffer: [Double] = []
    private let rawAccelBufferLock = NSLock()
    // #173 barometer cue: ambient-pressure samples (hPa). Empty on devices with
    // no barometer, in which case the cabin-pressure cue simply never fires.
    private var baroBuffer: [Double] = []
    private let baroBufferLock = NSLock()
    private var accelWindowTimer: Timer?
    private var impactConfirmTimer: Timer?
    private var lastSpeedMps: Double = 0

    /// Speed (m/s) of the most recent **raw** fix, fed by `LocationEngine.rawSpeedSink`.
    ///
    /// Only the transport classifier reads this. Telematics and impact detection
    /// deliberately keep using `lastSpeedMps` (accepted fixes) — their thresholds
    /// are calibrated against filtered speeds.
    private var lastRawSpeedMps: Double = 0
    private var lastLat: Double = 0
    private var lastLng: Double = 0
    private static let accelWindowInterval: TimeInterval = 1.0
    // #181: delay before sampling post-impact GPS speed for Δv corroboration.
    private static let crashDvDelaySeconds: TimeInterval = 2.0
    // #182: margin after a candidate's deadline before the safety-net fires, so
    // the in-process confirmation reliably wins the race when the app is alive.
    private static let crashConfirmGuardMs: Int64 = 3_000

    // #183 opt-in ML crash model; nil ⇒ rule engine. Loaded off the main thread.
    //
    // #311: written from the loader's background queue and read from the main
    // run loop (the accel-window Timer), so every access goes through
    // `crashModelLock`. Without it this is an unsynchronised cross-thread ARC
    // retain/release on a class reference — a crash risk, not just a stale read.
    // Android guards the same field with `@Volatile`.
    private var _crashModel: CrashModel?
    private let crashModelLock = NSLock()
    private var crashModel: CrashModel? {
        get { crashModelLock.lock(); defer { crashModelLock.unlock() }; return _crashModel }
        set { crashModelLock.lock(); _crashModel = newValue; crashModelLock.unlock() }
    }
    // Recent GPS speed history (timestamp ms, km/h) for the model's speed_max/dv
    // features over the same ~16 s window the crash model was trained on.
    private let crashSpeedWindowMs: Int64 = 16_000
    private var speedHistory: [(Int64, Double)] = []
    private let speedHistoryLock = NSLock()

    /// One processed accel window's model features (#310).
    ///
    /// The model was trained on scalars reduced from a fixed **16 s** event
    /// window, but detection runs every `accelWindowInterval`. Keeping the
    /// per-window features lets `crashFeatureVector` aggregate back up to the
    /// training window while the detector still evaluates once a second.
    private struct AccelWindowFeatures {
        let timestampMs: Int64
        let peakG: Double
        let meanG: Double
        let gyroPeakDps: Double
    }

    /// Rolling ~16 s history of per-window accel/gyro features (#310).
    ///
    /// `peak_g`, `mean_g` and `gyro_peak_dps` used to be taken from the single
    /// 1 s window being scored, while `speed_max`/`dv` came from the 16 s
    /// `speedHistory` — so the model saw a feature vector straddling two time
    /// bases, none of it matching how it was trained. `mean_g` was the worst
    /// offender: the mean over the 1 s window containing a spike is nothing like
    /// the mean over 16 s of driving.
    private var crashFeatureHistory: [AccelWindowFeatures] = []
    private let crashFeatureHistoryLock = NSLock()

    /// How far back `preImpactSpeedMps` looks for the speed the vehicle was
    /// carrying into an impact (#312).
    ///
    /// A crash collapses speed within 1–2 s and GPS arrives at ~1 Hz, so the
    /// "current" speed at the moment a window is scored can already be the
    /// post-impact one. Short enough that it is still *this* event's speed, long
    /// enough to survive a fix or two of collapse.
    private let crashPreImpactWindowMs: Int64 = 3_000

    /// Whether ``ready(config:)`` has been called.
    public var isReadyState: Bool { isReady }

    /// Test seam: whether the battery-budget engine is currently built/active.
    /// Exposed so regression tests can assert that a runtime `setConfig()` (the
    /// remote-config apply path) actually (re)builds the engine when
    /// `batteryBudgetPerHour` changes — see `applyBatteryBudgetConfig()`.
    var isBatteryBudgetEngineActive: Bool { batteryBudgetEngine != nil }

    private init() {
        eventSender = delegateEventSender
        delegateEventSender.sdk = self
    }

    // MARK: - Event Sender (for framework bridges)

    /// Returns the internal ``TraceletEventSending`` for use by framework bridges.
    ///
    /// Flutter, React Native, and other bridges provide their own event sender
    /// implementation via this accessor, bypassing the delegate pattern.
    public func getEventSender() -> TraceletEventSending {
        return eventSender
    }

    /// Replace the default delegate-based event sender with a custom one.
    ///
    /// Framework bridges (Flutter, React Native) call this **before** ``ready(config:)``
    /// to inject their own event-channel implementation.
    ///
    /// - Parameter sender: A ``TraceletEventSending`` implementation.
    public func setEventSender(_ sender: TraceletEventSending) {
        precondition(!isReady, "setEventSender() must be called before ready()")
        self.eventSender = sender
    }

    /// Sets a headless dispatcher for background event delivery.
    ///
    /// Used by framework bridges (Flutter, React Native) to forward events
    /// to their respective background runtimes.
    public func setHeadlessDispatcher(_ dispatcher: HeadlessDispatching?) {
        delegateEventSender.headlessDispatcher = dispatcher
    }

    public var isTracking: Bool {
        return locationEngine.isTracking || stateManager.enabled
    }

    // =========================================================================
    // MARK: - Lifecycle
    // =========================================================================

    /// Initialize all subsystems with a typed configuration.
    ///
    /// Type-safe overload matching the Dart API:
    ///
    /// ```swift
    /// sdk.ready(config: TraceletConfig(
    ///     geo: .init(desiredAccuracy: .high, distanceFilter: 10.0),
    ///     app: .init(stopOnTerminate: false, startOnBoot: true)
    /// ))
    /// ```
    ///
    /// - Parameter config: Typed configuration.
    /// - Returns: Current state as a dictionary.
    @discardableResult
    public func ready(config: TraceletConfig) -> [String: Any] {
        return ready(config: config.toMap())
    }

    /// Initialize the SDK using an Objective-C compatible config wrapper.
    ///
    /// - Parameter objcConfig: ``TraceletConfigObjC`` instance.
    /// - Returns: Current state as a dictionary.
    @objc(readyWithObjCConfig:)
    @discardableResult
    public func ready(objcConfig: TraceletConfigObjC) -> [String: Any] {
        return ready(config: objcConfig.toMap())
    }

    /// Initialize all subsystems with the given configuration.
    ///
    /// **Must be called before any other method.** Returns the current state.
    ///
    /// - Parameter config: Configuration dictionary matching Dart `Config.toMap()` format.
    /// - Returns: Current state as a dictionary.
    public func requestStateFlush() {
        var providerState = locationEngine.buildProviderState()
        providerState["event"] = "providerchange"
        eventSender.sendProviderChange(providerState)
        
        let isMoving = stateManager.isMoving
        let locationMap = locationEngine.getLastGpsLocation().map { locationEngine.buildLocationMap($0) }
        var motionMap = locationMap ?? [:]
        motionMap["isMoving"] = isMoving
        sendMotionChangeWithTrip(motionMap)
    }

    /// Emits a motionchange carrying the trip in force at that moment (#402).
    ///
    /// The Dart layer runs its own trip detection for waypoints and distance,
    /// and would otherwise mint a *second* id for the same journey — one that
    /// matched nothing in the database. Attaching it to the event that opened
    /// or closed the trip also makes it race-free: the id is read right after
    /// the transition that set it, rather than fetched afterwards, by which
    /// time trip end may already have cleared it.
    ///
    /// Assigning `nil` removes the key, which is the intended shape: no key
    /// means no trip was active.
    private func sendMotionChangeWithTrip(_ data: [String: Any]) {
        var withTrip = data
        withTrip["tripId"] = tripManager.currentTripId
        eventSender.sendMotionChange(withTrip)
    }

    /// Records the background edge on the always-on channel.
    @objc private func handleDidEnterBackground() {
        TraceletLog.lifecycle(
            "app: moved to BACKGROUND — tracking must continue from here")
    }

    @objc private func handleWillEnterForeground() {
        TraceletLog.lifecycle("app: moved to FOREGROUND")
        // #182: deliver any crash/fall confirmations whose deadline elapsed while
        // the app was backgrounded/suspended.
        drainDueConfirmations()
        requestStateFlush()
    }

    @discardableResult
    public func ready(config: [String: Any]) -> [String: Any] {
        initialize()  // no-op if already initialized

        // Merge the incoming config; the effective config (with any cached remote
        // overrides applied below) is read back from configManager at return.
        _ = configManager.setConfig(config)

        if config["encryptDatabase"] as? Bool == true {
            let key = config["encryptionKey"] as? String ?? ""
            rustDatabase?.setEncryptionKey(key: key)
        } else {
            rustDatabase?.setEncryptionKey(key: "")
        }

        if configManager.isDebug() { soundManager.start() }
        logger.pruneOldLogs()

        // [Enterprise] Auto-encrypt database if configured.
        if configManager.getEncryptDatabase(), let state = rustEngineState {
            do {
                let currentConfig = state.getConfig()
                let newSecurity = SecurityConfig(encryptDatabase: true)
                let newConfig = EngineConfig(
                    geo: currentConfig.geo,
                    motion: currentConfig.motion,
                    http: currentConfig.http,
                    geofence: currentConfig.geofence,
                    persistence: currentConfig.persistence,
                    audit: currentConfig.audit,
                    security: newSecurity,
                    attestation: currentConfig.attestation
                )
                try state.updateConfig(newConfig: newConfig)
                // DB encryption is now entirely managed by rustDatabase directly.
            } catch {
                TraceletLog.error("Auto-encrypt database failed: \(error)")
            }
        }

        // [Enterprise] Start attestation refresh if configured.
        if configManager.getAttestationEnabled() {
            deviceAttestor.startRefresh(intervalSeconds: configManager.getAttestationRefreshInterval())
        }

        // [Enterprise] Remote config: apply the last-good cached copy synchronously
        // so a restart resumes on the freshest known config instantly and offline.
        // The fresh background fetch + periodic refresh is started at the end of
        // ready(), once isReady is set.
        let remoteConfigUrl = configManager.getRemoteConfigUrl()
        if remoteConfigUrl != nil, let cached = remoteConfigManager.cachedConfig() {
            _ = configManager.setConfig(cached)
            // Mirror the applied override to Dart so activeConfig/diagnostics
            // reflect the cached remote config on this cold start too.
            eventSender.sendRemoteConfigEvent(cached)
        }

        // Initialize battery budget engine from config
        applyBatteryBudgetConfig()

        initBehaviorEngines()

        isReady = true
        syncConfigToRustFlat()
        checkSyncProvider()

        // Apply the interval-based sync cadence from the freshly-applied config (#149).
        startSyncIntervalTimer()

        // Rebuild the native location processor with the config just applied by
        // ready(); otherwise the engine keeps the previous/default processor in
        // memory and filters fixes the new config should accept (#157).
        locationEngine.rebuildProcessor()

        if stateManager.enabled {
            // #256: in SPEED/SMART modes the persisted trackingMode may be a
            // TEMPORARY stationary sub-state (.geofences/.periodic) entered by the
            // continuous motion-aware pipeline while stationary. Resuming it as a
            // standalone startGeofences()/startPeriodic() tears down the
            // motion-detection pipeline that switches back to continuous on
            // movement. Resume the continuous pipeline instead; it re-enters the
            // stationary sub-state on its own. Matches Android's completeReady().
            let motionMode = configManager.getMotionDetectionMode()
            if motionMode == .smart || motionMode == .speed {
                TraceletLog.debug("[Tracelet] ready: Resuming motion-aware tracking")
                start(isResume: true)
            } else {
                switch stateManager.trackingMode {
                case .continuous:
                    TraceletLog.debug("[Tracelet] ready: Resuming continuous tracking")
                    start(isResume: true)
                case .periodic:
                    TraceletLog.debug("[Tracelet] ready: Resuming periodic tracking")
                    startPeriodic()
                case .geofences:
                    TraceletLog.debug("[Tracelet] ready: Resuming geofence tracking")
                    _ = startGeofences(isResume: true)
                }
            }
        }

        // [Enterprise] Start the remote-config background fetch + periodic refresh
        // now that isReady is true, so setConfig() can apply fresh overrides at
        // runtime (restarting the tracking pipeline if needed).
        if let remoteUrl = remoteConfigUrl {
            remoteConfigManager.start(url: remoteUrl) { [weak self] remote in
                guard let self = self else { return }
                _ = self.setConfig(remote)
                // Notify Dart so activeConfig / diagnostics / the Dart-side
                // battery-budget engine reflect the freshly fetched override.
                self.eventSender.sendRemoteConfigEvent(remote)
            }
        }

        logger.info("ready() called")
        return stateManager.toMap(configManager.getConfig())
    }

    /// Start continuous location tracking.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func start(isResume: Bool = false) -> [String: Any] {
        precondition(isReady, "TraceletSdk.ready() must be called before start()")

        let wasTracking = locationEngine.isTracking

        // A manual start() while tracking is ALREADY active is a no-op. Previously
        // it reset isMoving to the configured default (isMoving=false) and forced
        // changePace(false), so a second start() slammed the device into the
        // STATIONARY state even while moving (and iOS could get stuck there).
        // Calling start() again must not disturb the live motion state — use
        // changePace() to change pace.
        if !isResume && wasTracking {
            stateManager.enabled = true
            stateManager.trackingMode = .continuous
            // #318/#324: recorded even though nothing changed, because "I called
            // start() and nothing happened" is a real report and this is its
            // answer — the session was already live, so no fresh session
            // boundary follows and the pace was deliberately left alone.
            TraceletLog.lifecycle(
                "session: start ignored — already tracking continuously "
                    + "(isMoving=\(stateManager.isMoving))")
            return stateManager.toMap(configManager.getConfig())
        }

        stateManager.enabled = true
        stateManager.trackingMode = .continuous
        if !isResume {
            stateManager.isMoving = configManager.getIsMoving()
        }

        smartMotionCoordinator.syncCurrentMode()

        let shouldForceMoving = stateManager.isMoving

        // Stop any periodic tracking before switching to continuous mode.
        locationEngine.stopPeriodic()
        periodicRefreshScheduler.stop()

        // Wire proximity-based geofence monitoring + trip waypoints.
        wireGeofenceLocationCallbacks(includeTripWaypoints: true)

        let motionMode = configManager.getMotionDetectionMode()

        if motionMode == .speed {
            startSpeedMotionManager(forceMoving: shouldForceMoving, isResume: isResume)
        } else if motionMode == .smart {
            startSpeedMotionManager(forceMoving: shouldForceMoving, isResume: isResume)
            // Seed the coordinator's accelerometer flag to the state we are
            // actually starting in. The Rust coordinator initialises
            // is_accel_moving = false and on_accel_state_change() early-returns on
            // an unchanged flag, so starting in MOVING left the accel input inert:
            // the stop-timeout would fire, report stationary, and the coordinator
            // would see no change and emit no action.
            if stateManager.isMoving {
                smartMotionCoordinator.onAccelStateChange(isMoving: true)
            }
            motionDetector.start()
        } else {
            motionDetector.start()
        }

        if stateManager.isMoving {
            locationEngine.start()
            startBackgroundActivitySessionIfNeeded()
        } else {
            _ = changePace(false)
            // A stationary start is dark otherwise: no continuous stream (by
            // design), and `changePace(false)` changes nothing in subsystems
            // that are already stationary. The app was left with no position at
            // all until the device physically moved. One fix anchors the
            // session; the pace it was asked to start in is untouched (#385).
            //
            // Restores acquisition this path lost in 3.2.0 (bb8af6a0), which
            // replaced an unconditional locationEngine.start() with the pace
            // branch above — the same edit landed on both platforms. The stream
            // had been doing double duty (ongoing feed *and* initial fix) and
            // only the first job was replaced.
            //
            // Fresh starts only. A resume runs on every process relaunch and
            // restores rather than commits its pace — the killed-state path
            // stays exactly as it was.
            if !isResume {
                TraceletLog.lifecycle(
                    "session: acquiring the initial fix for a stationary start (#385)")
                locationEngine.requestStartupFix()
            }
        }

        startHeartbeat()
        startStopAfterElapsedTimer()
        startBatteryBudgetSampling()
        startBehaviorSampling()
        preventSuspendManager.start()
        serviceSessionManager.start()

        eventSender.sendEnabledChange(true)
        logger.info("start() — tracking started")
        // #318/#324: the session boundary itself. iOS has no separate killed-state
        // pipeline to anchor a trace to — a relaunched process runs this very
        // method — so this entry is what a `relaunch:` line is read against, and
        // the most common answer to "it stopped tracking" is a `session: stop`
        // with no start after it. `resume=true` marks the SDK's own takeover
        // (ready(), auto-resume) rather than a call from the app.
        TraceletLog.lifecycle(
            "session: start — mode=continuous resume=\(isResume) "
                + "isMoving=\(stateManager.isMoving) "
                + "motionMode=\(configManager.getMotionDetectionMode()) "
                + "launchedInBackground=\(stateManager.didLaunchInBackground)")

        return stateManager.toMap(configManager.getConfig())
    }

    /// Wires the location callbacks used by every tracking mode that also does
    /// geofencing.
    ///
    /// Geofence **crossing** detection rides `LocationEngine.onRawGeofenceLocation`
    /// — the raw fix stream, before the persistence distance filter — so a
    /// stationary device inside a small fence isn't starved of ENTER/EXIT
    /// transitions when CoreLocation withholds updates under `distanceFilter`
    /// (field reports of "ENTER/EXIT not happening"). Proximity *scope* and trip
    /// waypoints stay on the persistence-filtered `onLocationUpdate` stream where
    /// their movement-driven cadence belongs.
    ///
    /// Setting `geofenceHighAccuracyMode` here (before the caller's
    /// `locationEngine.start()`) makes `configureLocationManager()` request
    /// time-based delivery for the high-accuracy path. Call this *before*
    /// starting the engine.
    private func wireGeofenceLocationCallbacks(includeTripWaypoints: Bool) {
        // Trip waypoints stay on the persistence-filtered stream where they
        // belong; both geofence duties ride the RAW one.
        //
        // #297 moved crossing *detection* to the raw stream but left proximity
        // *scope* on the filtered one — the same bug in a less obvious place
        // (#352). In standard (OS) geofence mode the SDK detects nothing itself,
        // so which fences are registered IS the feature, and updateProximity()
        // is what registers them. Running that off the filtered stream lets the
        // persistence filter decide whether geofencing works at all — and
        // 3.8.0's transport-mode auto-tune (#299) retunes a committed `still`
        // mode to maxImpliedSpeed=3 m/s, rejecting every fix once the device
        // moves. Mirrors the Android fix.
        locationEngine.onLocationUpdate = { [weak self] lat, lng, _ in
            guard let self = self, includeTripWaypoints else { return }
            self.tripManager.onLocationReceived(
                latitude: lat,
                longitude: lng,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }

        // Called unconditionally: whether a fence is evaluated here or left to
        // CoreLocation is a per-fence question the manager answers, and not one
        // the config flag alone can settle — polygons and sub-100 m circles are
        // ours to decide however `geofenceModeHighAccuracy` is set (#355).
        locationEngine.geofenceHighAccuracyMode = geofenceManager.hasEvaluatorOwnedGeofences()
        // Claim the wake-up the inflated OS region exists to produce: if the app
        // relaunched into a low-power posture, coming near a small fence must
        // bring the stream back or the evaluator has nothing to decide on (#355).
        geofenceManager.onEvaluatorWakeup = { [weak self] in
            self?.locationEngine.start()
        }
        // The line above answers "who owns these fences?" once. The fence set is
        // mutable for the rest of the session, so it has to be re-asked every
        // time it changes (#357).
        geofenceManager.onEvaluatorOwnershipChanged = { [weak self] in
            self?.applyGeofenceEvaluationCadence()
        }
        locationEngine.onRawGeofenceLocation = { [weak self] lat, lng, accuracy in
            guard let self = self else { return }
            self.geofenceManager.updateProximity(latitude: lat, longitude: lng)
            self.geofenceManager.evaluateHighAccuracyProximity(
                latitude: lat, longitude: lng, accuracy: accuracy
            )
        }
    }

    /// Re-aligns the location cadence with who owns the currently-stored fences.
    ///
    /// `wireGeofenceLocationCallbacks` settles this at `start()`, when there may
    /// be no fences at all — `start()` then `addGeofence(radius: 10)` is the
    /// ordinary order, and it left `geofenceHighAccuracyMode` false for the rest
    /// of the session. CoreLocation kept the configured `distanceFilter`, so the
    /// evaluator was handed one fix per `distanceFilter` metres travelled: a
    /// device can cross a 10 m fence's exit band and be back inside between two
    /// deliveries, and EXIT needs two *consecutive* fixes beyond it. Field trace
    /// showed deliveries 10.5 m / 10.3 m / 10.9 m apart against a 10 m filter,
    /// with no EXIT at all on the first walk (#357).
    private func applyGeofenceEvaluationCadence() {
        guard stateManager.enabled else { return }
        let needsInAppEvaluation = geofenceManager.hasEvaluatorOwnedGeofences()
        guard locationEngine.geofenceHighAccuracyMode != needsInAppEvaluation else { return }

        TraceletLog.lifecycle(
            "[geofence] fence set changed — in-app evaluation "
                + "\(needsInAppEvaluation ? "required" : "no longer required")"
                + ", realigning the location cadence (#357)")
        // Setting this re-applies the provider options live when tracking.
        locationEngine.geofenceHighAccuracyMode = needsInAppEvaluation

        if stateManager.trackingMode == .geofences {
            applyGeofenceModePosture(needsInAppEvaluation: needsInAppEvaluation)
        } else if needsInAppEvaluation, !locationEngine.isTracking {
            // Continuous mode does not necessarily have a stream running — the
            // #319 stationary throttle stops the engine — and a fence added in
            // that window would be registered against nothing. `start()` is a
            // no-op when it is already tracking.
            TraceletLog.lifecycle(
                "[geofence] starting the location stream for an in-app-evaluated "
                    + "fence — nothing was running to decide it from (#357)")
            locationEngine.start()
        }
    }

    /// Applies the power posture `geofences` mode runs at, given whether any
    /// stored fence must be evaluated in-app.
    ///
    /// Continuous GPS is needed exactly when a fence is evaluated in-app — high
    /// accuracy mode, a polygon, or a sub-100 m circle (#355). A fence the OS can
    /// decide for itself needs none of it: region monitoring fires enter/exit
    /// (and relaunches the app) while suspended or terminated, and starting a
    /// stream keeps the persistent blue location indicator on even with
    /// `showsBackgroundLocationIndicator = false` (#210).
    ///
    /// Shared by `startGeofences()` and the mid-session refresh so the two cannot
    /// drift: a fence added later must be able to *reach* this posture, and one
    /// removed later — KnockOut removes on EXIT — must be able to leave it, or
    /// the mode leaks continuous GPS for the rest of the session (#357).
    private func applyGeofenceModePosture(needsInAppEvaluation: Bool) {
        if needsInAppEvaluation {
            locationEngine.start()
            preventSuspendManager.start()
            backgroundActivitySessionManager.start()
            serviceSessionManager.start()
        } else {
            locationEngine.stop()

            if configManager.getPreventSuspend() {
                preventSuspendManager.start()
            } else {
                preventSuspendManager.stop()
            }

            // Explicitly stop CLBackgroundActivitySession if switching from High to Low.
            // Like continuous updates, it forces the location indicator on.
            backgroundActivitySessionManager.stop()

            // iOS 18+: Preserve authorization across suspension/termination.
            startServiceSessionForCurrentAuth()
        }
    }

    /// Stop all tracking.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func stop() -> [String: Any] {
        BackgroundTaskHelper.shared.run("stop") { [self] in
            // #318/#324: read before the state is cleared, so the entry says what was
            // torn down rather than the zeroed state that follows.
            let wasTracking = stateManager.enabled
            let wasMode = stateManager.trackingMode
            let wasMoving = stateManager.isMoving

            stateManager.enabled = false
            stateManager.isMoving = false

            locationEngine.stop()
            locationEngine.speedSink = nil
            locationEngine.onRawGeofenceLocation = nil
            locationEngine.geofenceHighAccuracyMode = false
            geofenceManager.onEvaluatorOwnershipChanged = nil
            // Cancel any in-flight debounced auto-sync so stop() halts background
            // network activity immediately instead of firing ~autoSyncDelay later (#213).
            syncProvider?.cancelPendingSync()
            motionDetector.stop()
            speedMotionManager?.stop()
            speedMotionManager = nil
            geofenceManager.destroy()
            stopHeartbeat()
            stopSyncIntervalTimer()
            cancelStopAfterElapsedTimer()
            locationEngine.stopPeriodic()
            periodicRefreshScheduler.stop()
            preventSuspendManager.stop()
            backgroundActivitySessionManager.stop()
            serviceSessionManager.stop()

            scheduleManager.stop()
            tripManager.reset()
            stopBatteryBudgetSampling()
            batteryBudgetEngine?.reset()
            stopBehaviorSampling()
            telematicsEngine?.reset()
            eventSender.sendEnabledChange(false)
            logger.info("stop() — tracking stopped")
            // #318/#324: the counterpart to `session: start`, and on its own the
            // answer to most "it stopped tracking" reports. It is also the entry
            // `relaunch: declined to resume — tracking was stopped before
            // termination` points back at: that line says the session was
            // already over, and this one says when it ended.
            TraceletLog.lifecycle(
                "session: stop — was mode=\(wasMode) enabled=\(wasTracking) "
                    + "isMoving=\(wasMoving)")
        }

        return stateManager.toMap(configManager.getConfig())
    }

    /// Start geofence-only tracking mode.
    ///
    /// The SDK will only monitor geofences without continuous location
    /// tracking, saving significant battery.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func startGeofences(isResume: Bool = false) -> [String: Any] {
        precondition(isReady, "TraceletSdk.ready() must be called before startGeofences()")

        // A redundant re-start — already tracking in .geofences mode — is not a
        // fresh session, even when the host app (not the SDK's own resume path)
        // makes the call. Apps commonly call startGeofences() on every launch to
        // "refresh" fences; treating that as a fresh start would reset the
        // inside-set and re-ENTER a stationary device on every launch (#292). So
        // only a genuine transition into geofence mode (from stopped or another
        // mode) resets inside-state; a redundant call is treated as a resume.
        let treatAsResume = isResume ||
            (stateManager.enabled && stateManager.trackingMode == .geofences)

        stateManager.enabled = true
        stateManager.trackingMode = .geofences

        locationEngine.speedSink = nil
        locationEngine.stop()
        motionDetector.stop()
        speedMotionManager?.stop()
        speedMotionManager = nil

        geofenceManager.reRegisterAll()

        // Wire proximity-based geofence monitoring.
        wireGeofenceLocationCallbacks(includeTripWaypoints: false)

        // Continuous GPS is needed exactly when a fence is evaluated in-app —
        // high-accuracy mode, a polygon, or a sub-100 m circle (#355). A small
        // fence cannot be served by region monitoring, so opting into one means
        // opting into the location stream that decides it.
        if geofenceManager.hasEvaluatorOwnedGeofences() {
            // A fresh start resets inside-state so the initial-entry trigger
            // fires exactly once. A resume/boot/redundant re-start must NOT reset
            // it, or a stationary device inside a fence re-emits ENTER on every
            // ready()/takeover or app-start refresh — false attendance punch-ins
            // (#292). The persisted knownInsideIds additionally suppresses the
            // re-ENTER a cold-start (empty evaluator) would otherwise produce.
            if treatAsResume {
                geofenceManager.clearHighAccuracyState()
            } else {
                geofenceManager.resetHighAccuracyInsideState()
            }
        }
        applyGeofenceModePosture(needsInAppEvaluation: geofenceManager.hasEvaluatorOwnedGeofences())

        eventSender.sendEnabledChange(true)
        logger.info("startGeofences() — geofence-only mode")
        // #318/#324: see start(). Recorded per mode because a geofence-only session
        // that never fires looks identical to no session at all in a report,
        // and standard mode deliberately runs with no continuous GPS — so the
        // absence of motion entries is expected here and a finding elsewhere.
        TraceletLog.lifecycle(
            "session: start — mode=geofences resume=\(treatAsResume) "
                + "highAccuracy=\(configManager.getGeofenceModeHighAccuracy()) "
                + "fences=\(geofenceManager.getGeofences().count)")

        return stateManager.toMap(configManager.getConfig())
    }

    /// Start periodic one-shot location tracking mode.
    ///
    /// Instead of continuous GPS updates, this mode wakes at the configured
    /// interval, performs a single location fix, dispatches the result, and
    /// immediately turns the location provider off.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func startPeriodic() -> [String: Any] {
        precondition(isReady, "TraceletSdk.ready() must be called before startPeriodic()")

        // Stop continuous tracking before switching to periodic mode.
        locationEngine.speedSink = nil
        locationEngine.stop()
        motionDetector.stop()
        speedMotionManager?.stop()
        speedMotionManager = nil

        stateManager.enabled = true
        stateManager.trackingMode = .periodic
        stateManager.isMoving = false

        locationEngine.startPeriodic()

        // Wire proximity-based geofence monitoring.
        wireGeofenceLocationCallbacks(includeTripWaypoints: false)

        startStopAfterElapsedTimer()

        // Schedule BGAppRefreshTask as a supplementary wake-up mechanism.
        let interval = TimeInterval(configManager.getPeriodicLocationInterval())
        periodicRefreshScheduler.start(interval: interval)

        // Only start preventSuspend in periodic mode when explicitly enabled.
        if configManager.getPreventSuspend() {
            preventSuspendManager.start()
        }

        // Do NOT start CLBackgroundActivitySession for periodic mode.
        // It causes a persistent blue location indicator in the status bar,
        // which is misleading — periodic mode only uses GPS briefly during
        // each fix. Background execution is already handled by:
        //   - BackgroundTaskHelper around each periodic fix
        //   - Temporarily enabling allowsBackgroundLocationUpdates per fix
        //   - significantLocationChanges as a wake-up mechanism
        //   - BGAppRefreshTask via PeriodicRefreshScheduler

        // iOS 18+: Preserve authorization across suspension/termination.
        // This does NOT show the location indicator.
        startServiceSessionForCurrentAuth()

        eventSender.sendEnabledChange(true)
        logger.info("startPeriodic() — periodic tracking started")
        // #318/#324: see start(). Periodic mode on iOS depends on wake-ups the OS is
        // free to withhold, so "it stopped firing overnight" is diagnosed by the
        // interval this session actually ran at against the gaps in the fixes.
        TraceletLog.lifecycle(
            "session: start — mode=periodic interval=\(Int(interval))s "
                + "preventSuspend=\(configManager.getPreventSuspend())")

        return stateManager.toMap(configManager.getConfig())
    }

    /// Get the current SDK state.
    ///
    /// - Returns: State as a dictionary. Returns a default disabled state if
    ///   ``ready(config:)`` has not been called yet.
    public func getState() -> [String: Any] {
        // `stateManager`/`configManager` are built by `initialize()`, so before
        // `ready()` they are still nil and the implicit unwrap trapped — despite
        // the contract above, and despite `reset()` routing its own not-ready
        // path straight here (#344).
        guard isReady, let stateManager = stateManager, let configManager = configManager else {
            return StateManager.disabledStateMap()
        }
        return stateManager.toMap(configManager.getConfig())
    }

    /// Update the SDK configuration.
    ///
    /// - Parameter config: Configuration dictionary.
    /// - Returns: Updated state as a dictionary.
    /// Update the SDK configuration using a typed ``TraceletConfig``.
    ///
    /// - Parameter config: Typed configuration struct.
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func setConfig(_ config: TraceletConfig) -> [String: Any] {
        return setConfig(config.toMap())
    }

    /// Update the SDK configuration using an Objective-C compatible config wrapper.
    ///
    /// - Parameter objcConfig: ``TraceletConfigObjC`` instance.
    /// - Returns: Updated state as a dictionary.
    @objc(setConfigWithObjC:)
    @discardableResult
    public func setConfig(objcConfig: TraceletConfigObjC) -> [String: Any] {
        return setConfig(objcConfig.toMap())
    }

    @discardableResult
    public func setConfig(_ config: [String: Any]) -> [String: Any] {
        guard isReady else { return getState() }
        let wasPreventing = configManager.getPreventSuspend()
        // Snapshot behavior-engine config before applying, so we can rebuild the
        // telematics / transport / crash-fall engines (and (re)load the ML crash
        // model) when any of it changes at runtime — otherwise toggling crash
        // detection or supplying a license key via setConfig() would never load
        // the model. Mirrors the Android SDK. initBehaviorEngines() is idempotent.
        let oldBehavior: [AnyHashable] = [
            configManager.getEnableDrivingEvents(), configManager.getEnableFusedClassifier(),
            configManager.getAutoTuneFromTransportMode(),
            configManager.getEnableCrashDetection(), configManager.getEnableFallDetection(),
            configManager.getCrashModelUrl() ?? "", configManager.getCrashModelUnlockUrl() ?? "",
            configManager.getCrashModelLicenseKey() ?? "", configManager.getCrashModelSha256() ?? "",
            configManager.getCrashModelThreshold(),
        ]
        // Snapshot config before applying so we can detect which tracking-relevant
        // keys changed and rebuild the WHOLE active pipeline (location + motion
        // detector + speed manager + smart coordinator) — not just the location
        // engine, which previously left motion sensors running on stale params (#230).
        let oldConfig = configManager.getConfig()
        let merged = configManager.setConfig(config)

        if config["encryptDatabase"] as? Bool == true {
            let key = config["encryptionKey"] as? String ?? ""
            rustDatabase?.setEncryptionKey(key: key)
        } else {
            rustDatabase?.setEncryptionKey(key: "")
        }

        let locationKeys = [
            "desiredAccuracy", "distanceFilter", "locationUpdateInterval",
            "fastestLocationUpdateInterval", "stationaryRadius", "deferTime",
            "disableElasticity", "elasticityMultiplier",
        ]
        let motionKeys = [
            "motionDetectionMode", "shakeThreshold", "stillThreshold", "stillSampleCount",
            "stopTimeout", "motionTriggerDelay", "stopDetectionDelay", "disableStopDetection",
            "stopOnStationary", "triggerActivities", "minimumActivityRecognitionConfidence",
            "activityRecognitionInterval", "disableMotionActivityUpdates",
            "speedMovingThreshold", "speedStationaryDelay", "speedWakeConfirmCount",
            "stationaryTrackingMode", "stationaryPeriodicInterval", "stationaryPeriodicAccuracy",
        ]
        // #303: the four thresholds transport-mode auto-tuning swaps. They reach
        // the processor through setBaseTuning, which preserves the positional
        // anchor — a rebuild would drop it and forfeit an odometer delta (#299).
        let tuningKeys = [
            "distanceFilter", "trackingAccuracyThreshold",
            "odometerAccuracyThreshold", "maxImpliedSpeed",
        ]
        // #303: the remaining LocationProcessor constructor parameters. These are
        // immutable in Rust, so changing one genuinely needs a rebuild — but not
        // a full pipeline restart, which is why they are kept out of
        // `needsRestart`. Every one of them used to be silently ignored until the
        // next cold start.
        let processorKeys = [
            "filterPolicy", "enableAdaptiveMode", "rejectMockLocations",
            "mockDetectionLevel", "enableSparseUpdates", "sparseDistanceThreshold",
            "sparseMaxIdleSeconds",
        ]
        let needsRestart = (locationKeys + motionKeys).contains { key in
            !valuesEqual(oldConfig[key], merged[key])
        }
        let changed = { [self] (keys: [String]) -> Bool in
            keys.contains { key in !self.valuesEqual(oldConfig[key], merged[key]) }
        }

        if stateManager.enabled {
            if needsRestart {
                logger.info("setConfig: tracking-relevant config changed — restarting active pipeline")
                // Preserve the active tracking mode and motion state across the
                // clean stop/start so the device doesn't silently revert to a
                // stationary continuous default.
                let currentMode = stateManager.trackingMode
                let wasMoving = stateManager.isMoving

                // #257: keep any Live Activity alive across the restart. iOS
                // cannot re-REQUEST a Live Activity while backgrounded ("Target
                // is not foreground"), so ending and recreating it here would
                // permanently lose it. Suppress the stop/start teardown and
                // update the surviving activity with the new config afterwards.
                var liveActivitySuppressed = false
                if #available(iOS 17.0, *) {
                    #if canImport(ActivityKit)
                    if configManager.getLiveActivityConfig() != nil {
                        locationEngine.suppressLiveActivityLifecycle = true
                        liveActivitySuppressed = true
                    }
                    #endif
                }

                _ = stop()

                stateManager.enabled = true
                stateManager.trackingMode = currentMode
                stateManager.isMoving = wasMoving

                // Rebuild the Rust processor so distanceFilter/elasticity/etc.
                // changes take effect on the very first fix after restart.
                locationEngine.rebuildProcessor()

                // #256: in SPEED/SMART motion-detection modes the SDK runs a single
                // continuous motion-aware pipeline that TEMPORARILY flips
                // trackingMode to .geofences/.periodic while the device is
                // stationary (switchToStationaryGeofencesForce /
                // switchToStationaryPeriodicForce). That temporary value is NOT an
                // explicitly-started standalone mode — rebuilding it via
                // startPeriodic()/startGeofences() tears down the very
                // motion-detection pipeline that is supposed to switch it back to
                // continuous once the device moves again, stranding tracking in a
                // standalone stationary mode. Restart the continuous pipeline
                // instead; it re-enters the stationary sub-state on its own when
                // still stationary.
                let motionMode = configManager.getMotionDetectionMode()
                let motionAware = motionMode == .smart || motionMode == .speed

                if motionAware {
                    _ = start(isResume: true)
                } else {
                    switch currentMode {
                    case .periodic:
                        _ = startPeriodic()
                    case .geofences:
                        _ = startGeofences(isResume: true)
                    default:
                        _ = start(isResume: true)
                    }
                }

                // Restart done — restore normal lifecycle and refresh the
                // surviving Live Activity's content to reflect the new config.
                if liveActivitySuppressed {
                    locationEngine.suppressLiveActivityLifecycle = false
                    if #available(iOS 17.0, *) {
                        #if canImport(ActivityKit)
                        if let lc = configManager.getLiveActivityConfig() {
                            LiveActivityManager.shared.updateLiveActivity(
                                title: lc.title,
                                body: lc.body,
                                startedAt: lc.startedAt,
                                showTimer: lc.showTimer
                            )
                        }
                        #endif
                    }
                }
            }

            // Toggle preventSuspend if it changed mid-session. (start()/stop()
            // also manage it, but ensure the final state matches the new config.)
            let nowPreventing = configManager.getPreventSuspend()
            if nowPreventing && !wasPreventing {
                preventSuspendManager.start()
            } else if !nowPreventing && wasPreventing {
                preventSuspendManager.stop()
            }
        } else if needsRestart {
            // Not actively tracking — still rebuild the processor so the next
            // start() picks up the new location config without a stale cache.
            locationEngine.rebuildProcessor()
        }

        // #303: carry the rest of the location-filter config into the processor.
        // Only the handful of keys in `locationKeys` ever reached it; everything
        // else was accepted, cached, and ignored until the next cold start.
        //
        // Ordered cheapest-effect-first, and skipped entirely when a restart
        // already rebuilt the processor from current config above.
        if !needsRestart {
            if changed(processorKeys) {
                // Constructor-only parameters: nothing short of a rebuild moves
                // them. No anchor to protect that a restart wouldn't drop anyway.
                locationEngine.rebuildProcessor()
            } else if changed(tuningKeys) {
                // Thresholds: swap in place so the odometer anchor survives.
                locationEngine.applyConfiguredBaseTuning()
            }
        }
        // Independent of the processor — the filter is its own object, so a
        // toggle must never cost the anchor.
        locationEngine.syncKalmanFilter()

        let newBehavior: [AnyHashable] = [
            configManager.getEnableDrivingEvents(), configManager.getEnableFusedClassifier(),
            // #301: Android already watched this key; iOS did not, so the two
            // platforms took different paths on the same setConfig() call.
            configManager.getAutoTuneFromTransportMode(),
            configManager.getEnableCrashDetection(), configManager.getEnableFallDetection(),
            configManager.getCrashModelUrl() ?? "", configManager.getCrashModelUnlockUrl() ?? "",
            configManager.getCrashModelLicenseKey() ?? "", configManager.getCrashModelSha256() ?? "",
            configManager.getCrashModelThreshold(),
        ]
        if oldBehavior != newBehavior {
            initBehaviorEngines()
            // #301: initBehaviorEngines() creates the classifier but only start()
            // ever started the ~1 Hz accel-window loop that drives it. Enabling
            // the classifier mid-session therefore produced a classifier that
            // never classified — and, with auto-tuning on, never retuned.
            // startBehaviorSampling() stops the old loop first and no-ops when
            // there is no consumer, so this is safe to call unconditionally.
            if stateManager.enabled { startBehaviorSampling() }
        }

        // #301: any of the above can leave the processor's thresholds out of step
        // with the committed transport mode — a rebuilt processor has dropped an
        // active auto-tune, and a disabled auto-tune has left one in force.
        syncTransportModeTuning()

        // The battery-budget engine is built at ready() from batteryBudgetPerHour
        // and is otherwise never touched here — so enabling/disabling/retargeting
        // the budget at runtime (e.g. a remote-config push of
        // {"geo":{"batteryBudgetPerHour":1.0}}) previously had no effect until the
        // app was cold-started. Rebuild it when the target changes, and (re)start
        // or stop sampling to match the live tracking state.
        if !valuesEqual(oldConfig["batteryBudgetPerHour"], merged["batteryBudgetPerHour"]) {
            applyBatteryBudgetConfig()
            if stateManager.enabled {
                // startBatteryBudgetSampling() stops any running timer first and
                // returns early when the engine is nil, so this both starts a
                // newly-enabled budget and halts a newly-disabled one.
                startBatteryBudgetSampling()
            }
        } else if !valuesEqual(oldConfig["distanceFilter"], merged["distanceFilter"])
            || !valuesEqual(oldConfig["desiredAccuracy"], merged["desiredAccuracy"])
            || !valuesEqual(
                oldConfig["periodicLocationInterval"], merged["periodicLocationInterval"])
        {
            // The ladder is expressed relative to the app's own parameters, so a
            // change to those has to reach it — otherwise an overlay in force
            // would keep enforcing rungs measured from the previous
            // configuration (#396).
            syncBatteryBudgetConfigured()
        }

        syncConfigToRustFlat()
        checkSyncProvider()
        return stateManager.toMap(configManager.getConfig())
    }

    /// Refreshes the active on-screen tracking indicator so it reflects the
    /// latest configuration, without restarting the tracking pipeline (#257).
    ///
    /// iOS has no foreground-service notification. Its analogue is the optional
    /// Live Activity, which a developer opts into by supplying a
    /// `liveActivityConfig` (title + body) and adding the Widget Extension. When
    /// one is configured and currently running, this repost its content from the
    /// latest `liveActivityConfig` (the dynamic body; the title is immutable on a
    /// running activity). If no Live Activity is configured or running, this is a
    /// safe no-op — matching the Android behavior when the foreground service is
    /// not running.
    public func updateNotification() {
        guard isReady else { return }
        if #available(iOS 17.0, *) {
            #if canImport(ActivityKit)
            guard let liveConfig = configManager.getLiveActivityConfig() else {
                logger.info("updateNotification: no liveActivityConfig set — nothing to refresh")
                return
            }
            // Only meaningful while a tracking session is active. Refresh the
            // running Live Activity in place, or (re)present it with the latest
            // config if it isn't currently on screen (it is bound to the moving
            // sub-state, so a transient stop can tear it down). Mirrors Android's
            // "no-op when the service isn't running" by gating on enabled.
            guard stateManager.enabled else {
                logger.info("updateNotification: tracking not enabled — nothing to refresh")
                return
            }
            LiveActivityManager.shared.refreshLiveActivity(
                title: liveConfig.title,
                body: liveConfig.body,
                startedAt: liveConfig.startedAt,
                showTimer: liveConfig.showTimer
            )
            #endif
        }
    }

    /// Loose equality for two heterogeneous config values, used to detect which
    /// keys changed between an old and new config snapshot. Config values are
    /// primitives (Int/Double/Bool/String) sourced from the same dictionary
    /// shape, so a stable string description is a reliable change signal.
    private func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        default: return String(describing: a!) == String(describing: b!)
        }
    }

    private func checkSyncProvider() {
        let url = configManager.getUrl()
        if !url.isEmpty, syncProvider == nil {
            TraceletLog.warning("⚠️ WARNING [Tracelet]: HTTP sync URL is configured (\"\(url)\"), but no SyncProvider is registered. Location synchronization will NOT work without the tracelet_sync package. Please ensure tracelet_sync is installed and initialized.")
        }
    }

    /// Reset all state and optionally apply new configuration.
    ///
    /// - Parameter config: Optional new configuration to apply after reset.
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func reset(_ config: [String: Any]? = nil) -> [String: Any] {
        guard isReady else { return getState() }
        BackgroundTaskHelper.shared.run("reset") { [self] in
            locationEngine.destroy()
            locationEngine.onLocationUpdate = nil
            locationEngine.speedSink = nil
            motionDetector.stop()
            speedMotionManager?.stop()
            speedMotionManager = nil
            stopHeartbeat()
            stopSyncIntervalTimer()
            cancelStopAfterElapsedTimer()
            periodicRefreshScheduler.stop()
            remoteConfigManager?.stop()

            // #353: mirrors the destroyAll()/autoResumeTracking() fix — geofences
            // are a standalone feature and must not require trackingMode ==
            // .geofences to survive.
            let keepGeofencesAlive = !configManager.getStopOnTerminate() && stateManager.enabled
            if !keepGeofencesAlive {
                geofenceManager.destroy()
            }

            preventSuspendManager.stop()
            backgroundActivitySessionManager.stop()
            serviceSessionManager.stop()

            stateManager.reset()
            configManager.reset(config)
            tripManager.reset()
            batteryBudgetEngine?.reset()
            auditTrailManager?.reset()
            isReady = false
            logger.info("reset() — all subsystems reset")
        }

        return stateManager.toMap(configManager.getConfig())
    }

    // =========================================================================
    // MARK: - Location
    // =========================================================================

    /// Get the current position as a one-shot request.
    ///
    /// - Parameters:
    ///   - options: Options dictionary (desiredAccuracy, timeout, maximumAge, persist, samples, extras).
    ///   - completion: Called with the location dictionary, or nil on failure.
    public func getCurrentPosition(options: [String: Any] = [:],
                                   completion: @escaping ([String: Any]?) -> Void) {
        guard isReady else { completion(nil); return }
        locationEngine.getCurrentPosition(options: options, callback: completion)
    }

    @discardableResult
    public func cancelCurrentPosition(_ requestId: String) -> Bool {
        guard isReady else { return false }
        return locationEngine.cancelCurrentPosition(requestId)
    }

    /// Get the last known location without requesting a new fix.
    ///
    /// - Parameter options: Options dictionary (persist, extras).
    /// - Returns: Location dictionary, or nil if no cached location is available.
    public func getLastKnownLocation(options: [String: Any] = [:]) -> [String: Any]? {
        guard isReady else { return nil }
        var result: [String: Any]?
        locationEngine.getLastKnownLocation(options: options) { result = $0 }
        return result
    }

    /// Start watching position at a high-frequency interval.
    ///
    /// - Parameter options: Options dictionary (interval, desiredAccuracy, extras).
    /// - Returns: Watch ID that can be used to stop the watch via ``stopWatchPosition(_:)``.
    public func watchPosition(options: [String: Any] = [:]) -> Int {
        guard isReady else { return -1 }
        return locationEngine.watchPosition(options: options)
    }

    /// Stop a watch started by ``watchPosition(options:)``.
    ///
    /// - Parameter watchId: The watch ID returned by ``watchPosition(options:)``.
    /// - Returns: `true` if the watcher was found and stopped.
    @discardableResult
    public func stopWatchPosition(_ watchId: Int) -> Bool {
        guard isReady else { return false }
        return locationEngine.stopWatchPosition(watchId)
    }

    /// Toggle the motion state.
    ///
    /// `isMoving: true` forces moving mode (high-frequency updates).
    /// `isMoving: false` forces stationary mode.
    ///
    /// - Parameter isMoving: The desired motion state.
    /// - Returns: `true` if the pace was changed.
    @discardableResult
    public func changePace(_ isMoving: Bool) -> Bool {
        guard isReady else { return false }
        
        let motionMode = configManager.getMotionDetectionMode()
        if motionMode == .speed {
            speedMotionManager?.onManualPaceChange(isMoving: isMoving)
            return true
        } else if motionMode == .smart {
            speedMotionManager?.onManualPaceChange(isMoving: isMoving)
            motionDetector.onManualPaceChange(isMoving)
            smartMotionCoordinator.onManualPaceChange(isMoving: isMoving)
            return true
        } else {
            let result = locationEngine.changePace(isMoving)
            motionDetector.onManualPaceChange(isMoving)
            return result
        }
    }

    /// Temporarily overrides the active Core Location acquisition policy.
    ///
    /// Unlike `setConfig`, this does not persist configuration, rebuild the
    /// location processor, or restart the tracking pipeline. Passing nil for
    /// both values restores the configured provider options.
    @discardableResult
    public func updateLocationProviderOptions(
        desiredAccuracy: TraceletDesiredAccuracy?,
        distanceFilter: Double?
    ) -> Bool {
        guard isReady else { return false }
        return locationEngine.updateLocationProviderOptions(
            desiredAccuracy: desiredAccuracy?.rawValue,
            distanceFilter: distanceFilter
        )
    }

    /// Get the current odometer value in meters.
    public func getOdometer() -> Double {
        guard isReady else { return 0.0 }
        return locationEngine.getOdometer()
    }

    /// Set the odometer value.
    ///
    /// - Parameter value: New odometer value in meters.
    /// - Returns: Location dictionary at the reset point.
    @discardableResult
    public func setOdometer(_ value: Double) -> [String: Any] {
        guard isReady else { return [:] }
        return locationEngine.setOdometer(value)
    }

    // =========================================================================
    // MARK: - Geofencing
    // =========================================================================

    /// Add a single geofence to the monitoring list.
    ///
    /// - Parameter geofence: Geofence dictionary (identifier, latitude, longitude, radius, etc.).
    /// - Returns: `true` if the geofence was added.
    @discardableResult
    public func addGeofence(_ geofence: [String: Any]) -> Bool {
        guard isReady else { return false }
        return geofenceManager.addGeofence(geofence)
    }

    /// Add a single geofence using a typed ``TraceletGeofence`` model.
    ///
    /// - Parameter geofence: Typed geofence model.
    /// - Returns: `true` if the geofence was added.
    @discardableResult
    public func addGeofence(_ geofence: TraceletGeofence) -> Bool {
        return addGeofence(geofence.toMap() as [String: Any])
    }

    /// Add multiple geofences at once.
    ///
    /// - Parameter geofences: Array of geofence dictionaries.
    /// - Returns: `true` if all geofences were added.
    @discardableResult
    public func addGeofences(_ geofences: [[String: Any]]) -> Bool {
        guard isReady else { return false }
        return geofenceManager.addGeofences(geofences)
    }

    /// Add multiple geofences using typed ``TraceletGeofence`` models.
    ///
    /// - Parameter geofences: Array of typed geofence models.
    /// - Returns: `true` if all geofences were added.
    @discardableResult
    public func addGeofences(_ geofences: [TraceletGeofence]) -> Bool {
        return addGeofences(geofences.map { $0.toMap() as [String: Any] })
    }

    /// Remove a geofence by its identifier.
    ///
    /// - Parameter identifier: The geofence identifier.
    /// - Returns: `true` if the geofence was removed.
    @discardableResult
    public func removeGeofence(_ identifier: String) -> Bool {
        guard isReady else { return false }
        return geofenceManager.removeGeofence(identifier)
    }

    /// Remove all geofences.
    ///
    /// - Returns: `true` if geofences were removed.
    @discardableResult
    public func removeGeofences() -> Bool {
        guard isReady else { return false }
        return geofenceManager.removeGeofences()
    }

    /// Get all registered geofences.
    ///
    /// - Returns: Array of geofence dictionaries.
    public func getGeofences() -> [[String: Any]] {
        return geofenceManager.getGeofences()
    }

    /// Get a single geofence by identifier.
    ///
    /// - Parameter identifier: The geofence identifier.
    /// - Returns: Geofence dictionary, or nil if not found.
    public func getGeofence(_ identifier: String) -> [String: Any]? {
        return geofenceManager.getGeofence(identifier)
    }

    /// Check whether a geofence with the given identifier exists.
    ///
    /// - Parameter identifier: The geofence identifier.
    /// - Returns: `true` if the geofence exists.
    public func geofenceExists(_ identifier: String) -> Bool {
        return geofenceManager.geofenceExists(identifier)
    }

    // =========================================================================
    // MARK: - Persistence
    // =========================================================================

    /// Get stored locations from the local database.
    ///
    /// - Parameter query: Optional query parameters (limit, offset, order, start, end).
    /// - Returns: Array of location dictionaries.
    public func getLocations(query: [String: Any]? = nil) -> [[String: Any]] {
        guard isReady else { return [] }
        guard let db = rustDatabase else { return [] }
        
        let startTimeMs = (query?["start"] as? NSNumber)?.int64Value ?? (query?["from"] as? NSNumber)?.int64Value
        let endTimeMs = (query?["end"] as? NSNumber)?.int64Value ?? (query?["to"] as? NSNumber)?.int64Value
        let limit = (query?["limit"] as? NSNumber)?.int32Value
        let offset = (query?["offset"] as? NSNumber)?.int32Value
        
        var orderDescending: Bool? = nil
        if let order = (query?["order"] as? NSNumber)?.intValue {
            orderDescending = (order == 1)
        }
        
        let rustQuery = LocationQuery(
            startTimeMs: startTimeMs,
            endTimeMs: endTimeMs,
            limit: limit,
            offset: offset,
            orderDescending: orderDescending
        )
        
        do {
            let records = try db.getLocationsBatch(query: rustQuery)
            return records.map { mapRecordToLocation($0) }
        } catch {
            TraceletLog.error("getLocations failed: \(error)")
            return []
        }
    }

    /// Canonical mapping of a persisted `DbLocationRecord` into the nested
    /// location schema used by `onLocation` and `getLocations`.
    ///
    /// Single source of truth so every consumer (getLocations + the sync
    /// interceptor sink) emits an identical shape and restores
    /// `route_context` / audit-hash metadata (Issue #126). See `LocationMapper`.
    public func mapRecordToLocation(_ record: DbLocationRecord) -> [String: Any] {
        return LocationMapper.buildLocationMap(
            id: record.id,
            uuid: record.uuid,
            timestamp: record.timestamp,
            latitude: record.latitude,
            longitude: record.longitude,
            altitude: record.altitude,
            speed: record.speed,
            heading: record.heading,
            accuracy: record.accuracy,
            isMock: record.isMock,
            activity: record.activity,
            activityConfidence: record.activityConfidence,
            routeContext: record.routeContext,
            isMoving: record.isMoving,
            odometer: locationEngine.getOdometer(),
            eventType: record.eventType,
            eventPayload: record.eventPayload,
            address: record.address
        )
    }

    /// Get the count of stored locations.
    ///
    /// - Parameter query: Optional query parameters (start, end).
    /// - Returns: Number of locations.
    public func getCount(query: [String: Any]? = nil) -> Int {
        guard isReady else { return 0 }
        guard let db = rustDatabase else { return 0 }
        do {
            let startTimeMs = (query?["start"] as? NSNumber)?.int64Value
                ?? (query?["from"] as? NSNumber)?.int64Value
            let endTimeMs = (query?["end"] as? NSNumber)?.int64Value
                ?? (query?["to"] as? NSNumber)?.int64Value
            if startTimeMs == nil && endTimeMs == nil {
                // No time filter — use the efficient native COUNT(*).
                return Int(try db.getLocationsCount())
            }
            // The native getLocationsCount ignores time bounds (#152), so a
            // filtered getCount() would otherwise return the whole-DB total.
            // Honor the query by counting the query-aware batch instead.
            let records = try db.getLocationsBatch(query: LocationQuery(
                startTimeMs: startTimeMs,
                endTimeMs: endTimeMs,
                limit: nil,
                offset: nil,
                orderDescending: nil
            ))
            return records.count
        } catch {
            TraceletLog.error("getCount failed: \(error)")
            return 0
        }
    }

    /// Destroy all stored locations.
    ///
    /// - Returns: `true` if locations were destroyed.
    @discardableResult
    public func destroyLocations() -> Bool {
        guard isReady else { return false }
        guard let db = rustDatabase else { return false }
        do {
            try db.destroyLocations()
            return true
        } catch {
            TraceletLog.error("destroyLocations failed: \(error)")
            return false
        }
    }

    /// Destroy (clear) locations that have already been synced to the backend.
    ///
    /// The Rust Core prunes each location from the local store the moment it is
    /// confirmed synced (see `sync` / `clearLocationsUpTo`), so there is never a
    /// "synced but still persisted" row to delete on demand. This method reports
    /// and resets the running total of locations that have been synced-and-pruned
    /// since it was last called — a real, DB-backed figure rather than the
    /// previous hardcoded `0` stub. Callers that have not synced anything since
    /// the last call correctly receive `0`.
    ///
    /// - Returns: Number of synced locations removed since the last call.
    @discardableResult
    public func destroySyncedLocations() -> Int {
        syncedLocationsLock.lock()
        defer { syncedLocationsLock.unlock() }
        let removed = syncedLocationsRemoved
        syncedLocationsRemoved = 0
        return removed
    }

    /// Destroy a single location by its public UUID (#251).
    ///
    /// The public location identifier is a UUID string, not the internal numeric
    /// database id. Previously this parsed the argument with `Int64(uuid)` and
    /// bailed out for any real UUID (e.g. `36ef46cf-…`), so pending locations
    /// could never be acknowledged. We now resolve the UUID to its row id via
    /// the database and delete that record. A purely numeric argument still
    /// works (treated as a raw row id) for backward compatibility.
    ///
    /// - Parameter uuid: The location UUID.
    /// - Returns: `true` if the location was destroyed.
    @discardableResult
    public func destroyLocation(_ uuid: String) -> Bool {
        guard isReady else { return false }
        guard let db = rustDatabase else { return false }
        do {
            let id: Int64
            if let record = try db.getLocationForAudit(uuid: uuid) {
                id = record.id
            } else if let numeric = Int64(uuid) {
                id = numeric
            } else {
                TraceletLog.error("destroyLocation: no location found for uuid=\(uuid)")
                return false
            }
            try db.destroyLocation(id: id)
            return true
        } catch {
            TraceletLog.error("destroyLocation failed: \(error)")
            return false
        }
    }

    /// Caches the timestamp of the last inserted location to prevent duplicate 
    /// DB writes from the same GPS fix.
    private var lastInsertedTimestamp: String? = nil

    /// Persists a geofence ENTER/EXIT record only if allowed by persistMode (#383).
    ///
    /// The geofence counterpart of `LocationEngine.persistLocationIfAllowed` — geofence
    /// transitions used to be wired straight to `insertLocation`, so `location` and
    /// `none` still wrote (and HTTP-synced) every crossing despite documenting otherwise.
    ///
    /// Only the DB write is gated. The listener event is dispatched separately by
    /// `GeofenceManager` via `eventDispatcher.sendGeofence`, so `none` keeps its
    /// documented "events are still fired" behaviour.
    ///
    /// Read live rather than latched at setup, so a `setConfig` mid-session takes
    /// effect on the next transition.
    private func persistGeofenceIfAllowed(_ eventData: [String: Any]) {
        guard configManager.shouldPersistGeofenceRecords() else { return }
        let _ = insertLocation(eventData)
    }

    /// Insert a custom location into the store.
    ///
    /// - Parameter params: Location data dictionary.
    /// - Returns: The UUID of the inserted location.
    public func insertLocation(_ params: [String: Any]) -> String {
        // Persist whenever the Rust DB is initialized — NOT only when isReady.
        // The killed-state relaunch path (autoResumeTracking) wires the DB and
        // sync provider but never calls ready(), so isReady stays false. Gating
        // on isReady here silently dropped every location captured after a
        // background relaunch, leaving the DB empty so auto-sync had nothing to
        // send. The db check below is the correct readiness signal.
        guard let db = rustDatabase else { return "" }
        let coords = params["coords"] as? [String: Any] ?? params
        let lat = coords["latitude"] as? Double ?? 0.0
        let lng = coords["longitude"] as? Double ?? 0.0
        let acc = coords["accuracy"] as? Double ?? 0.0
        let speed = coords["speed"] as? Double ?? 0.0
        let heading = coords["heading"] as? Double ?? 0.0
        let altitude = coords["altitude"] as? Double ?? 0.0
        let isMock = (params["mock"] as? Bool) ?? (params["is_mock"] as? Bool) ?? false
        let isMoving = params["is_moving"] as? Bool ?? false
        let activityMap = params["activity"] as? [String: Any]
        let activity = activityMap?["type"] as? String ?? "unknown"
        let activityConfidence = activityMap?["confidence"] as? Int ?? -1
        let timestamp = params["timestamp"] as? String
        let uuid = params["uuid"] as? String
        
        let eventType = params["event"] as? String ?? "location"
        var eventPayload: String? = params["event_payload"] as? String
        if eventPayload == nil, let geofenceData = params["geofence"] as? [String: Any] {
            if let jsonData = try? JSONSerialization.data(withJSONObject: geofenceData, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                eventPayload = jsonString
            }
        }

        // #187: persist the reverse-geocoded address (added by resolveAddress) so
        // it survives into the DB-sourced sync payload, not just the live event.
        var address: String? = params["address"] as? String
        if address == nil, let addressData = params["address"] as? [String: Any] {
            if let jsonData = try? JSONSerialization.data(withJSONObject: addressData, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                address = jsonString
            }
        }
        
        // Prevent duplicate insertions of the exact same GPS fix. The heartbeat
        // writer (startHeartbeat) tags the last GPS fix with event="heartbeat"
        // and calls insertLocation too, so it must share the location writer's
        // dedup key. Otherwise a fix already persisted by the normal dispatch is
        // re-inserted by the heartbeat (identical timestamp), producing
        // byte-identical duplicate rows that getLocations() then returns twice.
        let persistsGpsFix = eventType == "location" || eventType == "heartbeat"
        if persistsGpsFix, let ts = timestamp, ts == lastInsertedTimestamp {
            return ""
        }
        if persistsGpsFix { lastInsertedTimestamp = timestamp }
        
        var routeContext = rustEngineState?.getRouteContext()

        // Audit trail (Enterprise): the canonical place audit links are created.
        // The LocationEngine.dispatch() path pre-computes `audit_hash` and passes
        // it in `params`. But background/headless persists that call insertLocation()
        // directly (autoResumeTracking, geofence events, etc.) never went through
        // dispatch(), so they previously skipped the chain entirely — leaving
        // location_events rows with no matching audit_trail row, so getAuditProof()
        // returned nil for any such record. Generate the audit link here when it
        // wasn't pre-computed, so EVERY persisted location is covered.
        var auditHash = params["audit_hash"] as? String
        var auditPrevHash = params["audit_previous_hash"]
        var auditChainIndex = params["audit_chain_index"]
        if auditHash == nil, uuid != nil, let auditFields = auditTrailManager?.appendToChain(params) {
            auditHash = auditFields["audit_hash"] as? String
            auditPrevHash = auditFields["audit_previous_hash"]
            auditChainIndex = auditFields["audit_chain_index"]
        }
        let batteryMap = params["battery"] as? [String: Any]
        let extrasMap = params["extras"] as? [String: Any]
        // #280: persist the location-source classification so it survives into
        // DB-sourced reads (getLocations) and the sync payload, instead of only
        // living on the live onLocation event. Stored as first-class
        // route_context keys (like audit_*), not inside extras.
        let locationSource = (params["locationSource"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let reducedAccuracy = params["reducedAccuracy"] as? Bool

        if auditHash != nil || batteryMap != nil || (extrasMap != nil && !extrasMap!.isEmpty)
            || locationSource != nil || reducedAccuracy != nil {
            var contextDict: [String: Any] = [:]
            if let rc = routeContext, let data = rc.data(using: .utf8) {
                if let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    contextDict = dict
                }
            }
            if let auditHash = auditHash {
                contextDict["audit_hash"] = auditHash
                if let prevHash = auditPrevHash { contextDict["audit_previous_hash"] = prevHash }
                if let chainIndex = auditChainIndex { contextDict["audit_chain_index"] = chainIndex }
            }
            if let batteryMap = batteryMap {
                var bObj: [String: Any] = [:]
                if let level = batteryMap["level"] { bObj["level"] = level }
                if let isCharging = batteryMap["is_charging"] { bObj["is_charging"] = isCharging }
                else if let isCharging = batteryMap["isCharging"] { bObj["isCharging"] = isCharging }
                contextDict["battery"] = bObj
            }
            if let extrasMap = extrasMap, !extrasMap.isEmpty {
                contextDict["extras"] = extrasMap
            }
            if let locationSource = locationSource {
                contextDict["locationSource"] = locationSource
            }
            if let reducedAccuracy = reducedAccuracy {
                contextDict["reducedAccuracy"] = reducedAccuracy
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: contextDict, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                routeContext = jsonString
            }
        }
        
        do {
            let newRowId = try db.insertLocation(
                uuid: uuid,
                lat: lat,
                lng: lng,
                acc: acc,
                speed: speed,
                heading: heading,
                altitude: altitude,
                isMock: isMock,
                isMoving: isMoving,
                activity: activity,
                activityConfidence: Int32(clamping: activityConfidence),
                routeContext: routeContext,
                timestampOverride: timestamp,
                eventType: eventType,
                eventPayload: eventPayload,
                address: address
            )
            enforceRetentionCaps(db)
            // Notify the sync plugin so it can trigger auto-sync
            if let sink = syncProvider as? LocationDataSink {
                sink.insertLocation(params)
            }
            return newRowId.description
        } catch {
            TraceletLog.error("insertLocation failed: \(error)")
            return ""
        }
    }

    /// Location inserts seen this process. See ``enforceRetentionCaps(_:)``.
    private var locationInsertsSeen = 0

    /// Retention pruning runs on the first location insert and every N-th
    /// thereafter, instead of on every insert (#361).
    private static let pruneEveryNInserts = 100

    /// Applies `maxDaysToPersist` and `maxRecordsToPersist` to `location_events`
    /// (#361).
    ///
    /// Both caps were accepted by `ready()`/`setConfig()`, echoed back in
    /// `State.config` — and enforced by nothing, so the local queue grew without
    /// bound however they were set. They were real up to 3.0 via `pruneOldLocations`
    /// / `enforceMaxRecords` on the Swift `TraceletDatabase`; the 3.1.0 migration
    /// onto the Rust core replaced the persist body with a sink fan-out and deleted
    /// the retention calls with it, leaving an unread counter and a docstring behind
    /// as the only trace.
    ///
    /// Deliberately here rather than back in `LocationEngine.persistLocationIfAllowed`,
    /// where the leftover counter sat: this is the single funnel every location
    /// reaches the DB through. The engine's persist path is only one caller — the
    /// public `insertLocation` API, the geofence writers and the killed-state
    /// relaunch path insert straight through here, and pruning in the engine would
    /// have left the reporter's own repro (100+ explicit `insertLocation` calls)
    /// still unbounded.
    ///
    /// Amortized over ``pruneEveryNInserts`` inserts rather than run on each one, so
    /// a COUNT-and-DELETE is not attached to every GPS fix. The queue can therefore
    /// sit up to that many records above `maxRecordsToPersist` between prunes; the
    /// cap bounds growth, it is not a per-insert invariant. The first insert of the
    /// process prunes, so a cap tightened while stopped — or a backlog inherited
    /// from a build that never enforced one — is cut down without waiting out a
    /// whole window.
    ///
    /// A retention failure must not fail the insert: the record is already committed
    /// and losing it to a prune error would be strictly worse than an oversized
    /// queue.
    ///
    /// The counter is deliberately unsynchronized, like ``lastInsertedTimestamp``
    /// above it. Inserts arrive from both the CoreLocation delegate and the public
    /// API, so a racy increment can make a prune land an insert early or late —
    /// which costs nothing, and is cheaper than serializing every insert behind a
    /// lock to schedule a periodic DELETE precisely.
    private func enforceRetentionCaps(_ db: DatabaseManager) {
        defer { locationInsertsSeen += 1 }
        guard locationInsertsSeen % TraceletSdk.pruneEveryNInserts == 0 else { return }
        do {
            let maxDays = Int32(clamping: configManager.getMaxDaysToPersist())
            let maxRecords = Int32(clamping: configManager.getMaxRecordsToPersist())
            let byAge = try db.pruneLocationsOlderThan(maxDays: maxDays)
            let byCount = try db.enforceMaxLocationRecords(maxRecords: maxRecords)
            if byAge > 0 || byCount > 0 {
                TraceletLog.debug(
                    "Retention: pruned \(byAge) location(s) older than \(maxDays) day(s), "
                        + "\(byCount) over the \(maxRecords)-record cap."
                )
            }
        } catch {
            TraceletLog.error("Retention pruning failed: \(error)")
        }
    }

    // =========================================================================
    // MARK: - HTTP Sync
    // =========================================================================

    /// Manually trigger HTTP synchronization of pending locations.
    ///
    /// How many already-synced telematics events stay readable through
    /// `getTelematicsEvents()` (#366).
    ///
    /// Sync marks rows instead of deleting them so uploading an event doesn't
    /// erase it from the app's own history (#313) — this is what stops that from
    /// growing for the lifetime of the install. Unsynced rows are never subject
    /// to it; they are still owed to the server.
    static let maxSyncedTelematicsRetained: Int32 = 1000

    /// Serializes telematics rows to the wire shape (#366, #367).
    ///
    /// The key names are the ones apps already parse out of `extras.__telematics`,
    /// so this stays additive: `speed` and `value` join the object, nothing is
    /// renamed or removed.
    static func telematicsDicts(_ events: [DbTelematicsRecord]) -> [[String: Any]] {
        events.map { event in
            [
                "id": event.id,
                "event_type": event.eventType,
                "severity": event.severity,
                "speed": event.speed,
                "value": event.value,
                "latitude": event.latitude,
                "longitude": event.longitude,
                "timestamp": event.timestamp,
                "synced": event.synced,
                // #402: the trip this event was recorded during, or JSON null
                // outside one. Present either way so the key can be relied on.
                "trip_id": event.tripId ?? NSNull()
            ]
        }
    }

    /// The JSON array apps read from `extras.__telematics`, or `nil` if it could
    /// not be serialized — in which case nothing was attached and the rows must
    /// stay unsynced.
    static func telematicsJsonString(_ events: [DbTelematicsRecord]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: telematicsDicts(events), options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// POSTs telematics to the dedicated `telematicsUrl` endpoint (#368).
    ///
    /// Wraps the array in `{"telematics": [...]}` so the body is an object, and
    /// routes through the sync provider so pinning, headers, timeouts and retry
    /// behave the same as the location path. Failures collapse to `false` — the
    /// caller keeps the rows unsynced rather than losing them (#366).
    static func postTelematicsBatch(
        provider: SyncProvider,
        config: HttpConfig,
        url: String,
        events: [DbTelematicsRecord]
    ) -> Bool {
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["telematics": telematicsDicts(events)],
            options: []
        ), let body = String(data: data, encoding: .utf8) else {
            TraceletLog.error("Telematics sync body could not be serialized")
            return false
        }
        do {
            return try provider.postTelematicsBlocking(config: config, url: url, body: body)
        } catch {
            TraceletLog.error("Telematics sync to \(url) failed: \(error)")
            return false
        }
    }

    /// - Parameter completion: Called with the list of synced location dictionaries.
    public func sync(completion: (([[String: Any]]) -> Void)? = nil) {
        guard isReady else { completion?([]); return }
        guard let db = rustDatabase,
              let state = rustEngineState else {
            completion?([])
            return
        }
        
        DispatchQueue.global(qos: .utility).async { [self] in
            do {
                let config = state.getConfig()
                let batchSize = config.http.maxBatchSize
                let records = try db.getLocationsBatch(query: LocationQuery(
                    startTimeMs: nil,
                    endTimeMs: nil,
                    limit: batchSize,
                    offset: nil,
                    // Honor the configured sort order (0=ascending, 1=descending)
                    // instead of always defaulting to ascending (Issue #138).
                    orderDescending: config.http.locationsOrderDirection == 1
                ))
                var configHttp = config.http
                // #370: this read `getConfig()["http"]["syncTelematics"]`, but the
                // config cache is flat — Dart's nested sections are flattened on
                // the way in — so `["http"]` was always nil and the flag always
                // false. syncTelematics never took effect here, whatever the app
                // configured. Use the accessor that knows the cache is flat.
                let syncTelematics = self.configManager.getSyncTelematics()
                
                // #366: the id range we attach, so a *successful* upload can mark
                // exactly those synced. This used to be a bare boolean feeding an
                // unconditional `clearTelematicsEvents()` — a table-wide delete
                // that ran even when the POST had failed, so an offline device
                // destroyed its driving events instead of queueing them. 0 means
                // nothing was attached.
                var attachedTelematicsMaxId: Int64 = 0
                // #368: a separate endpoint means the telematics travel on their
                // own request, so they must not also ride the location payload.
                let telematicsUrl = self.configManager.getTelematicsUrl().isEmpty
                    ? nil : self.configManager.getTelematicsUrl()
                var telematicsToPost: [DbTelematicsRecord] = []
                if syncTelematics {
                    let telematics = try db.getTelematicsEvents(limit: 250)
                    if !telematics.isEmpty {
                        attachedTelematicsMaxId = telematics.map { $0.id }.max() ?? 0
                        if telematicsUrl != nil {
                            telematicsToPost = telematics
                        } else if let jsonString = Self.telematicsJsonString(telematics) {
                            var newExtras = configHttp.extras ?? [:]
                            newExtras["__telematics"] = jsonString
                            configHttp.extras = newExtras
                        } else {
                            // Serialization failed — nothing was attached, so the
                            // rows must stay unsynced rather than be settled below.
                            attachedTelematicsMaxId = 0
                        }
                    }
                }

                let hasTelematics = attachedTelematicsMaxId > 0
                if records.isEmpty && !hasTelematics {
                    DispatchQueue.main.async { completion?([]) }
                    return
                }

                guard let syncProvider = syncProvider else {
                    TraceletLog.error("Sync failed: No SyncProvider registered (is tracelet_sync installed?)")
                    DispatchQueue.main.async { completion?([]) }
                    return
                }

                // #368: posted before the locations so a telematics-only sync still
                // has something to do when `records` is empty.
                var telematicsPosted = false
                if let telematicsUrl = telematicsUrl, !telematicsToPost.isEmpty {
                    telematicsPosted = Self.postTelematicsBatch(
                        provider: syncProvider,
                        config: configHttp,
                        url: telematicsUrl,
                        events: telematicsToPost
                    )
                }

                // Skipping the location POST is only safe when the telematics
                // already went somewhere else (#368). On the default path they
                // ride this request, so it must still be made even with an empty
                // batch — otherwise they would sit unsynced until a location
                // happened along.
                let syncedCount = (records.isEmpty && telematicsUrl != nil)
                    ? 0
                    : try syncProvider.syncBatchBlocking(config: configHttp, records: records)

                // #366: telematics are only settled when the request that carried
                // them actually succeeded. Attached to the location payload, that
                // is the location POST; sent to `telematicsUrl`, it is their own.
                let telematicsDelivered = telematicsUrl != nil ? telematicsPosted : syncedCount > 0
                if syncedCount > 0 || telematicsDelivered {
                    if syncedCount > 0 {
                        let successfullySynced = Array(records.prefix(Int(syncedCount)))
                        if let lastRecord = successfullySynced.last {
                            try db.clearLocationsUpTo(maxId: lastRecord.id)
                            self.syncedLocationsLock.lock()
                            self.syncedLocationsRemoved += Int(syncedCount)
                            self.syncedLocationsLock.unlock()
                        }
                    }
                    if telematicsDelivered && attachedTelematicsMaxId > 0 {
                        // Mark, don't delete: #313 requires an uploaded event to
                        // stay visible in the app's own history. Bounded by the
                        // synced-tail trim so the table can't grow forever.
                        try db.markTelematicsSynced(maxId: attachedTelematicsMaxId)
                        _ = try db.pruneSyncedTelematics(keep: Self.maxSyncedTelematicsRetained)
                    }
                    DispatchQueue.main.async { completion?([]) }
                } else {
                    if hasTelematics {
                        TraceletLog.info(
                            "sync failed; telematics up to id \(attachedTelematicsMaxId) kept unsynced for the next attempt"
                        )
                    }
                    DispatchQueue.main.async { completion?([]) }
                }
            } catch {
                TraceletLog.error("Sync failed: \(error)")
                DispatchQueue.main.async { completion?([]) }
            }
        }
    }

    /// Update dynamic HTTP headers on the native side.
    ///
    /// Dynamic headers are merged with the static headers at sync time.
    /// Dynamic headers take precedence when keys overlap.
    ///
    /// - Parameter headers: Header key-value pairs.
    public func setDynamicHeaders(_ headers: [String: String]) {
        guard isReady else { return }
        configManager.setDynamicHeaders(headers)
        rustEngineState?.setDynamicHeaders(headers: headers)
    }

    // =========================================================================
    // MARK: - Route Context
    // =========================================================================

    /// Set the route context that will be persisted with every subsequent location.
    ///
    /// - Parameter context: Route context dictionary (taskId, driverId, etc.).
    public func setRouteContext(_ context: [String: Any]) {
        guard isReady else { return }
        configManager.setRouteContext(context)
        do {
            let data = try JSONSerialization.data(withJSONObject: context, options: [])
            if let jsonString = String(data: data, encoding: .utf8) {
                rustEngineState?.setRouteContext(json: jsonString)
            }
        } catch {
            TraceletLog.error("Failed to serialize routeContext: \(error)")
        }
    }

    /// Clear the current route context.
    public func clearRouteContext() {
        guard isReady else { return }
        configManager.clearRouteContext()
        rustEngineState?.setRouteContext(json: nil)
    }

    // =========================================================================
    // MARK: - Utility
    // =========================================================================

    /// Whether the device is currently in power-save (battery saver) mode.
    public var isPowerSaveMode: Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Get the current location permission status.
    ///
    /// - Returns: Authorization status code (0=notDetermined, 2=whenInUse, 3=always, 4=denied).
    public func getPermissionStatus() -> Int {
        return permissionManager.getAuthorizationStatus()
    }

    /// Whether the app has background ("Always") location permission.
    public var hasBackgroundPermission: Bool {
        return getPermissionStatus() == 3
    }

    /// Get the current location provider state.
    ///
    /// - Returns: Provider state dictionary.
    public func getProviderState() -> [String: Any] {
        let status = permissionManager.getAuthorizationStatus()
        let enabled = CLLocationManager.locationServicesEnabled()
        return [
            "enabled": enabled,
            "status": status,
            "gps": enabled,
            "network": enabled,
        ]
    }

    /// Get information about available device sensors.
    ///
    /// - Returns: Sensors dictionary.
    /// The location-filter thresholds actually in force in the Rust processor,
    /// or `nil` before one exists (#303).
    ///
    /// Deliberately reads the processor rather than `ConfigManager`: the two
    /// silently disagreeing is exactly the bug #303 fixed, so a getter answering
    /// from config could never surface a regression. While a transport-mode
    /// auto-tune is committed these are the tuned values, not the configured
    /// ones — which is what makes an auto-tune observable rather than a silent
    /// mutation.
    public func getCurrentLocationTuning() -> LocationTuning? {
        guard let engine = locationEngine else { return nil }
        return engine.currentTuning()
    }

    public func getSensors() -> [String: Any] {
        return [
            "accelerometer": true,
            "gyroscope": true,
            "magnetometer": true,
            "significantMotion": true,
            "motionActivity": isReady ? !configManager.getDisableMotionActivityUpdates() : true,
        ]
    }

    /// Get information about the device.
    ///
    /// - Returns: Device info dictionary.
    public func getDeviceInfo() -> [String: Any] {
        #if canImport(UIKit)
        let device = UIDevice.current
        return [
            "manufacturer": "Apple",
            "model": device.model,
            "platform": "ios",
            "version": device.systemVersion,
            "framework": "native",
        ]
        #else
        return [
            "manufacturer": "Apple",
            "model": "unknown",
            "platform": "ios",
            "version": ProcessInfo.processInfo.operatingSystemVersionString,
            "framework": "native",
        ]
        #endif
    }

    /// Play a debug sound effect.
    ///
    /// - Parameter name: Sound identifier.
    /// - Returns: `true` if the sound was played.
    @discardableResult
    public func playSound(_ name: String) -> Bool {
        guard isReady else { return false }
        let _ = soundManager.playSound(name)
        return true
    }

    // =========================================================================
    // MARK: - Logging
    // =========================================================================

    /// Get the plugin log as a string.
    ///
    /// - Parameter query: Optional query parameters.
    /// - Returns: Formatted log string.
    public func getLog(query: [String: Any]? = nil) -> String {
        guard isReady else { return "" }
        return logger.getLog(query: query)
    }

    /// Destroy all log entries.
    ///
    /// - Returns: `true` if logs were destroyed.
    @discardableResult
    public func destroyLog() -> Bool {
        guard isReady else { return false }
        return logger.destroyLog()
    }

    /// Write a custom log entry.
    ///
    /// - Parameters:
    ///   - level: Log level ("error", "warn", "info", "debug", "verbose").
    ///   - message: Log message.
    public func log(_ level: String, _ message: String) {
        guard isReady else { return }
        logger.log(levelString: level, message: message)
    }

    // =========================================================================
    // MARK: - Telematics
    // =========================================================================

    /// The most recent stored driving/impact events — **newest first, whether or
    /// not they have been synced** (#313).
    ///
    /// This is the history API behind `Tracelet.getTelematicsEvents()` and the
    /// Doctor bug report. It used to share the sync batcher's query
    /// (`WHERE synced = 0 ORDER BY id ASC`), which meant it returned the *oldest*
    /// events rather than the most recent, and that enabling `syncTelematics`
    /// silently emptied the app's own local history. Sync keeps that query via
    /// ``getUnsyncedTelematics(limit:)``.
    ///
    /// - Parameter limit: Maximum number of events to return.
    /// - Returns: Array of `DbTelematicsRecord` objects.
    public func getTelematicsEvents(limit: Int) -> [DbTelematicsRecord] {
        guard isReady, let db = rustDatabase else { return [] }
        do {
            return try db.getTelematicsHistory(limit: Int32(limit))
        } catch {
            TraceletLog.error("Failed to get telematics events: \(error)")
            return []
        }
    }

    /// Unsynced telematics events, oldest first — the *sync* view (#313).
    ///
    /// The batcher uploads these in id order and then marks everything up to the
    /// highest id synced, so this must stay ascending and must exclude anything
    /// already uploaded.
    private func getUnsyncedTelematics(limit: Int) -> [DbTelematicsRecord] {
        guard isReady, let db = rustDatabase else { return [] }
        do {
            return try db.getTelematicsEvents(limit: Int32(limit))
        } catch {
            TraceletLog.error("Failed to get unsynced telematics events: \(error)")
            return []
        }
    }

    /// Unsynced telematics events mapped for the custom sync-body builder context (#214).
    ///
    /// Returns an empty array unless `syncTelematics` is enabled — so apps that
    /// don't opt into telematics get no extra data and no overhead — matching the
    /// default payload's `__telematics` gating.
    public func getTelematicsForCustomBuilder(limit: Int = 250) -> [[String: Any]] {
        guard isReady, configManager.getSyncTelematics() else { return [] }
        let events = getUnsyncedTelematics(limit: limit)
        // Remember the highest id exposed so a successful sync marks exactly these
        // synced — avoids re-sending them every batch (#214 dedup).
        if let maxId = events.map({ $0.id }).max() {
            lastExposedTelematicsMaxId = maxId
        }
        // #367: additive — existing keys keep their names and meaning.
        return Self.telematicsDicts(events)
    }

    /// Highest telematics id handed to a custom builder via
    /// `getTelematicsForCustomBuilder`, marked synced on a successful custom-path
    /// sync (#214 dedup).
    private var lastExposedTelematicsMaxId: Int64 = 0

    /// Marks the telematics previously exposed to a custom builder as synced after
    /// a successful custom-path sync. No-op when nothing was exposed (default
    /// payload path), so it can't lose unsent telematics (#214 dedup).
    public func markExposedTelematicsSynced() {
        let maxId = lastExposedTelematicsMaxId
        guard maxId > 0 else { return }
        do {
            try rustDatabase?.markTelematicsSynced(maxId: maxId)
        } catch {
            TraceletLog.error("markTelematicsSynced failed: \(error)")
        }
        lastExposedTelematicsMaxId = 0
    }

    public func getLogs(limit: Int) -> [LogEntry] {
        guard let db = rustDatabase else { return [] }
        do {
            return try db.getLogs(limit: Int32(limit))
        } catch {
            TraceletLog.error("Failed to get logs: \(error)")
            return []
        }
    }
    
    public func clearLogs() {
        guard let db = rustDatabase else { return }
        do {
            try db.clearLogs()
        } catch {
            TraceletLog.error("Failed to clear logs: \(error)")
        }
    }

    /// Destroy all synced and unsynced telematics events.
    ///
    /// - Returns: `true` if cleared successfully.
    @discardableResult
    public func destroyTelematicsEvents() -> Bool {
        guard isReady, let db = rustDatabase else { return false }
        do {
            try db.clearTelematicsEvents()
            return true
        } catch {
            logger.error("Failed to clear telematics events: \(error)")
            return false
        }
    }

    /// Simulate a telematics event (e.g. for testing).
    ///
    /// - Parameters:
    ///   - eventType: The type of event (e.g. "harsh_braking").
    ///   - severity: Severity value (e.g. g-force).
    ///   - latitude: Event latitude.
    ///   - longitude: Event longitude.
    /// - Returns: `true` if inserted successfully.
    @discardableResult
    public func simulateTelematicsEvent(eventType: String, severity: Double, latitude: Double, longitude: Double) -> Bool {
        guard isReady, let db = rustDatabase else { return false }
        do {
            // #367: a simulated event has no measured magnitudes; 0.0 keeps the
            // public 4-arg signature (Pigeon + React Native) unchanged.
            try db.insertTelematicsEvent(
                eventType: eventType, severity: severity, speed: 0.0, value: 0.0,
                lat: latitude, lng: longitude)
            return true
        } catch {
            logger.error("Failed to simulate telematics event: \(error)")
            return false
        }
    }

    // =========================================================================
    // MARK: - Scheduling
    // =========================================================================

    /// Start the scheduler (uses the `schedule` array in config).
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func startSchedule() -> [String: Any] {
        guard isReady else { return getState() }
        scheduleManager.start()
        return stateManager.toMap(configManager.getConfig())
    }

    /// Stop the scheduler.
    ///
    /// - Returns: Updated state as a dictionary.
    @discardableResult
    public func stopSchedule() -> [String: Any] {
        guard isReady else { return getState() }
        scheduleManager.stop()
        return stateManager.toMap(configManager.getConfig())
    }

    // =========================================================================
    // MARK: - Enterprise: Audit Trail
    // =========================================================================

    /// Verify the integrity of the tamper-proof audit trail.
    ///
    /// - Returns: Verification result dictionary.
    public func verifyAuditTrail() -> [String: Any] {
        guard auditTrailManager != nil else { return [:] }
        return auditTrailManager.verifyChain()
    }

    /// Get the audit proof for a specific location record.
    ///
    /// - Parameter uuid: The location UUID.
    /// - Returns: Audit proof dictionary, or nil if not found.
    public func getAuditProof(_ uuid: String) -> [String: Any]? {
        guard auditTrailManager != nil else { return nil }
        return auditTrailManager.getProof(uuid: uuid)
    }

    // =========================================================================
    // MARK: - Enterprise: Privacy Zones
    // =========================================================================

    /// Add a single privacy zone.
    ///
    /// - Parameter zone: Privacy zone dictionary (identifier, latitude, longitude, radius, action).
    /// - Returns: `true` if the zone was added.
    @discardableResult
    public func addPrivacyZone(_ zone: [String: Any]) -> Bool {
        guard privacyZoneManager != nil else { return false }
        return privacyZoneManager.addZone(zone)
    }

    /// Add a single privacy zone using a typed ``TraceletPrivacyZone`` model.
    ///
    /// - Parameter zone: Typed privacy zone model.
    /// - Returns: `true` if the zone was added.
    @discardableResult
    public func addPrivacyZone(_ zone: TraceletPrivacyZone) -> Bool {
        return addPrivacyZone(zone.toMap())
    }

    /// Add multiple privacy zones at once.
    ///
    /// - Parameter zones: Array of privacy zone dictionaries.
    /// - Returns: `true` if all zones were added.
    @discardableResult
    public func addPrivacyZones(_ zones: [[String: Any]]) -> Bool {
        guard privacyZoneManager != nil else { return false }
        return privacyZoneManager.addZones(zones)
    }

    /// Add multiple privacy zones using typed ``TraceletPrivacyZone`` models.
    ///
    /// - Parameter zones: Array of typed privacy zone models.
    /// - Returns: `true` if all zones were added.
    @discardableResult
    public func addPrivacyZones(_ zones: [TraceletPrivacyZone]) -> Bool {
        return addPrivacyZones(zones.map { $0.toMap() })
    }

    /// Remove a privacy zone by its identifier.
    ///
    /// - Parameter identifier: The zone identifier.
    /// - Returns: `true` if the zone was removed.
    @discardableResult
    public func removePrivacyZone(_ identifier: String) -> Bool {
        guard privacyZoneManager != nil else { return false }
        return privacyZoneManager.removeZone(identifier)
    }

    /// Remove all privacy zones.
    ///
    /// - Returns: `true` if zones were removed.
    @discardableResult
    public func removePrivacyZones() -> Bool {
        guard privacyZoneManager != nil else { return false }
        return privacyZoneManager.removeAllZones()
    }

    /// Get all registered privacy zones.
    ///
    /// - Returns: Array of privacy zone dictionaries.
    public func getPrivacyZones() -> [[String: Any]] {
        guard privacyZoneManager != nil else { return [] }
        return privacyZoneManager.getZones()
    }

    // =========================================================================
    // MARK: - Enterprise: Device Attestation
    // =========================================================================

    /// Request a fresh device attestation token.
    ///
    /// - Parameter completion: Called with the attestation token dictionary, or nil.
    public func getAttestationToken(completion: @escaping ([String: Any]?) -> Void) {
        guard isReady else { completion(nil); return }
        deviceAttestor.requestToken(completion: completion)
    }

    // =========================================================================
    // MARK: - Enterprise: Dead Reckoning
    // =========================================================================

    /// Get the current dead reckoning state.
    ///
    /// - Returns: DR state dictionary, or nil if DR is disabled or GPS is available.

    // MARK: - Encryption

    public func isDatabaseEncrypted() -> Bool {
        return true
    }

    public func encryptDatabase() -> Bool {
        return true
    }


    public func getDeadReckoningState() -> [String: Any]? {
        // DR state is managed internally by LocationEngine — expose if active.
        return nil // TODO: Wire up when DeadReckoningEngine exposes state
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Create all subsystems. Call ``setEventSender(_:)`` first.
    ///
    /// Safe to call multiple times — returns immediately if already initialized.
    /// Called automatically by ``ready(config:)`` if not already invoked.
    /// Framework bridges (Flutter, React Native) should call this during plugin
    /// registration so that callback properties (e.g. ``httpSyncManager``'s
    /// ``onRequestFreshHeaders``) can be wired before ``ready()`` is called.
    public func initialize() {
        guard configManager == nil else { return }
        // Register bootstrap factory for headless/background restarts
        TraceletBootstrapIOS.eventSenderFactory = { [weak self] in
            self?.getEventSender() ?? DelegateEventSender()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        // The background edge was never observed at all, so a report could show
        // the app coming back but never leaving — and "tracking stops when I
        // background it" is a claim about exactly that boundary.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Persistence
        // Note: iOS does not need a separate DatabaseEncryptionManager.
        // Android uses SQLCipher (application-level AES-256 encryption)
        // managed by DatabaseEncryptionManager, whereas iOS uses
        // NSFileProtectionComplete (hardware-level, OS-managed encryption).
        // Auto-encryption is triggered in ready() if encryptDatabase=true.
        configManager = ConfigManager()
        stateManager = StateManager()
        // #304: the permission manager is constructed at field-init time, before
        // this config exists, so hand it the same instance setConfig writes to —
        // otherwise `disableLocationAuthorizationAlert` can never be observed.
        permissionManager.configManager = configManager

        // ── Rust Core bootstrap ──
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        let dbDir = documentsDirectory + "/tracelet"
        if !FileManager.default.fileExists(atPath: dbDir) {
            try? FileManager.default.createDirectory(atPath: dbDir, withIntermediateDirectories: true, attributes: nil)
        }
        let dbPath = dbDir + "/tracelet.db"
        do {
            let db = try DatabaseManager(dbPath: dbPath)
            
            let savedConfig = configManager.getConfig()
            if savedConfig["encryptDatabase"] as? Bool == true {
                let key = savedConfig["encryptionKey"] as? String ?? ""
                db.setEncryptionKey(key: key)
            } else {
                db.setEncryptionKey(key: "")
            }
            
            let state = EngineState()
            let dispatcher = EventDispatcher(db: db, state: state)
            self.rustDatabase = db
            
            self.rustEngineState = state
            self.rustPluginEventDispatcher = dispatcher
            syncConfigToRustFlat()
            TraceletLog.debug("Tracelet: Rust Core initialized at \(dbPath)")
        } catch {
            TraceletLog.error("Tracelet: Failed to initialize Rust Core: \(error)")
        }

        // Logger
        logger = TraceletLogger(configManager: configManager)
        logger.rustDatabase = rustDatabase
        TraceletLog.attach(logger)

        // Enterprise features
        auditTrailManager = AuditTrailManager(configManager: configManager, rustDatabase: rustDatabase)
        privacyZoneManager = PrivacyZoneManager(configManager: configManager, rustDatabase: rustDatabase)
        deviceAttestor = DeviceAttestor()
        remoteConfigManager = RemoteConfigManager(configManager: configManager) { [weak self] msg in
            self?.logger.info(msg)
        }

        // Location engine
        locationEngine = LocationEngine(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: eventSender
        )
        locationEngine.registerSink(RustDatabaseSinkWrapper(sdk: self))
        locationEngine.registerSink(TelematicsSinkWrapper(sdk: self))
        if let syncSink = syncProvider as? LocationDataSink {
            locationEngine.registerSink(syncSink)
        }
        locationEngine.rustPluginEventDispatcher = rustPluginEventDispatcher
        locationEngine.auditTrailManager = auditTrailManager
        locationEngine.privacyZoneManager = privacyZoneManager
        locationEngine.onLocationPersisted = { [weak self] in
            // Location persistence handled by Rust
        }

        // Trip manager
        tripManager = TraceletTripManager()
        // #402: the database is told the trip *before* any location for it is
        // written, so every row recorded during the trip is stamped with it.
        tripManager.onTripStart = { [weak self] data in
            self?.rustDatabase?.setActiveTripId(tripId: data["tripId"] as? String)
            self?.eventSender.sendTripStart(data)
        }
        tripManager.onTripEnd = { [weak self] data in
            self?.eventSender.sendTrip(data)
            // Cleared only after the summary is out, and never restored: the
            // next trip mints its own id.
            self?.rustDatabase?.setActiveTripId(tripId: nil)
        }

        // Motion detector
        motionDetector = MotionDetector(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: eventSender,
            logger: logger
        )
        motionDetector.onMotionStateChanged = { [weak self] isMoving in
            self?.handleMotionStateChange(isMoving)
        }
        // Keep the LocationEngine's activity in sync so enriched locations don't
        // report a permanent "unknown" (#155).
        motionDetector.onActivityChanged = { [weak self] type, confidence in
            self?.locationEngine.currentActivityType = type
            self?.locationEngine.currentActivityConfidence = confidence
        }
        // 3.3.0: feed accelerometer samples (g) to the classifier/impact keystone.
        motionDetector.onAccelSample = { [weak self] magnitudeG in
            self?.feedAccelSample(magnitudeG)
        }
        // #179: feed gyroscope samples (deg/s) for crash corroboration.
        motionDetector.onGyroSample = { [weak self] dps in
            guard let self = self, self.impactDetector != nil else { return }
            self.gyroBufferLock.lock()
            self.gyroBuffer.append(dps)
            self.gyroBufferLock.unlock()
        }
        // #173: feed barometer samples (hPa) for the cabin-pressure crash cue.
        motionDetector.onPressureSample = { [weak self] hpa in
            guard let self = self, self.impactDetector != nil else { return }
            self.baroBufferLock.lock()
            self.baroBuffer.append(hpa)
            self.baroBufferLock.unlock()
        }
        // #180: buffer raw total-g to detect a free-fall preceding a fall impact.
        motionDetector.onAccelRawSample = { [weak self] totalG in
            guard let self = self, self.impactDetector != nil else { return }
            self.rawAccelBufferLock.lock()
            self.rawAccelBuffer.append(totalG)
            self.rawAccelBufferLock.unlock()
        }
        motionDetector.onStopTimeoutStarted = { [weak self] in
            self?.locationEngine.overrideDistanceFilter(forStopTimeout: true, source: "MotionDetector")
        }
        motionDetector.onStopTimeoutCancelled = { [weak self] in
            self?.locationEngine.overrideDistanceFilter(forStopTimeout: false, source: "MotionDetector")
        }
        motionDetector.onStopRequested = { [weak self] in
            self?.stop()
        }

        // Geofencing
        geofenceManager = GeofenceManager(
            configManager: configManager,
            eventSender: eventSender,
            rustDatabase: rustDatabase
        )
        geofenceManager.onGeofenceEvent = { [weak self] eventData in
            self?.persistGeofenceIfAllowed(eventData)
        }
        
        // Smart motion coordinator
        smartMotionCoordinator = TraceletSmartMotionCoordinator(sdk: self)

        // HTTP sync is handled natively by Rust Core via PluginEventDispatcher


        // Scheduling
        scheduleManager = ScheduleManager(
            configManager: configManager,
            stateManager: stateManager,
            eventDispatcher: eventSender
        )
        scheduleManager.onScheduleStart = { [weak self] in self?.handleScheduleStart() }
        scheduleManager.onScheduleStop = { [weak self] in self?.handleScheduleStop() }

        // Utilities
        soundManager = SoundManager(configManager: configManager)

        // Battery monitoring
        BatteryUtils.initialize()

        // Background keep-alive managers
        preventSuspendManager = PreventSuspendManager(configManager: configManager)
        backgroundActivitySessionManager = BackgroundActivitySessionManager()
        serviceSessionManager = ServiceSessionManager()
        periodicRefreshScheduler = PeriodicRefreshScheduler()
        periodicRefreshScheduler.registerTask()
        periodicRefreshScheduler.onWakeUp = { [weak self] in
            guard let self = self,
                  self.stateManager.enabled,
                  self.stateManager.trackingMode == .periodic else { return }
            self.locationEngine.performPeriodicFix()
            self.locationEngine.restartPeriodicTimerIfNeeded()
        }

        // #182: on (re)launch, deliver any crash/fall confirmations whose
        // deadline elapsed while the app was killed/suspended.
        drainDueConfirmations()
    }

    // MARK: - Private: Background activity session

    /// Opens the iOS 17+ `CLBackgroundActivitySession` for continuous tracking —
    /// unless `useSignificantChangesOnly` is enabled.
    ///
    /// `CLBackgroundActivitySession` keeps a background location activity alive
    /// and auto-shows the system location indicator (Dynamic Island / status-bar
    /// pill), even when continuous GPS is not running. That defeats
    /// significant-change monitoring, whose entire purpose is low-power
    /// background location WITHOUT a persistent "ongoing location" indicator
    /// (Issue #261). Periodic mode and low-accuracy geofence-only mode already
    /// avoid the session for the same reason; this brings significant-changes-
    /// only into line with them.
    ///
    /// The indicator may still blink briefly when a significant-change event is
    /// delivered — that is normal iOS behavior and not a persistent session.
    private func startBackgroundActivitySessionIfNeeded() {
        if configManager.getUseSignificantChangesOnly() {
            logger.debug(
                "Not starting CLBackgroundActivitySession — useSignificantChangesOnly is enabled (#261)"
            )
            return
        }
        backgroundActivitySessionManager.start()
    }

    // MARK: - Private: Motion State

    private func handleMotionStateChange(_ isMoving: Bool) {
        // A CMMotionActivity callback can land after stop() — never let it
        // restart tracking (changePace/coordinator can start GPS again).
        guard stateManager.enabled else {
            logger.debug("handleMotionStateChange ignored — tracking is stopped")
            return
        }
        // #318: unlike Android there is no separate killed-state pipeline on iOS
        // — a relaunched process runs this same handler — so one entry covers
        // both. Read against the `relaunch:` entry above: transitions appearing
        // only *before* it means the relaunched session never detected motion,
        // while none at all after a resume points at CMMotionActivityManager
        // rather than at delivery.
        TraceletLog.lifecycle(
            "motion: isMoving=\(isMoving) mode=\(configManager.getMotionDetectionMode()) "
                + "launchedInBackground=\(stateManager.didLaunchInBackground)")
        if configManager.getMotionDetectionMode() == .smart {
            // In SMART mode, route the accel event through the coordinator first.
            // Only reset the speed state machine when the coordinator actually
            // decides to SWITCH_TO_CONTINUOUS (a genuine wake-up from stationary).
            // This prevents micro-vibrations from the significant motion sensor
            // from force-resetting the speed SM on every fire (infinite loop),
            // while still allowing the system to wake from stationary when the
            // coordinator determines real movement has begun.
            let action = smartMotionCoordinator.onAccelStateChange(isMoving: isMoving)
            if action == .switchToContinuous {
                speedMotionManager?.onManualPaceChange(isMoving: true)
            }
            return
        }

        TraceletLog.debug("[Tracelet] Motion state changed: isMoving=\(isMoving)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stateManager.isMoving = isMoving
            self.locationEngine.changePace(isMoving)

            if isMoving {
                self.startBackgroundActivitySessionIfNeeded()
            } else {
                self.backgroundActivitySessionManager.stop()
            }

            // Feed TripManager with motion state change
            let lastLoc = self.locationEngine.getLastLocation()
            self.tripManager.onMotionStateChanged(
                isMoving: isMoving,
                latitude: lastLoc?.coordinate.latitude,
                longitude: lastLoc?.coordinate.longitude,
                timestamp: lastLoc.map { ISO8601DateFormatter().string(from: $0.timestamp) }
            )
        }
    }

    // MARK: - Private: Schedule

    private func handleScheduleStart() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.stateManager.enabled else { return }
            self.start()
        }
    }

    private func handleScheduleStop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.stateManager.enabled else { return }
            self.stop()
        }
    }

    // MARK: - Private: Heartbeat

    /// Last location timestamp persisted by a heartbeat — used to deduplicate DB writes.
    private var lastHeartbeatLocationTime: TimeInterval = 0

    /// Re-aligns the engine with the committed motion state (#319).
    ///
    /// The Android counterpart fixes a confirmed field failure: its motion
    /// subsystems can settle back into stationary *without* emitting a
    /// transition, and because the engine's mode is switched only from those
    /// transitions it kept running continuous GPS — location indicator pinned
    /// on, fixes every couple of seconds — until the app was next opened.
    ///
    /// iOS has no reproduction of that specific trigger, and is less exposed to
    /// it: the Android path runs through `MotionDetector.onManualPaceChange()`
    /// reconfiguring sensors directly, which has no iOS equivalent because
    /// `CMMotionActivityManager` runs continuously regardless of the tracking
    /// mode. This is therefore a safety net rather than a port of a known bug.
    ///
    /// It is still worth having on both platforms. The failure is silent, costs
    /// the user battery for the rest of the session, and every other way of
    /// reaching it — a queued callback landing after a mode switch, a
    /// force-switch bailing on its `stateManager.enabled` guard after the state
    /// was already written — leaves the same divergence. Reconciling on the
    /// heartbeat bounds the damage to one interval, and the lifecycle entry
    /// makes it visible in a bug report instead of invisible.
    ///
    /// `stateManager.isMoving` is the authority: `switchToContinuousForce()` and
    /// `switchToStationaryPeriodicForce()` both write it as they switch, so it
    /// is the committed intent rather than a competing opinion.
    private func reconcileTrackingMode() {
        guard stateManager.enabled else { return }
        // Only continuous sessions run the stationary/continuous split; periodic
        // and geofence modes own their own scheduling.
        guard stateManager.trackingMode == .continuous else { return }

        let wantsStationary = !stateManager.isMoving
        let isStationary = locationEngine.isPeriodicTracking
        guard wantsStationary != isStationary else { return }

        if wantsStationary {
            TraceletLog.lifecycle(
                "motion: engine was still tracking continuously while the "
                    + "committed state is stationary — switching to stationary "
                    + "periodic (#319)")
            switchToStationaryPeriodicForce()
        } else {
            TraceletLog.lifecycle(
                "motion: engine was in stationary periodic while the committed "
                    + "state is moving — resuming continuous (#319)")
            switchToContinuousForce()
        }
    }

    private func startHeartbeat() {
        stopHeartbeat()
        let interval = configManager.getHeartbeatInterval()
        guard interval > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(interval),
                repeats: true
            ) { [weak self] _ in
                guard let self = self else { return }
                TraceletLog.debug("[Tracelet] Heartbeat fired")
                self.reconcileTrackingMode()
                guard let location = self.locationEngine.getLastGpsLocation() else {
                    if self.configManager.isDebug() {
                        TraceletLog.debug("[Tracelet] Heartbeat: no cached location, skipping")
                    }
                    return
                }
                // Build a fully enriched location map with UUID, battery, etc.
                var locationMap = self.locationEngine.buildLocationMap(location)
                locationMap["event"] = "heartbeat"

                // Only persist to DB if this is a genuinely new GPS fix
                // (different timestamp from the last heartbeat write).
                // This avoids hundreds of redundant DB inserts per hour
                // when the user is stationary and the cached location
                // hasn't changed.
                let fixTime = location.timestamp.timeIntervalSince1970
                if fixTime != self.lastHeartbeatLocationTime {
                    self.lastHeartbeatLocationTime = fixTime
                    let _ = self.insertLocation(locationMap)
                    self.locationEngine.onLocationPersisted?()
                }

                // Always send the event so Flutter UI stays alive
                let data: [String: Any] = ["location": locationMap]
                self.eventSender.sendHeartbeat(data)
                TraceletLog.debug(String(format: "[Tracelet] Heartbeat: lat=%.6f, lon=%.6f, accuracy=%.1fm",
                      location.coordinate.latitude, location.coordinate.longitude,
                      location.horizontalAccuracy))
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Private: Interval-based sync (#149)

    /// Starts the interval-based sync timer.
    ///
    /// When `HttpConfig.syncInterval` (seconds) is greater than 0 and auto-sync is
    /// enabled, the SDK periodically flushes any pending locations to the configured
    /// endpoint on this cadence — independent of the `autoSyncDelay` debounce that
    /// fires on new inserts. A value of 0 (the default) leaves the timer disabled.
    private func startSyncIntervalTimer() {
        stopSyncIntervalTimer()
        let interval = configManager.getSyncInterval()
        guard interval > 0, configManager.getAutoSync() else { return }
        guard !configManager.getUrl().isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            self?.syncIntervalTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(interval),
                repeats: true
            ) { [weak self] _ in
                guard let self = self, self.isReady else { return }
                self.sync(completion: nil)
            }
        }
        TraceletLog.debug(String(format: "[Tracelet] syncInterval timer started (%ds)", interval))
    }

    private func stopSyncIntervalTimer() {
        syncIntervalTimer?.invalidate()
        syncIntervalTimer = nil
    }

    // MARK: - 3.3.0 behavior engines (telematics / classifier / impact)

    private func initBehaviorEngines() {
        telematicsEngine = configManager.getEnableDrivingEvents()
            ? TelematicsEngine(config: TelematicsConfig(
                harshBrakingG: configManager.getHarshBrakingG(),
                harshAccelerationG: configManager.getHarshAccelerationG(),
                harshCorneringG: configManager.getHarshCorneringG(),
                speedLimitKmh: configManager.getSpeedLimitKmh(),
                speedingToleranceKmh: configManager.getSpeedingToleranceKmh(),
                speedingMinDurationMs: configManager.getSpeedingMinDurationMs(),
                minSpeedForEventsKmh: configManager.getMinSpeedForEventsKmh(),
                eventDebounceMs: configManager.getEventDebounceMs()))
            : nil

        transportClassifier = configManager.getEnableFusedClassifier()
            ? TransportModeClassifier(config: ClassifierConfig(
                modeSwitchDwellMs: configManager.getModeSwitchDwellMs(),
                minConfidence: configManager.getMinModeConfidence()))
            : nil

        // #299: classify from raw pre-filter speeds. Left attached while the
        // classifier exists and detached with it, so a disabled classifier costs
        // nothing on the location path.
        locationEngine?.rawSpeedSink = transportClassifier != nil
            ? { [weak self] speed in self?.lastRawSpeedMps = speed }
            : nil

        impactDetector = (configManager.getEnableCrashDetection() || configManager.getEnableFallDetection())
            ? ImpactDetector(config: ImpactConfig(
                enableCrash: configManager.getEnableCrashDetection(),
                enableFall: configManager.getEnableFallDetection(),
                crashGThreshold: configManager.getCrashGThreshold(),
                crashMinSpeedKmh: configManager.getCrashMinSpeedKmh(),
                fallGThreshold: configManager.getFallGThreshold(),
                confirmWindowMs: configManager.getConfirmWindowMs(),
                minConfidence: configManager.getMinImpactConfidence()))
            : nil

        // Crash/fall impulses peak in ~50-150 ms, far faster than the 10 Hz used
        // for motion detection. When impact detection is active, sample the
        // accelerometer at a higher rate so the peak is actually captured (battery
        // cost is accepted because the feature is opt-in).
        motionDetector?.impactHighRate = (impactDetector != nil)
        motionDetector?.gyroEnabled = (impactDetector != nil)   // #179 gyro corroboration
        motionDetector?.baroEnabled = (impactDetector != nil)   // #173 barometer cue

        // #183: opt-in ML crash model. Download/decrypt off the main thread; until
        // (or unless) it loads, the rule engine is used. Loaded only when crash
        // detection is on AND a model URL (or licensing unlock endpoint) is set.
        crashModel = nil
        let crashUrl = configManager.getCrashModelUrl()
        let unlockUrl = configManager.getCrashModelUnlockUrl()
        let licenseKey = configManager.getCrashModelLicenseKey()
        if configManager.getEnableCrashDetection() && (crashUrl != nil || unlockUrl != nil) {
            let sha = configManager.getCrashModelSha256()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                var modelUrl = crashUrl
                var modelSha = sha
                if let unlockUrl = unlockUrl, let licenseKey = licenseKey {
                    self.emitCrashModelStatus("unlocking")
                    let token = CrashModelLoader.integrityTokenProvider?()
                    if let unlocked = CrashModelLoader.unlock(
                        unlockUrl: unlockUrl, licenseKey: licenseKey, integrityToken: token,
                        log: { [weak self] msg in self?.logger.debug(msg) }
                    ) {
                        modelUrl = unlocked.url
                        modelSha = unlocked.sha256 ?? modelSha
                    } else {
                        self.emitCrashModelStatus("failed", "license unlock failed")
                    }
                }
                guard let url = modelUrl else { return }
                self.emitCrashModelStatus("downloading")
                if let m = CrashModelLoader.load(
                    url: url, sha256: modelSha,
                    log: { [weak self] msg in self?.logger.debug(msg) }
                ) {
                    self.crashModel = m
                    self.logger.info("Crash ML model active.")
                    self.emitCrashModelStatus("ready", "\(m.treeCount()) trees")
                } else {
                    self.emitCrashModelStatus("failed", "model download or decrypt failed")
                }
            }
        }
    }

    /// Forwards an ML crash-model lifecycle status to the host (best-effort).
    private func emitCrashModelStatus(_ status: String, _ detail: String? = nil) {
        var data: [String: Any] = ["status": status]
        if let detail = detail { data["detail"] = detail }
        eventSender.sendCrashModelStatus(data)
    }

    /// Feeds an accepted location fix to the telematics engine and emits events.
    func processTelematics(_ location: [String: Any]) {
        let coords = location["coords"] as? [String: Any] ?? location
        let speed = (coords["speed"] as? Double) ?? 0.0
        let heading = (coords["heading"] as? Double) ?? -1.0
        let lat = (coords["latitude"] as? Double) ?? 0.0
        let lng = (coords["longitude"] as? Double) ?? 0.0
        // Capture speed/position + ML speed-history unconditionally — crash
        // detection can run without driving events.
        lastSpeedMps = speed
        lastLat = lat
        lastLng = lng
        recordSpeedSample(speed)
        guard let engine = telematicsEngine else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let events = engine.processFix(speed: speed, heading: heading, latitude: lat, longitude: lng, timestampMs: nowMs)
        for e in events {
            eventSender.sendDrivingEvent([
                "kind": e.kind, "severity": e.severity, "speed": e.speed,
                "value": e.value, "latitude": e.latitude, "longitude": e.longitude,
                "timestampMs": e.timestampMs,
            ])
            // Persist to the telematics DB so getTelematicsEvents() returns the
            // real history (not just Doctor-simulated events).
            // #367: `speed` and `value` are the magnitudes behind the normalized
            // severity — persist them, or stored history and every synced payload
            // keeps only the flag.
            try? rustDatabase?.insertTelematicsEvent(
                eventType: e.kind, severity: e.severity, speed: e.speed, value: e.value,
                lat: e.latitude, lng: e.longitude)
        }
    }

    /// Buffers one accelerometer sample (gravity-subtracted g) for the window loop.
    func feedAccelSample(_ magnitudeG: Double) {
        guard transportClassifier != nil || impactDetector != nil else { return }
        accelBufferLock.lock()
        accelBuffer.append(magnitudeG)
        accelBufferLock.unlock()
    }

    /// Re-aligns the location processor's thresholds with the classifier's
    /// committed transport mode (#301).
    ///
    /// Auto-tuning only ever fires on a *committed mode change*, which makes it
    /// blind to everything else that can move the two out of step:
    ///
    /// - `setConfig()` rebuilds the processor for a location-key change, resetting
    ///   it to the configured thresholds while the committed mode stays put — so
    ///   a user who never changes activity keeps the base thresholds forever.
    /// - Turning `autoTuneFromTransportMode` off leaves the last applied tuning in
    ///   force, since the next commit returns early before it can restore.
    /// - Turning `enableFusedClassifier` off destroys the classifier, so no
    ///   further commit ever arrives to undo the tuning.
    ///
    /// Calling this after any reconfiguration closes all three: with auto-tuning
    /// off it restores the host's own values, and with it on it re-applies the
    /// mode currently committed (`unknown` also restores).
    /// #303: this path changes the four thresholds without any `modeChange` event
    /// — the mode did not change, so synthesising one would corrupt the event
    /// stream for consumers that count commits. It is logged instead, at INFO for
    /// the same reason the geofence decision trace is: the symptom (filters not
    /// behaving as configured) is reported days later from a bug report, and
    /// DEBUG is not on in production.
    private func syncTransportModeTuning() {
        guard let engine = locationEngine else { return }
        guard configManager.getAutoTuneFromTransportMode() else {
            engine.restoreBaseTuning()
            TraceletLog.info(
                "auto-tune: off — reconfiguration restored the configured thresholds "
                    + "(\(engine.currentTuningDescription()))"
            )
            return
        }
        let mode = transportClassifier.map { String(describing: $0.currentMode()).lowercased() }
            ?? "unknown"
        engine.applyTransportModeTuning(mode)
        TraceletLog.info(
            "auto-tune: reconfiguration re-aligned thresholds with committed mode "
                + "'\(mode)' (\(engine.currentTuningDescription()))"
        )
    }

    private func startBehaviorSampling() {
        stopBehaviorSampling()
        guard transportClassifier != nil || impactDetector != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.accelWindowTimer = Timer.scheduledTimer(withTimeInterval: Self.accelWindowInterval, repeats: true) { [weak self] _ in
                self?.processAccelWindow()
            }
        }
    }

    private func stopBehaviorSampling() {
        accelWindowTimer?.invalidate(); accelWindowTimer = nil
        accelBufferLock.lock(); accelBuffer.removeAll(); accelBufferLock.unlock()
        gyroBufferLock.lock(); gyroBuffer.removeAll(); gyroBufferLock.unlock()
        rawAccelBufferLock.lock(); rawAccelBuffer.removeAll(); rawAccelBufferLock.unlock()
        baroBufferLock.lock(); baroBuffer.removeAll(); baroBufferLock.unlock()
        // #310: don't carry a previous session's feature window into a new one.
        crashFeatureHistoryLock.lock(); crashFeatureHistory.removeAll(); crashFeatureHistoryLock.unlock()
        // NOTE: the impact confirmation loop is intentionally NOT stopped here.
        // A crash typically ends in the vehicle stopping, which disables tracking
        // (stopTimeout) and would otherwise abandon a pending `potential_crash`
        // before its countdown elapses — so the confirmed `crash` would never
        // fire. The confirmation loop runs independently and self-terminates once
        // no candidates remain (see `ensureImpactConfirmLoop`).
    }

    /// Ensures the impact confirmation poll is running. Decoupled from tracking
    /// state: once a candidate is pending it keeps polling — across a tracking
    /// stop — until every candidate has confirmed (deadline elapsed), been
    /// confirmed explicitly, or cancelled. Self-terminates when nothing pends.
    private func ensureImpactConfirmLoop() {
        guard impactConfirmTimer == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.impactConfirmTimer == nil else { return }
            self.impactConfirmTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self, let detector = self.impactDetector else {
                    timer.invalidate()
                    self?.impactConfirmTimer = nil
                    return
                }
                let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                for e in detector.checkConfirmations(nowMs: nowMs) { self.emitImpact(e) }
                if detector.pendingCount() == 0 {
                    timer.invalidate()
                    self.impactConfirmTimer = nil
                }
            }
        }
    }

    /// Records one GPS speed sample (m/s) into the rolling crash speed-history
    /// window, evicting samples older than `crashSpeedWindowMs` (#183).
    private func recordSpeedSample(_ speedMps: Double) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        speedHistoryLock.lock()
        speedHistory.append((now, speedMps))
        let cutoff = now - crashSpeedWindowMs
        while let first = speedHistory.first, first.0 < cutoff { speedHistory.removeFirst() }
        speedHistoryLock.unlock()
    }

    /// The speed (m/s) the device was carrying into an impact (#312).
    ///
    /// The maximum GPS speed over the last `crashPreImpactWindowMs`, falling back
    /// to the latest fix when no history has accumulated yet. Using the *latest*
    /// fix directly is what the crash gate used to do, and it loses real crashes:
    /// a collision collapses speed within 1–2 s, so a post-impact fix can land
    /// before the window containing the impact is scored, dropping the reported
    /// speed under `crashMinSpeedKmh` and failing the gate both the rule and the
    /// ML path sit behind.
    private func preImpactSpeedMps(_ nowMs: Int64) -> Double {
        speedHistoryLock.lock()
        let cutoff = nowMs - crashPreImpactWindowMs
        let recentMax = speedHistory.filter { $0.0 >= cutoff }.map { $0.1 }.max()
        speedHistoryLock.unlock()
        return max(recentMax ?? 0.0, lastSpeedMps)
    }

    /// Records one processed accel window's features into the rolling ~16 s
    /// history, evicting entries older than `crashSpeedWindowMs` (#310).
    private func recordCrashFeatureWindow(_ nowMs: Int64, _ window: AccelWindow, _ gyroPeakDps: Double) {
        crashFeatureHistoryLock.lock()
        crashFeatureHistory.append(
            AccelWindowFeatures(
                timestampMs: nowMs, peakG: window.peakG, meanG: window.meanG,
                gyroPeakDps: gyroPeakDps))
        let cutoff = nowMs - crashSpeedWindowMs
        while let first = crashFeatureHistory.first, first.timestampMs < cutoff {
            crashFeatureHistory.removeFirst()
        }
        crashFeatureHistoryLock.unlock()
    }

    /// Builds the crash model's feature vector, ordered to match
    /// `model.featureNames()`. peak_g/mean_g in g, gyro_peak_dps in deg/s,
    /// speed_max/dv (pre-impact speed drop) in km/h (#183).
    ///
    /// Every feature is aggregated over the same ~16 s window the model was
    /// trained on (#310) — `peak_g`/`gyro_peak_dps` as the maximum across the
    /// window's 1 s slices, `mean_g` as their mean, `speed_max`/`dv` from the GPS
    /// speed history. Detection still runs once a second; only the *features* are
    /// widened, so a spike is scored in the context the model expects rather than
    /// against a 1 s slice it never saw in training.
    ///
    /// Call `recordCrashFeatureWindow` for the current window first, so it is
    /// included here.
    private func crashFeatureVector(_ model: CrashModel) -> [Double] {
        speedHistoryLock.lock()
        let speedsKmh = speedHistory.map { $0.1 * 3.6 }
        speedHistoryLock.unlock()
        let speedMax = speedsKmh.max() ?? (lastSpeedMps * 3.6)
        let speedMin = speedsKmh.min() ?? (lastSpeedMps * 3.6)

        crashFeatureHistoryLock.lock()
        let windows = crashFeatureHistory
        crashFeatureHistoryLock.unlock()
        let peakG = windows.map { $0.peakG }.max() ?? 0.0
        let meanG = windows.isEmpty
            ? 0.0
            : windows.reduce(0.0) { $0 + $1.meanG } / Double(windows.count)
        let gyroPeak = windows.map { $0.gyroPeakDps }.max() ?? 0.0

        let byName: [String: Double] = [
            "peak_g": peakG,
            "mean_g": meanG,
            "gyro_peak_dps": gyroPeak,
            "speed_max": speedMax,
            "dv": speedMax - speedMin,
        ]
        // Every declared name is guaranteed to be present: the Rust core rejects
        // a model declaring anything outside its supported set at load (#309), so
        // a miss here is unreachable.
        return model.featureNames().map { byName[$0] ?? 0.0 }
    }

    /// Post-impact stillness — the third phase of the canonical fall signature
    /// (#180): free-fall → impact peak → the body coming to rest. From this
    /// window's total-acceleration trace (g), finds the impact peak and checks
    /// that the samples after it settle back near 1 g with little movement.
    static func isPostImpactStill(_ rawTotalG: [Double]) -> Bool {
        guard rawTotalG.count >= 6 else { return false }
        var peakIdx = 0
        var peakDev = 0.0
        for (i, v) in rawTotalG.enumerated() {
            let dev = abs(v - 1.0)
            if dev > peakDev {
                peakDev = dev
                peakIdx = i
            }
        }
        // Need a genuine impact and a few settling samples after it.
        guard peakDev >= 0.5, peakIdx + 3 < rawTotalG.count else { return false }
        let tail = rawTotalG[(peakIdx + 1)...]
        return tail.allSatisfy { abs($0 - 1.0) < 0.3 }
    }

    /// Schedules a one-shot post-impact GPS speed read ~`crashDvDelaySeconds`
    /// after a crash candidate and folds it into the core's Δv corroboration
    /// (#181). A sharp speed collapse (e.g. 60 → 0 km/h) raises the candidate's
    /// confidence; a maintained speed leaves it unchanged (never suppressed).
    private func scheduleDvCorroboration() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.crashDvDelaySeconds) { [weak self] in
            guard let self, let detector = self.impactDetector else { return }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            if detector.corroborateDv(speedAfterMps: self.lastSpeedMps, nowMs: nowMs) {
                self.logger.debug("crash Δv: post-impact speed collapse corroborated (#181)")
            }
        }
    }

    private func processAccelWindow() {
        accelBufferLock.lock()
        let samples = accelBuffer
        accelBuffer.removeAll()
        accelBufferLock.unlock()
        guard !samples.isEmpty else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let window = computeAccelWindow(magnitudesG: samples, durationMs: Int64(Self.accelWindowInterval * 1000))

        if let classifier = transportClassifier {
            // #299: classify from raw pre-filter speeds, so auto-tuning the distance
            // filter cannot feed back into the mode that selected it.
            let result = classifier.classify(window: window, speedMps: lastRawSpeedMps, nowMs: nowMs)
            // #214 pt3: keep the engine's fused mode fresh every window so it can be
            // persisted into the location's activity column when authoritative.
            let mode = String(describing: result.mode).lowercased()
            locationEngine?.fusedTransportMode = mode
            locationEngine?.fusedTransportModeConfidence = result.confidence
            if result.changed {
                // #299: retune the location filters for the newly committed mode.
                // Only on a *commit* — confidence-gated and dwell-debounced — so the
                // thresholds cannot chatter with per-window classification noise.
                let tuning = locationEngine?.applyTransportModeTuning(mode)
                var payload: [String: Any] = [
                    "mode": mode,
                    "confidence": result.confidence,
                ]
                // Report the applied thresholds so an auto-tune is visible to the
                // host rather than being a silent config mutation.
                if let tuning = tuning {
                    payload["appliedTuning"] = [
                        "distanceFilter": tuning.distanceFilter,
                        "trackingAccuracyThreshold": tuning.trackingAccuracyThreshold,
                        "odometerAccuracyThreshold": tuning.odometerAccuracyThreshold,
                        "maxImpliedSpeed": tuning.maxImpliedSpeed,
                    ]
                }
                eventSender.sendModeChange(payload)
            }
        }
        if let detector = impactDetector {
            // #312: the speed carried into the impact, not the latest fix — which
            // by now may already be the post-crash one. Drives both the speed gate
            // and the on-foot fall context so the two stay coherent.
            let speedBeforeMps = preImpactSpeedMps(nowMs)
            let onFoot = speedBeforeMps * 3.6 < configManager.getCrashMinSpeedKmh()
            // Peak rotation (deg/s) over this window — crash corroboration (#179).
            gyroBufferLock.lock()
            let gyroPeak = gyroBuffer.max() ?? 0.0
            gyroBuffer.removeAll()
            gyroBufferLock.unlock()
            // Cabin-pressure swing (hPa) over this window — crash corroboration
            // (#173). peak−trough of the buffered barometer samples; 0 when the
            // device has no barometer (buffer stays empty), so the cue is
            // strictly best-effort and never suppresses.
            baroBufferLock.lock()
            let baroDelta = (baroBuffer.count >= 2) ? ((baroBuffer.max() ?? 0.0) - (baroBuffer.min() ?? 0.0)) : 0.0
            baroBuffer.removeAll()
            baroBufferLock.unlock()
            // Free-fall preceding the impact — fall corroboration (#180).
            rawAccelBufferLock.lock()
            let rawTotalG = rawAccelBuffer
            let minTotalG = rawAccelBuffer.min()
            rawAccelBuffer.removeAll()
            rawAccelBufferLock.unlock()
            let wasInFreeFall = (minTotalG ?? 1.0) < 0.5
            // Third phase of the canonical fall signature (#180) — the body
            // coming to rest after the jolt, derived from the same window.
            let postImpactStill = Self.isPostImpactStill(rawTotalG)
            // #183 ML gating (Replace mode): when the opt-in model is loaded, run
            // inference for this window and let its probability decide the crash
            // (still speed-gated in the core). crashProba < 0 ⇒ rule engine.
            // #310: fold this window into the rolling ~16 s feature history so the
            // model is scored over the window it was trained on.
            recordCrashFeatureWindow(nowMs, window, gyroPeak)
            var crashProba = -1.0
            if let model = crashModel {
                crashProba = model.predictProba(features: crashFeatureVector(model))
            }
            // Observability (#183): surface each real model inference so the
            // model path can be verified on-device. Only logged when the model
            // actually ran (crashProba >= 0) and the window has a notable peak,
            // to avoid spamming the ~1 Hz idle loop.
            if crashProba >= 0.0 && window.peakG > 1.5 {
                let thr = configManager.getCrashModelThreshold()
                let verdict = crashProba >= thr ? "CRASH" : "below-threshold"
                logger.debug(
                    String(
                        format: "crash model: proba=%.3f peak=%.2fg speed=%.1fkm/h thr=%.3f → %@",
                        crashProba, window.peakG, speedBeforeMps * 3.6, thr, verdict
                    )
                )
            }
            if let candidate = detector.onImpactWindow(peakG: window.peakG, speedBeforeMps: speedBeforeMps, gyroPeakDps: gyroPeak, wasInFreeFall: wasInFreeFall, postImpactStill: postImpactStill, isOnFoot: onFoot, latitude: lastLat, longitude: lastLng, nowMs: nowMs, crashProba: crashProba, crashProbaThreshold: configManager.getCrashModelThreshold()) {
                emitImpact(candidate)
                // Keep the countdown alive even if tracking stops right after the
                // crash (vehicle comes to rest → stopTimeout disables tracking).
                ensureImpactConfirmLoop()
                // #181: a real crash collapses the vehicle's speed within ~1–2 s.
                // Sample the post-impact GPS speed shortly after to corroborate.
                if candidate.kind == "potential_crash" {
                    scheduleDvCorroboration()
                    // #173: a severe collision / airbag deployment spikes cabin
                    // pressure. The transient is concurrent with the impact, so
                    // fold this window's pressure swing in immediately. A flat or
                    // absent barometer leaves confidence unchanged.
                    if baroDelta > 0.0 {
                        if detector.corroborateBarometric(pressureDeltaHpa: baroDelta, nowMs: nowMs) {
                            logger.debug("crash barometer: cabin-pressure spike corroborated (#173)")
                        }
                    }
                }
                // #182: persist the candidate and arm a process-death safety net
                // so the confirmation still fires if iOS suspends/kills the app
                // before its in-process countdown elapses.
                if candidate.kind.hasPrefix("potential_") {
                    scheduleProcessDeathSafeConfirm(candidate)
                }
            }
        }
    }

    /// Persists a pending crash/fall candidate and schedules a user-facing local
    /// notification just past its confirmation deadline (#182). If iOS kills the
    /// app during the countdown — common after a violent impact — the
    /// notification still alerts the user, and `drainDueConfirmations()` re-emits
    /// the confirmed event when the SDK next runs.
    private func scheduleProcessDeathSafeConfirm(_ candidate: ImpactEvent) {
        let p = PendingImpact(
            id: candidate.id,
            kind: candidate.kind,
            confidence: candidate.confidence,
            peakG: candidate.peakG,
            speedBefore: candidate.speedBefore,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            timestampMs: candidate.timestampMs,
            confirmDeadlineMs: candidate.confirmDeadlineMs,
        )
        CrashConfirmStore.shared.put(p)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let delaySeconds = Double(p.confirmDeadlineMs + Self.crashConfirmGuardMs - nowMs) / 1000.0
        CrashConfirmNotifier.schedule(p, delaySeconds: delaySeconds)
    }

    /// Re-emits a confirmed crash/fall from a persisted candidate (#182). Called
    /// by `drainDueConfirmations()` when the app was killed during the
    /// confirmation countdown, so the host's escalation/SOS flow still runs.
    /// Mirrors the confirmed-event side of `emitImpact` without touching the
    /// (now-gone) in-memory Rust detector.
    func deliverConfirmedImpact(_ p: PendingImpact) {
        eventSender.sendImpact([
            "kind": p.confirmedKind, "id": p.id, "confidence": p.confidence, "peakG": p.peakG,
            "speedBefore": p.speedBefore, "latitude": p.latitude, "longitude": p.longitude,
            "timestampMs": p.timestampMs, "confirmDeadlineMs": p.confirmDeadlineMs,
        ])
        // #367: peak g and the speed going in are an impact's magnitudes, the
        // same role speed/value play for a driving event.
        try? rustDatabase?.insertTelematicsEvent(
            eventType: p.confirmedKind, severity: p.confidence, speed: p.speedBefore,
            value: p.peakG, lat: p.latitude, lng: p.longitude)
    }

    /// Delivers any crash/fall candidates whose deadline elapsed while the app
    /// was suspended or killed (#182). Called on init and on foreground.
    private func drainDueConfirmations() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        for due in CrashConfirmStore.shared.due(nowMs: nowMs, guardMs: Self.crashConfirmGuardMs) {
            guard let claimed = CrashConfirmStore.shared.claim(due.id) else { continue }
            logger.debug("crash confirm: delivering process-death-survived \(claimed.confirmedKind) #\(claimed.id) (#182)")
            deliverConfirmedImpact(claimed)
            CrashConfirmNotifier.cancel(id: claimed.id)
        }
    }

    private func emitImpact(_ e: ImpactEvent) {
        eventSender.sendImpact([
            "kind": e.kind, "id": e.id, "confidence": e.confidence, "peakG": e.peakG,
            "speedBefore": e.speedBefore, "latitude": e.latitude, "longitude": e.longitude,
            "timestampMs": e.timestampMs, "confirmDeadlineMs": e.confirmDeadlineMs,
        ])
        // Persist confirmed impacts (not transient potential_* candidates, which
        // may still be cancelled) to the telematics DB for history/retrieval.
        if e.kind == "crash" || e.kind == "fall" {
            // #367: as above — peak g and entry speed are the impact's magnitudes.
            try? rustDatabase?.insertTelematicsEvent(
                eventType: e.kind, severity: e.confidence, speed: e.speedBefore,
                value: e.peakG, lat: e.latitude, lng: e.longitude)
            // #182: an in-process confirmation just delivered this event — drop
            // the persisted candidate and cancel its safety-net notification so
            // the relaunch drain never re-emits a duplicate.
            CrashConfirmStore.shared.remove(e.id)
            CrashConfirmNotifier.cancel(id: e.id)
        }
    }

    /// Confirms a pending impact candidate (called from the Pigeon host API).
    public func confirmImpact(_ id: Int64) -> Bool {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard let confirmed = impactDetector?.confirm(id: id, nowMs: nowMs) else { return false }
        emitImpact(confirmed)
        return true
    }

    /// Cancels a pending impact candidate (called from the Pigeon host API).
    public func cancelImpact(_ id: Int64) -> Bool {
        // #182: drop the persisted candidate and disarm its safety net so a
        // cancelled candidate is never re-confirmed after a relaunch.
        CrashConfirmStore.shared.remove(id)
        CrashConfirmNotifier.cancel(id: id)
        return impactDetector?.cancel(id: id) ?? false
    }

    /// Debug (#183): runs one synthetic window through the REAL crash pipeline —
    /// the loaded ML model and the live `impactDetector` — so the model path can
    /// be verified without a physical impact. Requires crash detection enabled.
    ///
    /// The model scores 5 features (peak_g, mean_g, gyro_peak_dps, speed_max, dv),
    /// so a bare g-spike is correctly rejected. When `crashLike` is true we feed a
    /// realistic crash profile (rotation + speed + sudden deceleration); when
    /// false a benign bump (no rotation/speed) to show the model rejecting noise.
    public func debugRunCrashModelInference(_ peakG: Double, _ speedKmh: Double, _ crashLike: Bool = true) -> [String: Any?] {
        guard let detector = impactDetector else {
            return [
                "modelRan": false,
                "fired": false,
                "error": "crash detection not enabled — toggle it on and start tracking first",
            ]
        }
        let speedMps = speedKmh / 3.6
        // Synthesize a window: baseline ~1 g with a single spike at peakG.
        var samples = [Double](repeating: 1.0, count: 49)
        samples.append(peakG)
        let window = computeAccelWindow(
            magnitudesG: samples, durationMs: Int64(Self.accelWindowInterval * 1000))
        // Crash-like corroboration: high rotation + a full speed drop (dv) at the
        // given speed. Benign: no rotation, no speed drop (model should reject).
        let gyroPeak = crashLike ? 250.0 : 0.0
        let speedMax = speedKmh
        let dv = crashLike ? speedKmh : 0.0
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var crashProba = -1.0
        if let model = crashModel {
            let byName: [String: Double] = [
                "peak_g": window.peakG,
                "mean_g": window.meanG,
                "gyro_peak_dps": gyroPeak,
                "speed_max": speedMax,
                "dv": dv,
            ]
            crashProba = model.predictProba(features: model.featureNames().map { byName[$0] ?? 0.0 })
        }
        let threshold = configManager.getCrashModelThreshold()
        let modelRan = crashProba >= 0.0
        logger.debug(
            String(
                format: "crash model (debug): proba=%.3f peak=%.2fg gyro=%.0f speed=%.1fkm/h dv=%.1f thr=%.3f modelRan=%@",
                crashProba, window.peakG, gyroPeak, speedKmh, dv, threshold, modelRan ? "true" : "false"
            )
        )
        let candidate = detector.onImpactWindow(
            peakG: window.peakG, speedBeforeMps: speedMps, gyroPeakDps: gyroPeak,
            wasInFreeFall: false, postImpactStill: false,
            isOnFoot: speedKmh < configManager.getCrashMinSpeedKmh(),
            latitude: lastLat, longitude: lastLng, nowMs: nowMs,
            crashProba: crashProba, crashProbaThreshold: threshold)
        if let candidate = candidate {
            emitImpact(candidate)
            ensureImpactConfirmLoop()
        }
        return [
            "modelRan": modelRan,
            "proba": crashProba,
            "threshold": threshold,
            "peakG": window.peakG,
            "fired": candidate != nil,
            "kind": candidate?.kind,
        ]
    }

    // MARK: - Private: Battery Budget Sampling

    /// (Re)builds the battery-budget engine from the current config.
    ///
    /// A non-zero `batteryBudgetPerHour` creates the engine seeded with the
    /// current distance filter / accuracy; a zero (or negative) value disables
    /// it. Called both at `ready()` and from `setConfig()` so the budget can be
    /// turned on/off/retargeted at runtime — e.g. via remote config — instead of
    /// only taking effect on the next cold start (#battery-budget-remote-config).
    private func applyBatteryBudgetConfig() {
        let budgetPerHour = configManager.getBatteryBudgetPerHour()
        if budgetPerHour > 0 {
            batteryBudgetEngine = TraceletBatteryBudgetEngine(
                targetBudgetPerHour: budgetPerHour,
                initialDistanceFilter: configManager.getDistanceFilter(),
                initialAccuracyIndex: configManager.getDesiredAccuracy(),
                initialPeriodicInterval: configManager.getPeriodicLocationInterval()
            )
        } else {
            batteryBudgetEngine = nil
            // Turning the budget off must lift whatever it had imposed, or the
            // last overlay would outlive the engine that justified it (#396).
            locationEngine.applyBudgetOverlay(
                distanceFilter: nil, desiredAccuracy: nil, trackingAccuracyFloor: 0)
            periodicRefreshScheduler.applyBudgetInterval(nil)
        }
    }

    /// Re-seeds the ladder's floor after the app changes its own tracking
    /// parameters, so an overlay in force is recomputed against the new
    /// configuration rather than against the one it was built with (#396).
    private func syncBatteryBudgetConfigured() {
        guard let engine = batteryBudgetEngine else { return }
        engine.updateConfigured(
            distanceFilter: configManager.getDistanceFilter(),
            accuracyIndex: configManager.getDesiredAccuracy(),
            periodicInterval: configManager.getPeriodicLocationInterval()
        )
        let state = engine.throttleState
        guard state.level > 0 else { return }
        locationEngine.applyBudgetOverlay(
            distanceFilter: state.distanceFilter,
            desiredAccuracy: Int(state.desiredAccuracy),
            trackingAccuracyFloor: Int(state.trackingAccuracyFloor)
        )
        periodicRefreshScheduler.applyBudgetInterval(state.periodicInterval.map { Int($0) })
    }

    private func startBatteryBudgetSampling() {
        stopBatteryBudgetSampling()
        guard let engine = batteryBudgetEngine else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.batteryBudgetTimer = Timer.scheduledTimer(
                withTimeInterval: Self.batterySampleInterval,
                repeats: true
            ) { [weak self] _ in
                guard let self = self, self.stateManager.enabled else { return }

                // On external power the ladder comes all the way down. Skipping
                // the sample instead — as this did — left a throttle picked up
                // during a discharge in force for the rest of the session (#396).
                let event: TraceletBudgetAdjustmentEvent?
                if BatteryUtils.isCharging() {
                    event = engine.noteCharging()
                } else {
                    event = engine.processSample(Double(BatteryUtils.getBatteryLevel()))
                }

                guard let event else { return }
                self.applyBudgetThrottle(engine: engine, event: event)
            }
        }
    }

    private func stopBatteryBudgetSampling() {
        batteryBudgetTimer?.invalidate()
        batteryBudgetTimer = nil
    }

    /// Puts a ladder movement into force as an overlay on the location engine.
    ///
    /// The pre-ladder version of this wrote the throttled values into
    /// `ConfigManager` and restarted the engine. That is what made the throttle
    /// permanent and invisible at once: `distanceFilter: 0` — the documented
    /// "record every fix" opt-out — was clamped to 10 and written over the app's
    /// own value, so `retune`'s protection for a configured zero no longer had
    /// anything to protect, and `activeConfig` began reporting a configuration
    /// the app had never set. The restart was the other half: it rebuilt the
    /// processor with the throttled numbers as its *base* tuning (#393).
    ///
    /// The overlay does neither. The app's configuration is untouched, the
    /// engine keeps running, and the whole thing lifts by passing `nil`.
    private func applyBudgetThrottle(
        engine: TraceletBatteryBudgetEngine,
        event: TraceletBudgetAdjustmentEvent
    ) {
        let state = engine.throttleState
        let throttled = state.level > 0

        locationEngine.applyBudgetOverlay(
            distanceFilter: throttled ? state.distanceFilter : nil,
            desiredAccuracy: throttled ? Int(state.desiredAccuracy) : nil,
            trackingAccuracyFloor: Int(state.trackingAccuracyFloor)
        )
        // Periodic mode re-reads its interval when it schedules the next
        // wake-up, so the overlay reaches it without a restart.
        periodicRefreshScheduler.applyBudgetInterval(
            throttled ? state.periodicInterval.map { Int($0) } : nil)

        eventSender.sendBudgetAdjustment([
            "currentBatteryDrain": event.currentBatteryDrain,
            "targetBudget": event.targetBudget,
            "newDistanceFilter": event.newDistanceFilter,
            "newDesiredAccuracy": event.newDesiredAccuracy,
            "newPeriodicInterval": event.newPeriodicInterval as Any,
            "throttleLevel": state.level,
        ])

        // Lifecycle, not info: a throttle that silently changes how a session
        // behaves for the rest of its life is exactly the class of event a
        // released app has to be able to report (#397). It fires a handful of
        // times a session at most.
        TraceletLog.lifecycle(String(
            format: "battery budget: throttle level %d — drain %.1f%%/hr vs budget %.1f%%/hr "
                + "(measured over %.0fs, ±%.1f%%/hr); overlay df=%.1fm acc=%d floor=%dm cadence=×%.2f",
            state.level, state.lastDrain, event.targetBudget,
            state.lastMeasurementSeconds, state.lastMeasurementResolution,
            state.distanceFilter, state.desiredAccuracy, state.trackingAccuracyFloor,
            state.cadenceMultiplier))
    }

    // MARK: - Private: stopAfterElapsedMinutes

    private func startStopAfterElapsedTimer() {
        cancelStopAfterElapsedTimer()
        let minutes = configManager.getStopAfterElapsedMinutes()
        guard minutes > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            self?.stopAfterElapsedTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(minutes * 60),
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                BackgroundTaskHelper.shared.run("stopAfterElapsed") {
                    self.stateManager.enabled = false
                    self.stateManager.isMoving = false
                    self.locationEngine.stop()
                    self.motionDetector.stop()
                    self.stopHeartbeat()
                    self.periodicRefreshScheduler.stop()
                    self.preventSuspendManager.stop()
                    self.backgroundActivitySessionManager.stop()
                    self.serviceSessionManager.stop()
                    self.eventSender.sendEnabledChange(false)
                }
            }
        }
    }

    private func cancelStopAfterElapsedTimer() {
        stopAfterElapsedTimer?.invalidate()
        stopAfterElapsedTimer = nil
    }

    // MARK: - Private: Service Session

    /// Starts a `CLServiceSession` (iOS 18+) matching the user's permission.
    private func startServiceSessionForCurrentAuth() {
        let status = locationEngine.getAuthorizationStatus()
        switch status {
        case 3: // authorizedAlways
            serviceSessionManager.start()
        case 2: // authorizedWhenInUse
            serviceSessionManager.startWhenInUse()
        default:
            break
        }
    }

    // MARK: - Public: App Termination

    /// Called when the app is about to be terminated.
    ///
    /// Ensures significant location monitoring is registered so iOS will
    /// relaunch the app on the next cell-tower change. Also creates a
    /// fresh `CLLocationManager` to survive the teardown and explicitly
    /// starts significant location monitoring on it.
    ///
    /// **Important:** This does NOT survive user force-quit on iOS (swipe
    /// up from app switcher). Apple explicitly kills all location services
    /// in that scenario. This handles system-initiated termination only
    /// (memory pressure, OS updates, etc.).
    public func onAppWillTerminate() {
        guard stateManager != nil, stateManager.enabled else { return }
        guard configManager != nil, !configManager.getStopOnTerminate() else { return }

        TraceletLog.debug("[Tracelet] onAppWillTerminate: stopOnTerminate=false, ensuring significant location monitoring")

        // Create a standalone CLLocationManager that outlives the current
        // singleton teardown. By starting significant location monitoring
        // on a fresh manager, we guarantee iOS has an active registration
        // that will trigger a relaunch.
        let terminationManager = CLLocationManager()
        terminationManager.startMonitoringSignificantLocationChanges()
        // Store in a static to prevent deallocation before the process ends.
        TraceletSdk._terminationLocationManager = terminationManager

        TraceletLog.debug("[Tracelet] onAppWillTerminate: significant location monitoring registered on termination manager")
        // #318: the last thing written before the process dies, and the entry the
        // next session is read against. If a relaunch entry never follows this
        // one, iOS did not relaunch us — which is expected after a user force-quit
        // and a bug otherwise.
        TraceletLog.lifecycle(
            "termination: registered significant-location monitoring for relaunch "
                + "— mode=\(stateManager.trackingMode)")
    }

    /// Holds a reference to the CLLocationManager created at termination
    /// time so it isn't deallocated before the process exits.
    private static var _terminationLocationManager: CLLocationManager?

    // MARK: - Public: Auto-Resume from killed state

    /// Automatically resumes tracking after the app is relaunched from a
    /// killed state by a significant location change.
    ///
    /// Call this from `application(_:didFinishLaunchingWithOptions:)` when
    /// `LaunchOptionsKey.location` is present.
    public func autoResumeTracking() {
        TraceletLog.debug("[Tracelet] autoResumeTracking: starting")
        if configManager == nil {
            TraceletLog.debug("[Tracelet] autoResumeTracking: configManager nil, calling initialize()")
            initialize()
        }

        // #318: each guard below silently ends the session. Recorded so a report
        // of "it stopped tracking overnight" distinguishes "iOS never relaunched
        // us" from "we were relaunched and declined to resume" — and, in the last
        // case, says which precondition failed.
        //
        // Guard: stopOnTerminate means we should NOT resume after kill.
        if configManager.getStopOnTerminate() {
            TraceletLog.debug("[Tracelet] autoResumeTracking: stopOnTerminate=true, aborting")
            TraceletLog.lifecycle(
                "relaunch: declined to resume — stopOnTerminate=true")
            stateManager.enabled = false
            return
        }

        guard stateManager.enabled else {
            TraceletLog.debug("[Tracelet] autoResumeTracking: stateManager.enabled=false, aborting")
            TraceletLog.lifecycle(
                "relaunch: declined to resume — tracking was stopped before termination")
            return
        }

        let authStatus = locationEngine.getAuthorizationStatus()
        guard authStatus == 3 else { // authorizedAlways
            TraceletLog.debug("[Tracelet] autoResumeTracking: authStatus=\(authStatus), need 3 (Always), disabling")
            // Downgrading from Always is a common and entirely silent cause of
            // "it just stopped": the relaunch happens, then this disables tracking.
            TraceletLog.lifecycle(
                "relaunch: declined to resume — authorization is \(authStatus), "
                    + "needs Always(3); tracking disabled")
            stateManager.enabled = false
            return
        }

        stateManager.didLaunchInBackground = true
        let trackingMode = stateManager.trackingMode
        TraceletLog.debug("[Tracelet] autoResumeTracking: trackingMode=\(trackingMode), resuming")
        // #318: the anchor entry for every killed-state investigation on iOS — it
        // records that the relaunch actually resumed, in which mode, and what
        // motion state it inherited. Its *absence* in a bug report is the finding:
        // iOS never relaunched the app, or bailed at one of the guards above.
        TraceletLog.lifecycle(
            "relaunch: resuming after killed-state launch — mode=\(trackingMode) "
                + "isMoving=\(stateManager.isMoving) "
                + "highAccuracyGeofence=\(configManager.getGeofenceModeHighAccuracy())")

        // HTTP Sync is auto-started by Rust Core Config
        TraceletLog.debug("[Tracelet] autoResumeTracking: Rust SyncManager active")

        // Wire onLocationPersisted so persisted locations trigger HTTP auto-sync.
        // Without this, locations accumulate in SQLite but never sync.
        locationEngine.onLocationPersisted = {
            // Location persistence handled by Rust
        }

        // Re-register persisted geofences. addGeofence()/addGeofences() never
        // set trackingMode = .geofences — that is only the dedicated
        // geofence-only session startGeofences() starts — so gating this
        // inside the .geofences case below (as it used to be) left a
        // continuous- or periodic-tracking app's standalone geofences
        // unregistered after every killed-state relaunch, with nothing ever
        // restoring them. reRegisterAll() is a cheap no-op when there are no
        // persisted geofences, so calling it unconditionally is safe for every
        // mode (#353, mirrors the Android fix).
        let fenceCountBeforeRestore = geofenceManager.getGeofences().count
        geofenceManager.reRegisterAll()
        if fenceCountBeforeRestore > 0 {
            TraceletLog.lifecycle(
                "geofences: re-registered \(fenceCountBeforeRestore) geofence(s) "
                    + "after killed-state relaunch — mode=\(trackingMode) (#353)")
        }

        switch trackingMode {
        case .continuous:
            // Wire before start() so the high-accuracy geofence path requests
            // time-based delivery (distanceFilter=None) from the outset.
            wireGeofenceLocationCallbacks(includeTripWaypoints: true)
            locationEngine.start()
            let motionMode = configManager.getMotionDetectionMode()
            if motionMode == .speed {
                startSpeedMotionManager(forceMoving: stateManager.isMoving, isResume: true)
            } else if motionMode == .smart {
                startSpeedMotionManager(forceMoving: stateManager.isMoving, isResume: true)
                motionDetector.start()
            } else {
                motionDetector.start()
            }
            startHeartbeat()
            preventSuspendManager.start()
            startBackgroundActivitySessionIfNeeded()
            serviceSessionManager.start()

        case .geofences:
            wireGeofenceLocationCallbacks(includeTripWaypoints: false)
            // #316: take the same posture startGeofences() would. This case used
            // to start the engine and the background activity session
            // unconditionally, so every significant-location relaunch silently
            // converted a low-power geofence-only app into continuous tracking —
            // with the persistent blue location indicator #210 removed — for the
            // rest of the process lifetime.
            applyGeofenceModePosture(
                needsInAppEvaluation: geofenceManager.hasEvaluatorOwnedGeofences())

        case .periodic:
            locationEngine.startPeriodic()
            wireGeofenceLocationCallbacks(includeTripWaypoints: false)
            let interval = TimeInterval(configManager.getPeriodicLocationInterval())
            periodicRefreshScheduler.start(interval: interval)
            if configManager.getPreventSuspend() {
                preventSuspendManager.start()
            }
            // Do NOT start CLBackgroundActivitySession for periodic mode —
            // it causes a persistent location indicator in the status bar.
            startServiceSessionForCurrentAuth()

        @unknown default:
            break
        }
    }

    // MARK: - Enterprise: Carbon Report

    /// Generate a carbon emissions report for a time range.
    ///
    /// - Parameter query: Query parameters (startTime, endTime, transportMode).
    /// - Returns: Carbon report dictionary.
    public func getCarbonReport(query: [String: Any]? = nil) -> [String: Any] {
        guard isReady else {
            return [
                "totalCarbonGrams": 0.0,
                "carbonByMode": [String: Double](),
                "distanceByMode": [String: Double](),
                "totalTrips": 0
            ]
        }
        
        let locations = self.getLocations(query: query)
        
        var totalGrams = 0.0
        var carbonByMode = [String: Double]()
        var distanceByMode = [String: Double]()
        var prevLat = 0.0
        var prevLng = 0.0
        var tripCount = 0
        var wasMoving = false
        
        for location in locations {
            let coords = location["coords"] as? [String: Any]
            guard let lat = (coords?["latitude"] as? NSNumber)?.doubleValue ?? (location["latitude"] as? NSNumber)?.doubleValue,
                  let lng = (coords?["longitude"] as? NSNumber)?.doubleValue ?? (location["longitude"] as? NSNumber)?.doubleValue else {
                continue
            }
            
            let act = location["activity"] as? [String: Any]
            let actType = act?["type"] as? String ?? "unknown"
            
            let isMovingInt = location["is_moving"] as? Int
            let isMovingBool = location["is_moving"] as? Bool
            let isMoving = isMovingInt == 1 || isMovingBool == true
            
            if !wasMoving && isMoving {
                tripCount += 1
            }
            wasMoving = isMoving
            
            if prevLat != 0.0 && prevLng != 0.0 {
                let dist = GeoUtils.haversine(prevLat, prevLng, lat, lng)
                distanceByMode[actType] = (distanceByMode[actType] ?? 0.0) + dist
                let factor = carbonFactorForMode(actType)
                let grams = (dist / 1000.0) * factor
                carbonByMode[actType] = (carbonByMode[actType] ?? 0.0) + grams
                totalGrams += grams
            }
            prevLat = lat
            prevLng = lng
        }
        
        return [
            "totalCarbonGrams": totalGrams,
            "carbonByMode": carbonByMode,
            "distanceByMode": distanceByMode,
            "totalTrips": tripCount
        ]
    }

    private func carbonFactorForMode(_ mode: String) -> Double {
        switch mode {
        case "car": return 192.0
        case "bus": return 89.0
        case "train": return 41.0
        case "bicycle", "bike": return 0.0
        case "walking", "walk", "on_foot": return 0.0
        case "e-scooter", "scooter": return 35.0
        case "motorcycle": return 113.0
        case "plane", "flight": return 255.0
        default: return 192.0
        }
    }
    // =========================================================================
    // MARK: - Cleanup
    // =========================================================================

    /// Comprehensive teardown of all subsystems.
    ///
    /// Called when the host application (or its bridge) is being destroyed.
    /// Respects `stopOnTerminate: false` by skipping teardown for critical
    /// background tracking components when enabled.
    public func destroyAll() {
        // destroyAll() is dispatched from the plugin during engine teardown. It
        // can run in a process/engine where initialize() never executed (e.g. a
        // secondary/headless engine). All subsystems — including configManager and
        // stateManager — are implicitly-unwrapped optionals assigned in
        // initialize(); touching them while nil traps fatally *during teardown*,
        // surfacing as a crash the app can't intercept (parity with Android #227).
        // If the SDK was never initialized there is nothing to tear down.
        guard configManager != nil, stateManager != nil else { return }

        // When stopOnTerminate=false and tracking is active, the SDK should
        // continue running in the background. Tearing down subsystems here
        // would kill that background continuity.
        let keepAlive = !configManager.getStopOnTerminate() && stateManager.enabled

        // LocationEngine — keep alive for continuous and geofence modes.
        // Periodic mode has its own scheduler lifecycle.
        if !(keepAlive && stateManager.trackingMode != .periodic) {
            locationEngine?.stop()
        }
        motionDetector?.stop()

        // GeofenceManager — geofences are a standalone feature: addGeofence()/
        // addGeofences() never require trackingMode == .geofences, which is only
        // the dedicated geofence-only *session* started by startGeofences().
        // Geofences must therefore survive teardown on the same `keepAlive`
        // terms as everything else in this function, regardless of which
        // tracking mode is active.
        //
        // This was previously additionally gated on `trackingMode == .geofences`,
        // so a `start()` (continuous) session with geofences added via
        // addGeofences() — a fully supported, documented combination — had
        // every geofence unregistered on the very first teardown, and nothing
        // ever re-registered them afterwards (autoResumeTracking() had the
        // matching .geofences-only gate on reRegisterAll(), fixed alongside
        // this). Continuous tracking itself kept working, which is why the
        // geofence feature could die silently and go unnoticed (#353, mirrors
        // the Android fix).
        let keepGeofencesAlive = keepAlive
        if !keepGeofencesAlive {
            let fenceCount = geofenceManager?.getGeofences().count ?? 0
            TraceletLog.lifecycle(
                "geofences: unregistering \(fenceCount) geofence(s) on destroyAll() "
                    + "— mode=\(stateManager.trackingMode) stopOnTerminate="
                    + "\(configManager.getStopOnTerminate()) enabled=\(stateManager.enabled) (#353)")
            geofenceManager?.destroy()
        }

        // Subsystems that should only survive if we are in a background-active mode.
        if !keepAlive {
            // TODO: Stop Rust SyncManager if necessary
            scheduleManager?.stop()
            stopHeartbeat()
            preventSuspendManager?.stop()
            backgroundActivitySessionManager?.stop()
            serviceSessionManager?.stop()
        }

        // Sound and budget sampling are safe to stop unconditionally.
        soundManager?.stop()
        stopBatteryBudgetSampling()

        // Periodic scheduler — keep alive only in periodic mode.
        let keepPeriodicAlive = keepAlive && stateManager.trackingMode == .periodic
        if !keepPeriodicAlive {
            periodicRefreshScheduler?.stop()
        }
    }

    /// - Parameter isResume: true when the SDK is picking a session back up
    ///   (relaunch / auto-resume) rather than the app asking for a fresh one.
    ///   Only a resume inherits the previous session's pace — see the reconcile
    ///   step below.
    private func startSpeedMotionManager(forceMoving: Bool = false, isResume: Bool = false) {
        let smm = SpeedMotionManager(stateManager: stateManager)
        smm.speedMovingThreshold = configManager.getSpeedMovingThreshold()
        smm.speedStationaryDelay = configManager.getSpeedStationaryDelay()
        smm.stationaryTrackingMode = configManager.getStationaryTrackingMode()
        smm.stationaryPeriodicInterval = configManager.getStationaryPeriodicInterval()
        smm.speedWakeConfirmCount = configManager.getSpeedWakeConfirmCount()
        smm.delegate = self
        smm.start(forceMoving: forceMoving)
        speedMotionManager = smm

        // The machine outlives a session: start() above restored whatever the
        // last one persisted, and anything but .stationary means "moving".
        // Inheriting that is right for a resume — a relaunched process has no
        // other record of the pace it was killed in — and wrong for a fresh
        // start(), which committed a pace from `motion.isMoving` a few lines
        // earlier. Adopting the restored value there let a previous session's
        // MOVING silently overrule an explicit `motion.isMoving: false`, so the
        // caller was handed isMoving=true from a start it had asked to begin
        // stationary, with syncCurrentMode() (#344) having already read the
        // committed pace.
        //
        // This must precede the last-known-speed seed below: a restored .moving
        // left in place falls to .slowing on the first low-speed fix, and
        // .slowing is still "moving", so it writes isMoving back to true.
        if !forceMoving && !isResume && smm.state != .stationary {
            TraceletLog.debug(
                "[Tracelet] start() committed a stationary pace — overriding restored \(smm.state.name)")
            smm.onManualPaceChange(isMoving: false)
        }

        // Feed CLLocation.speed to the state machine on every fix
        locationEngine.speedSink = { [weak smm] speed in
            smm?.onLocation(speed: speed)
        }

        // Seed the machine with the last GPS speed this process actually
        // resolved — and only if there is one.
        //
        // `lastEffectiveSpeed` is 0.0 on a process that has not yet handled a
        // fix, which is exactly the state a killed-state relaunch or a
        // background takeover starts in. Feeding that 0.0 told a session that
        // had just resumed as MOVING that it was stopped: it dropped straight to
        // SLOWING and, `speedStationaryDelay` later, to STATIONARY — switching
        // off the continuous stream while the user was still walking. The
        // location indicator disappearing shortly after backgrounding the app is
        // this, and nothing about the device had changed.
        //
        // 0.0 means "no speed reported", not "stopped" — the same distinction
        // the processor draws for a fix that carries no speed. A null
        // `lastLocation` is precisely "no fix handled in this process", which is
        // unknown rather than zero, so there is nothing to seed with.
        if locationEngine.getLastLocation() != nil {
            smm.onLocation(speed: locationEngine.lastEffectiveSpeed)
        } else {
            TraceletLog.lifecycle(
                "pace: no fix resolved in this process yet — not seeding the machine with a "
                    + "fabricated 0.0 m/s, which would stand a resumed session down")
        }

        TraceletLog.debug(String(format: "[Tracelet] Speed motion mode started (threshold=%.1f, delay=%ds, stationary=%@)",
              smm.speedMovingThreshold, smm.speedStationaryDelay, smm.stationaryTrackingMode == .geofences ? "geofences" : "periodic"))

        // Sync stateManager.isMoving with restored speed motion state if not forcing
        if !forceMoving {
            if smm.state == .stationary {
                smartMotionCoordinator.onSpeedStateChange(isMoving: false)
                stateManager.isMoving = false
            } else {
                smartMotionCoordinator.onSpeedStateChange(isMoving: true)
                stateManager.isMoving = true
            }
        } else {
            // A forced-moving start left the coordinator's speed input on
            // whatever the *previous* session ended with, because only the
            // branch above ever wrote it. `is_speed_moving` is process-lived
            // state behind the FFI that no start() resets, so a session that
            // parked stationary handed the next one a `false` — and the core
            // dedupes a repeat of that flag to `.none`, so the machine could
            // never re-assert it either.
            //
            // The whole session then hung on the accelerometer alone: the OR
            // said moving only while accel did, and the one path that flips
            // accel back (the tremor override in `onSpeedStateChange`) was
            // the transition whose action used to be discarded. Seeding here
            // is the mirror of the accel seed in `start()` — the machine was
            // just forced to MOVING, so the coordinator has to be told (#409).
            smartMotionCoordinator.onSpeedStateChange(isMoving: true)
        }

        // If we're resuming in stationary state, switch immediately
        if smm.state == .stationary {
            if smm.stationaryTrackingMode == .geofences {
                locationEngine.switchToStationaryGeofences()
            } else {
                locationEngine.switchToStationaryPeriodic()
            }
        }
    }
}

// MARK: - SpeedMotionDelegate

extension TraceletSdk: SpeedMotionDelegate {

    public func switchToContinuous() {
        if configManager.getMotionDetectionMode() == .smart {
            smartMotionCoordinator.onSpeedStateChange(isMoving: true)
            return
        }
        switchToContinuousForce()
    }

    public func switchToContinuousForce() {
        BackgroundTaskHelper.shared.run("speedSwitchContinuous") { [self] in
            // A queued speed/smart callback can execute after stop() — never
            // restart continuous GPS once the user has stopped tracking.
            guard stateManager.enabled else {
                logger.debug("switchToContinuousForce ignored — tracking is stopped")
                return
            }
            stateManager.isMoving = true
            stateManager.trackingMode = .continuous
            locationEngine.switchToContinuous()
            // #261: honor useSignificantChangesOnly here too. This is the path
            // the speed/smart motion pipeline takes when it confirms movement,
            // independent of start()'s moving branch — so it must apply the same
            // guard or the persistent location indicator comes back.
            startBackgroundActivitySessionIfNeeded()

            // Emit motionchange event for backward compatibility
            let lastLoc = locationEngine.getLastLocation()
            tripManager.onMotionStateChanged(
                isMoving: true,
                latitude: lastLoc?.coordinate.latitude,
                longitude: lastLoc?.coordinate.longitude,
                timestamp: lastLoc.map { ISO8601DateFormatter().string(from: $0.timestamp) }
            )

            if let loc = lastLoc {
                var map = locationEngine.buildLocationMap(loc, speed: locationEngine.lastEffectiveSpeed)
                map["isMoving"] = true
                map["event"] = "motionchange"
                sendMotionChangeWithTrip(map)
            } else {
                sendMotionChangeWithTrip(["isMoving": true])
            }
        }
    }

    public func switchToStationaryPeriodic() {
        if configManager.getMotionDetectionMode() == .smart {
            smartMotionCoordinator.onSpeedStateChange(isMoving: false)
            return
        }
        switchToStationaryPeriodicForce()
    }

    public func switchToStationaryPeriodicForce() {
        BackgroundTaskHelper.shared.run("speedSwitchStationary") { [self] in
            // A queued speed/smart callback can execute after stop() — never
            // restart the stationary periodic timer once tracking is stopped.
            guard stateManager.enabled else {
                logger.debug("switchToStationaryPeriodicForce ignored — tracking is stopped")
                return
            }
            stateManager.isMoving = false
            locationEngine.switchToStationaryPeriodic()
            backgroundActivitySessionManager.stop()

            // Emit motionchange event for backward compatibility
            let lastLoc = locationEngine.getLastLocation()
            tripManager.onMotionStateChanged(
                isMoving: false,
                latitude: lastLoc?.coordinate.latitude,
                longitude: lastLoc?.coordinate.longitude,
                timestamp: lastLoc.map { ISO8601DateFormatter().string(from: $0.timestamp) }
            )

            if let loc = lastLoc {
                var map = locationEngine.buildLocationMap(loc, speed: locationEngine.lastEffectiveSpeed)
                map["isMoving"] = false
                map["event"] = "motionchange"
                sendMotionChangeWithTrip(map)
            } else {
                sendMotionChangeWithTrip(["isMoving": false])
            }

            // Handle stopOnStationary
            if configManager.getStopOnStationary() {
                stop()
            }
        }
    }

    public func switchToStationaryGeofences() {
        if configManager.getMotionDetectionMode() == .smart {
            smartMotionCoordinator.onSpeedStateChange(isMoving: false)
        } else {
            switchToStationaryGeofencesForce()
        }
    }

    public func switchToStationaryGeofencesForce() {
        BackgroundTaskHelper.shared.run("speedSwitchGeofences") { [self] in
            // A queued speed/smart callback can execute after stop() — never
            // re-register geofence monitoring once tracking is stopped.
            guard stateManager.enabled else {
                logger.debug("switchToStationaryGeofencesForce ignored — tracking is stopped")
                return
            }
            stateManager.isMoving = false
            stateManager.trackingMode = .geofences
            locationEngine.switchToStationaryGeofences()
            backgroundActivitySessionManager.stop()
            geofenceManager.reRegisterAll()

            // Emit motionchange event for backward compatibility
            let lastLoc = locationEngine.getLastLocation()
            tripManager.onMotionStateChanged(
                isMoving: false,
                latitude: lastLoc?.coordinate.latitude,
                longitude: lastLoc?.coordinate.longitude,
                timestamp: lastLoc.map { ISO8601DateFormatter().string(from: $0.timestamp) }
            )

            if let loc = lastLoc {
                var map = locationEngine.buildLocationMap(loc, speed: locationEngine.lastEffectiveSpeed)
                map["isMoving"] = false
                map["event"] = "motionchange"
                sendMotionChangeWithTrip(map)
            } else {
                sendMotionChangeWithTrip(["isMoving": false])
            }

            // Handle stopOnStationary
            if configManager.getStopOnStationary() {
                stop()
            }
        }
    }

    public func speedMotionDidStartSlowing() {
        locationEngine.overrideDistanceFilter(forStopTimeout: true, source: "SpeedMotionManager")
    }

    public func speedMotionDidCancelSlowing() {
        locationEngine.overrideDistanceFilter(forStopTimeout: false, source: "SpeedMotionManager")
    }

    public func emitSpeedMotionEvent(state: Int, previousState: Int, trackingMode: Int) {
        eventSender.sendSpeedMotionEvent([
            "state": state,
            "previousState": previousState,
            "trackingMode": trackingMode
        ])
    }

    /// Synchronizes the active platform configuration stored in ``configManager`` 
    /// to the underlying Rust Core ``rustEngineState`` instance.
    ///
    /// This method maps every individual geolocation, motion, network, geofencing,
    /// persistence, audit, database encryption, and device attestation property 
    /// from the native iOS ConfigManager directly into a UniFFI-exported 
    /// ``EngineConfig`` record, ensuring the Rust core engine maintains perfect 
    /// configuration parity with the platform layer.
    private func syncConfigToRustFlat() {
        guard let state = rustEngineState else { return }
        do {
            let newConfig = EngineConfig(
                geo: GeoConfig(
                    desiredAccuracy: Int32(configManager.getDesiredAccuracy()),
                    distanceFilter: configManager.getDistanceFilter(),
                    stationaryRadius: configManager.getStationaryRadius(),
                    locationTimeout: Int32(configManager.getLocationTimeout()),
                    disableElasticity: configManager.getDisableElasticity(),
                    elasticityMultiplier: configManager.getElasticityMultiplier(),
                    enableAdaptiveMode: configManager.getEnableAdaptiveMode(),
                    enableTimestampMeta: configManager.getEnableTimestampMeta(),
                    enableSparseUpdates: configManager.getEnableSparseUpdates(),
                    sparseDistanceThreshold: configManager.getSparseDistanceThreshold(),
                    stopAfterElapsedMinutes: Int32(configManager.getStopAfterElapsedMinutes()),
                    maxMonitoredGeofences: Int32(configManager.getMaxMonitoredGeofences()),
                    periodicLocationInterval: Int32(configManager.getPeriodicLocationInterval()),
                    periodicDesiredAccuracy: Int32(configManager.getPeriodicDesiredAccuracy()),
                    sparseMaxIdleSeconds: Int32(configManager.getSparseMaxIdleSeconds()),
                    batteryBudgetPerHour: configManager.getBatteryBudgetPerHour(),
                    enableDeadReckoning: configManager.getEnableDeadReckoning(),
                    deadReckoningActivationDelay: Int32(configManager.getDeadReckoningActivationDelay()),
                    deadReckoningMaxDuration: Int32(configManager.getDeadReckoningMaxDuration()),
                    resolveAddress: configManager.getResolveAddress()
                ),
                motion: MotionConfig(
                    stopTimeout: Int32(configManager.getStopTimeout()),
                    motionTriggerDelay: Int32(configManager.getMotionTriggerDelay()),
                    disableMotionActivityUpdates: configManager.getDisableMotionActivityUpdates(),
                    disableStopDetection: configManager.getDisableStopDetection(),
                    shakeThreshold: configManager.getShakeThreshold(),
                    isMoving: configManager.getIsMoving(),
                    activityRecognitionInterval: Int32(configManager.getActivityRecognitionInterval()),
                    minimumActivityRecognitionConfidence: Int32(configManager.getMinimumActivityRecognitionConfidence()),
                    stopDetectionDelay: Int32(configManager.getStopDetectionDelay()),
                    stopOnStationary: configManager.getStopOnStationary(),
                    stationaryRadius: configManager.getStationaryRadius(),
                    useSignificantChangesOnly: configManager.getUseSignificantChangesOnly(),
                    stillThreshold: configManager.getStillThreshold(),
                    stillSampleCount: Int32(configManager.getStillSampleCount()),
                    motionDetectionMode: Int32(configManager.getMotionDetectionMode().rawValue),
                    speedMovingThreshold: configManager.getSpeedMovingThreshold(),
                    speedStationaryThreshold: configManager.getSpeedStationaryThreshold(),
                    speedStationaryDelay: Int32(configManager.getSpeedStationaryDelay()),
                    stationaryTrackingMode: Int32(configManager.getStationaryTrackingMode().rawValue),
                    stationaryPeriodicInterval: Int32(configManager.getStationaryPeriodicInterval()),
                    stationaryPeriodicAccuracy: Int32(configManager.getStationaryPeriodicAccuracy()),
                    speedWakeConfirmCount: Int32(configManager.getSpeedWakeConfirmCount())
                ),
                http: HttpConfig(
                    url: configManager.getUrl().isEmpty ? nil : configManager.getUrl(),
                    method: configManager.getHttpMethod().uppercased() == "PUT" ? 1 : 0,
                    headers: configManager.getMergedHttpHeaders(),
                    batchSync: configManager.getBatchSync(),
                    maxBatchSize: Int32(configManager.getMaxBatchSize()),
                    autoSync: configManager.getAutoSync(),
                    maxRetries: Int32(configManager.getMaxRetries()),
                    retryBackoffBase: Int32(configManager.getRetryBackoffBase()),
                    retryBackoffCap: Int32(configManager.getRetryBackoffCap()),
                    autoSyncDelay: Int32(configManager.getAutoSyncDelay()),
                    sslPinningCertificates: configManager.getSslPinningCertificates().isEmpty ? nil : configManager.getSslPinningCertificates(),
                    sslPinningFingerprints: configManager.getSslPinningFingerprints().isEmpty ? nil : configManager.getSslPinningFingerprints(),
                    httpRootProperty: configManager.getHttpRootProperty(),
                    params: configManager.getHttpParams().mapValues { "\($0)" },
                    extras: configManager.getHttpExtras().mapValues { "\($0)" },
                    disableAutoSyncOnCellular: configManager.getDisableAutoSyncOnCellular(),
                    enableDeltaCompression: configManager.getEnableDeltaCompression(),
                    deltaCoordinatePrecision: Int32(configManager.getDeltaCoordinatePrecision()),
                    locationsOrderDirection: Int32(configManager.getLocationsOrderDirection()),
                    autoSyncThreshold: Int32(configManager.getAutoSyncThreshold()),
                    httpTimeout: Int32(configManager.getHttpTimeout()),
                    syncInterval: Int32(configManager.getSyncInterval()),
                    syncTelematics: configManager.getSyncTelematics(),
                    telematicsUrl: configManager.getTelematicsUrl().isEmpty ? nil : configManager.getTelematicsUrl()
                ),
                geofence: GeofenceConfig(
                    geofenceInitialTrigger: configManager.getGeofenceInitialTrigger(),
                    geofenceInitialTriggerEntry: configManager.getGeofenceInitialTriggerEntry(),
                    geofenceProximityRadius: Int32(configManager.getGeofenceProximityRadius())
                ),
                persistence: PersistenceConfig(
                    maxDaysToPersist: Int32(configManager.getMaxDaysToPersist()),
                    maxRecordsToPersist: Int32(configManager.getMaxRecordsToPersist())
                ),
                audit: AuditConfig(
                    enabled: configManager.getAuditEnabled()
                ),
                security: SecurityConfig(
                    encryptDatabase: configManager.getEncryptDatabase()
                ),
                attestation: AttestationConfig(
                    enabled: configManager.getAttestationEnabled()
                )
            )
            try state.updateConfig(newConfig: newConfig)
            TraceletLog.debug("Tracelet: Successfully synchronized ConfigManager state to Rust Core.")
        } catch {
            TraceletLog.error("Tracelet: Failed to sync config to Rust Core: \(error)")
        }
    }
}

private struct RustDatabaseSinkWrapper: LocationDataSink {
    weak var sdk: TraceletSdk?

    func insertLocation(_ location: [String: Any]) -> String {
        return sdk?.insertLocation(location) ?? ""
    }
}

/// Feeds each accepted location into the telematics engine (3.3.0).
private struct TelematicsSinkWrapper: LocationDataSink {
    weak var sdk: TraceletSdk?

    func insertLocation(_ location: [String: Any]) -> String {
        sdk?.processTelematics(location)
        return ""
    }
}
