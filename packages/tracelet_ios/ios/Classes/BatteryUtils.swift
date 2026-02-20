import UIKit

/// Battery level and charging state utilities.
final class BatteryUtils {
    static func getBatteryLevel() -> Float {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
    }

    static func isCharging() -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    static func getBatteryInfo() -> [String: Any] {
        return [
            "level": getBatteryLevel(),
            "is_charging": isCharging(),
        ]
    }
}
