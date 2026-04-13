import Foundation

/// Tracks plugin runtime state: enabled, tracking mode, odometer, motion state, etc.
public final class StateManager {
    private let defaults: UserDefaults
    private let prefix = "com.tracelet.state."

    public var enabled: Bool {
        get { defaults.bool(forKey: prefix + "enabled") }
        set { defaults.set(newValue, forKey: prefix + "enabled") }
    }

    /// 0 = location tracking, 1 = geofences-only
    public var trackingMode: Int {
        get { defaults.integer(forKey: prefix + "trackingMode") }
        set { defaults.set(newValue, forKey: prefix + "trackingMode") }
    }

    public var schedulerEnabled: Bool {
        get { defaults.bool(forKey: prefix + "schedulerEnabled") }
        set { defaults.set(newValue, forKey: prefix + "schedulerEnabled") }
    }

    public var isMoving: Bool {
        get { defaults.bool(forKey: prefix + "isMoving") }
        set { defaults.set(newValue, forKey: prefix + "isMoving") }
    }

    public var odometer: Double {
        get { defaults.double(forKey: prefix + "odometer") }
        set { defaults.set(newValue, forKey: prefix + "odometer") }
    }

    public var didLaunchInBackground: Bool {
        get { defaults.bool(forKey: prefix + "didLaunchInBackground") }
        set { defaults.set(newValue, forKey: prefix + "didLaunchInBackground") }
    }

    public var lastLocationTime: Double {
        get { defaults.double(forKey: prefix + "lastLocationTime") }
        set { defaults.set(newValue, forKey: prefix + "lastLocationTime") }
    }

    /// Last periodic fix latitude (for odometer computation across app restarts).
    /// Returns `NaN` when no periodic fix has been recorded.
    public var lastPeriodicLatitude: Double {
        get {
            guard defaults.object(forKey: prefix + "lastPeriodicLatitude") != nil else {
                return Double.nan
            }
            return defaults.double(forKey: prefix + "lastPeriodicLatitude")
        }
        set {
            if newValue.isNaN {
                defaults.removeObject(forKey: prefix + "lastPeriodicLatitude")
            } else {
                defaults.set(newValue, forKey: prefix + "lastPeriodicLatitude")
            }
        }
    }

    /// Last periodic fix longitude (for odometer computation across app restarts).
    /// Returns `NaN` when no periodic fix has been recorded.
    public var lastPeriodicLongitude: Double {
        get {
            guard defaults.object(forKey: prefix + "lastPeriodicLongitude") != nil else {
                return Double.nan
            }
            return defaults.double(forKey: prefix + "lastPeriodicLongitude")
        }
        set {
            if newValue.isNaN {
                defaults.removeObject(forKey: prefix + "lastPeriodicLongitude")
            } else {
                defaults.set(newValue, forKey: prefix + "lastPeriodicLongitude")
            }
        }
    }

    // MARK: - Speed Motion Detection

    /// Persisted speed-motion state ("moving", "slowing", "stationary").
    public var speedMotionState: String? {
        get { defaults.string(forKey: prefix + "speedMotionState") }
        set { defaults.set(newValue, forKey: prefix + "speedMotionState") }
    }

    /// Consecutive low-speed sample count (SLOWING phase).
    public var speedLowCount: Int {
        get { defaults.integer(forKey: prefix + "speedLowCount") }
        set { defaults.set(newValue, forKey: prefix + "speedLowCount") }
    }

    /// Consecutive wake-speed sample count (STATIONARY phase).
    public var speedWakeCount: Int {
        get { defaults.integer(forKey: prefix + "speedWakeCount") }
        set { defaults.set(newValue, forKey: prefix + "speedWakeCount") }
    }

    /// Timestamp of the last speed-motion state transition.
    public var speedLastTransition: Double {
        get { defaults.double(forKey: prefix + "speedLastTransition") }
        set { defaults.set(newValue, forKey: prefix + "speedLastTransition") }
    }

    public init() {
        defaults = UserDefaults.standard
    }

    /// Adds `distance` meters to the cumulative odometer.
    public func addOdometer(distance: Double) {
        odometer += distance
    }

    public func reset() {
        enabled = false
        trackingMode = 0
        schedulerEnabled = false
        isMoving = false
        odometer = 0.0
        didLaunchInBackground = false
        lastLocationTime = 0
        lastPeriodicLatitude = .nan
        lastPeriodicLongitude = .nan
        speedMotionState = nil
        speedLowCount = 0
        speedWakeCount = 0
        speedLastTransition = 0
    }

    public func toMap(_ config: [String: Any]?) -> [String: Any] {
        return [
            "enabled": enabled,
            "trackingMode": trackingMode,
            "schedulerEnabled": schedulerEnabled,
            "isMoving": isMoving,
            "odometer": odometer,
            "didLaunchInBackground": didLaunchInBackground,
            "lastLocationTime": lastLocationTime,
            "config": config as Any,
        ]
    }
}
