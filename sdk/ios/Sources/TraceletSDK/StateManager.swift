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
