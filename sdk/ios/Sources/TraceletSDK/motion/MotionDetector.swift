import CoreMotion
import Foundation

/// Motion detection engine with two operating modes:
///
/// ## Full mode (default)
/// Uses `CMMotionActivityManager` for rich activity classification (walking,
/// running, cycling, automotive, stationary) plus `CMPedometer` as a backup
/// moving-detector. Requires the Motion & Fitness permission
/// (`NSMotionUsageDescription`).
///
/// ## Accelerometer-only mode (`disableMotionActivityUpdates = true`)
/// Uses `CMMotionManager` raw accelerometer data for basic stationary↔moving
/// detection. **No permissions required.** Does not provide activity
/// classification — only fires `onMotionStateChanged(isMoving)`.
///
/// Transition flow (both modes):
/// 1. MOVING → sensor detects stillness → start stopTimeout countdown
/// 2. After stopTimeout elapses → declare STATIONARY → fire onMotionChange(false)
/// 3. In stationary: listen for shake → declare MOVING → fire onMotionChange(true)
public final class MotionDetector {
    private let configManager: ConfigManager
    private let stateManager: StateManager
    private let eventDispatcher: TraceletEventSending
    private let logger: TraceletLogger

    // Full mode (permission-required) — lazily initialized so they are
    // never allocated in accelerometer-only mode (I-L1).
    private lazy var activityManager = CMMotionActivityManager()
    private lazy var pedometer = CMPedometer()

    private let motionManager = CMMotionManager()

    /// Serial queue for pull-model accelerometer sampling and the stationary
    /// duty cycle. Replaces per-sample OperationQueue push delivery (#130).
    private let motionQueue = DispatchQueue(label: "com.tracelet.motion", qos: .utility)

    /// Pull-model sampler timer for the MOVING state (reads accelerometerData @10Hz).
    private var movingSampler: DispatchSourceTimer?

    /// Duty-cycle timer for the accelerometer-only STATIONARY state.
    private var dutyCycleTimer: DispatchSourceTimer?

    private var isRunning = false
    private var isFullModeStarted = false
    private var stopTimerWorkItem: DispatchWorkItem?
    private var currentActivity: String = "unknown"
    private var currentConfidence: Int = -1

    // NOTE: the iOS-tuned stillness/shake thresholds and sample count are NOT
    // declared here. They used to be `private static let` constants that nothing
    // referenced — the live values come from `ConfigManager.getStillThreshold()`,
    // `getShakeThreshold()` and `getStillSampleCount()`, whose fallbacks carry the
    // tuning (and whose doc comments now carry the rationale). Keeping a second,
    // unreferenced copy here meant the documented iOS defaults (0.15 g / 0.35 g /
    // 50 samples) silently disagreed with the effective ones.

    /// Accel-only STATIONARY duty cycle (#130): sample a short burst, then idle.
    /// Burst long enough to catch sustained motion; period bounds resume latency.
    private static let dutyBurstSeconds: TimeInterval = 1.5   // ~15 samples @10Hz
    private static let dutyPeriodSeconds: TimeInterval = 10.0 // worst-case resume latency

    /// Consecutive above-threshold samples required to abort an in-progress
    /// stop-timeout countdown. At 10Hz this is ~0.5s of sustained motion.
    ///
    /// A single above-threshold sample is almost always sensor noise (the
    /// stillThreshold is a low 0.15g). Aborting the countdown on one such
    /// sample resets all stillness progress, so in a slightly noisy
    /// environment the device can keep restarting the countdown and never
    /// transition to stationary — leaving continuous GPS running and draining
    /// the battery. Requiring sustained motion to abort avoids that.
    ///
    /// - SeeAlso: Android `MotionDetector.MOTION_ABORT_COUNT` (5)
    private static let motionAbortCount = 5

    private var consecutiveStillSamples = 0

    /// Consecutive above-threshold samples seen after the stop-timeout
    /// countdown has started — see [motionAbortCount].
    private var consecutiveMotionSamples = 0

    /// Called when motion state changes (isMoving).
    public var onMotionStateChanged: ((Bool) -> Void)?

    /// Emitted per accelerometer sample with the gravity-subtracted magnitude
    /// in g — feeds the 3.3.0 transport-mode classifier and impact detector.
    public var onAccelSample: ((Double) -> Void)?

    /// When `true` (crash/fall detection enabled), the accelerometer is sampled at
    /// a higher rate so short impact spikes (~50-150 ms) are actually captured
    /// instead of being missed between the 10 Hz motion-detection samples. Applies
    /// on the next start. Costs more battery, acceptable for opt-in impact detection.
    public var impactHighRate: Bool = false

    /// Accelerometer update interval — faster when impact detection is active.
    private var accelUpdateInterval: TimeInterval { impactHighRate ? 1.0 / 100.0 : 1.0 / 10.0 }

    /// Emitted per gyroscope sample with the rotation-rate magnitude in deg/s,
    /// for crash corroboration (#179). Only sampled while `gyroEnabled` is set
    /// (crash/fall detection on). Decoupled from the motion-detection state
    /// machine — gyro never affects stationary/moving decisions.
    public var onGyroSample: ((Double) -> Void)?

    /// Enables gyroscope sampling (set when crash/fall detection is active).
    public var gyroEnabled: Bool = false

    private var gyroSampler: DispatchSourceTimer?

    /// Emitted per barometer sample with the ambient pressure in hPa (millibar),
    /// for the cabin-pressure crash cue (#173). A severe collision / airbag
    /// deployment produces a brief pressure transient. Only sampled while
    /// `baroEnabled` is set (crash/fall detection on) and only on devices whose
    /// barometer is available — most importantly it never affects the
    /// motion-detection state machine.
    public var onPressureSample: ((Double) -> Void)?

    /// Enables barometer sampling (set when crash/fall detection is active).
    public var baroEnabled: Bool = false

    private lazy var altimeter = CMAltimeter()
    private var altimeterStarted = false
    /// Emitted per accelerometer sample with the raw total magnitude in g
    /// (gravity included; ~1 g rest, ~0 g free-fall) for fall detection (#180).
    public var onAccelRawSample: ((Double) -> Void)?

    /// Called when stopOnStationary fires — requests full tracking stop.
    public var onStopRequested: (() -> Void)?

    /// Called when the stopTimeout countdown begins.
    public var onStopTimeoutStarted: (() -> Void)?

    /// Called when the stopTimeout countdown is cancelled or finishes.
    public var onStopTimeoutCancelled: (() -> Void)?

    /// Called when the detected activity (type, confidence) changes. The SDK
    /// binds this to push the activity into the LocationEngine so enriched
    /// locations carry the real activity instead of a permanent "unknown" (#155).
    public var onActivityChanged: ((String, Int) -> Void)?

    /// Whether operating in accelerometer-only (permission-free) mode.
    private var isAccelerometerOnlyMode: Bool {
        configManager.getDisableMotionActivityUpdates()
    }

    public init(configManager: ConfigManager,
         stateManager: StateManager,
         eventDispatcher: TraceletEventSending,
         logger: TraceletLogger) {
        self.configManager = configManager
        self.stateManager = stateManager
        self.eventDispatcher = eventDispatcher
        self.logger = logger
    }

    // MARK: - Start / Stop

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        if gyroEnabled { startGyroMonitoring() }
        if baroEnabled { startBaroMonitoring() }
        if isAccelerometerOnlyMode {
            startAccelerometerOnlyMode()
        } else {
            startFullMode()
        }
    }

    /// Gyroscope sampler (crash corroboration). Pull-model read of rotation rate,
    /// magnitude emitted in deg/s.
    private func startGyroMonitoring() {
        guard motionManager.isGyroAvailable else { return }
        motionManager.gyroUpdateInterval = accelUpdateInterval
        if !motionManager.isGyroActive { motionManager.startGyroUpdates() }
        gyroSampler?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: motionQueue)
        timer.schedule(deadline: .now() + accelUpdateInterval, repeating: accelUpdateInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self, let r = self.motionManager.gyroData?.rotationRate else { return }
            let dps = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot() * (180.0 / Double.pi)
            self.onGyroSample?(dps)
        }
        timer.resume()
        gyroSampler = timer
    }

    private func stopGyroMonitoring() {
        gyroSampler?.cancel(); gyroSampler = nil
        motionManager.stopGyroUpdates()
    }

    /// Barometer monitor (crash cabin-pressure cue, #173). `CMAltimeter`
    /// reports relative-altitude updates whose `pressure` is in kPa; multiply
    /// by 10 to emit hPa (millibar) to match the Android `TYPE_PRESSURE` units.
    private func startBaroMonitoring() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        guard !altimeterStarted else { return }
        altimeterStarted = true
        let queue = OperationQueue()
        queue.name = "com.tracelet.baro"
        queue.qualityOfService = .utility
        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            let hpa = data.pressure.doubleValue * 10.0
            self.onPressureSample?(hpa)
        }
    }

    private func stopBaroMonitoring() {
        guard altimeterStarted else { return }
        altimeter.stopRelativeAltitudeUpdates()
        altimeterStarted = false
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if isFullModeStarted {
            // Full mode cleanup
            activityManager.stopActivityUpdates()
            pedometer.stopUpdates()
            isFullModeStarted = false
        }

        // Sampler / duty-cycle cleanup, then power down the sensor.
        stopMovingSampler()
        stopDutyCycle()
        stopGyroMonitoring()
        stopBaroMonitoring()
        motionManager.stopAccelerometerUpdates()

        // Shared cleanup
        if stopTimerWorkItem != nil {
            stopTimerWorkItem?.cancel()
            stopTimerWorkItem = nil
            onStopTimeoutCancelled?()
        }
        consecutiveStillSamples = 0
    }

    // MARK: - Full mode (CMMotionActivityManager + CMPedometer)

    private func startFullMode() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            logger.debug("Motion activity not available — falling back to accelerometer-only")
            startAccelerometerOnlyMode()
            return
        }

        isFullModeStarted = true

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.handleActivityUpdate(activity)
        }

        // Pedometer backup: step data means the user is walking
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self = self, data != nil else { return }
                if !self.stateManager.isMoving {
                    self.triggerMotionChange(isMoving: true)
                }
            }
        }

        // Accelerometer is only needed for stillness detection while MOVING.
        // While stationary, CMMotionActivityManager (above) wakes us on the next
        // moving activity, so we keep the sensor off to save power (#130).
        if motionManager.isAccelerometerAvailable, stateManager.isMoving {
            startMovingSampler()
            logger.verbose(String(format: "Accelerometer sampler started (threshold=%.3f, samples=%d)",
                  configManager.getStillThreshold(), configManager.getStillSampleCount()))
        }
    }

    // MARK: - Accelerometer-only mode (no permission required)

    /// Start permission-free motion detection using raw accelerometer data.
    ///
    /// - Moving state: monitors for sustained stillness to trigger stop-timeout.
    /// - Stationary state: monitors for shake to re-declare moving.
    ///
    /// Uses `CMMotionManager.startAccelerometerUpdates()` which does NOT require
    /// `NSMotionUsageDescription` — it accesses raw hardware sensor data only.
    private func startAccelerometerOnlyMode() {
        logger.verbose("Starting accelerometer-only mode (no Motion & Fitness permission)")

        guard motionManager.isAccelerometerAvailable else {
            logger.debug("Accelerometer not available on this device")
            return
        }

        if stateManager.isMoving {
            // Moving → continuous stillness detection.
            startMovingSampler()
        } else {
            // Stationary → duty-cycled bursts instead of continuous polling, so
            // the CPU stays idle between bursts (#130).
            startDutyCycle()
        }
    }

    // MARK: - Pull-model sampling (moving state) & duty cycle (stationary)

    /// Starts pull-model accelerometer sampling for stillness/shake detection.
    /// Reads `motionManager.accelerometerData` on `motionQueue` at 10Hz instead
    /// of pushing every sample through an OperationQueue (#130).
    private func startMovingSampler() {
        guard motionManager.isAccelerometerAvailable else { return }
        stopDutyCycle()
        consecutiveStillSamples = 0
        consecutiveMotionSamples = 0
        motionManager.accelerometerUpdateInterval = accelUpdateInterval
        if !motionManager.isAccelerometerActive {
            motionManager.startAccelerometerUpdates()   // no handler → pull model
        }
        movingSampler?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: motionQueue)
        // Pull-model read cadence governs the effective sample rate (10 Hz
        // normally, 100 Hz when impact detection is active so crash spikes land).
        timer.schedule(deadline: .now() + accelUpdateInterval, repeating: accelUpdateInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self, let data = self.motionManager.accelerometerData else { return }
            self.handleAcceleration(data.acceleration)
        }
        timer.resume()
        movingSampler = timer
    }

    private func stopMovingSampler() {
        movingSampler?.cancel()
        movingSampler = nil
    }

    /// Starts the STATIONARY duty cycle (accel-only mode): a short accelerometer
    /// burst every `dutyPeriodSeconds`, with the sensor powered down in between.
    private func startDutyCycle() {
        guard isAccelerometerOnlyMode, motionManager.isAccelerometerAvailable else { return }
        stopMovingSampler()
        dutyCycleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: motionQueue)
        timer.schedule(deadline: .now() + MotionDetector.dutyPeriodSeconds,
                       repeating: MotionDetector.dutyPeriodSeconds)
        timer.setEventHandler { [weak self] in self?.runDutyBurst() }
        timer.resume()
        dutyCycleTimer = timer
    }

    private func stopDutyCycle() {
        dutyCycleTimer?.cancel()
        dutyCycleTimer = nil
    }

    /// One duty-cycle burst: power the sensor on and sample for `dutyBurstSeconds`.
    private func runDutyBurst() {
        guard isRunning, !stateManager.isMoving else { return }
        motionManager.accelerometerUpdateInterval = accelUpdateInterval
        if !motionManager.isAccelerometerActive {
            motionManager.startAccelerometerUpdates()
        }
        sampleBurst(until: DispatchTime.now() + MotionDetector.dutyBurstSeconds)
    }

    /// Recursively reads samples on `motionQueue` until the burst window ends or
    /// motion is declared, then powers the sensor down until the next period.
    private func sampleBurst(until deadline: DispatchTime) {
        guard isRunning, !stateManager.isMoving, DispatchTime.now() < deadline else {
            // Burst over (still stationary) → idle the sensor until next period.
            if !stateManager.isMoving { motionManager.stopAccelerometerUpdates() }
            return
        }
        if let data = motionManager.accelerometerData {
            handleAcceleration(data.acceleration)   // may declare moving on shake
        }
        motionQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.sampleBurst(until: deadline)
        }
    }

    // Internal for testing
    internal func handleAcceleration(_ acc: CMAcceleration) {
        // Compute magnitude and subtract gravity (~1g). iOS CMAccelerometer
        // reports in g units, so this residual is already in g.
        let magnitude = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z) - 1.0
        onAccelSample?(abs(magnitude))
        // Raw total g (gravity included) for free-fall detection (#180): ~1 g at
        // rest, ~0 g in free-fall. CMAccelerometer reports in g already.
        onAccelRawSample?(magnitude + 1.0)

        if stateManager.isMoving {
            // Currently moving — detect sustained stillness
            if configManager.getDisableStopDetection() { return }

            if abs(magnitude) < configManager.getStillThreshold() {
                // A quiet sample — reset any motion streak building toward an
                // abort, then count toward the still threshold.
                consecutiveMotionSamples = 0
                consecutiveStillSamples += 1
                if consecutiveStillSamples == configManager.getStillSampleCount() {
                    // Sustained stillness — start stop-timeout countdown
                    logger.verbose(String(format: "Accelerometer detected sustained stillness (%d samples), starting stop-timeout",
                          consecutiveStillSamples))
                    // Keep the sampler running so we can abort if motion resumes.
                    startStopTimeoutCountdown()
                }
            } else if consecutiveStillSamples >= configManager.getStillSampleCount() {
                // The countdown is running. Only abort on *sustained* motion — a
                // single above-threshold sample is almost always sensor noise,
                // and aborting on it resets all stillness progress and can keep
                // the device stuck in the moving state.
                consecutiveMotionSamples += 1
                if consecutiveMotionSamples >= MotionDetector.motionAbortCount {
                    logger.verbose("Accelerometer sustained motion resumed — aborting stop-timeout countdown")
                    consecutiveStillSamples = 0
                    consecutiveMotionSamples = 0
                    handleMovingDetected()
                }
            } else {
                // Not yet in a countdown — a normal motion sample just breaks the
                // still streak.
                consecutiveStillSamples = 0
            }
        } else {
            // Currently stationary — detect shake/movement
            if abs(magnitude) > configManager.getShakeThreshold() {
                logger.verbose(String(format: "Accelerometer detected SHAKE (magnitude: %.2f), triggering moving", abs(magnitude)))
                stopDutyCycle()
                handleMovingDetected()
            }
        }
    }

    // MARK: - Motion permission

    /// Returns the current motion authorization status without triggering any dialog.
    ///
    /// Status codes match the Dart `AuthorizationStatus` enum:
    /// - `0` notDetermined — never asked
    /// - `3` always (authorized)
    /// - `4` deniedForever — permanently denied / restricted
    ///
    /// When `disableMotionActivityUpdates` is `true`, always returns `3` (granted)
    /// because the accelerometer-only mode requires no permission.
    public func getMotionAuthorizationStatus() -> Int {
        // Accelerometer-only mode doesn't need any permission
        if configManager.getDisableMotionActivityUpdates() {
            return 3
        }

        guard CMMotionActivityManager.isActivityAvailable() else {
            return 3 // Not available — treat as "no permission needed"
        }
        let status = CMMotionActivityManager.authorizationStatus()
        switch status {
        case .notDetermined: return 0
        case .restricted:    return 4
        case .denied:        return 4
        case .authorized:    return 3
        @unknown default:    return 0
        }
    }

    /// Triggers the OS Motion & Fitness permission dialog (if notDetermined)
    /// and returns the actual status after the user responds.
    ///
    /// When `disableMotionActivityUpdates` is `true`, returns `3` immediately
    /// without showing any dialog (accelerometer-only mode needs no permission).
    public func requestMotionPermission(callback: @escaping (Int) -> Void) {
        // Accelerometer-only mode doesn't need any permission
        if configManager.getDisableMotionActivityUpdates() {
            callback(3)
            return
        }

        let current = getMotionAuthorizationStatus()
        guard current == 0 else {
            callback(current)
            return
        }

        // Query a tiny time range to trigger the OS dialog
        let now = Date()
        let past = now.addingTimeInterval(-1)
        activityManager.queryActivityStarting(from: past, to: now, to: .main) { [weak self] _, _ in
            let newStatus = self?.getMotionAuthorizationStatus() ?? 3
            callback(newStatus)
        }
    }

    // MARK: - Sensors info

    public func getSensors() -> [String: Any] {
        return [
            "motionActivity": CMMotionActivityManager.isActivityAvailable(),
            "accelerometer": motionManager.isAccelerometerAvailable,
            "gyroscope": motionManager.isGyroAvailable,
            "magnetometer": motionManager.isMagnetometerAvailable,
            "pedometer": CMPedometer.isStepCountingAvailable(),
            "significantMotion": true,
            "platform": "ios",
        ]
    }

    // MARK: - Activity handling (full mode only)

    private func handleActivityUpdate(_ activity: CMMotionActivity) {
        // Motion state detection
        if activity.stationary {
            logger.verbose("handleActivityUpdate: detected STATIONARY activity")
            handleStationaryDetected()
        } else if activity.walking || activity.running || activity.cycling || activity.automotive {
            logger.verbose("handleActivityUpdate: detected MOVING activity (walking:\(activity.walking) running:\(activity.running) cycling:\(activity.cycling) automotive:\(activity.automotive))")
            handleMovingDetected()
        }

        let (type, confidence) = classifyActivity(activity)

        // Apply confidence filter (for the Dart event stream)
        let minConfidence = configManager.getMinimumActivityRecognitionConfidence()
        if confidence < minConfidence { return }

        // Apply activity type filter
        let triggerActivities = configManager.getTriggerActivities()
        if !triggerActivities.isEmpty {
            let allowed = triggerActivities
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if !allowed.contains(type.lowercased()) && type != "still" { return }
        }

        let prevActivity = currentActivity
        currentActivity = type
        currentConfidence = confidence

        // Propagate the activity to the LocationEngine so enriched locations
        // carry it instead of a permanent "unknown" (#155).
        onActivityChanged?(type, confidence)

        // Dispatch activity change event to Dart
        if type != prevActivity {
            eventDispatcher.sendActivityChange([
                "activity": type,
                "confidence": confidence,
            ])
        }
    }

    private func classifyActivity(_ activity: CMMotionActivity) -> (String, Int) {
        let confidence: Int
        switch activity.confidence {
        case .low: confidence = 25
        case .medium: confidence = 50
        case .high: confidence = 75
        @unknown default: confidence = -1
        }

        if activity.stationary { return ("still", confidence) }
        if activity.walking { return ("walking", confidence) }
        if activity.running { return ("running", confidence) }
        if activity.cycling { return ("on_bicycle", confidence) }
        if activity.automotive { return ("in_vehicle", confidence) }
        return ("unknown", confidence)
    }

    private func handleMovingDetected() {
        if stopTimerWorkItem != nil {
            logger.debug("handleMovingDetected: Cancelling stopTimerWorkItem due to movement")
            stopTimerWorkItem?.cancel()
            stopTimerWorkItem = nil
            onStopTimeoutCancelled?()
        }

        if !stateManager.isMoving {
            let delay = configManager.getMotionTriggerDelay()
            if delay > 0 {
                logger.debug("handleMovingDetected: starting moving delay of \(delay)s")
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
                    self?.triggerMotionChange(isMoving: true)
                }
            } else {
                logger.debug("handleMovingDetected: triggering isMoving=true immediately")
                triggerMotionChange(isMoving: true)
            }
        } else {
            // Already moving — ensure the stillness sampler is running (it may
            // have been torn down when stillness was previously detected).
            if isRunning {
                startMovingSampler()
            }
        }
    }

    private func handleStationaryDetected() {
        guard stateManager.isMoving else { return }
        guard !configManager.getDisableStopDetection() else {
            logger.debug("handleStationaryDetected: stop detection disabled in config")
            return
        }
        logger.debug("handleStationaryDetected: stationary detected, starting countdown")
        startStopTimeoutCountdown()
    }

    // MARK: - Stop timeout (shared by both modes)

    private func startStopTimeoutCountdown() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.stopTimerWorkItem != nil {
                logger.debug("startStopTimeoutCountdown: Timer is already running")
                return
            }

            let stopTimeout = self.configManager.getStopTimeout()
            let stopDetectionDelay = self.configManager.getStopDetectionDelay()
            let totalDelay = TimeInterval(stopTimeout * 60 + stopDetectionDelay)
            guard totalDelay > 0 else {
                logger.debug("startStopTimeoutCountdown: totalDelay <= 0, stopping immediately")
                self.triggerMotionChange(isMoving: false)
                return
            }

            logger.debug("startStopTimeoutCountdown: Starting timer for \(totalDelay) seconds")
            self.onStopTimeoutStarted?()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                logger.debug("startStopTimeoutCountdown: Timer FIRED! Transitioning to STATIONARY")
                self.onStopTimeoutCancelled?()
                self.triggerMotionChange(isMoving: false)
            }
            self.stopTimerWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay, execute: workItem)
        }
    }

    // MARK: - State transitions

    private func triggerMotionChange(isMoving: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.stateManager.isMoving != isMoving else { return }
            // In SMART mode the accelerometer is only one of two inputs: the
            // coordinator combines it with the GPS-speed machine and owns
            // isMoving. Writing it here would claim the transition on the
            // accelerometer's word alone, leaving the reported state disagreeing
            // with the last motionchange event whenever the coordinator decides
            // otherwise. TraceletSdk.switchTo*Force() sets it once the
            // coordinator has actually decided.
            if self.configManager.getMotionDetectionMode() != .smart {
                self.stateManager.isMoving = isMoving
            }
            self.onMotionStateChanged?(isMoving)

            if !isMoving && self.configManager.getStopOnStationary() {
                self.onStopRequested?()
                return // Full stop — no further monitoring
            }

            if !isMoving {
                // Entered STATIONARY — stop the high-rate sampler. Full mode
                // wakes via CMMotionActivityManager; accel-only mode duty-cycles.
                self.stopMovingSampler()
                guard self.isRunning else {
                    self.motionManager.stopAccelerometerUpdates()
                    return
                }
                if self.isAccelerometerOnlyMode {
                    self.startDutyCycle()
                } else {
                    self.motionManager.stopAccelerometerUpdates()
                }
                return
            }

            // Entered MOVING — (re)start the pull-model stillness sampler.
            if self.isRunning {
                self.startMovingSampler()
            }
        }
    }

    /// Re-syncs MotionDetector's sensor state when the tracking mode is manually
    /// changed (e.g. from changePace or SmartMotionCoordinator).
    public func onManualPaceChange(_ isMoving: Bool) {
        if isMoving {
            if stopTimerWorkItem != nil {
                logger.debug("onManualPaceChange(true): Cancelling stopTimerWorkItem")
                stopTimerWorkItem?.cancel()
                stopTimerWorkItem = nil
                onStopTimeoutCancelled?()
            }
            consecutiveStillSamples = 0
        }

        guard isRunning else { return }
        if isMoving {
            // Moving → continuous stillness sampler.
            startMovingSampler()
        } else {
            // Stationary → stop the sampler; accel-only mode duty-cycles, full
            // mode relies on CMMotionActivityManager.
            stopMovingSampler()
            if isAccelerometerOnlyMode {
                startDutyCycle()
            } else {
                motionManager.stopAccelerometerUpdates()
            }
        }
    }
}
