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
    public func syncCurrentMode() {
        guard let stateManager = sdk?.stateManager else { return }

        let useGeofences = sdk?.configManager?.getStationaryTrackingMode() == .geofences
        coreCoordinator?.setCurrentMode(
            mode: TraceletSmartMotionCoordinator.coordinatorMode(
                sessionMode: stateManager.trackingMode,
                isMoving: stateManager.isMoving,
                useGeofencesWhenStationary: useGeofences))
        coreCoordinator?.setUseGeofencesWhenStationary(useGeofences: useGeofences)
    }

    /// The posture the coordinator should be holding, given the session mode and
    /// the committed pace. Pure so the mapping in #344 can be pinned directly.
    static func coordinatorMode(
        sessionMode: TraceletTrackingMode,
        isMoving: Bool,
        useGeofencesWhenStationary: Bool
    ) -> TrackingMode {
        let stationary: TrackingMode = useGeofencesWhenStationary ? .stationaryGeofences : .stationaryPeriodic
        switch sessionMode {
        case .continuous:
            return isMoving ? .continuous : stationary
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

    public func onSpeedStateChange(isMoving: Bool) {
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
                _ = coreCoordinator?.onAccelStateChange(isMoving: false)
            case .some(let speed):
                TraceletLog.debug(String(format: "[Tracelet] SmartMotionCoordinator: GPS speed %.2f m/s is above the %.2f m/s tremor threshold — trusting accel, staying continuous.",
                                         speed, TraceletSmartMotionCoordinator.tremorSpeedThreshold))
            }
        }
        guard let action = coreCoordinator?.onSpeedStateChange(isMoving: isMoving) else { return }
        TraceletLog.debug("[Tracelet] SmartMotionCoordinator: onSpeedStateChange -> isMoving=\(isMoving), action=\(action)")
        handleAction(action)
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
