import Foundation

/// Delegate that the `SpeedMotionManager` calls to switch the location engine
/// between continuous and stationary modes and to emit Pigeon events.
public protocol SpeedMotionDelegate: AnyObject {
    func switchToContinuous()
    func switchToStationaryPeriodic()
    func switchToStationaryGeofences()
    func speedMotionDidStartSlowing()
    func speedMotionDidCancelSlowing()
    /// Emit a speed-motion state change event to Dart.
    func emitSpeedMotionEvent(state: Int, previousState: Int, trackingMode: Int)
}

/// GPS-speed-based motion detection state machine.
///
/// Drives MOVING -> SLOWING -> STATIONARY transitions based on
/// `CLLocation.speed` from each location fix. Designed for vehicle tracking
/// where accelerometer-based stop detection is unreliable (phone on a smooth
/// dashboard reads near-zero even at highway speed).
///
/// This class is a peer to `MotionDetector` (not a branch inside it).
/// Inputs are location fixes, not sensor streams.
///
/// ## State Machine
///
/// ```
/// MOVING (continuous) --speed<threshold--> SLOWING (continuous)
///    ^                                          |
///    |                                   delay elapsed
///    |                                          v
///    +--wakeConfirmCount fixes>=threshold-- STATIONARY (periodic or geofences)
/// ```
public final class SpeedMotionManager {

    // MARK: - State

    public enum SpeedMotionState: Int {
        case moving = 0
        case slowing = 1
        case stationary = 2

        /// Readable name for logs. The lifecycle trace is read by humans in bug
        /// reports, where a bare `rawValue: 2` means nothing without the source.
        var name: String {
            switch self {
            case .moving: return "MOVING"
            case .slowing: return "SLOWING"
            case .stationary: return "STATIONARY"
            }
        }
    }

    public private(set) var state: SpeedMotionState = .moving

    /// Consecutive low-speed samples while SLOWING.
    public private(set) var lowSpeedCount: Int = 0

    /// Consecutive wake-speed samples while STATIONARY.
    public private(set) var wakeCount: Int = 0

    /// Timestamp of the first low-speed sample that initiated the current
    /// SLOWING phase. Used for elapsed-time calculation.
    /// Consecutive above-threshold fixes required to abandon an in-progress
    /// SLOWING countdown.
    ///
    /// GPS speed is noisy while a device is physically still: a stream of
    /// `0.00 m/s` fixes can contain an isolated blip above the threshold
    /// (observed on Android: `1.56 m/s` from a phone on a desk). Treating one
    /// such fix as "moving again" cancelled the countdown and restarted the whole
    /// `speedStationaryDelay` window, so a still device could take several
    /// windows — or never — to reach STATIONARY.
    ///
    /// Requiring sustained motion mirrors `MotionDetector.motionAbortCount` for
    /// accelerometer noise. It is safe because SLOWING is still *continuous*
    /// tracking, so delaying the return to MOVING by a couple of fixes costs no
    /// location fidelity.
    ///
    /// - SeeAlso: Android `SpeedMotionManager.SPEED_ABORT_FIX_COUNT` (3)
    static let speedAbortFixCount = 3

    /// Consecutive above-threshold fixes seen while SLOWING — see
    /// [speedAbortFixCount]. Deliberately not persisted: an isolated blip must
    /// not survive a process restart.
    private var highSpeedCount = 0

    private var slowingStartTime: TimeInterval = 0

    /// Timestamp of the last `onLocation` call, for approximate inter-fix interval.
    private var lastFixTime: TimeInterval = 0

    private var isRunning = false

    // MARK: - Config

    /// Speed (m/s) below which the device is considered not moving.
    public var speedMovingThreshold: Double = 0.9

    /// Speed below which a *moving* session begins slowing down (m/s).
    ///
    /// The lower half of a hysteresis band, and the reason a walker no longer
    /// oscillates. One threshold used to govern both directions, so a pace that
    /// varied either side of it — every ordinary walk does — produced
    /// MOVING → SLOWING → STATIONARY → MOVING in a loop, and a completed
    /// countdown stopped the continuous stream while the user was still
    /// walking (pedestrian pace hysteresis, PR #399).
    ///
    /// `<= 0` derives it from ``speedMovingThreshold``.
    public var speedStationaryThreshold: Double = 0

    /// Fraction of ``speedMovingThreshold`` used when no explicit stationary
    /// threshold is configured. Mirrors the Rust core's default.
    private static let stationaryThresholdRatio: Double = 0.65

    /// The speed a moving session must drop below to start slowing.
    var effectiveStationaryThreshold: Double {
        speedStationaryThreshold > 0
            ? min(speedStationaryThreshold, speedMovingThreshold)
            : speedMovingThreshold * Self.stationaryThresholdRatio
    }

    /// Seconds of sustained low speed before transitioning to STATIONARY.
    public var speedStationaryDelay: Int = 180

    /// Stationary tracking mode: periodic or geofences.
    public var stationaryTrackingMode: StationaryTrackingMode = .periodic

    /// Interval for periodic one-shot fixes in stationary mode (seconds).
    public var stationaryPeriodicInterval: Int = 120

    /// Number of consecutive high-speed fixes required to wake from STATIONARY.
    public var speedWakeConfirmCount: Int = 1

    // MARK: - Dependencies

    public weak var delegate: SpeedMotionDelegate?

    private let stateManager: StateManager

    // MARK: - Init

    public init(stateManager: StateManager) {
        self.stateManager = stateManager
    }

    // MARK: - Lifecycle

    /// Start the speed motion manager. Loads persisted state from StateManager.
    public func start(forceMoving: Bool = false) {
        guard !isRunning else { return }
        isRunning = true

        // Validate config bounds
        if speedStationaryDelay < 0 {
            TraceletLog.warning(String(format: "[SpeedMotion] WARNING: speedStationaryDelay was %d, clamping to 0", speedStationaryDelay))
            speedStationaryDelay = 0
        } else if speedStationaryDelay == 0 {
            TraceletLog.warning("[SpeedMotion] WARNING: speedStationaryDelay is 0 — device will transition to STATIONARY immediately after a single low-speed fix")
        }
        if speedWakeConfirmCount < 1 {
            TraceletLog.warning(String(format: "[SpeedMotion] WARNING: speedWakeConfirmCount was %d, clamping to 1", speedWakeConfirmCount))
            speedWakeConfirmCount = 1
        }

        // Restore persisted state
        if let persisted = stateManager.speedMotionState,
           let restored = SpeedMotionState(rawValue: persisted) {
            state = restored
        } else {
            state = .moving
        }
        lowSpeedCount = stateManager.speedLowCount
        wakeCount = stateManager.speedWakeCount
        slowingStartTime = stateManager.speedLastTransition

        if forceMoving {
            state = .moving
            lowSpeedCount = 0
            wakeCount = 0
            highSpeedCount = 0
            stateManager.speedMotionState = state.rawValue
            stateManager.speedLowCount = 0
            stateManager.speedWakeCount = 0
            stateManager.isMoving = true
            TraceletLog.debug("[SpeedMotion] start() — forced to MOVING state")
        } else {
            // #334: a relaunched process inherits this state, and inheriting
            // STATIONARY is indistinguishable from "tracking silently stopped"
            // unless the trace says so. Once per session, so it belongs on the
            // always-on channel.
            TraceletLog.lifecycle(String(
                format: "speed-motion: restored %@ (lowSpeedCount=%d, wakeCount=%d)",
                state.name, lowSpeedCount, wakeCount))

            if state == .stationary {
                switchToStationary()
            } else if state == .slowing {
                TraceletLog.debug("[SpeedMotion] start: restored SLOWING state, restarting timer")
                delegate?.speedMotionDidStartSlowing()
                startSlowingTimer()
            }
        }
    }

    /// Stop the speed motion manager and reset runtime counters.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        TraceletLog.debug("[SpeedMotion] stop")
    }

    /// Handle manual pace changes triggered by the caller.
    public func onManualPaceChange(isMoving: Bool) {
        guard isRunning else { return }
        TraceletLog.debug("[SpeedMotion] onManualPaceChange(isMoving=\(isMoving))")
        lowSpeedCount = 0
        wakeCount = 0
        highSpeedCount = 0
        stopSlowingTimer()
        let previousState = state
        state = isMoving ? .moving : .stationary
        if previousState == .slowing { delegate?.speedMotionDidCancelSlowing() }
        commitTransition(from: previousState, because: "manual pace change")
        if isMoving {
            delegate?.switchToContinuous()
        } else {
            switchToStationary()
        }
    }

    // MARK: - Location Feed

    /// Drive state machine transitions from a location fix speed.
    ///
    /// - Parameter speed: `CLLocation.speed` in m/s. Negative values (invalid)
    ///   are treated as 0 (stationary).
    public func onLocation(speed: Double) {
        guard isRunning else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let effectiveSpeed = max(speed, 0)

        // Each handler commits its own transition through `commitTransition`.
        // A second, outer commit used to run here as well, which emitted most
        // transitions twice (#335).
        switch state {
        case .moving:
            handleMoving(speed: effectiveSpeed, now: now)
        case .slowing:
            handleSlowing(speed: effectiveSpeed, now: now)
        case .stationary:
            handleStationary(speed: effectiveSpeed, now: now)
        }

        lastFixTime = now
    }

    /// Commits a state change that has already been written to ``state``:
    /// persists it, emits exactly one event, and records it on the always-on
    /// lifecycle channel. No-op when the state did not actually change.
    ///
    /// Every edge used to hand-roll this sequence and ``onLocation`` re-ran it
    /// afterwards, so `MOVING -> SLOWING`, `SLOWING -> MOVING` and
    /// `SLOWING -> STATIONARY` each emitted twice while `STATIONARY -> MOVING`
    /// emitted once (#335). This mirrors Android's `transitionTo`.
    ///
    /// The lifecycle entry exists because this machine decides whether a moving
    /// vehicle keeps continuous tracking, and at the shipped log levels its
    /// reasoning left no trace at all — a bug report showed the downgrade with
    /// nothing to say why (#334). `reason` carries the speed the decision was
    /// made on, which is the whole story in the case that motivated it: a
    /// fabricated `speed=0.00` while the car was doing 10 m/s (#332). These
    /// fire a handful of times per trip, not per fix, which is the bar
    /// ``TraceletLogger/lifecycle(_:)`` sets for the channel.
    private func commitTransition(from previousState: SpeedMotionState, because reason: String) {
        guard state != previousState else { return }
        persistState()
        emitEvent(previous: previousState, current: state)
        TraceletLog.lifecycle(
            "speed-motion: \(previousState.name) -> \(state.name) — \(reason)")
    }

    // MARK: - State Handlers

    private var slowingTimerWorkItem: DispatchWorkItem?

    private func handleMoving(speed: Double, now: TimeInterval) {
        // The *stationary* threshold, not the moving one: leaving MOVING takes a
        // clearer signal than entering it did, which is what keeps a walk whose
        // pace varies either side of the entry threshold from flapping (pedestrian pace hysteresis, PR #399).
        if speed < effectiveStationaryThreshold {
            let previousState = state
            state = .slowing
            lowSpeedCount = 1
            wakeCount = 0
            highSpeedCount = 0
            slowingStartTime = now
            startSlowingTimer()

            delegate?.speedMotionDidStartSlowing()

            commitTransition(from: previousState, because: String(
                format: "speed=%.2f < stationary threshold=%.2f (moving threshold=%.2f)",
                speed, effectiveStationaryThreshold, speedMovingThreshold))
        }
    }

    private func startSlowingTimer() {
        stopSlowingTimer()
        let delay = TimeInterval(speedStationaryDelay)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.state == .slowing {
                    let previousState = self.state
                    self.state = .stationary
                    self.wakeCount = 0
                    self.lowSpeedCount = 0
                    self.delegate?.speedMotionDidCancelSlowing()
                    self.switchToStationary()
                    self.commitTransition(
                        from: previousState,
                        because: "SLOWING countdown of \(self.speedStationaryDelay)s expired")
                }
            }
            self.slowingTimerWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func stopSlowingTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.slowingTimerWorkItem?.cancel()
            self?.slowingTimerWorkItem = nil
        }
    }

    private func switchToStationary() {
        if stationaryTrackingMode == .geofences {
            delegate?.switchToStationaryGeofences()
        } else {
            delegate?.switchToStationaryPeriodic()
        }
    }

    private func handleSlowing(speed: Double, now: TimeInterval) {
        if speed >= speedMovingThreshold {
            highSpeedCount += 1
            if highSpeedCount < SpeedMotionManager.speedAbortFixCount {
                // Almost certainly GPS noise on a still device. Keep the countdown
                // running: cancelling it restarts the whole speedStationaryDelay
                // window and can postpone STATIONARY indefinitely.
                TraceletLog.debug(String(format: "[SpeedMotion] SLOWING: ignoring high-speed fix %d/%d (speed=%.2f >= threshold=%.2f) — countdown continues",
                      highSpeedCount, SpeedMotionManager.speedAbortFixCount, speed, speedMovingThreshold))
                return
            }
            // Back to moving
            let previousState = state
            state = .moving
            let abortCount = SpeedMotionManager.speedAbortFixCount
            lowSpeedCount = 0
            highSpeedCount = 0
            stopSlowingTimer()

            delegate?.speedMotionDidCancelSlowing()

            commitTransition(from: previousState, because: String(
                format: "sustained speed=%.2f >= threshold=%.2f for %d fixes",
                speed, speedMovingThreshold, abortCount))
            return
        }

        // Still slow — any partial high-speed streak was noise.
        highSpeedCount = 0
        lowSpeedCount += 1
        let elapsed = now - slowingStartTime
        if elapsed >= Double(speedStationaryDelay) {
            let previousState = state
            state = .stationary
            wakeCount = 0
            stopSlowingTimer()

            delegate?.speedMotionDidCancelSlowing()
            switchToStationary()

            commitTransition(from: previousState, because: String(
                format: "speed=%.2f, elapsed=%.0fs >= delay=%ds, lowCount=%d",
                speed, elapsed, speedStationaryDelay, lowSpeedCount))
        }
    }

    private func handleStationary(speed: Double, now: TimeInterval) {
        if speed >= speedMovingThreshold {
            wakeCount += 1
            TraceletLog.debug(String(format: "[SpeedMotion] STATIONARY: wake fix (speed=%.2f, wakeCount=%d/%d)",
                  speed, wakeCount, speedWakeConfirmCount))
            if wakeCount >= speedWakeConfirmCount {
                let previousState = state
                let confirmCount = speedWakeConfirmCount
                state = .moving
                lowSpeedCount = 0
                wakeCount = 0
                delegate?.switchToContinuous()
                commitTransition(from: previousState, because: String(
                    format: "woke on speed=%.2f >= threshold=%.2f (%d confirming fixes)",
                    speed, speedMovingThreshold, confirmCount))
            }
        } else {
            // Reset wake count on low-speed fix
            if wakeCount > 0 {
                TraceletLog.debug(String(format: "[SpeedMotion] STATIONARY: reset wakeCount (speed=%.2f < threshold)",
                      speed))
            }
            wakeCount = 0
        }
    }

    // MARK: - Persistence

    private func persistState() {
        stateManager.speedMotionState = state.rawValue
        stateManager.speedLowCount = lowSpeedCount
        stateManager.speedWakeCount = wakeCount
        stateManager.speedLastTransition = slowingStartTime
    }

    // MARK: - Event Emission

    private func emitEvent(previous: SpeedMotionState, current: SpeedMotionState) {
        let trackingMode: Int = (current == .stationary)
            ? (stationaryTrackingMode == .geofences ? 1 : 2) // geofences=1, periodic=2
            : 0 // continuous=0
        
        delegate?.emitSpeedMotionEvent(
            state: current.rawValue,
            previousState: previous.rawValue,
            trackingMode: trackingMode
        )
    }

    // MARK: - Config Loading

    /// Convenience to load config from a MotionConfig dictionary.
    public func loadConfig(from motionConfig: [String: Any]) {
        if let threshold = motionConfig["speedMovingThreshold"] as? Double {
            speedMovingThreshold = threshold
        }
        if let threshold = motionConfig["speedStationaryThreshold"] as? Double {
            speedStationaryThreshold = threshold
        }
        if let delay = motionConfig["speedStationaryDelay"] as? Int {
            speedStationaryDelay = delay
        }
        if let val = motionConfig["stationaryTrackingMode"] as? Int, let mode = StationaryTrackingMode(rawValue: val) {
            stationaryTrackingMode = mode
        }
        if let interval = motionConfig["stationaryPeriodicInterval"] as? Int {
            stationaryPeriodicInterval = interval
        }
        if let count = motionConfig["speedWakeConfirmCount"] as? Int {
            speedWakeConfirmCount = count
        }
    }
}
