import CoreLocation
import Foundation
import UIKit

public protocol LocationDataSink {
    @discardableResult
    func insertLocation(_ location: [String: Any]) -> String
}

/// CLLocationManager wrapper providing continuous location tracking,
/// one-shot position, watch position, significant location changes,
/// and odometer computation.
public final class LocationEngine: NSObject, CLLocationManagerDelegate {
    /// Internally settable so tests can inject a CLLocationManager subclass
    /// that records calls (e.g. `requestLocation`). Production code never
    /// reassigns this after init.
    internal var locationManager: CLLocationManager
    private let configManager: ConfigManager
    private let stateManager: StateManager
    private let eventDispatcher: TraceletEventSending
    /// Internally readable so tests can assert what is subscribed (#286).
    /// Production code only mutates this through register/unregisterSink.
    internal private(set) var sinks: [LocationDataSink] = []

    private var lastLocation: CLLocation?
    /// Last GPS-quality location (horizontalAccuracy ≤ 100m).
    /// Used by heartbeat to avoid returning low-accuracy significant-change fixes.
    private var lastGpsLocation: CLLocation?
    private var oneShots: [((CLLocation?) -> Void)] = []
    private var watchCallbacks: [Int: Bool] = [:]
    private var nextWatchId = 0
    public private(set) var isTracking = false

    /// Whether `startUpdatingLocation()` is feeding the continuous stream *right
    /// now* — as opposed to ``isTracking``, which answers the wider question
    /// "is a session alive".
    ///
    /// The two came apart when the speed/smart pipeline learned to park without
    /// tearing the session down: ``switchToStationaryPeriodic()`` and
    /// ``switchToStationaryGeofences()`` stop continuous updates but deliberately
    /// leave `isTracking` true so delegate callbacks are still processed. Anything
    /// asking "is the stream running" therefore got `true` from a parked engine.
    ///
    /// `TraceletSmartMotionCoordinator.syncCurrentMode()` is exactly such a
    /// caller: it ORs the committed pace with the engine's state to decide the
    /// coordinator's posture (#409). Reading `isTracking` there writes Continuous
    /// into a coordinator whose engine is parked, and the core emits no wake-up
    /// for a posture it already believes is Continuous — #344's swallowed shake,
    /// re-entered from the #409 side. This flag is the signal that question
    /// actually meant. It is also what the always-on park/resume lifecycle lines
    /// key off, so they cannot narrate a transition that did not happen.
    public private(set) var isContinuousStreaming = false

    /// When `true`, `start()`/`stop()` leave the Live Activity untouched.
    ///
    /// A `setConfig()` that changes a restart-sensitive key rebuilds the
    /// pipeline via a stop→start cycle. On iOS a Live Activity cannot be
    /// *re-requested* while the app is backgrounded ("Target is not
    /// foreground"), so tearing it down and recreating it during a restart
    /// would permanently lose it. Instead `TraceletSdk.setConfig()` sets this
    /// flag so the existing activity survives the restart and is then updated
    /// in place with the new config (#257).
    public var suppressLiveActivityLifecycle = false

    /// Temporary OS-provider overrides. These intentionally do not mutate
    /// ConfigManager or the Rust accepted-point filter. They only control how
    /// Core Location acquires and delivers fixes while continuous tracking is
    /// active, and are cleared by stop().
    private var runtimeDesiredAccuracy: Int?
    private var runtimeDistanceFilter: Double?

    /// The battery-budget ladder's overlay, if one is in force (#393, #396).
    ///
    /// Deliberately a separate pair from the runtime overrides above rather than
    /// a write into ConfigManager. The budget engine used to call `setConfig`,
    /// which made its throttled values indistinguishable from the app's own —
    /// permanently, since `distanceFilter: 0` clamped up to 10 and nothing ever
    /// restored it, and visibly, since `activeConfig` and every bug report built
    /// from it then described a configuration the app had never asked for.
    ///
    /// An explicit `updateLocationProviderOptions` call still wins: the app
    /// asking for something specific outranks the SDK's own economising.
    private var budgetDesiredAccuracy: Int?
    private var budgetDistanceFilter: Double?
    /// Floor the ladder has put under the tracking accuracy gate, re-applied
    /// whenever the processor is rebuilt.
    private var budgetTrackingAccuracyFloor: Int = 0

    /// Background task ID for the current periodic fix request.
    /// Ended in didUpdateLocations/didFailWithError when periodic mode is active.
    private var periodicFixBgTaskId: UIBackgroundTaskIdentifier?
    /// Cancellable timeout work item for periodic fix cleanup.
    private var periodicFixTimeoutWork: DispatchWorkItem?

    /// Opaque reference to CLBackgroundActivitySession for iOS 17+ Live Updates
    /// battery optimization. Kept opaque to allow compilation on older iOS targets.
    private var backgroundActivitySession: Any?

    /// Last computed effective speed (m/s) from tracking location updates.
    /// Used by the plugin to provide speed in motionchange events, since the
    /// cached CLLocation.speed may be stale, 0, or -1.
    public private(set) var lastEffectiveSpeed: Double = 0.0

    /// Optional callback invoked on every accepted location (for geofenceModeHighAccuracy).
    ///
    /// Params: latitude, longitude, horizontalAccuracy (meters). Accuracy feeds
    /// the drift-aware geofence EXIT decision (issue #274). CLLocation reports a
    /// negative `horizontalAccuracy` when invalid; the evaluator treats any
    /// non-positive value as "unknown" and skips gating.
    public var onLocationUpdate: ((Double, Double, Double) -> Void)?

    /// Optional callback invoked on every **raw** fix — before the Rust
    /// `LocationProcessor` distance/accuracy/sparse filter — for
    /// geofenceModeHighAccuracy crossing evaluation.
    ///
    /// The tracking distance filter reduces *persistence* volume: a stationary
    /// device's repeated fixes are dropped so the DB and sync queue don't fill
    /// with duplicates. But geofence crossing detection needs *every* fix — a
    /// device drifting across a boundary, or one whose EXIT must be confirmed
    /// across two consecutive out-of-fence fixes (#294), is starved if crossings
    /// only run on fixes that survive the persistence filter. With
    /// `distanceFilter > 0`, CoreLocation itself withholds updates from a
    /// stationary device, so `onLocationUpdate` never fires and transitions are
    /// missed (field reports of "ENTER/EXIT not happening").
    ///
    /// This callback decouples the two: crossings evaluate on the raw stream
    /// while persistence keeps its distance filter. Params: latitude, longitude,
    /// horizontalAccuracy (meters); CoreLocation reports negative when invalid.
    public var onRawGeofenceLocation: ((Double, Double, Double) -> Void)?

    /// When true, CoreLocation is configured with `distanceFilter =
    /// kCLDistanceFilterNone` so a stationary/backgrounded device is still
    /// delivered fixes for `onRawGeofenceLocation` to evaluate. The persistence
    /// distance filter (the Rust `LocationProcessor`) is unchanged, so this does
    /// not increase stored/synced location volume. Set from
    /// `hasEvaluatorOwnedGeofences()` — high-accuracy mode, a polygon, or a
    /// sub-100 m circle — not from `geofenceModeHighAccuracy` alone.
    ///
    /// Applied live: the fence set is mutable while tracking, so a fence added
    /// mid-session must drop the OS distance filter immediately rather than at
    /// the next `start()` — which, in continuous mode, never comes (#357).
    public var geofenceHighAccuracyMode: Bool = false {
        didSet {
            guard geofenceHighAccuracyMode != oldValue, isTracking else { return }
            applyLocationProviderOptions()
        }
    }

    /// Optional callback invoked after a location is persisted to the database.
    /// Used by the plugin to trigger HTTP auto-sync.
    public var onLocationPersisted: (() -> Void)?

    /// Whether a mock location warning has already been fired for this session.
    private var mockLocationWarningFired = false

    /// Tracks the last known accuracy authorization to detect transitions.
    private var lastAccuracyAuthorization: Int = -1  // -1 = unknown, 0 = full, 1 = reduced

    /// Counter for throttling DB retention pruning (I-H6).
    private var insertCountSincePrune = 0
    private static let pruneEveryNInserts = 100

    // MARK: - Rust-powered location processing

    /// Rust-backed location processor for distance/accuracy/speed/mock filtering.
    private var locationProcessor: LocationProcessor?

    /// Rust-backed Kalman filter for smoothing lat/lng.
    private var kalmanFilter: KalmanLocationFilter?

    /// Rust-backed PluginEventDispatcher for DB persistence + auto HTTP sync
    public var rustPluginEventDispatcher: EventDispatcher?

    /// Build (or rebuild) the Rust LocationProcessor from current config.
    public func rebuildProcessor() {
        locationProcessor = LocationProcessor(
            distanceFilter: configManager.getDistanceFilter(),
            disableElasticity: configManager.getDisableElasticity(),
            elasticityMultiplier: configManager.getElasticityMultiplier(),
            enableAdaptiveMode: configManager.getEnableAdaptiveMode(),
            trackingAccuracyThreshold: Int32(configManager.getTrackingAccuracyThreshold()),
            filterPolicy: Int32(configManager.getFilterPolicy()),
            maxImpliedSpeed: Int32(configManager.getMaxImpliedSpeed()),
            odometerAccuracyThreshold: Int32(configManager.getOdometerAccuracyThreshold()),
            rejectMockLocations: configManager.getRejectMockLocations(),
            mockDetectionLevel: Int32(configManager.getMockDetectionLevel()),
            enableSparseUpdates: configManager.getEnableSparseUpdates(),
            sparseDistanceThreshold: configManager.getSparseDistanceThreshold(),
            sparseMaxIdleSeconds: Int32(configManager.getSparseMaxIdleSeconds())
        )
        kalmanFilter = configManager.getEnableKalmanFilter() ? KalmanLocationFilter() : nil
        // A rebuild must not drop a throttle that is still in force, or the gate
        // would tighten back under fixes the ladder is deliberately coarsening
        // (#396).
        if budgetTrackingAccuracyFloor > 0 {
            locationProcessor?.setAccuracyFloor(metres: Int32(budgetTrackingAccuracyFloor))
        }
    }

    /// Returns the processor, building it if needed.
    private func getProcessor() -> LocationProcessor {
        if let p = locationProcessor { return p }
        rebuildProcessor()
        return locationProcessor!
    }

    /// Applies the filter thresholds appropriate to a committed transport mode (#299).
    ///
    /// Called only when the classifier *commits* a mode change — already gated by
    /// confidence and an 8 s dwell — never per accelerometer window, so the
    /// thresholds cannot chatter. A mode with no tuning (`unknown`) restores the
    /// host's own configuration rather than guessing.
    ///
    /// Returns the applied tuning, or `nil` when auto-tuning is disabled or the
    /// mode carries no opinion. Callers surface it on the `modeChange` event so an
    /// auto-tune shows up in logs instead of being a silent config mutation.
    @discardableResult
    public func applyTransportModeTuning(_ mode: String) -> LocationTuning? {
        guard configManager.getAutoTuneFromTransportMode() else {
            // #301: auto-tuning may have been switched off *after* a mode
            // committed. Undo any tuning still in force rather than leaving the
            // host running on thresholds it no longer asked for.
            restoreBaseTuning()
            return nil
        }
        let processor = getProcessor()
        guard let tuning = tuningForTransportMode(mode: Self.rustTransportMode(mode)) else {
            processor.restoreBaseTuning()
            TraceletLog.debug("[Tracelet] auto-tune: '\(mode)' has no tuning — restored configured thresholds")
            return nil
        }
        processor.retune(tuning: tuning)
        TraceletLog.debug(
            "[Tracelet] auto-tune: '\(mode)' → distanceFilter=\(tuning.distanceFilter)m "
                + "trackingAccuracy=\(tuning.trackingAccuracyThreshold)m "
                + "odometerAccuracy=\(tuning.odometerAccuracyThreshold)m "
                + "maxImpliedSpeed=\(tuning.maxImpliedSpeed)m/s"
        )
        return tuning
    }

    /// Restores the thresholds this engine was configured with, undoing any
    /// auto-tune (#301).
    ///
    /// No-op when no processor exists yet — unlike `getProcessor()` this must not
    /// build one as a side effect, since it is called from reconfiguration paths
    /// that run before tracking has ever started.
    public func restoreBaseTuning() {
        locationProcessor?.restoreBaseTuning()
    }

    /// Pushes the four configured filter thresholds into the processor as its new
    /// *base* tuning (#303).
    ///
    /// `setConfig` only rebuilt the processor for a short list of location keys,
    /// so `trackingAccuracyThreshold`, `odometerAccuracyThreshold` and
    /// `maxImpliedSpeed` never reached it — they sat in `ConfigManager` until the
    /// next cold start, and `restoreBaseTuning()` reverted to the values captured
    /// when the processor was constructed rather than the ones the host had since
    /// configured.
    ///
    /// Deliberately not a `rebuildProcessor()` call: a rebuild drops the
    /// positional anchor and forfeits one inter-fix delta from the odometer,
    /// which is exactly what `retune` was introduced to avoid (#299).
    /// `setBaseTuning` preserves it, and defers to an auto-tune that is currently
    /// in force while still updating what a later restore lands on.
    ///
    /// No-op before a processor exists; the next `rebuildProcessor()` reads the
    /// same values straight from config.
    public func applyConfiguredBaseTuning() {
        guard let processor = locationProcessor else { return }
        processor.setBaseTuning(
            tuning: LocationTuning(
                distanceFilter: configManager.getDistanceFilter(),
                trackingAccuracyThreshold: Int32(configManager.getTrackingAccuracyThreshold()),
                odometerAccuracyThreshold: Int32(configManager.getOdometerAccuracyThreshold()),
                maxImpliedSpeed: Int32(configManager.getMaxImpliedSpeed())
            )
        )
    }

    /// The thresholds actually in force right now, or `nil` before a processor
    /// exists (#303).
    ///
    /// Reads back from the processor, never from config: the two disagreeing is
    /// precisely the bug #303 fixed, so answering from config would make a
    /// regression undetectable.
    public func currentTuning() -> LocationTuning? {
        locationProcessor?.currentTuning()
    }

    /// The thresholds actually in force right now, formatted for a log line
    /// (#303).
    ///
    /// Reads back from the processor rather than from config, so the line reports
    /// what the filter is really using — including an auto-tune the host did not
    /// set. Returns `"no processor"` before one exists, which is itself the
    /// useful answer on a pre-`start()` reconfiguration.
    public func currentTuningDescription() -> String {
        guard let t = locationProcessor?.currentTuning() else { return "no processor" }
        return "distanceFilter=\(t.distanceFilter)m "
            + "trackingAccuracy=\(t.trackingAccuracyThreshold)m "
            + "odometerAccuracy=\(t.odometerAccuracyThreshold)m "
            + "maxImpliedSpeed=\(t.maxImpliedSpeed)m/s"
    }

    /// Brings the Kalman filter in line with `useKalmanFilter` (#303).
    ///
    /// The filter is otherwise only constructed inside `rebuildProcessor()`, and
    /// the key is not one that triggers a rebuild — so toggling smoothing at
    /// runtime did nothing until the app was restarted. That matters more since
    /// #299 made Kalman smoothing feed the odometer: enabling it mid-session
    /// silently failed to change recorded distance.
    ///
    /// Toggling rebuilds only the filter, never the processor, so the odometer
    /// anchor survives. An already-correct state is left alone so the filter's
    /// own velocity estimate is not reset on unrelated `setConfig` calls.
    public func syncKalmanFilter() {
        let wanted = configManager.getEnableKalmanFilter()
        if wanted && kalmanFilter == nil {
            kalmanFilter = KalmanLocationFilter()
        } else if !wanted && kalmanFilter != nil {
            kalmanFilter = nil
        }
    }

    /// Maps a classifier mode name back to the Rust `TransportMode` enum.
    private static func rustTransportMode(_ mode: String) -> TransportMode {
        switch mode.lowercased() {
        case "still": return .still
        case "walking": return .walking
        case "running": return .running
        case "cycling": return .cycling
        case "vehicle": return .vehicle
        default: return .unknown
        }
    }

    /// Maximum accuracy (meters) to consider a fix as GPS-sourced.
    static let gpsAccuracyThreshold: Double = 50.0

    /// Determines if a location fix is GPS-sourced (not network/cell).
    static func isGpsFix(_ location: CLLocation) -> Bool {
        return location.horizontalAccuracy > 0 &&
            location.horizontalAccuracy <= gpsAccuracyThreshold
    }

    /// [Enterprise] Audit trail manager — set by the plugin after initialization.
    public var auditTrailManager: AuditTrailManager?

    /// [Enterprise] Privacy zone manager — set by the plugin after initialization.
    public var privacyZoneManager: PrivacyZoneManager?

    /// Optional callback invoked to feed raw speed to SpeedMotionManager.
    public var speedSink: ((Double) -> Void)?

    /// Optional sink for the speed of every **raw** fix, before the processor's
    /// distance/accuracy/speed filters (#299).
    ///
    /// The transport classifier consumes this rather than the speed of accepted
    /// fixes. When auto-tuning is on, the classified mode selects the distance
    /// filter — so classifying from post-filter speeds would close a loop where
    /// tightening the filter changes the very speeds that chose it.
    public var rawSpeedSink: ((Double) -> Void)?

    // Dead Reckoning
    private var deadReckoningEngine: DeadReckoningEngine?
    private var gpsLossTimer: Timer?

    /// Current activity type — set by MotionDetector for DR algorithm selection.
    public var currentActivityType: String = "unknown"

    /// Confidence (0–100) of `currentActivityType`, from the platform Activity
    /// Recognition. -1 when unknown/unset.
    public var currentActivityConfidence: Int = -1

    /// Latest fused transport mode (e.g. "driving") from the transport classifier,
    /// kept fresh by the SDK. When `fusedClassifierAuthoritative` is enabled it
    /// becomes the persisted `activity.type`, so the classified mode survives
    /// process termination and syncs historically (#214 part 3).
    public var fusedTransportMode: String?

    /// Confidence (0.0–1.0) of `fusedTransportMode`, kept fresh alongside it.
    public var fusedTransportModeConfidence: Double = 0

    /// The activity type to persist/dispatch: the fused transport mode when the
    /// classifier is authoritative (and available), otherwise the raw AR activity.
    /// Always expressed in the Activity Recognition vocabulary so `activity.type`
    /// stays a single vocabulary for consumers regardless of the source.
    private func effectiveActivityType() -> String {
        if configManager.getFusedClassifierAuthoritative(), let fused = fusedTransportMode {
            return Self.arActivityName(forFusedMode: fused)
        }
        return currentActivityType
    }

    /// Maps the transport classifier's mode names to the Activity Recognition
    /// vocabulary persisted in `activity.type` ("cycling" → "on_bicycle",
    /// "vehicle" → "in_vehicle"); the remaining modes (still/walking/running/
    /// unknown) are already identical in both.
    private static func arActivityName(forFusedMode mode: String) -> String {
        switch mode {
        case "cycling": return "on_bicycle"
        case "vehicle": return "in_vehicle"
        default: return mode
        }
    }

    /// The activity confidence to persist/dispatch (0–100), matching
    /// `effectiveActivityType()`: the fused mode confidence (scaled from 0.0–1.0)
    /// when authoritative and available, otherwise the platform AR confidence.
    private func effectiveActivityConfidence() -> Int {
        if configManager.getFusedClassifierAuthoritative(), fusedTransportMode != nil {
            return Int((fusedTransportModeConfidence * 100).rounded())
        }
        return currentActivityConfidence
    }

    public init(configManager: ConfigManager,
         stateManager: StateManager,
         eventDispatcher: TraceletEventSending) {
        self.configManager = configManager
        self.stateManager = stateManager
        self.eventDispatcher = eventDispatcher
        self.locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
    }

    public func registerSink(_ sink: LocationDataSink) {
        // Dedupe (parity with Android, #204/#286): the same sink was otherwise
        // added more than once — the sync plugin registered it directly *and*
        // through the `TraceletSdk.syncProvider` didSet, and `initialize()`
        // re-registers the current provider — and every duplicate entry fans a
        // single persisted location out into another insertLocation call.
        if sinks.contains(where: { ($0 as AnyObject) === (sink as AnyObject) }) { return }
        sinks.append(sink)
    }

    /// Removes a previously registered sink (used when a sync provider is
    /// replaced). Android has had this since #204; iOS had no way to detach a
    /// sink at all, so stale sync providers stayed subscribed forever (#286).
    public func unregisterSink(_ sink: LocationDataSink) {
        sinks.removeAll { ($0 as AnyObject) === (sink as AnyObject) }
    }

    /// Merges per-call [local] extras on top of any existing (global) extras in
    /// the location map instead of replacing them, so both the global HTTP extras
    /// and the extras passed to getCurrentPosition / getLastKnownLocation survive
    /// into the synced payload (Issue #201).
    private func mergedExtras(base: Any?, local: [String: Any]) -> Any? {
        if local.isEmpty { return base }
        var merged = (base as? [String: Any]) ?? [:]
        for (key, value) in local { merged[key] = value }
        return merged
    }

    // MARK: - Start / Stop

    public func start() {
        // Guard: require at least WhenInUse authorization before starting.
        // Dispatch a providerChange event so the app/Flutter UI can react
        // instead of silently doing nothing.
        let authStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authStatus = locationManager.authorizationStatus
        } else {
            authStatus = CLLocationManager.authorizationStatus()
        }
        if authStatus != .authorizedWhenInUse && authStatus != .authorizedAlways {
            TraceletLog.debug("[Tracelet] start() called without location authorization (status=\(authStatus.rawValue))")
            eventDispatcher.sendProviderChange(buildProviderState())
            return
        }

        guard !isTracking else { return }
        isTracking = true

        // A pending anchor is superseded by the stream this starts; the flag
        // must not survive onto the stream's first fix (#385).
        startupFixPending = false

        // The stall clock starts now, not at the first accepted fix: a session
        // that never accepts one at all is exactly the case worth announcing
        // (#397).
        lastAcceptedFixAt = Date()
        rejectionsSinceAccept.removeAll()
        stallAnnounced = false
        staleFixesSincePace = 0

        configureLocationManager()
        checkReducedAccuracy()

        // Register for significant-location changes as a fallback wake-up
        // mechanism. If iOS terminates the app, significant-location changes
        // will relaunch it so tracking can resume (autoResumeTracking guards
        // the killed-state entry point for Always-only enforcement).
        locationManager.startMonitoringSignificantLocationChanges()

        // `geofenceHighAccuracyMode` and not just the config flag: a polygon or a
        // sub-100 m circle is evaluated in-app however that flag is set, and
        // in-app evaluation is exactly what the continuous stream feeds. Keying
        // this on the flag alone meant `startGeofences()` took its
        // needs-in-app-evaluation branch, called start(), and still got no
        // `startUpdatingLocation()` — so at default settings a small fence in
        // `geofences` mode could never fire (#357).
        let isLowPowerGeofences = stateManager.trackingMode == .geofences
            && !configManager.getGeofenceModeHighAccuracy()
            && !geofenceHighAccuracyMode
        let skipContinuousGps = configManager.getUseSignificantChangesOnly() || isLowPowerGeofences

        // Always-on: this is the transition the OS location indicator follows,
        // so "the icon disappeared" is answerable from a released app's report.
        //
        // Emitted here rather than before the branch, because the two skip modes
        // deliberately start no stream and saying otherwise leaves a report with
        // an unclosed interval — a start with no stop, which is exactly the shape
        // of the session #409 is about.
        if !skipContinuousGps {
            locationManager.startUpdatingLocation()
            startGpsLossTimer()
            announceContinuousStart(resuming: false)
        } else {
            isContinuousStreaming = false
            TraceletLog.lifecycle(
                "location stream: continuous updates skipped — "
                    + (configManager.getUseSignificantChangesOnly()
                        ? "useSignificantChangesOnly, significant-change monitoring is the only wake-up"
                        : "low-power geofences, region monitoring is the only wake-up"))
        }

        if #available(iOS 17.0, *) {
            if let liveConfig = configManager.getLiveActivityConfig() {
                // The Live Activity is a UI layer over the existing location
                // pipeline. Background delivery is provided by the standard
                // startUpdatingLocation() path plus BackgroundActivitySession/
                // ServiceSession (owned by TraceletSdk) — we deliberately do NOT
                // open a second CLLocationUpdate.liveUpdates() stream, which would
                // double GPS work and duplicate every fix.
                #if canImport(ActivityKit)
                // Skipped while a setConfig() restart is in progress so the
                // existing activity survives (it is updated in place instead).
                if !suppressLiveActivityLifecycle {
                    LiveActivityManager.shared.startLiveActivity(
                        title: liveConfig.title,
                        body: liveConfig.body,
                        startedAt: liveConfig.startedAt,
                        showTimer: liveConfig.showTimer
                    )
                }
                #endif
            } else if configManager.getUseBackgroundActivitySession() {
                backgroundActivitySession = CLBackgroundActivitySession()
            }
        }
    }

    public func stop() {
        // Cleared before the isTracking guard on purpose: the startup fix runs
        // while *not* tracking, so a stop() during it returns below without
        // ever reaching this line otherwise (#385). The force-accept slot goes
        // with it: it belongs to the session that took the anchor.
        startupFixPending = false
        forceAcceptNextFilteredLocation = false
        guard isTracking else { return }
        isTracking = false
        isPeriodicTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        deactivateDeadReckoning()
        cancelGpsLossTimer()
        stopPeriodicTimer()
        runtimeDesiredAccuracy = nil
        runtimeDistanceFilter = nil
        // The budget overlay deliberately survives: a session that stops and
        // starts again has not changed how fast the device is draining, and
        // re-deciding from scratch each time is how the pre-ladder engine kept
        // finding new ground to ratchet from (#396).
        lastAcceptedFixAt = nil
        rejectionsSinceAccept.removeAll()
        stallAnnounced = false
        staleFixesSincePace = 0
        // Only if updates were actually flowing. A session parked by the
        // speed/smart pipeline already announced its stop at the park, and a
        // second line here would date the parking to the moment the user
        // stopped tracking — minutes or hours late. Matches Android, which
        // logs this only when a tracking callback is registered.
        if isContinuousStreaming {
            TraceletLog.lifecycle("location stream: continuous updates stopping")
        }
        isContinuousStreaming = false

        if #available(iOS 17.0, *) {
            #if canImport(ActivityKit)
            // Left running while a setConfig() restart is in progress so the
            // activity survives and is updated in place afterwards (#257).
            if !suppressLiveActivityLifecycle {
                LiveActivityManager.shared.stopLiveActivity()
            }
            #endif
            (backgroundActivitySession as? CLBackgroundActivitySession)?.invalidate()
            backgroundActivitySession = nil
        }
    }

    // MARK: - Periodic one-shot tracking

    /// Whether periodic one-shot mode is active.
    public private(set) var isPeriodicTracking = false
    private var periodicTimer: Timer?

    /// Starts periodic one-shot location tracking.
    ///
    /// Instead of continuous GPS, this mode:
    /// 1. Registers for significant location changes (no blue arrow) as a
    ///    wake-up mechanism.
    /// 2. Schedules a repeating timer at `periodicLocationInterval`.
    /// 3. On each tick, calls `requestLocation()` for a single GPS fix
    ///    (~5 sec blue arrow), dispatches the result, and stops GPS.
    ///
    /// **Important:** If `preventSuspend` is `false`, iOS may suspend the app
    /// and the timer will not fire. Use `preventSuspend: true` in `AppConfig`
    /// or rely on `BGAppRefreshTask` as a supplementary wakeup mechanism.
    public func startPeriodic() {
        guard !isPeriodicTracking else { return }
        isPeriodicTracking = true
        isTracking = true // so delegate callbacks are processed
        isContinuousStreaming = false

        let interval = configManager.getPeriodicLocationInterval()
        TraceletLog.debug(String(format: "[Tracelet] startPeriodic: interval=%ds, accuracy=%d", interval, configManager.getPeriodicDesiredAccuracy()))

        configureLocationManagerForPeriodic()
        checkReducedAccuracy()

        // Significant location changes as a fallback wake-up mechanism
        // (no blue arrow, wakes on cell tower changes).
        // autoResumeTracking() guards the killed-state entry point.
        locationManager.startMonitoringSignificantLocationChanges()

        // Do NOT call startUpdatingLocation() — that's the whole point.
        // Instead, schedule periodic one-shot fixes.
        startPeriodicTimer()
    }

    /// Stops periodic one-shot tracking.
    public func stopPeriodic() {
        guard isPeriodicTracking else { return }
        isPeriodicTracking = false
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        stopPeriodicTimer()
        // Reset last periodic coordinates so the next start doesn't
        // compute distance from a stale position.
        stateManager.lastPeriodicLatitude = .nan
        stateManager.lastPeriodicLongitude = .nan
    }

    // MARK: - Speed-Mode Atomic Switching
    //
    // These methods switch between continuous and stationary tracking modes
    // WITHOUT invalidating CLServiceSession / CLBackgroundActivitySession.
    // Sessions are only torn down on a full user-initiated stop().

    /// Switch from continuous to stationary periodic one-shot tracking.
    ///
    /// Stops continuous `startUpdatingLocation()` and starts the periodic
    /// timer. Significant-location-change monitoring and background sessions
    /// remain active.
    public func switchToStationaryPeriodic() {
        TraceletLog.debug("[Tracelet] switchToStationaryPeriodic: stopping continuous, starting periodic timer")
        announceContinuousStop(becoming: "stationary periodic")
        locationManager.stopUpdatingLocation()
        cancelGpsLossTimer()
        deactivateDeadReckoning()

        isPeriodicTracking = true
        // isTracking stays true so delegate callbacks are processed
        configureLocationManagerForPeriodic()
        startPeriodicTimer()
    }

    /// Switch from continuous to stationary geofence-only mode.
    ///
    /// Stops continuous `startUpdatingLocation()` but leaves region monitoring
    /// active. Background sessions remain active.
    public func switchToStationaryGeofences() {
        TraceletLog.debug("[Tracelet] switchToStationaryGeofences: stopping continuous, geofences remain active")
        announceContinuousStop(becoming: "stationary geofences")
        locationManager.stopUpdatingLocation()
        cancelGpsLossTimer()
        deactivateDeadReckoning()
        // Region monitoring (geofences) is managed by GeofenceManager and
        // remains active. isTracking stays true for delegate callbacks.
    }

    /// Switch from stationary (periodic or geofences) back to continuous tracking.
    ///
    /// Stops the periodic timer and resumes `startUpdatingLocation()`.
    /// Background sessions remain active.
    public func switchToContinuous() {
        TraceletLog.debug("[Tracelet] switchToContinuous: stopping periodic, resuming continuous")
        stopPeriodicTimer()
        isPeriodicTracking = false

        // #261: in significant-changes-only mode we must NOT start continuous
        // GPS. startUpdatingLocation() (with allowsBackgroundLocationUpdates)
        // itself shows the persistent system location indicator — independent
        // of CLBackgroundActivitySession — which defeats significant-change
        // monitoring. The motion pipeline can call this on a confirmed
        // movement, so honor the flag here just like start() does and keep
        // significant-change monitoring (registered in start()) as the sole
        // wake-up mechanism.
        if configManager.getUseSignificantChangesOnly() {
            TraceletLog.debug("[Tracelet] switchToContinuous: useSignificantChangesOnly enabled — staying on significant-change monitoring, not starting continuous GPS (#261)")
            return
        }

        configureLocationManager()
        announceContinuousStart(resuming: true)
        locationManager.startUpdatingLocation()
        startGpsLossTimer()
    }

    /// Records the end of the continuous stream on the always-on channel, if it
    /// was in fact running.
    ///
    /// The parks below stop `startUpdatingLocation()` without tearing the
    /// session down, so they never went through ``stop()`` — the one place that
    /// logged this. On Android the same transition runs through
    /// `LocationEngine.stop()` and is recorded, so an iOS report was missing the
    /// single line that says when GPS was parked: the evidence #409 was
    /// diagnosed from, absent on exactly one of the two platforms.
    private func announceContinuousStop(becoming mode: String) {
        guard isContinuousStreaming else { return }
        isContinuousStreaming = false
        TraceletLog.lifecycle("location stream: continuous updates stopping — parking in \(mode)")
    }

    /// The mirror of ``announceContinuousStop(becoming:)``: the stream is now
    /// feeding, from a fresh ``start()`` or from a resume out of a park.
    private func announceContinuousStart(resuming: Bool) {
        guard !isContinuousStreaming else { return }
        isContinuousStreaming = true
        TraceletLog.lifecycle(String(
            format: "location stream: continuous updates starting — accuracy=%d distanceFilter=%.1fm%@",
            runtimeDesiredAccuracy ?? budgetDesiredAccuracy ?? configManager.getDesiredAccuracy(),
            runtimeDistanceFilter ?? budgetDistanceFilter ?? configManager.getDistanceFilter(),
            resuming ? " (resuming from a stationary park)" : ""))
    }

    /// Configures CLLocationManager for periodic mode.
    ///
    /// Key difference from `configureLocationManager()`:
    /// - `allowsBackgroundLocationUpdates = false` — no persistent blue arrow
    /// - Uses `periodicDesiredAccuracy` instead of `desiredAccuracy`
    private func configureLocationManagerForPeriodic() {
        // DO NOT set allowsBackgroundLocationUpdates = true
        // This prevents the persistent blue arrow in the status bar
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.pausesLocationUpdatesAutomatically = false

        let accuracy = configManager.getPeriodicDesiredAccuracy()
        switch accuracy {
        case 0: locationManager.desiredAccuracy = kCLLocationAccuracyBest
        case 1: locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case 2: locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        case 3: locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        case 4: locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        default: locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = configManager.getActivityType()
    }

    /// Starts the periodic timer that triggers one-shot location fixes.
    private func startPeriodicTimer() {
        stopPeriodicTimer()
        let interval = TimeInterval(configManager.getPeriodicLocationInterval())

        // Fire immediately for the first fix
        performPeriodicFix()

        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.performPeriodicFix()
        }
        // Allow iOS to coalesce timer fires with other system work for
        // energy efficiency. 10% tolerance is Apple’s recommendation (I-H2).
        timer.tolerance = interval * 0.1
        periodicTimer = timer
    }

    /// Stops the periodic timer.
    private func stopPeriodicTimer() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    /// Restarts the periodic timer if it has been invalidated.
    ///
    /// When iOS suspends the app, the in-memory `Timer` is killed. If the
    /// app is woken (e.g., by `BGAppRefreshTask` or significant-location
    /// change), the timer needs to be re-created so periodic fixes resume
    /// at the configured interval.
    public func restartPeriodicTimerIfNeeded() {
        guard isPeriodicTracking else { return }
        guard periodicTimer == nil || !(periodicTimer?.isValid ?? false) else { return }
        TraceletLog.debug("[Tracelet] Restarting periodic timer (was invalidated/nil)")
        let interval = TimeInterval(configManager.getPeriodicLocationInterval())
        let timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.performPeriodicFix()
        }
        // Allow iOS to coalesce timer fires with other system work for
        // energy efficiency. 10% tolerance is Apple's recommendation.
        timer.tolerance = interval * 0.1
        periodicTimer = timer
    }

    /// Number of GPS samples collected per high-accuracy periodic fix before
    /// the most accurate one is persisted (#282). Bounded by `locationTimeout`.
    private static let periodicHighAccuracySampleCount = 3

    /// Performs a single one-shot location fix for periodic mode.
    ///
    /// Temporarily enables `allowsBackgroundLocationUpdates` and calls
    /// `requestLocation()`. The delegate callback (`didUpdateLocations`)
    /// handles dispatching and then turns GPS back off.
    ///
    /// This method is `internal` so that `PeriodicRefreshScheduler` and
    /// the plugin can trigger a fix from a `BGAppRefreshTask` wake-up.
    public func performPeriodicFix() {
        guard isPeriodicTracking else { return }

        // #282: In high-accuracy periodic mode, iOS's single requestLocation()
        // one-shot often returns a stale cached or first-coarse fix before the
        // GPS hardware converges. Route through the shared best-of-N sampling
        // window (the same path getCurrentPosition uses) so we persist the most
        // accurate fix instead. feedSample() consumes the samples during the
        // window (no double-dispatch) and restoreAfterSampling() puts the
        // low-power periodic configuration back. Non-best accuracy keeps the
        // cheaper single-shot path below.
        if configManager.getPeriodicDesiredAccuracy() == 0 {
            // Don't start a second window on top of an in-flight one (only
            // possible if the periodic interval is shorter than locationTimeout).
            guard sampleState == nil else {
                TraceletLog.debug("[Tracelet] performPeriodicFix: sampling window already active, skipping tick")
                return
            }
            TraceletLog.debug("[Tracelet] performPeriodicFix: high-accuracy best-of-N sampling window")
            periodicFixTimeoutWork?.cancel()
            endPeriodicFixBgTask()
            periodicFixBgTaskId = BackgroundTaskHelper.shared.begin("periodicFix")
            collectSamples(
                count: Self.periodicHighAccuracySampleCount,
                accuracyTarget: nil,
                requestId: nil,
                initialCandidates: [],
                timeoutSeconds: configManager.getLocationTimeout(),
                persist: true,
                extras: [:]
            ) { [weak self] _ in
                self?.endPeriodicFixBgTask()
            }
            return
        }

        TraceletLog.debug("[Tracelet] performPeriodicFix: requesting one-shot GPS fix")

        // Cancel any previous timeout that hasn't fired yet
        periodicFixTimeoutWork?.cancel()
        endPeriodicFixBgTask()

        periodicFixBgTaskId = BackgroundTaskHelper.shared.begin("periodicFix")

        // Temporarily enable background location for this single fix
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.requestLocation()

        // Timeout: restore state after locationTimeout seconds if no callback
        let timeout = configManager.getLocationTimeout()
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPeriodicTracking else {
                self?.endPeriodicFixBgTask()
                return
            }
            // Restore non-background state
            self.locationManager.allowsBackgroundLocationUpdates = false
            self.locationManager.stopUpdatingLocation()
            self.endPeriodicFixBgTask()
        }
        periodicFixTimeoutWork = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(timeout), execute: timeoutWork)
    }

    /// Ends the periodic fix background task if one is active.
    private func endPeriodicFixBgTask() {
        if let taskId = periodicFixBgTaskId {
            BackgroundTaskHelper.shared.end(taskId)
            periodicFixBgTaskId = nil
        }
    }

    public func destroy() {
        stop()
        lastLocation = nil
        lastGpsLocation = nil
        oneShots.removeAll()
        stopAllWatchers()
        locationProcessor = nil
        kalmanFilter = nil
    }

    /// Stops all active watch-position subscriptions.
    public func stopAllWatchers() {
        watchCallbacks.removeAll()
    }

    // MARK: - Configuration

    private func configureLocationManager() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = configManager.getShowsBackgroundLocationIndicator()
        locationManager.pausesLocationUpdatesAutomatically = configManager.getPausesLocationUpdatesAutomatically()

        applyLocationProviderOptions()
        locationManager.activityType = configManager.getActivityType()
    }

    /// Replaces the active, temporary provider override without stopping or
    /// restarting Core Location. Passing nil for both values restores the
    /// persisted provider options. Returns false when continuous tracking is
    /// inactive or the distance filter is invalid.
    @discardableResult
    public func updateLocationProviderOptions(
        desiredAccuracy: Int?,
        distanceFilter: Double?
    ) -> Bool {
        guard isTracking, !isPeriodicTracking else { return false }
        if let distanceFilter = distanceFilter,
           (!distanceFilter.isFinite || distanceFilter < 0) {
            return false
        }

        runtimeDesiredAccuracy = desiredAccuracy
        runtimeDistanceFilter = distanceFilter
        applyLocationProviderOptions()
        return true
    }

    // MARK: - Stall watchdog (#397)

    /// Consecutive fixes whose speed was too old to drive the pace machine.
    ///
    /// Bounds the always-on logging to one line per run rather than one per fix.
    private var staleFixesSincePace = 0

    /// When the processor last accepted a fix, or `nil` before the first one.
    private var lastAcceptedFixAt: Date?
    /// Rejections since the last accepted fix, by reason.
    private var rejectionsSinceAccept: [String: Int] = [:]
    /// Whether the current stall has already been announced, so the lifecycle
    /// channel gets one line per stall rather than one per fix.
    private var stallAnnounced = false

    /// Oldest a fix may be and still be allowed to drive the pace machine.
    ///
    /// Ten seconds: comfortably longer than any live fix interval, and far
    /// shorter than the gap across which a cached fix survives a stationary
    /// period. A reading older than this describes a moment that has passed.
    private static let maximumPaceFixAge: TimeInterval = 10

    /// How long a tracking session may accept nothing before the SDK says so.
    ///
    /// Twice the processor's idle escape, so a stall this long means something
    /// the escape cannot fix — every fix failing the accuracy gate, a permission
    /// downgrade, a radio delivering nothing usable.
    private static let stallAnnounceSeconds: TimeInterval = 120

    /// Records the outcome of one filter decision and announces a stalled or
    /// recovered stream on the always-on lifecycle channel.
    ///
    /// A stream that accepts nothing for minutes is indistinguishable from a
    /// parked device in the logs, and both look like "tracking is running". That
    /// ambiguity is what made the field reports for #393/#394 take two exports
    /// and a source read to resolve — so the SDK now states it, at a level that
    /// survives a released app's default `logLevel` (#318, #397).
    private func noteFilterDecision(_ result: LocationProcessorResult, accepted: Bool) {
        let now = Date()
        if accepted {
            if stallAnnounced, let since = lastAcceptedFixAt {
                let histogram = rejectionsSinceAccept
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " ")
                TraceletLog.lifecycle(String(
                    format: "location stream recovered after %.0fs — %d fix(es) rejected meanwhile [%@]%@",
                    now.timeIntervalSince(since),
                    rejectionsSinceAccept.values.reduce(0, +),
                    histogram,
                    result.idleEscape ? ", admitted by the idle escape (#394)" : ""))
            }
            if result.idleEscape && !stallAnnounced {
                TraceletLog.lifecycle(String(
                    format: "adaptive sampling held a fix for %.0fs behind a %.0fm gate — "
                        + "admitted it at the configured filter instead (#394)",
                    result.anchorAgeSeconds, result.effectiveDistanceFilter))
            }
            if result.anchorReseeded {
                TraceletLog.lifecycle(String(
                    format: "anchor re-seeded after a %.0fs gap with no observations — "
                        + "position taken, %.0fm span not counted as travel (#395)",
                    result.anchorAgeSeconds, result.distance))
            }
            lastAcceptedFixAt = now
            rejectionsSinceAccept.removeAll()
            stallAnnounced = false
            return
        }

        rejectionsSinceAccept[result.reason ?? "unknown", default: 0] += 1

        guard let since = lastAcceptedFixAt else {
            // No fix has ever been accepted; `start()` seeds this, so reaching
            // here means the very first one has not landed yet.
            lastAcceptedFixAt = now
            return
        }
        let stalledFor = now.timeIntervalSince(since)
        guard !stallAnnounced, stalledFor >= Self.stallAnnounceSeconds else { return }
        stallAnnounced = true

        let histogram = rejectionsSinceAccept
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        TraceletLog.lifecycle(String(
            format: "location stream stalled — nothing accepted for %.0fs, %d fix(es) rejected [%@]; "
                + "last gate=%.1fm (configured %.1fm), last fix acc=%.1fm, in force: %@",
            stalledFor,
            rejectionsSinceAccept.values.reduce(0, +),
            histogram,
            result.effectiveDistanceFilter,
            configManager.getDistanceFilter(),
            result.accuracy,
            currentTuningDescription()))
    }

    /// Installs the battery-budget ladder's overlay, or clears it when the
    /// ladder returns to level 0 (#396).
    ///
    /// Nothing here touches ConfigManager: the app's configuration is what the
    /// app set, and the throttle is a temporary lens over it. The accuracy floor
    /// is the one piece that reaches the Rust processor, and it only ever
    /// *loosens* the tracking gate — because a ladder that has asked iOS for
    /// 100 m fixes must not leave a 15 m gate in place to reject them, which is
    /// how the old engine managed to spend the battery and keep none of the
    /// locations (#393).
    public func applyBudgetOverlay(
        distanceFilter: Double?,
        desiredAccuracy: Int?,
        trackingAccuracyFloor: Int
    ) {
        budgetDistanceFilter = distanceFilter
        budgetDesiredAccuracy = desiredAccuracy
        budgetTrackingAccuracyFloor = max(0, trackingAccuracyFloor)
        locationProcessor?.setAccuracyFloor(metres: Int32(budgetTrackingAccuracyFloor))
        if isTracking {
            applyLocationProviderOptions()
        }
    }

    /// Applies only the location provider's live acquisition policy. Keeping
    /// this separate from ConfigManager and LocationProcessor lets callers
    /// throttle GPS acquisition temporarily without resetting track/odometer
    /// continuity or changing which delivered points are accepted.
    private func applyLocationProviderOptions() {
        let accuracy = runtimeDesiredAccuracy ?? budgetDesiredAccuracy ?? configManager.getDesiredAccuracy()
        switch accuracy {
        case 0: locationManager.desiredAccuracy = kCLLocationAccuracyBest
        case 1: locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case 2: locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        case 3, 4: locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        default: locationManager.desiredAccuracy = kCLLocationAccuracyBest
        }

        let distanceFilter = runtimeDistanceFilter ?? budgetDistanceFilter ?? configManager.getDistanceFilter()
        let isSpeedMode = configManager.getMotionDetectionMode() == .speed
        // High-accuracy geofence mode needs time-based delivery so a stationary
        // device still gets fixes to evaluate crossings against. Persistence
        // volume is unaffected — the Rust processor keeps its own distance filter.
        if isStopTimeoutActive || geofenceHighAccuracyMode {
            locationManager.distanceFilter = kCLDistanceFilterNone
        } else {
            locationManager.distanceFilter = (distanceFilter > 0 && !isSpeedMode) ? distanceFilter : kCLDistanceFilterNone
        }
    }

    private var activeStopTimeouts: Set<String> = []

    /// Tracks whether a stop timeout is currently active.
    public var isStopTimeoutActive: Bool {
        return !activeStopTimeouts.isEmpty
    }

    /// Overrides the distance filter temporarily.
    /// Used by TraceletSdk to keep the app awake during the stop timeout by forcing continuous GPS updates.
    public func overrideDistanceFilter(forStopTimeout: Bool, source: String = "Unknown") {
        if forStopTimeout {
            activeStopTimeouts.insert(source)
        } else {
            activeStopTimeouts.remove(source)
        }
        
        let isActive = isStopTimeoutActive
        if isActive {
            // If preventSuspend is enabled, the app is already kept alive via 
            // audio session. Overriding the GPS to continuous is redundant 
            // and wastes battery.
            if configManager.getPreventSuspend() {
                TraceletLog.debug("[Tracelet-Location] overrideDistanceFilter: skipped because preventSuspend is true")
                return
            }
            locationManager.distanceFilter = kCLDistanceFilterNone
        } else {
            applyLocationProviderOptions()
        }
    }

    /// Checks for iOS 14+ reduced accuracy authorization and auto-requests
    /// temporary full accuracy if available. Logs a warning when reduced.
    private func checkReducedAccuracy() {
        if #available(iOS 14.0, *) {
            let current = locationManager.accuracyAuthorization == .fullAccuracy ? 0 : 1
            lastAccuracyAuthorization = current
            if current == 1 {
                TraceletLog.warning("[Tracelet] WARNING: Reduced accuracy authorization — locations will be approximate (~5 km). desiredAccuracy is ignored by iOS in this mode.")
                // Auto-request temporary full accuracy. The purpose key must
                // match a key in the app's Info.plist
                // NSLocationTemporaryUsageDescriptionDictionary.
                locationManager.requestTemporaryFullAccuracyAuthorization(
                    withPurposeKey: "TraceletFullAccuracy"
                )
                TraceletLog.debug("[Tracelet] Requested temporary full accuracy (purposeKey: TraceletFullAccuracy)")
            }
        }
    }

    /// Whether the current accuracy authorization is reduced (iOS 14+).
    private var isReducedAccuracy: Bool {
        if #available(iOS 14.0, *) {
            return locationManager.accuracyAuthorization == .reducedAccuracy
        }
        return false
    }

    // MARK: - One-shot position

    /// Fetches the current position with configurable options.
    ///
    /// Supported keys in `options`:
    /// - `desiredAccuracy` (Int): Accuracy level override.
    /// - `timeout` (Int): Timeout in seconds (default 30).
    /// - `maximumAge` (Int): Max age in ms of a cached location.
    /// - `persist` (Bool): Whether to persist to DB (default true).
    /// - `samples` (Int): Number of samples; best accuracy is returned (default 1).
    /// - `accuracyTarget` (Double): Optional horizontal target in metres.
    /// - `requestId` (String): Optional caller-owned cancellation identifier.
    /// - `extras` ([String: Any]): Extra data to attach.
    public func getCurrentPosition(options: [String: Any], callback: @escaping ([String: Any]?) -> Void) {
        // Guard: require at least WhenInUse authorization before attempting.
        let authStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authStatus = locationManager.authorizationStatus
        } else {
            authStatus = CLLocationManager.authorizationStatus()
        }
        guard authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways else {
            TraceletLog.debug("[Tracelet] getCurrentPosition called without location authorization (status=\(authStatus.rawValue)). Call requestPermission() first.")
            callback(nil)
            return
        }

        let persist = options["persist"] as? Bool ?? true
        let maximumAge = (options["maximumAge"] as? NSNumber)?.int64Value ?? 0
        let samples = max((options["samples"] as? NSNumber)?.intValue ?? 1, 1)
        let timeout = max((options["timeout"] as? NSNumber)?.intValue ?? 30, 0)
        let rawAccuracyTarget = (options["accuracyTarget"] as? NSNumber)?.doubleValue
        let accuracyTarget: Double?
        if let target = rawAccuracyTarget, target.isFinite, target >= 0 {
            accuracyTarget = target
        } else {
            accuracyTarget = nil
        }
        let requestId = options["requestId"] as? String
        let extras = options["extras"] as? [String: Any] ?? [:]

        var cachedCandidate: CLLocation?
        if maximumAge > 0, let cached = lastLocation {
            let ageMs = Int64(Date().timeIntervalSince(cached.timestamp) * 1000)
            if ageMs <= maximumAge, cached.horizontalAccuracy >= 0 {
                if (accuracyTarget.map({ cached.horizontalAccuracy <= $0 }) ?? true) &&
                    requestId == nil {
                    var locationMap = buildLocationMap(cached)
                    locationMap["extras"] = mergedExtras(base: locationMap["extras"], local: extras)
                    if persist {
                        self.sinks.forEach { $0.insertLocation(locationMap) }
                        self.onLocationPersisted?()
                    }
                    callback(locationMap)
                    return
                }
                cachedCandidate = cached
            }
        }

        // Use collectSamples for all cases — including samples == 1.
        // CLLocationManager.requestLocation() may return a stale cached
        // location without waking the GPS hardware. collectSamples uses
        // startUpdatingLocation() which forces a fresh GPS fix with proper
        // timeout handling.
        collectSamples(
            count: samples,
            accuracyTarget: accuracyTarget,
            requestId: requestId,
            initialCandidates: cachedCandidate.map { [$0] } ?? [],
            timeoutSeconds: timeout,
            persist: persist,
            extras: extras,
            callback: callback
        )
    }

    /// Returns the last known location without activating any provider.
    ///
    /// This is a zero-battery-cost operation. Returns nil if no cached
    /// location is available.
    ///
    /// Supported keys in `options`:
    /// - `persist` (Bool): Whether to persist to DB (default false).
    /// - `extras` ([String: Any]): Extra data to attach.
    public func getLastKnownLocation(options: [String: Any], callback: ([String: Any]?) -> Void) {
        let persist = options["persist"] as? Bool ?? false
        let extras = options["extras"] as? [String: Any] ?? [:]

        guard let location = lastLocation ?? locationManager.location else {
            callback(nil)
            return
        }

        var locationMap = buildLocationMap(location)
        locationMap["extras"] = mergedExtras(base: locationMap["extras"], local: extras)
        locationMap["event"] = "getLastKnownLocation"
        if persist {
            self.sinks.forEach { $0.insertLocation(locationMap) }
            self.onLocationPersisted?()
        }
        callback(locationMap)
    }

    // MARK: - Watch position

    public func watchPosition(options: [String: Any]) -> Int {
        let watchId = nextWatchId
        nextWatchId += 1
        watchCallbacks[watchId] = true

        // Start tracking if not already
        if !isTracking {
            configureLocationManager()
            locationManager.startUpdatingLocation()
            isTracking = true
            isContinuousStreaming = true
        }
        return watchId
    }

    public func stopWatchPosition(_ watchId: Int) -> Bool {
        watchCallbacks.removeValue(forKey: watchId)
        return true
    }

    // MARK: - Pace control

    public func changePace(_ isMoving: Bool) -> Bool {
        let wasTracking = isTracking
        stateManager.isMoving = isMoving
        if isMoving {
            start()
            // On an actual stationary → moving transition, fire an additional
            // one-shot request so a fresh fix arrives as soon as the GPS
            // hardware is warm, without waiting for the continuous stream's
            // first delivery. iOS prioritizes requestLocation() over the
            // rate-limited updates from startUpdatingLocation(), and routes
            // the result through didUpdateLocations so the full processing
            // pipeline (filters, Kalman, persistence) still applies.
            // Skip for periodic mode (already driven by requestLocation).
            if !wasTracking && !isPeriodicTracking {
                locationManager.requestLocation()
            }
        } else {
            stop()
        }
        // Dispatch motionChange event (consistent with Android)
        let locationMap: [String: Any]
        if let loc = lastLocation {
            var map = buildLocationMap(loc, speed: lastEffectiveSpeed)
            map["isMoving"] = isMoving
            map["event"] = "motionchange"
            locationMap = map
            
            enrichWithAddressIfNeeded(locationMap: locationMap, location: loc) { [weak self] enrichedMap in
                self?.eventDispatcher.sendMotionChange(enrichedMap)
            }
        } else {
            locationMap = ["isMoving": isMoving]
            eventDispatcher.sendMotionChange(locationMap)
        }
        return true
    }

    /// Acquires the single fix that anchors a session which *starts* stationary
    /// (#385).
    ///
    /// A fresh `start()` with `motion.isMoving: false` — the default — runs no
    /// continuous stream by design, and on this path nothing else acquires
    /// either: `changePace(false)` hands the pace to the motion subsystems,
    /// which are already stationary and so change nothing. The app was left
    /// with no position at all until the device physically moved and
    /// `changePace(true)` took the stationary → moving transition, which is
    /// where the equivalent one-shot below already lived.
    ///
    /// Routed through `requestLocation()` — and therefore through
    /// `didUpdateLocations` — rather than the best-of-N sampling window that
    /// `getCurrentPosition` uses: the sampling window delivers via
    /// `deliverBest`, which writes to the sinks directly and would bypass the
    /// `persistMode` gate and the `event: "location"` tag that every automatic
    /// fix carries. An anchor the app never asked for must obey the same
    /// persistence rules as the stream it stands in for.
    public func requestStartupFix() {
        let authStatus: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authStatus = locationManager.authorizationStatus
        } else {
            authStatus = CLLocationManager.authorizationStatus()
        }
        guard authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways else {
            TraceletLog.debug("[Tracelet] requestStartupFix skipped — not authorized (status=\(authStatus.rawValue))")
            return
        }

        // The stream is already acquiring — a moving start, or the
        // in-app-evaluated-geofence branch of a stationary one (#357). Periodic
        // owns the manager outright and restores its own configuration after
        // each fix; do not reach into it.
        guard !isTracking, !isPeriodicTracking else { return }

        // Don't collide with an in-flight getCurrentPosition window: its
        // `feedSample` would consume the fix and `restoreAfterSampling` would
        // stop the updates it started.
        guard sampleState == nil else { return }

        // start() never ran on this path, so the manager still holds whatever
        // accuracy a previous mode left on it. Apply the configured one.
        applyLocationProviderOptions()
        startupFixPending = true
        locationManager.requestLocation()
    }

    /// Set between [requestStartupFix] and the fix it asks for, so
    /// `didUpdateLocations` can recognise the session's anchor.
    ///
    /// Cleared by the first delivery, by a delegate error, and by `stop()`, so
    /// a request that never lands cannot leave the flag on an unrelated fix
    /// later in the session.
    private var startupFixPending = false

    /// Force-accepts one fix the processor would otherwise drop, so the fix
    /// that wakes a stationary session is delivered even though it sits within
    /// `distanceFilter` of the anchor `start()` took (#385).
    ///
    /// The Android engine has carried the same flag since the killed-state
    /// wake-up path needed it, for the same reason: "the RustProcessor might
    /// filter the actual location (distance=0) and the server won't know we
    /// woke up".
    internal var forceAcceptNextFilteredLocation = false

    // MARK: - Odometer

    public func getOdometer() -> Double {
        return stateManager.odometer
    }

    /// Sets the odometer to a specific value.
    ///
    /// The processor's odometer anchor goes with it (#387). Distance is
    /// measured from that anchor, not from the total, so writing the counter
    /// alone left the next accepted fix to add the whole span since the
    /// previous one — for the common "reset to zero, then start tracking",
    /// however far the device had travelled while it was not being tracked.
    /// `setOdometer(0)` meant "the odometer is zero" for exactly one fix.
    ///
    /// Only the odometer anchor is cleared, never the tracking one: that would
    /// waive the distance filter for the next fix and change which locations
    /// are recorded, which is not something setting a counter should do.
    public func setOdometer(_ value: Double) -> [String: Any] {
        stateManager.odometer = value
        locationProcessor?.resetOdometerAnchor()
        if let loc = lastLocation {
            return buildLocationMap(loc)
        }
        return ["odometer": value]
    }

    public func getLastLocation() -> CLLocation? {
        return lastLocation
    }

    /// Returns the best available location for heartbeat: prefers the last
    /// GPS-quality fix (≤100m accuracy) over a potentially stale significant-
    /// location-change fix. Falls back to lastLocation if no GPS fix exists.
    public func getLastGpsLocation() -> CLLocation? {
        return lastGpsLocation ?? lastLocation
    }

    // MARK: - Provider state

    public func buildProviderState() -> [String: Any] {
        var state: [String: Any] = [
            "enabled": CLLocationManager.locationServicesEnabled(),
            "gps": true,
            "network": true,
            "platform": "ios",
        ]

        if #available(iOS 14.0, *) {
            let status = locationManager.authorizationStatus
            state["status"] = authorizationStatusToInt(status)
            state["accuracyAuthorization"] = locationManager.accuracyAuthorization == .fullAccuracy ? 0 : 1
        } else {
            let status = CLLocationManager.authorizationStatus()
            state["status"] = authorizationStatusToInt(status)
        }

        return state
    }

    /// Returns the current authorization status as an integer:
    /// 0 = notDetermined, 1 = restricted/denied, 2 = whenInUse, 3 = always.
    public func getAuthorizationStatus() -> Int {
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        return authorizationStatusToInt(status)
    }

    private func authorizationStatusToInt(_ status: CLAuthorizationStatus) -> Int {
        switch status {
        case .notDetermined: return 0
        case .restricted: return 1
        case .denied: return 1
        case .authorizedWhenInUse: return 2
        case .authorizedAlways: return 3
        @unknown default: return 0
        }
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Consumed here so exactly one fix is treated as the session's anchor
        // (#385) — see `speedSink` below.
        let isStartupFix = startupFixPending
        startupFixPending = false

        // Only reset DR timer on GPS-quality fixes (not cell/Wi-Fi).
        if LocationEngine.isGpsFix(location) {
            resetGpsLossTimer()
            if deadReckoningEngine?.isActive == true {
                TraceletLog.debug("[Tracelet] GPS signal recovered — deactivating dead reckoning")
                deactivateDeadReckoning()
            }
        }

        // Request background execution time for the entire persist + dispatch
        // chain. Without this, iOS may suspend the app mid-flight when waking
        // from significant-location-change or background delivery.
        let bgTaskId = BackgroundTaskHelper.shared.begin("locationUpdate")
        defer { BackgroundTaskHelper.shared.end(bgTaskId) }

        // --- Mock location rejection (defense-in-depth) ---
        if configManager.getRejectMockLocations() && isLocationMock(location) {
            if !mockLocationWarningFired {
                mockLocationWarningFired = true
                var providerState = buildProviderState()
                providerState["mockLocationsDetected"] = true
                eventDispatcher.sendProviderChange(providerState)
            }
            return // Drop the mock location entirely.
        }

        // --- Geofence crossing evaluation on the RAW stream ---
        // Runs before the persistence distance filter below so a stationary
        // device (whose fixes that filter drops) is never starved of crossing
        // evaluations. See `onRawGeofenceLocation`. Persistence is unaffected —
        // the processor filter still gates what reaches the DB/sync queue.
        onRawGeofenceLocation?(
            location.coordinate.latitude,
            location.coordinate.longitude,
            location.horizontalAccuracy
        )

        // Feed multi-sample collection if active
        let consumedBySampler = feedSample(location)

        // --- Compute speed from distance/time as fallback ---
        var computedSpeed: Double = 0.0
        var distance: Double = 0.0

        if let last = lastLocation {
            distance = location.distance(from: last)
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
            computedSpeed = (distance > 0 && timeDelta > 0) ? distance / timeDelta : 0.0

            // A derived speed is only as good as its time base, and `timeDelta > 0`
            // is satisfied by one millisecond. A session start where CoreLocation
            // flushes a cached fix alongside a fresh one divides a real distance by
            // an almost-zero interval, which produced 10073 m/s from a phone on a
            // desk — enough to wake the speed motion machine out of STATIONARY,
            // since speedWakeConfirmCount is 1 by default (#342).
            //
            // `maxImpliedSpeed` already encodes what counts as credible movement;
            // above it this is an artefact, not a measurement. Report *no* speed
            // rather than a fabricated one. That is not #332 in reverse: this
            // branch is only reached when the platform supplied no speed at all,
            // so 0 is the pre-existing meaning of "unknown" rather than a value
            // invented in place of a real reading. A genuinely moving device has a
            // Doppler speed and never gets here.
            let maxImplied = Double(configManager.getMaxImpliedSpeed())
            if maxImplied > 0 && computedSpeed > maxImplied {
                TraceletLog.debug(String(
                    format: "[Tracelet] Discarding implausible derived speed %.2f m/s "
                        + "(%.2fm over %.3fs, max %.0f m/s) — reporting no speed",
                    computedSpeed, distance, timeDelta, maxImplied))
                computedSpeed = 0.0
            }
        } else if isPeriodicTracking {
            // Fallback: when the app was killed and relaunched by
            // BGAppRefreshTask, lastLocation is nil. Use persisted periodic
            // coordinates so the odometer isn't lost across restarts.
            let lastLat = stateManager.lastPeriodicLatitude
            let lastLng = stateManager.lastPeriodicLongitude
            if !lastLat.isNaN && !lastLng.isNaN {
                let lastCL = CLLocation(latitude: lastLat, longitude: lastLng)
                distance = location.distance(from: lastCL)
            }
        }

        // Resolve effective speed: platform speed if available, otherwise computed.
        //
        // The startup anchor (#385) has no valid time base for the derivation:
        // `lastLocation` survives stop(), so the first fix of a new session in a
        // live process would be derived against wherever the *previous* session
        // ended. A device carried 5 km between two sessions yields ~8 m/s —
        // inside `maxImpliedSpeed` (80 m/s), so nothing discards it. A Doppler
        // reading is a real measurement and is kept; the derivation is dropped,
        // for this one fix only, which is what "no speed" already means here.
        let effectiveSpeed = (location.speed > 0)
            ? location.speed
            : (isStartupFix ? 0.0 : computedSpeed)

        // Feed the transport classifier from the raw stream — see `rawSpeedSink`.
        rawSpeedSink?(effectiveSpeed)

        // --- Kalman smoothing (optional) ---
        // Runs BEFORE the processor so the odometer accumulates over the smoothed
        // track rather than the raw one (#299). Previously this ran afterwards and
        // only fed `coords`, so enabling `useKalmanFilter` smoothed the map while
        // distance kept accumulating raw GPS jitter.
        //
        // Feeding every fix (not only accepted ones) also keeps the filter's
        // velocity estimate continuous across fixes the processor rejects.
        var smoothedLat = location.coordinate.latitude
        var smoothedLng = location.coordinate.longitude
        if let kalman = kalmanFilter {
            let smoothed = kalman.process(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                timestampMs: Int64(location.timestamp.timeIntervalSince1970 * 1000)
            )
            smoothedLat = smoothed.latitude
            smoothedLng = smoothed.longitude
        }

        // --- Rust-powered filtering (distance, accuracy, speed, mock, sparse) ---
        let mock = isLocationMock(location)
        let processor = getProcessor()
        let batteryInfo = BatteryUtils.getBatteryInfo()
        let batteryLevel = (batteryInfo["level"] as? NSNumber)?.doubleValue ?? -1.0
        let isCharging = batteryInfo["is_charging"] as? Bool ?? false

        let adaptiveCtx = AdaptiveContext(
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            // #299: use the effective activity, so a `fusedClassifierAuthoritative`
            // classifier actually reaches the adaptive sampler as documented.
            activityType: mapActivityType(effectiveActivityType()),
            activityConfidence: mapActivityConfidence(effectiveActivityConfidence()),
            speed: effectiveSpeed
        )
        let result = processor.process(
            latitude: smoothedLat,
            longitude: smoothedLng,
            accuracy: location.horizontalAccuracy,
            speed: effectiveSpeed,
            timestampMs: Int64(location.timestamp.timeIntervalSince1970 * 1000),
            isMock: mock,
            adaptiveContext: adaptiveCtx
        )
        // IMPORTANT: Always feed the speed motion state machine, even when the
        // Rust processor rejects the location for persistence/dispatch. The speed
        // SM needs every speed reading to correctly transition between
        // MOVING → SLOWING → STATIONARY. Without this, a stationary device
        // whose locations are filtered (e.g. same lat/lng, no distance change)
        // will never transition out of MOVING state.
        //
        // `result.effectiveSpeed` is the speed the processor resolved for this
        // fix whether or not it accepted it — it used to be hardcoded to 0 on
        // every rejection, which fed the machine a fabricated "stopped" for
        // most of every drive (#332).
        //
        // The anchor keeps the measured-speed-only rule applied above: the
        // *processor* derives its own speed from its own last accepted fix
        // (`state.last_latitude`), which stop() does not clear either, so
        // `result.effectiveSpeed` re-introduces exactly the cross-session
        // derivation that `effectiveSpeed` just declined. Left alone it would
        // overturn the pace `start()` committed a few lines before asking for
        // the anchor — 8 m/s is well above `speedMovingThreshold` (1.5 m/s) —
        // which is the silent override of a committed pace #344 exists to
        // prevent (#385).
        let motionSpeed = isStartupFix ? effectiveSpeed : result.effectiveSpeed
        // Only a *current* fix may tell the pace machine how fast we are going.
        //
        // Core Location delivers a cached fix as soon as updates restart, and
        // that fix carries the speed from whenever it was taken — which, on a
        // session the accelerometer has just woken, is from before the device
        // stopped. It stands the session back down in the same second it woke,
        // so walking in the background cycles between waking and stopping
        // instead of tracking.
        //
        // Persistence and dispatch are deliberately untouched: a cached fix is
        // still a real position. It is only its *speed* that says nothing about
        // now.
        let fixAge = -location.timestamp.timeIntervalSinceNow
        if fixAge <= Self.maximumPaceFixAge {
            if staleFixesSincePace > 0 {
                // Always-on: this is the moment the pace machine regains a real
                // input, and its absence is what a "tracking stopped by itself"
                // report is actually describing.
                TraceletLog.lifecycle(String(
                    format: "pace: a current fix again after %d stale one(s) — speed=%.2f m/s",
                    staleFixesSincePace, motionSpeed))
                staleFixesSincePace = 0
            }
            speedSink?(motionSpeed)
        } else {
            staleFixesSincePace += 1
            // Once per run of stale fixes, not once per fix: the run is the
            // event, and a released app has to be able to report it.
            if staleFixesSincePace == 1 {
                TraceletLog.lifecycle(String(
                    format: "pace: ignoring a %.1fs-old fix's speed (%.2f m/s) — a reading older "
                        + "than %.0fs says nothing about the current pace, and letting it "
                        + "through stood a just-woken session back down",
                    fixAge, motionSpeed, Self.maximumPaceFixAge))
            }
        }

        var isForcedAccept = false
        if !result.accepted, forceAcceptNextFilteredLocation {
            TraceletLog.debug(
                "[Tracelet] Location filtered by Rust processor, but FORCE ACCEPTING "
                    + "as the fix that woke a stationary session (#385)")
            isForcedAccept = true
            forceAcceptNextFilteredLocation = false
        } else if result.accepted {
            forceAcceptNextFilteredLocation = false
            // Hand back the slot the anchor just took (#385).
            //
            // The processor waives the distance filter only for a fix with no
            // predecessor (`state.last_latitude.is_some() && distance < ...`).
            // Before the anchor existed, the fix that woke a stationary session
            // — the #54 one-shot on a changePace(true), or the first fix of the
            // stream the coordinator starts — *was* that first fix, and was
            // delivered for free. The anchor now holds that slot, and the wake
            // fix is metres away from it, so it would be dropped as a
            // duplicate: the app would be told it is moving and handed no
            // position to go with it.
            //
            // Deliberately not scoped to any one wake path: this is about the
            // *next* fix whatever produces it, which is what makes it cover the
            // accelerometer wake as well as the explicit pace change. While the
            // session stays stationary there is no stream, so nothing else can
            // consume it in the meantime.
            if isStartupFix { forceAcceptNextFilteredLocation = true }
        }

        if !result.accepted && !isForcedAccept {
            // #334: the speed handed to the motion machine belongs on this line.
            // Without it, a rejected fix's contribution to a stationary decision
            // can only be inferred by cross-reading the [SpeedMotion] entries.
            //
            // #397: so do the numbers the decision was actually made on. A bare
            // `DISTANCE_FILTER` cannot be checked against anything — an 8 m gate
            // and the 750 m one adaptive sampling can inflate it to look
            // identical in a log, and telling them apart is the whole diagnosis.
            TraceletLog.debug(String(
                format: "[Tracelet] Location filtered by Rust processor: %@ "
                    + "(speed=%.2f m/s fed to speed motion, acc=%.1fm, "
                    + "moved=%.1fm vs gate=%.1fm, anchor=%.0fs, thresholds df=%.1f/acc=%d/spd=%d)",
                result.reason ?? "unknown", result.effectiveSpeed, result.accuracy,
                result.distance, result.effectiveDistanceFilter, result.anchorAgeSeconds,
                currentTuning()?.distanceFilter ?? -1,
                currentTuning()?.trackingAccuracyThreshold ?? -1,
                currentTuning()?.maxImpliedSpeed ?? -1))
            noteFilterDecision(result, accepted: false)
            if result.odometerDelta > 0 {
                stateManager.addOdometer(distance: result.odometerDelta)
            }
            return
        }

        noteFilterDecision(result, accepted: true)

        // Odometer update from processor's computed delta
        if result.odometerDelta > 0 {
            stateManager.addOdometer(distance: result.odometerDelta)
        }

        // `motionSpeed`, not `result.effectiveSpeed`: this property is read as
        // the session's current speed, and startSpeedMotionManager() seeds the
        // machine with it — so an anchor's derived value would reach the
        // machine one session later through that door even though the sink
        // above declined it (#385).
        lastEffectiveSpeed = motionSpeed

        // Persist last periodic coordinates for cross-restart odometer
        if isPeriodicTracking {
            stateManager.lastPeriodicLatitude = location.coordinate.latitude
            stateManager.lastPeriodicLongitude = location.coordinate.longitude
        }

        lastLocation = location
        if location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 100 {
            lastGpsLocation = location
        }
        stateManager.lastLocationTime = Date().timeIntervalSince1970 * 1000

        // `motionSpeed` is identical to result.effectiveSpeed for every fix but
        // the anchor, which reports what was measured rather than what was
        // derived (#385).
        let locationMap = buildLocationMap(location, speed: motionSpeed, smoothedLat: smoothedLat, smoothedLng: smoothedLng)

        // Fire one-shot callbacks
        fireOneShots(location)

        // If consumed exclusively by sampler, don't dispatch as tracking event
        if consumedBySampler && !isTracking { return }

        // Fire watch position events
        if !watchCallbacks.isEmpty {
            eventDispatcher.sendWatchPosition(locationMap)
        }

        // Persist and dispatch (respecting persistMode)

        // [Enterprise] Privacy zone check — BEFORE audit + persist + send.
        if let pzm = privacyZoneManager {
            let privacyResult = pzm.processLocation(locationMap)
            switch privacyResult.action {
            case .drop:
                // Exclusion zone — drop this location entirely.
                if isPeriodicTracking {
                    locationManager.stopUpdatingLocation()
                    locationManager.allowsBackgroundLocationUpdates = false
                    periodicFixTimeoutWork?.cancel()
                    periodicFixTimeoutWork = nil
                    endPeriodicFixBgTask()
                }
                return
            case .eventOnly:
                // Dispatch to Flutter but do NOT persist or audit.
                var data = privacyResult.location ?? locationMap
                if isPeriodicTracking { data["event"] = "periodic" }
                
                enrichWithAddressIfNeeded(locationMap: data, location: location) { [weak self] enrichedData in
                    self?.eventDispatcher.sendLocation(enrichedData)
                    self?.onLocationUpdate?(location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy)
                    if self?.isPeriodicTracking == true {
                        self?.locationManager.stopUpdatingLocation()
                        self?.locationManager.allowsBackgroundLocationUpdates = false
                        self?.periodicFixTimeoutWork?.cancel()
                        self?.periodicFixTimeoutWork = nil
                        self?.endPeriodicFixBgTask()
                    }
                }
                return
            case .degraded:
                // Use degraded coordinates for audit + persist + dispatch.
                var degraded = privacyResult.location ?? locationMap
                let pzEventTag = isForcedAccept
                    ? "motionchange"
                    : (isPeriodicTracking ? "periodic" : "location")
                degraded["event"] = pzEventTag
                if let auditFields = auditTrailManager?.appendToChain(degraded) {
                    for (key, value) in auditFields {
                        degraded[key] = value
                    }
                }
                
                enrichWithAddressIfNeeded(locationMap: degraded, location: location) { [weak self] enrichedDegraded in
                    self?.persistLocationIfAllowed(enrichedDegraded, event: pzEventTag)
                    self?.eventDispatcher.sendLocation(enrichedDegraded)
                    self?.onLocationUpdate?(location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy)
                    if self?.isPeriodicTracking == true {
                        self?.locationManager.stopUpdatingLocation()
                        self?.locationManager.allowsBackgroundLocationUpdates = false
                        self?.periodicFixTimeoutWork?.cancel()
                        self?.periodicFixTimeoutWork = nil
                        self?.endPeriodicFixBgTask()
                    }
                }
                return
            case .passThrough:
                break // Fall through to normal flow
            }
        }

        // [Enterprise] Compute audit hash and merge into location map
        var dispatchMap = locationMap
        if let auditFields = auditTrailManager?.appendToChain(locationMap) {
            for (key, value) in auditFields {
                dispatchMap[key] = value
            }
        }
        // Tag periodic fixes so Dart can distinguish them from continuous-mode events
        // A force-accepted fix is the one that marks a pace change, so it is
        // tagged as such — the same tag Android gives it (#385).
        let eventTag = isForcedAccept
            ? "motionchange"
            : (isPeriodicTracking ? "periodic" : "location")
        dispatchMap["event"] = eventTag
        
        enrichWithAddressIfNeeded(locationMap: dispatchMap, location: location) { [weak self] enrichedMap in
            guard let self = self else { return }
            self.persistLocationIfAllowed(enrichedMap, event: eventTag)
            self.eventDispatcher.sendLocation(enrichedMap)

            // Notify geofenceModeHighAccuracy listener (if active)
            self.onLocationUpdate?(location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy)

            // In periodic mode, immediately stop GPS after receiving the fix
            // to minimise blue-arrow visibility.
            if self.isPeriodicTracking {
                TraceletLog.debug(String(format: "[Tracelet] Periodic fix received: lat=%.6f, lon=%.6f, accuracy=%.1fm",
                      location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy))
                self.locationManager.stopUpdatingLocation()
                self.locationManager.allowsBackgroundLocationUpdates = false
                // Cancel the timeout and end the background task now that the fix succeeded.
                self.periodicFixTimeoutWork?.cancel()
                self.periodicFixTimeoutWork = nil
                self.endPeriodicFixBgTask()
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        TraceletLog.error("[Tracelet] Location error: \(error.localizedDescription)")

        // A startup fix that failed is over; the flag must not survive onto an
        // unrelated fix later in the session (#385).
        startupFixPending = false

        // Fail all one-shots — fallback to lastLocation if available
        let fallbackLocation = lastLocation
        for callback in oneShots {
            callback(fallbackLocation)
        }
        oneShots.removeAll()

        // Fail active sample collection — don't let it hang until timeout.
        if let state = sampleState, !state.finished {
            state.finished = true
            sampleState = nil
            if !isTracking {
                locationManager.stopUpdatingLocation()
            }
            locationManager.distanceFilter = geofenceHighAccuracyMode
                ? kCLDistanceFilterNone
                : configManager.getDistanceFilter()

            if !state.collected.isEmpty {
                deliverBest(samples: state.collected, persist: state.persist, extras: state.extras, callback: state.callback)
            } else if let fallback = lastLocation {
                deliverBest(samples: [fallback], persist: state.persist, extras: state.extras, callback: state.callback)
            } else {
                state.callback(nil)
            }
        }

        // In periodic mode, ensure GPS and background updates are turned off
        // on error — mirrors the cleanup in didUpdateLocations. Without this,
        // a failed requestLocation() leaves allowsBackgroundLocationUpdates
        // enabled, keeping the location icon visible until the timeout fires.
        if isPeriodicTracking {
            locationManager.stopUpdatingLocation()
            locationManager.allowsBackgroundLocationUpdates = false
            periodicFixTimeoutWork?.cancel()
            periodicFixTimeoutWork = nil
            endPeriodicFixBgTask()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Detect accuracy authorization transitions (iOS 14+).
        if #available(iOS 14.0, *) {
            let current = manager.accuracyAuthorization == .fullAccuracy ? 0 : 1
            if lastAccuracyAuthorization >= 0 && current != lastAccuracyAuthorization {
                if current == 1 {
                    TraceletLog.debug("[Tracelet] Accuracy authorization changed to REDUCED — locations will be approximate (~5 km)")
                } else {
                    TraceletLog.debug("[Tracelet] Accuracy authorization restored to FULL")
                }
            }
            lastAccuracyAuthorization = current
        }

        let providerState = buildProviderState()
        eventDispatcher.sendProviderChange(providerState)
    }

    // MARK: - Multi-sample collection

    private var sampleState: SampleState?

    /// Internal state for multi-sample collection.
    private class SampleState {
        let targetCount: Int
        let accuracyTarget: CLLocationAccuracy?
        let requestId: String?
        let persist: Bool
        let extras: [String: Any]
        let callback: ([String: Any]?) -> Void
        var collected: [CLLocation]
        var finished = false
        var cancelled = false
        var terminal = false

        init(
            count: Int,
            accuracyTarget: CLLocationAccuracy?,
            requestId: String?,
            initialCandidates: [CLLocation],
            persist: Bool,
            extras: [String: Any],
            callback: @escaping ([String: Any]?) -> Void
        ) {
            self.targetCount = count
            self.accuracyTarget = accuracyTarget
            self.requestId = requestId
            self.collected = initialCandidates
            self.persist = persist
            self.extras = extras
            self.callback = callback
        }
    }

    private func collectSamples(
        count: Int,
        accuracyTarget: CLLocationAccuracy?,
        requestId: String?,
        initialCandidates: [CLLocation],
        timeoutSeconds: Int,
        persist: Bool,
        extras: [String: Any],
        callback: @escaping ([String: Any]?) -> Void
    ) {
        cancelActiveSample()
        let state = SampleState(
            count: count,
            accuracyTarget: accuracyTarget,
            requestId: requestId,
            initialCandidates: initialCandidates,
            persist: persist,
            extras: extras,
            callback: callback
        )
        sampleState = state
        if let target = accuracyTarget,
           initialCandidates.contains(where: { $0.horizontalAccuracy <= target }) {
            finishSample(state)
            return
        }


        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = configManager.getShowsBackgroundLocationIndicator()
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = configManager.getActivityType()
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(timeoutSeconds)
        ) { [weak self, weak state] in
            guard let self, let state, self.sampleState === state, !state.finished else { return }
            self.finishSample(state)
        }
    }

    private func feedSample(_ location: CLLocation) -> Bool {
        guard let state = sampleState, !state.finished else { return false }
        guard location.horizontalAccuracy >= 0 else { return true }

        state.collected.append(location)
        let reachedTarget = state.accuracyTarget.map {
            location.horizontalAccuracy <= $0
        } ?? false
        if reachedTarget ||
            (state.accuracyTarget == nil && state.collected.count >= state.targetCount) {
            finishSample(state)
        }
        return true
    }

    private func finishSample(_ state: SampleState) {
        guard sampleState === state, !state.finished else { return }
        state.finished = true
        restoreAfterSampling()
        let candidates = state.collected
        if !candidates.isEmpty {
            deliverBest(samples: candidates, persist: state.persist, extras: state.extras) { [weak self, weak state] result in
                guard let self, let state else { return }
                self.completeSample(state, result: result)
            }
        } else if let fallback = lastLocation, fallback.horizontalAccuracy >= 0 {
            deliverBest(samples: [fallback], persist: state.persist, extras: state.extras) { [weak self, weak state] result in
                guard let self, let state else { return }
                self.completeSample(state, result: result)
            }
        } else {
            completeSample(state, result: nil)
        }
    }

    private func completeSample(_ state: SampleState, result: [String: Any]?) {
        guard !state.terminal else { return }
        state.terminal = true
        if sampleState === state {
            sampleState = nil
        }
        state.callback(state.cancelled ? nil : result)
    }

    public func cancelCurrentPosition(_ requestId: String) -> Bool {
        guard let state = sampleState,
              state.requestId == requestId,
              !state.terminal else { return false }
        cancelSample(state)
        return true
    }

    private func cancelActiveSample() {
        guard let state = sampleState, !state.terminal else { return }
        cancelSample(state)
    }

    private func cancelSample(_ state: SampleState) {
        state.cancelled = true
        if !state.finished {
            state.finished = true
            restoreAfterSampling()
        }
        completeSample(state, result: nil)
    }

    /// Restores CLLocationManager to the correct state after sample collection.
    ///
    /// If periodic tracking is active, stops continuous updates and restores
    /// the low-power periodic configuration. If continuous tracking is active,
    /// restores the configured distance filter and accuracy. If tracking is
    /// not active at all, stops updates entirely.
    private func restoreAfterSampling() {
        if isPeriodicTracking {
            // Stop the continuous GPS that collectSamples started and
            // restore the low-power periodic configuration.
            locationManager.stopUpdatingLocation()
            configureLocationManagerForPeriodic()
        } else if isTracking {
            // Continuous tracking — restore configured filter & accuracy.
            configureLocationManager()
        } else {
            // Not tracking at all — shut down updates.
            locationManager.stopUpdatingLocation()
        }
    }

    private func deliverBest(samples: [CLLocation], persist: Bool, extras: [String: Any], callback: @escaping ([String: Any]?) -> Void) {
        guard let best = samples.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else {
            callback(nil)
            return
        }
        var locationMap = buildLocationMap(best)
        locationMap["extras"] = mergedExtras(base: locationMap["extras"], local: extras)
        
        enrichWithAddressIfNeeded(locationMap: locationMap, location: best) { [weak self] enrichedMap in
            if persist {
                self?.sinks.forEach { $0.insertLocation(enrichedMap) }
                self?.onLocationPersisted?()
                self?.eventDispatcher.sendLocation(enrichedMap)
            }
            callback(enrichedMap)
        }
    }

    // MARK: - Helpers

    private func fireOneShots(_ location: CLLocation) {
        guard !oneShots.isEmpty else { return }
        for callback in oneShots {
            callback(location)
        }
        oneShots.removeAll()
    }

    /// Builds an enriched location map ready for Dart/DB.
    ///
    /// - Parameters:
    ///   - location: The raw CLLocation.
    ///   - speed: Pre-computed effective speed (m/s).
    ///   - smoothedLat: Kalman-smoothed latitude (nil = use raw).
    ///   - smoothedLng: Kalman-smoothed longitude (nil = use raw).
    public func buildLocationMap(_ location: CLLocation, speed: Double? = nil, smoothedLat: Double? = nil, smoothedLng: Double? = nil) -> [String: Any] {
        // Use provided effective speed, or fall back to platform speed.
        let effectiveSpeed = speed ?? max(location.speed, -1)

        var coords: [String: Any] = [
            "latitude": smoothedLat ?? location.coordinate.latitude,
            "longitude": smoothedLng ?? location.coordinate.longitude,
            "altitude": location.altitude,
            "speed": effectiveSpeed,
            "heading": max(location.course, -1),
            "accuracy": location.horizontalAccuracy,
            "altitudeAccuracy": location.verticalAccuracy,
        ]

        if #available(iOS 13.4, *) {
            coords["speedAccuracy"] = location.speedAccuracy
            coords["headingAccuracy"] = location.courseAccuracy
        }

        if let floor = location.floor {
            coords["floor"] = floor.level
        }

        let battery = BatteryUtils.getBatteryInfo()

        let mock = isLocationMock(location)

        // Always include heuristic metadata even if rejection is off
        let driftMs = Date().timeIntervalSince(location.timestamp) * 1000.0
        var heuristics: [String: Any] = [
            "timestampDriftMs": driftMs,
        ]
        if #available(iOS 15.0, *) {
            heuristics["platformFlagMock"] = location.sourceInformation?.isSimulatedBySoftware ?? false
        }
        let mockHeuristics = heuristics

        // Classify the location source based on accuracy heuristic.
        // iOS does not expose provider names; accuracy is the best signal.
        // When reduced accuracy is active, iOS returns ~5 km fixes regardless
        // of desiredAccuracy, so classify accordingly.
        let reduced = isReducedAccuracy
        let locationSource: String
        if reduced {
            locationSource = "cell"  // reduced accuracy ≈ coarse cell-level
        } else if location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 50 {
            locationSource = "gps"
        } else if location.horizontalAccuracy <= 200 {
            locationSource = "wifi"
        } else if location.horizontalAccuracy > 200 {
            locationSource = "cell"
        } else {
            locationSource = "unknown"
        }

        var result: [String: Any] = [
            "uuid": Self.generateUUID(),
            "timestamp": iso8601String(from: location.timestamp),
            "coords": coords,
            "is_moving": stateManager.isMoving,
            "odometer": stateManager.odometer,
            "locationSource": locationSource,
            "reducedAccuracy": reduced,
            "mock": mock,
            "mockHeuristics": mockHeuristics as Any,
            "activity": [
                // #214 pt3: use the effective activity — the fused transport mode
                // when the classifier is authoritative (falls back to the platform
                // Activity Recognition value). Previously hardcoded "unknown", so
                // every persisted/dispatched location dropped the classified mode
                // even with fusedClassifierAuthoritative=true (the dead-reckoning
                // path below already did this; buildLocationMap was missed).
                "type": effectiveActivityType(),
                "confidence": effectiveActivityConfidence(),
            ],
            "battery": battery,
            "event": "",
        ]

        let extras = configManager.getHttpExtras()
        result["extras"] = extras.isEmpty ? [:] as [String: Any] : extras

        // enableTimestampMeta: attach additional timing metadata
        if configManager.getEnableTimestampMeta() {
            result["timestampMeta"] = [
                "time": location.timestamp.timeIntervalSince1970 * 1000, // ms since epoch
                "systemTime": Date().timeIntervalSince1970 * 1000,
                "systemClockElapsedRealtime": ProcessInfo.processInfo.systemUptime * 1000,
            ]
        }

        return result
    }

    /// Generates a UUID string using C-level functions directly.
    /// Avoids Foundation UUID struct + uppercase formatting overhead.
    private static func generateUUID() -> String {
        var uuid: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutablePointer(to: &uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                uuid_generate_random($0)
            }
        }
        var cString = [CChar](repeating: 0, count: 37)
        withUnsafePointer(to: uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                uuid_unparse_lower($0, &cString)
            }
        }
        return String(cString: cString)
    }

    /// Cached ISO 8601 formatter — creating one per call is expensive.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func iso8601String(from date: Date) -> String {
        return LocationEngine.isoFormatter.string(from: date)
    }

    /// Persists a location to the database only if allowed by persistMode.
    /// Also runs retention pruning (maxDaysToPersist / maxRecordsToPersist).
    ///
    /// persistMode: 0 = all, 1 = location only, 2 = geofence only, 3 = none
    private func persistLocationIfAllowed(_ location: [String: Any], event: String) {
        let persistMode = configManager.getPersistMode()
        // Mode 3 = none, Mode 2 = geofence only → skip location inserts
        if persistMode == 3 || persistMode == 2 { return }
        // Skip provider change records if disabled
        if event == "providerchange" && configManager.getDisableProviderChangeRecord() { return }

        // Route through Native Sinks for DB persistence + auto HTTP sync
        self.sinks.forEach { $0.insertLocation(location) }

        // Notify HTTP sync manager (if wired) so auto-sync can fire.
        onLocationPersisted?()
    }

    /// Detects whether a CLLocation was produced by a simulated/mock provider.
    ///
    /// Detection level is controlled by `mockDetectionLevel` in config:
    /// - **0 (disabled)**: Always returns `false`.
    /// - **1 (basic)**: Uses `CLLocation.sourceInformation?.isSimulatedBySoftware`
    ///   on iOS 15+. Returns `false` on older iOS versions.
    /// - **2 (heuristic)**: Basic + timestamp drift check (compare location
    ///   timestamp against current wall-clock time; large drift is suspicious).
    ///
    /// iOS has fewer heuristic signals than Android (no satellite count, no
    /// monotonic elapsed-realtime clock on locations), so heuristic mode
    /// primarily adds timestamp drift detection.
    private func isLocationMock(_ location: CLLocation) -> Bool {
        let level = configManager.getMockDetectionLevel()
        if level == 0 { return false }

        // Level 1+ (basic): Platform API flag
        if #available(iOS 15.0, *) {
            if location.sourceInformation?.isSimulatedBySoftware ?? false {
                return true
            }
        }
        if level < 2 { return false }

        // Level 2 (heuristic): Timestamp drift check
        // Real GPS locations have a timestamp very close to the current time.
        // However, unlike Android, iOS does not provide a monotonic hardware timestamp
        // (`elapsedRealtimeNanos`) on `CLLocation`. Comparing `location.timestamp`
        // against `Date()` is extremely dangerous because it will falsely flag
        // perfectly valid locations if the user's device clock is slightly out of sync
        // with network UTC time.
        // Therefore, we do not reject locations based on timestamp drift on iOS.
        
        return false
    }

    // MARK: - Dead Reckoning (Enterprise)

    /// Returns the current dead reckoning state, or nil if not active.
    func getDeadReckoningState() -> [String: Any]? {
        return deadReckoningEngine?.getState()
    }

    /// Starts the GPS-loss timer. After `deadReckoningActivationDelay` seconds
    /// without a GPS fix, dead reckoning activates automatically.
    private func startGpsLossTimer() {
        guard configManager.getEnableDeadReckoning() else { return }
        cancelGpsLossTimer()

        let delay = TimeInterval(configManager.getDeadReckoningActivationDelay())
        TraceletLog.debug("[Tracelet] DR: GPS-loss timer started (\(delay)s)")
        gpsLossTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            self?.activateDeadReckoning()
        }
    }

    /// Resets the GPS-loss timer (called on each GPS fix).
    private func resetGpsLossTimer() {
        guard configManager.getEnableDeadReckoning() else { return }
        cancelGpsLossTimer()
        startGpsLossTimer()
    }

    private func cancelGpsLossTimer() {
        gpsLossTimer?.invalidate()
        gpsLossTimer = nil
    }

    /// Activates dead reckoning from the last known GPS position.
    private func activateDeadReckoning() {
        guard let last = lastLocation else {
            TraceletLog.debug("[Tracelet] DR: Cannot activate — no last known location")
            // Restart timer so we try again once a location arrives.
            startGpsLossTimer()
            return
        }
        TraceletLog.debug("[Tracelet] DR: GPS lost for \(configManager.getDeadReckoningActivationDelay())s — activating (last=\(last.coordinate.latitude),\(last.coordinate.longitude) acc=\(last.horizontalAccuracy))")

        let engine = DeadReckoningEngine(configManager: configManager)
        engine.onEstimatedLocation = { [weak self] drLocation in
            self?.onDrLocationEstimated(drLocation)
        }
        engine.onDeactivated = {
            TraceletLog.debug("[Tracelet] Dead reckoning auto-stopped (max duration)")
        }
        engine.activate(
            lat: last.coordinate.latitude,
            lng: last.coordinate.longitude,
            altitude: last.altitude,
            heading: last.course >= 0 ? last.course : 0,
            activity: currentActivityType
        )
        deadReckoningEngine = engine
    }

    /// Deactivates dead reckoning.
    private func deactivateDeadReckoning() {
        deadReckoningEngine?.deactivate()
        deadReckoningEngine = nil
    }

    /// Processes a dead-reckoned location estimate and dispatches it.
    private func onDrLocationEstimated(_ drLocation: [String: Any]) {
        guard let lat = drLocation["latitude"] as? Double,
              let lng = drLocation["longitude"] as? Double else { return }
        let altitude = drLocation["altitude"] as? Double ?? 0
        let heading = drLocation["heading"] as? Double ?? 0
        let accuracy = drLocation["accuracy"] as? Double ?? 50
        let speed = drLocation["speed"] as? Double ?? 0

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = isoFormatter.string(from: Date())

        let enriched: [String: Any] = [
            "uuid": UUID().uuidString,
            "timestamp": timestamp,
            "isMoving": stateManager.isMoving,
            "odometer": stateManager.odometer,
            "event": "dead_reckoning",
            "mock": false,
            "isDeadReckoned": true,
            "coords": [
                "latitude": lat,
                "longitude": lng,
                "altitude": altitude,
                "speed": speed,
                "heading": heading,
                "accuracy": accuracy,
                "speedAccuracy": -1.0,
                "headingAccuracy": -1.0,
                "altitudeAccuracy": -1.0,
            ],
            "activity": [
                // #214 pt3: persist the fused transport mode when authoritative so
                // it survives termination and syncs historically (falls back to AR).
                "type": effectiveActivityType(),
                "confidence": effectiveActivityConfidence(),
            ],
            "battery": [
                "level": -1.0,
                "is_charging": false,
            ],
        ]

        persistLocationIfAllowed(enriched, event: "dead_reckoning")
        eventDispatcher.sendLocation(enriched)
    }

    // MARK: - Activity type mapping helpers (iOS string → Rust enum)

    private func mapActivityType(_ type: String) -> ActivityType {
        switch type.lowercased() {
        case "still": return .still
        case "walking": return .walking
        case "running": return .running
        case "on_foot": return .onFoot
        case "in_vehicle", "automotive": return .inVehicle
        case "on_bicycle", "cycling": return .onBicycle
        default: return .unknown
        }
    }

    private func mapActivityConfidence(_ confidence: Int) -> ActivityConfidence {
        if confidence >= 75 { return .high }
        if confidence >= 50 { return .medium }
        return .low
    }

    // MARK: - Reverse Geocoding

    private func enrichWithAddressIfNeeded(locationMap: [String: Any], location: CLLocation?, completion: @escaping ([String: Any]) -> Void) {
        guard configManager.getResolveAddress(), let clLoc = location else {
            completion(locationMap)
            return
        }
        
        TraceletLog.debug(String(format: "[Tracelet] GEOCODE: Requesting reverse geocoding for lat=%.6f, lon=%.6f", clLoc.coordinate.latitude, clLoc.coordinate.longitude))
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(clLoc) { placemarks, error in
            var finalMap = locationMap
            
            if let err = error {
                TraceletLog.error(String(format: "[Tracelet] GEOCODE: Error resolving address: %@", err.localizedDescription))
            }
            
            if let placemark = placemarks?.first {
                TraceletLog.debug(String(format: "[Tracelet] GEOCODE: Found placemark: %@", placemark.description))
                var addressMap: [String: Any] = [:]
                if let thoroughfare = placemark.thoroughfare { addressMap["street"] = thoroughfare }
                else if let name = placemark.name { addressMap["street"] = name }
                
                if let locality = placemark.locality { addressMap["city"] = locality }
                if let adminArea = placemark.administrativeArea { addressMap["state"] = adminArea }
                if let postalCode = placemark.postalCode { addressMap["postalCode"] = postalCode }
                if let country = placemark.country { addressMap["country"] = country }
                
                if !addressMap.isEmpty {
                    finalMap["address"] = addressMap
                    TraceletLog.debug(String(format: "[Tracelet] GEOCODE: Mapped address: %@", addressMap.description))
                } else {
                    TraceletLog.debug("[Tracelet] GEOCODE: Placemark had no mappable address fields.")
                }
            } else {
                TraceletLog.debug("[Tracelet] GEOCODE: No placemarks found.")
            }
            completion(finalMap)
        }
    }
}
