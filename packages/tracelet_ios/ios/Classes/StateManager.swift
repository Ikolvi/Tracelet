import Foundation

/// Tracks plugin runtime state: enabled, tracking mode, odometer, motion state, etc.
final class StateManager {
    private let defaults: UserDefaults
    private let prefix = "com.tracelet.state."

    var enabled: Bool {
        get { defaults.bool(forKey: prefix + "enabled") }
        set { defaults.set(newValue, forKey: prefix + "enabled") }
    }

    /// 0 = location tracking, 1 = geofences-only
    var trackingMode: Int {
        get { defaults.integer(forKey: prefix + "trackingMode") }
        set { defaults.set(newValue, forKey: prefix + "trackingMode") }
    }

    var schedulerEnabled: Bool {
        get { defaults.bool(forKey: prefix + "schedulerEnabled") }
        set { defaults.set(newValue, forKey: prefix + "schedulerEnabled") }
    }

    var isMoving: Bool {
        get { defaults.bool(forKey: prefix + "isMoving") }
        set { defaults.set(newValue, forKey: prefix + "isMoving") }
    }

    var odometer: Double {
        get { defaults.double(forKey: prefix + "odometer") }
        set { defaults.set(newValue, forKey: prefix + "odometer") }
    }

    var didLaunchInBackground: Bool {
        get { defaults.bool(forKey: prefix + "didLaunchInBackground") }
        set { defaults.set(newValue, forKey: prefix + "didLaunchInBackground") }
    }

    var lastLocationTime: Double {
        get { defaults.double(forKey: prefix + "lastLocationTime") }
        set { defaults.set(newValue, forKey: prefix + "lastLocationTime") }
    }

    init() {
        defaults = UserDefaults.standard
    }

    func reset() {
        enabled = false
        trackingMode = 0
        schedulerEnabled = false
        isMoving = false
        odometer = 0.0
        didLaunchInBackground = false
        lastLocationTime = 0
    }

    func toMap(_ config: [String: Any]) -> [String: Any] {
        var map: [String: Any] = [
            "enabled": enabled,
            "trackingMode": trackingMode,
            "schedulerEnabled": schedulerEnabled,
            "isMoving": isMoving,
            "odometer": odometer,
            "didLaunchInBackground": didLaunchInBackground,
            "lastLocationTime": lastLocationTime,
        ]
        // Merge config into state for the Dart side
        for (k, v) in config {
            map[k] = v
        }
        return map
    }
}
