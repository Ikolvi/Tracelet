import Foundation
import CoreLocation

/// Coordinates between MotionDetector (Accelerometer/ActivityRecognition) and
/// SpeedMotionManager (GPS Speed) to implement the 'smart' MotionDetectionMode.
///
/// Implements a Logical OR:
/// If EITHER sensor detects motion, the app stays in continuous tracking mode.
/// If BOTH sensors detect stationary, the app stops continuous tracking and relies
/// on Geofences/periodic wakeups to save battery.
public class TraceletSmartMotionCoordinator {
    
    private var coreCoordinator: SmartMotionCoordinator?
    
    public var isAccelMoving: Bool { coreCoordinator?.isAccelMoving() ?? false }
    public var isSpeedMoving: Bool { coreCoordinator?.isSpeedMoving() ?? true }
    
    private weak var sdk: TraceletSdk?
    
    public init(sdk: TraceletSdk) {
        self.sdk = sdk
        
        let useGeofences = sdk.configManager?.getStationaryTrackingMode() == .geofences
        self.coreCoordinator = SmartMotionCoordinator(useGeofencesWhenStationary: useGeofences)
    }
    
    /// Synchronize the Rust core mode with the native StateManager on startup or mode change.
    ///
    /// `stateManager.trackingMode` and the coordinator's `currentMode` measure
    /// different things, and conflating them wedged the coordinator (#344):
    ///
    /// * `trackingMode` is the **session** mode — which start API was called. It
    ///   is set to `.continuous` by `start()` and stays there for the whole
    ///   session; `switchToStationaryPeriodicForce()` deliberately leaves it
    ///   alone and records the pace in `stateManager.isMoving` instead.
    /// * `currentMode` is the **posture** — whether the engine is running
    ///   continuous GPS right now or is parked in a stationary schedule.
    ///
    /// `start()` sets `isMoving` from `motion.isMoving` (false by default) and
    /// then calls this, so mapping `.continuous -> .continuous` wrote
    /// `Continuous` into a coordinator whose inputs both said stationary. The
    /// core's `evaluate_state` emits no action for that pair in either
    /// direction: a moving accelerometer sees `currentMode == .continuous` and
    /// returns `.none`, so `switchToContinuousForce()` never ran and the session
    /// stayed parked — no fixes recorded, nothing to sync — until the process
    /// was killed. Reading the posture off `isMoving` keeps the two in step, and
    /// the first real accel or speed event produces the wake-up.
    ///
    /// #409 is the same wedge from the other side: `isMoving` false with a *live*
    /// stream parked the coordinator while the engine kept streaming, and
    /// `evaluate_state` returns `.none` for that pair too. The posture is now the
    /// OR of the committed pace and the engine's actual state — the only reading
    /// that survives both directions.
    ///
    /// The engine's state is `isContinuousStreaming`, not `isTracking`: the
    /// speed/smart pipeline parks by stopping continuous updates while leaving
    /// `isTracking` true so delegate callbacks keep arriving, so `isTracking`
    /// reads `true` on a parked engine. ORing *that* in writes Continuous into a
    /// coordinator that is genuinely parked, and the core emits no wake-up for a
    /// posture it already believes is Continuous — #344's swallowed shake,
    /// re-entered through the #409 fix.
    public func syncCurrentMode() {
        guard let stateManager = sdk?.stateManager else { return }

        let useGeofences = sdk?.configManager?.getStationaryTrackingMode() == .geofences
        coreCoordinator?.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: stateManager.trackingMode,
                isMoving: stateManager.isMoving,
                isStreamLive: sdk?.locationEngine?.isContinuousStreaming ?? false,
                useGeofencesWhenStationary: useGeofences))
        coreCoordinator?.setUseGeofencesWhenStationary(useGeofences: useGeofences)
    }

    /// The posture the coordinator should be holding, given the session mode, the
    /// committed pace, and whether the engine is streaming right now. Pure so the
    /// mappings in #344 and #409 can be pinned directly.
    static func coordinatorMode(
        sessionMode: TraceletTrackingMode,
        isMoving: Bool,
        isStreamLive: Bool,
        useGeofencesWhenStationary: Bool
    ) -> TrackingMode {
        let stationary: TrackingMode = useGeofencesWhenStationary ? .stationaryGeofences : .stationaryPeriodic
        switch sessionMode {
        case .continuous:
            // `isMoving` predicts what start() is *about* to do; `isStreamLive`
            // reports what the engine is doing *now*. Either alone gets a case
            // wrong, so the posture is the OR of them (#409).
            //
            // `isMoving` alone was the wedge. start() syncs before it touches the
            // engine, so a session resuming stationary while a stream was still
            // live wrote a stationary posture into a coordinator whose engine was
            // streaming — and `evaluate_state` only emits the stop action when it
            // believes the posture is `.continuous`. Every later stationary
            // decision returned `.none` and GPS ran at the configured interval for
            // the rest of the session, on a device correctly reported as parked.
            //
            // `isStreamLive` alone breaks #344's direction: this runs before
            // start() starts the engine, so a moving start would sync stationary
            // and then stream — the same wedge, mirrored.
            return (isMoving || isStreamLive) ? .continuous : stationary
        case .geofences:
            return .stationaryGeofences
        case .periodic:
            return .stationaryPeriodic
        }
    }
    
    /// Called when the accelerometer/activity recognition state changes.
    /// Returns the action taken so the caller can conditionally reset
    /// the speed state machine on real wake-ups.
    @discardableResult
    public func onAccelStateChange(isMoving: Bool) -> CoordinatorAction {
        guard let action = coreCoordinator?.onAccelStateChange(isMoving: isMoving) else { return .none }
        TraceletLog.debug("[Tracelet] SmartMotionCoordinator: onAccelStateChange -> isMoving=\(isMoving), action=\(action)")
        handleAction(action)
        return action
    }
    
    /// GPS speed at or below which a *moving* accelerometer is read as hand
    /// tremor on a physically still device rather than as real motion.
    private static let tremorSpeedThreshold: Double = 0.15

    /// The last speed this process actually resolved, or `nil` if it has not
    /// resolved one yet.
    ///
    /// `lastEffectiveSpeed` and `lastLocation` are written together on every
    /// accepted fix, so a nil location is exactly "no fix has been accepted in
    /// this process" — which is *unknown*, not zero.
    private var resolvedSpeed: Double? {
        guard let engine = sdk?.locationEngine, engine.getLastLocation() != nil else { return nil }
        return engine.lastEffectiveSpeed
    }

    /// Returns the action taken, mirroring ``onAccelStateChange(isMoving:)``.
    /// Discardable — every existing caller ignores it — but it is the only
    /// externally visible product of this call, so a test has nothing else to
    /// assert the speed wake-up on.
    @discardableResult
    public func onSpeedStateChange(isMoving: Bool) -> CoordinatorAction {
        var overrideAction: CoordinatorAction = .none
        if !isMoving && isAccelMoving {
            // The speed machine says stationary and the accelerometer disagrees.
            // Two situations look like this:
            //   a) the device is physically still and the accelerometer is
            //      picking up hand tremor — GPS speed is genuinely ~0;
            //   b) the user is walking slowly, below the speed threshold — the
            //      accelerometer is the one telling the truth.
            // Only (a) justifies overruling a positive motion signal.
            //
            // #333: this used to read `getLastLocation()?.speed`, the raw
            // CLLocation value, which is **-1** on a fix that carries no speed —
            // and -1 sails through a `<= 0.15` test. An unknown speed was
            // therefore treated as proof the device was parked, and the
            // accelerometer got overridden on missing data. `lastEffectiveSpeed`
            // is the resolved value (documented on its declaration as existing
            // precisely because the cached CLLocation.speed "may be stale, 0, or
            // -1"), and no resolved speed at all now leaves the accelerometer
            // standing rather than silently siding against it.
            switch resolvedSpeed {
            case .none:
                TraceletLog.debug("[Tracelet] SmartMotionCoordinator: no GPS speed resolved yet — trusting accel, staying continuous.")
            case .some(let speed) where speed <= TraceletSmartMotionCoordinator.tremorSpeedThreshold:
                TraceletLog.debug(String(format: "[Tracelet] SmartMotionCoordinator: GPS speed near zero (%.2f m/s) — overriding accel to false (hand tremor).", speed))
                // Through the wrapper, so the action this produces is *handled*.
                // It used to be `_ = coreCoordinator?.onAccelStateChange(false)`,
                // and the accel flag is the second half of the OR: when the speed
                // flag is already stationary, flipping it here is the transition
                // that carries the whole stop decision. `evaluate_state` returned
                // `.switchToStationaryPeriodic` and it went on the floor, then the
                // `onSpeedStateChange` below deduped to `.none` because the flag
                // it would have flipped was already false — so nothing was ever
                // handled, the engine was never told, and continuous GPS ran on a
                // parked device for the rest of the session (#409).
                overrideAction = onAccelStateChange(isMoving: false)
            case .some(let speed):
                TraceletLog.debug(String(format: "[Tracelet] SmartMotionCoordinator: GPS speed %.2f m/s is above the %.2f m/s tremor threshold — trusting accel, staying continuous.",
                                         speed, TraceletSmartMotionCoordinator.tremorSpeedThreshold))
            }
        }
        guard let action = coreCoordinator?.onSpeedStateChange(isMoving: isMoving) else { return overrideAction }
        TraceletLog.debug("[Tracelet] SmartMotionCoordinator: onSpeedStateChange -> isMoving=\(isMoving), action=\(action)")
        handleAction(action)
        // The override above already switched the engine when the speed flag was
        // the one that was stale; reporting `.none` here would hide that from a
        // caller that reads the result.
        return action == .none ? overrideAction : action
    }
    
    /// Called when the user manually forces the pace via changePace().
    public func onManualPaceChange(isMoving: Bool) {
        if let accelAction = coreCoordinator?.onAccelStateChange(isMoving: isMoving) {
            handleAction(accelAction)
        }
        if let speedAction = coreCoordinator?.onSpeedStateChange(isMoving: isMoving) {
            handleAction(speedAction)
        }
    }
    
    private func handleAction(_ action: CoordinatorAction) {
        guard let sdk = sdk else { return }

        switch action {
        case .switchToContinuous:
            recordModeSwitch("CONTINUOUS")
            sdk.switchToContinuousForce()
            sdk.motionDetector.onManualPaceChange(true)

        case .switchToStationaryGeofences:
            recordModeSwitch("STATIONARY_GEOFENCES")
            sdk.switchToStationaryGeofencesForce()
            sdk.motionDetector.onManualPaceChange(false)

        case .switchToStationaryPeriodic:
            recordModeSwitch("STATIONARY_PERIODIC")
            sdk.switchToStationaryPeriodicForce()
            sdk.motionDetector.onManualPaceChange(false)

        case .none:
            break
        }
    }

    /// Records a tracking-mode switch on the always-on lifecycle channel,
    /// naming both inputs of the OR (#334).
    ///
    /// The coordinator is a logical OR of the accelerometer and the GPS-speed
    /// machine, so a downgrade means *both* said stationary. Which one flipped
    /// last — and what the other was doing at the time — is the first question
    /// asked of any "it stopped tracking while I was moving" report, and at the
    /// shipped log levels the answer was not recorded anywhere.
    private func recordModeSwitch(_ mode: String) {
        let speedText = resolvedSpeed.map { String(format: "%.2f", $0) } ?? "unknown"
        TraceletLog.lifecycle(
            "smart-motion: switching to \(mode) — accelMoving=\(isAccelMoving) "
                + "speedMoving=\(isSpeedMoving) lastSpeed=\(speedText)m/s")
    }
}
