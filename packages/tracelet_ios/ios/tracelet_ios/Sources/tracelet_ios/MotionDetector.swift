import CoreMotion
import Foundation

/// Motion detection using CMMotionActivityManager and CMPedometer.
///
/// Detects transitions between stationary ↔ moving states. Uses
/// a configurable stopTimeout before declaring stationary state.
final class MotionDetector {
    private let configManager: ConfigManager
    private let stateManager: StateManager
    private let eventDispatcher: EventDispatcher

    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    private var isRunning = false
    private var stopTimer: Timer?
    private var currentActivity: String = "unknown"
    private var currentConfidence: Int = -1

    /// Called when motion state changes (isMoving).
    var onMotionStateChanged: ((Bool) -> Void)?

    init(configManager: ConfigManager,
         stateManager: StateManager,
         eventDispatcher: EventDispatcher) {
        self.configManager = configManager
        self.stateManager = stateManager
        self.eventDispatcher = eventDispatcher
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        guard CMMotionActivityManager.isActivityAvailable() else {
            NSLog("[Tracelet] Motion activity not available on this device")
            return
        }
        guard !configManager.getDisableMotionActivityUpdates() else { return }

        isRunning = true

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.handleActivityUpdate(activity)
        }

        // Also start pedometer for step-based motion detection backup
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self = self, data != nil else { return }
                // Pedometer data arriving means the user is walking
                if !self.stateManager.isMoving {
                    self.triggerMotionChange(isMoving: true)
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        stopTimer?.invalidate()
        stopTimer = nil
    }

    // MARK: - Sensors info

    func getSensors() -> [String: Any] {
        return [
            "motionActivity": CMMotionActivityManager.isActivityAvailable(),
            "accelerometer": true,
            "gyroscope": CMMotionManager().isGyroAvailable,
            "magnetometer": CMMotionManager().isMagnetometerAvailable,
            "pedometer": CMPedometer.isStepCountingAvailable(),
            "significantMotion": true,
            "platform": "ios",
        ]
    }

    // MARK: - Activity handling

    private func handleActivityUpdate(_ activity: CMMotionActivity) {
        let (type, confidence) = classifyActivity(activity)

        let prevActivity = currentActivity
        currentActivity = type
        currentConfidence = confidence

        // Dispatch activityChange event
        let activityData: [String: Any] = [
            "activity": type,
            "confidence": confidence,
        ]

        if type != prevActivity {
            eventDispatcher.sendActivityChange(activityData)
        }

        // Motion state detection
        if activity.stationary {
            handleStationaryDetected()
        } else if activity.walking || activity.running || activity.cycling || activity.automotive {
            handleMovingDetected()
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
        guard !configManager.getDisableStopDetection() else { return }

        // Cancel any pending stop timer
        stopTimer?.invalidate()
        stopTimer = nil

        if !stateManager.isMoving {
            let delay = configManager.getMotionTriggerDelay()
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
                    self?.triggerMotionChange(isMoving: true)
                }
            } else {
                triggerMotionChange(isMoving: true)
            }
        }
    }

    private func handleStationaryDetected() {
        guard stateManager.isMoving else { return }
        guard !configManager.getDisableStopDetection() else { return }

        // Start stop-timeout countdown
        let stopTimeout = configManager.getStopTimeout()
        guard stopTimeout > 0 else {
            triggerMotionChange(isMoving: false)
            return
        }

        if stopTimer == nil {
            stopTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(stopTimeout * 60),
                repeats: false
            ) { [weak self] _ in
                self?.triggerMotionChange(isMoving: false)
            }
        }
    }

    private func triggerMotionChange(isMoving: Bool) {
        guard stateManager.isMoving != isMoving else { return }
        stateManager.isMoving = isMoving
        onMotionStateChanged?(isMoving)
    }
}
