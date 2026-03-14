import UIKit

/// Battery level and charging state utilities.
///
/// `isBatteryMonitoringEnabled` is set once via `initialize()` rather than
/// on every query, avoiding repeated KVO observer churn.
public final class BatteryUtils {
    /// Must be called once (on main thread) during plugin setup.
    public static func initialize() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    public static func getBatteryLevel() -> Float {
        return UIDevice.current.batteryLevel
    }

    public static func isCharging() -> Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    public static func getBatteryInfo() -> [String: Any] {
        return [
            "level": getBatteryLevel(),
            "is_charging": isCharging(),
        ]
    }
}
