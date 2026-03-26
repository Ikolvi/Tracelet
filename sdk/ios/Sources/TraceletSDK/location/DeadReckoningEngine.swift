import CoreMotion
import Foundation

/// Inertial dead reckoning engine for GPS-denied environments.
///
/// Uses accelerometer + magnetometer (via `CMDeviceMotion`) to estimate
/// position when GPS is lost. Implements Pedestrian Dead Reckoning (PDR)
/// with step detection and heading estimation. For vehicle/cycling modes,
/// uses direct acceleration integration with a high-pass filter.
///
/// Accuracy degrades linearly with elapsed time:
/// - Pedestrian: base 5m + 1m/s
/// - Vehicle: base 10m + 3m/s
///
/// Lifecycle:
/// 1. ``activate(lat:lng:altitude:heading:activity:)`` — start sensors
/// 2. Engine emits estimated positions via ``onEstimatedLocation`` every ~1s
/// 3. ``deactivate()`` — stop sensors, clean up
/// 4. Auto-stops after configured max duration
public final class DeadReckoningEngine {
    /// Meters per degree of latitude (approximate).
    private static let metersPerDegLat: Double = 111_139.0

    /// Minimum acceleration peak-to-trough for a valid step (g-force).
    private static let stepThreshold: Double = 0.2

    /// Minimum time between steps — prevents double-counting.
    private static let minStepInterval: TimeInterval = 0.25

    /// Maximum time between steps — if exceeded, reset peak detector.
    private static let maxStepInterval: TimeInterval = 2.0

    /// High-pass filter coefficient for vehicle acceleration integration.
    private static let highPassAlpha: Double = 0.8

    /// Location emission interval.
    private static let emitInterval: TimeInterval = 1.0

    // State
    public private(set) var isActive = false
    private var activationDate: Date?

    // Position
    private var currentLat: Double = 0
    private var currentLng: Double = 0
    private var currentAltitude: Double = 0
    private var currentHeading: Double = 0 // degrees from true north

    // Step detection (PDR)
    private var lastAccelMagnitude: Double = 0
    private var accelPeak: Double = 0
    private var accelTrough: Double = .greatestFiniteMagnitude
    private var lastStepDate: Date?
    private var stepCount: Int = 0
    private var isAscending = false

    // Vehicle mode integration
    private var velocityX: Double = 0
    private var velocityY: Double = 0
    private var lastSensorTime: TimeInterval = 0
    private var filteredAccelX: Double = 0
    private var filteredAccelY: Double = 0

    // Sensors
    private let motionManager = CMMotionManager()
    private let sensorQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.tracelet.deadreckoning"
        q.qualityOfService = .userInitiated
        return q
    }()

    // Timers
    private var emitTimer: Timer?
    private var maxDurationTimer: Timer?

    // Config
    private let configManager: ConfigManager

    // Activity type for algorithm selection
    private var activityType: String = "unknown"

    /// Callback: emits estimated location data.
    public var onEstimatedLocation: (([String: Any]) -> Void)?

    /// Callback: notifies when dead reckoning auto-stops (max duration).
    public var onDeactivated: (() -> Void)?

    public init(configManager: ConfigManager) {
        self.configManager = configManager
        self.activationDate = nil
        self.lastStepDate = nil
    }

    // MARK: - Public API

    /// Activate dead reckoning from the last known GPS position.
    public func activate(
        lat: Double,
        lng: Double,
        altitude: Double,
        heading: Double,
        activity: String
    ) {
        guard !isActive else { return }

        currentLat = lat
        currentLng = lng
        currentAltitude = altitude
        currentHeading = heading >= 0 ? heading : 0
        activityType = activity
        activationDate = Date()
        isActive = true

        // Reset state
        stepCount = 0
        lastStepDate = nil
        accelPeak = 0
        accelTrough = .greatestFiniteMagnitude
        isAscending = false
        velocityX = 0
        velocityY = 0
        lastSensorTime = 0
        filteredAccelX = 0
        filteredAccelY = 0
        lastAccelMagnitude = 0

        NSLog("[Tracelet] DeadReckoning activated at (\(lat), \(lng)), heading=\(heading), activity=\(activity)")

        startSensors()
        startEmitTimer()
        startMaxDurationTimer()
    }

    /// Deactivate dead reckoning and release all sensor resources.
    public func deactivate() {
        guard isActive else { return }
        isActive = false

        stopSensors()
        stopEmitTimer()
        stopMaxDurationTimer()

        NSLog("[Tracelet] DeadReckoning deactivated after \(getElapsedSeconds())s, \(stepCount) steps")
    }

    /// Returns the current DR state, or nil if not active.
    public func getState() -> [String: Any]? {
        guard isActive else { return nil }
        let elapsed = getElapsedSeconds()
        return [
            "active": true,
            "elapsed": elapsed,
            "estimatedAccuracy": computeAccuracy(elapsed),
            "latitude": currentLat,
            "longitude": currentLng,
            "heading": currentHeading,
            "stepCount": stepCount,
            "activityType": activityType,
        ]
    }

    // MARK: - Sensor Management

    private func startSensors() {
        // Use CMDeviceMotion when available (fused accelerometer + gyroscope + magnetometer)
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 50.0 // 50 Hz
            motionManager.startDeviceMotionUpdates(
                using: .xMagneticNorthZVertical,
                to: sensorQueue
            ) { [weak self] motion, error in
                guard let self = self, let motion = motion, error == nil else { return }
                self.processDeviceMotion(motion)
            }
        } else if motionManager.isAccelerometerAvailable {
            // Fallback: raw accelerometer only (no heading)
            motionManager.accelerometerUpdateInterval = 1.0 / 50.0
            motionManager.startAccelerometerUpdates(to: sensorQueue) { [weak self] data, error in
                guard let self = self, let data = data, error == nil else { return }
                let acc = data.acceleration
                let magnitude = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z) - 1.0
                self.processStepDetection(abs(magnitude))
            }
        }
    }

    private func stopSensors() {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
    }

    // MARK: - Device Motion Processing

    private func processDeviceMotion(_ motion: CMDeviceMotion) {
        guard isActive else { return }

        // Update heading from device motion attitude
        // heading = yaw angle in degrees (0 = magnetic north)
        var heading = motion.attitude.yaw * 180.0 / .pi
        if heading < 0 { heading += 360.0 }
        currentHeading = heading

        // User acceleration (gravity-subtracted)
        let ax = motion.userAcceleration.x
        let ay = motion.userAcceleration.y
        let az = motion.userAcceleration.z
        let magnitude = sqrt(ax * ax + ay * ay + az * az)

        if isVehicleMode() {
            processVehicleAcceleration(ax: ax, ay: ay, timestamp: motion.timestamp)
        } else {
            processStepDetection(magnitude)
        }
    }

    // MARK: - Pedestrian Dead Reckoning (PDR)

    /// Step detection via peak-trough analysis on acceleration magnitude.
    /// Uses Weinberg step length estimation.
    private func processStepDetection(_ magnitude: Double) {
        let now = Date()

        // Track peaks and troughs
        if magnitude > lastAccelMagnitude {
            if !isAscending && lastAccelMagnitude < accelTrough {
                accelTrough = lastAccelMagnitude
            }
            isAscending = true
        } else {
            if isAscending && lastAccelMagnitude > accelPeak {
                accelPeak = lastAccelMagnitude
            }
            isAscending = false

            // Check for step: peak-to-trough exceeds threshold
            let diff = accelPeak - accelTrough
            if diff > Self.stepThreshold {
                let timeSinceLastStep = lastStepDate.map { now.timeIntervalSince($0) } ?? Self.minStepInterval
                if timeSinceLastStep >= Self.minStepInterval {
                    let stepLength = estimateStepLength(diff)
                    advancePosition(stepLength)
                    stepCount += 1
                    lastStepDate = now

                    accelPeak = 0
                    accelTrough = .greatestFiniteMagnitude
                }
            }
        }

        // Reset peak detector if no step for too long
        if let lastStep = lastStepDate, now.timeIntervalSince(lastStep) > Self.maxStepInterval {
            accelPeak = 0
            accelTrough = .greatestFiniteMagnitude
        }

        lastAccelMagnitude = magnitude
    }

    /// Estimate step length using the Weinberg formula.
    private func estimateStepLength(_ peakToDiff: Double) -> Double {
        return 0.7 * pow(peakToDiff, 0.25)
    }

    // MARK: - Vehicle Mode

    private func processVehicleAcceleration(ax: Double, ay: Double, timestamp: TimeInterval) {
        if lastSensorTime == 0 {
            lastSensorTime = timestamp
            return
        }

        let dt = timestamp - lastSensorTime
        lastSensorTime = timestamp

        guard dt > 0, dt < 0.5 else { return }

        // High-pass filter
        filteredAccelX = Self.highPassAlpha * (filteredAccelX + ax)
        filteredAccelY = Self.highPassAlpha * (filteredAccelY + ay)

        // Integrate acceleration → velocity
        velocityX += filteredAccelX * dt
        velocityY += filteredAccelY * dt

        // Velocity damping
        velocityX *= 0.98
        velocityY *= 0.98

        // Integrate velocity → displacement
        let dx = velocityX * dt
        let dy = velocityY * dt

        // Transform to world frame using heading
        let headingRad = currentHeading * .pi / 180.0
        let worldDx = dx * cos(headingRad) - dy * sin(headingRad)
        let worldDy = dx * sin(headingRad) + dy * cos(headingRad)

        let metersPerDegLng = Self.metersPerDegLat * cos(currentLat * .pi / 180.0)
        currentLat += worldDy / Self.metersPerDegLat
        currentLng += worldDx / metersPerDegLng
    }

    // MARK: - Position Advancement

    private func advancePosition(_ stepLength: Double) {
        let headingRad = currentHeading * .pi / 180.0
        let metersPerDegLng = Self.metersPerDegLat * cos(currentLat * .pi / 180.0)

        currentLat += (stepLength * cos(headingRad)) / Self.metersPerDegLat
        currentLng += (stepLength * sin(headingRad)) / metersPerDegLng
    }

    // MARK: - Location Emission

    private func startEmitTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.emitTimer = Timer.scheduledTimer(
                withTimeInterval: Self.emitInterval,
                repeats: true
            ) { [weak self] _ in
                self?.emitLocation()
            }
        }
    }

    private func stopEmitTimer() {
        emitTimer?.invalidate()
        emitTimer = nil
    }

    private func emitLocation() {
        guard isActive else { return }
        let elapsed = getElapsedSeconds()
        let accuracy = computeAccuracy(elapsed)

        let location: [String: Any] = [
            "latitude": currentLat,
            "longitude": currentLng,
            "altitude": currentAltitude,
            "heading": currentHeading,
            "accuracy": accuracy,
            "speed": estimateSpeed(),
            "elapsed": elapsed,
            "isDeadReckoned": true,
        ]

        onEstimatedLocation?(location)
    }

    // MARK: - Max Duration

    private func startMaxDurationTimer() {
        let maxDuration = TimeInterval(configManager.getDeadReckoningMaxDuration())
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.maxDurationTimer = Timer.scheduledTimer(
                withTimeInterval: maxDuration,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                NSLog("[Tracelet] DeadReckoning max duration reached (\(Int(maxDuration))s)")
                self.deactivate()
                self.onDeactivated?()
            }
        }
    }

    private func stopMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
    }

    // MARK: - Helpers

    private func getElapsedSeconds() -> Int {
        guard let activation = activationDate else { return 0 }
        return Int(Date().timeIntervalSince(activation))
    }

    private func computeAccuracy(_ elapsedSeconds: Int) -> Double {
        if isVehicleMode() {
            return 10.0 + Double(elapsedSeconds) * 3.0
        }
        return 5.0 + Double(elapsedSeconds) * 1.0
    }

    private func estimateSpeed() -> Double {
        if isVehicleMode() {
            return sqrt(velocityX * velocityX + velocityY * velocityY)
        }
        guard let lastStep = lastStepDate else { return 0 }
        let timeSinceLastStep = Date().timeIntervalSince(lastStep)
        if timeSinceLastStep < Self.maxStepInterval {
            return 0.7 * pow(Self.stepThreshold, 0.25) * 1.0 / max(timeSinceLastStep, Self.minStepInterval)
        }
        return 0
    }

    private func isVehicleMode() -> Bool {
        return activityType == "in_vehicle" || activityType == "on_bicycle"
    }
}
