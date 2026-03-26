import Foundation

/// Delegate protocol for receiving Tracelet SDK events.
///
/// Implement this protocol to receive location updates, motion changes,
/// geofence events, and other tracking events from the SDK.
///
/// All callbacks are invoked on the main thread.
public protocol TraceletDelegate: AnyObject {

    /// Called when a new location is received.
    func tracelet(_ sdk: TraceletSdk, didUpdateLocation location: [String: Any])

    /// Called when the motion state changes (moving/stationary).
    func tracelet(_ sdk: TraceletSdk, didChangeMotion data: [String: Any])

    /// Called when a new activity is detected.
    func tracelet(_ sdk: TraceletSdk, didChangeActivity data: [String: Any])

    /// Called when the location provider state changes.
    func tracelet(_ sdk: TraceletSdk, didChangeProvider data: [String: Any])

    /// Called when a geofence event occurs (enter/exit/dwell).
    func tracelet(_ sdk: TraceletSdk, didTriggerGeofence data: [String: Any])

    /// Called when the set of monitored geofences changes.
    func tracelet(_ sdk: TraceletSdk, didChangeGeofences data: [String: Any])

    /// Called on each heartbeat interval.
    func tracelet(_ sdk: TraceletSdk, didHeartbeat data: [String: Any])

    /// Called when an HTTP sync event occurs.
    func tracelet(_ sdk: TraceletSdk, didSyncHttp data: [String: Any])

    /// Called when a schedule event fires.
    func tracelet(_ sdk: TraceletSdk, didSchedule data: [String: Any])

    /// Called when power-save mode changes.
    func tracelet(_ sdk: TraceletSdk, didChangePowerSave isPowerSave: Bool)

    /// Called when connectivity state changes.
    func tracelet(_ sdk: TraceletSdk, didChangeConnectivity data: [String: Any])

    /// Called when tracking is enabled or disabled.
    func tracelet(_ sdk: TraceletSdk, didChangeEnabled enabled: Bool)

    /// Called when an authorization event occurs (HTTP 401 refresh).
    func tracelet(_ sdk: TraceletSdk, didAuthorize data: [String: Any])

    /// Called when a trip ends.
    func tracelet(_ sdk: TraceletSdk, didEndTrip data: [String: Any])

    /// Called when the battery budget engine adjusts parameters.
    func tracelet(_ sdk: TraceletSdk, didAdjustBudget data: [String: Any])
}

/// Default empty implementations so delegates only need to implement
/// the callbacks they care about.
public extension TraceletDelegate {
    func tracelet(_ sdk: TraceletSdk, didUpdateLocation location: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeMotion data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeActivity data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeProvider data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didTriggerGeofence data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeGeofences data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didHeartbeat data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didSyncHttp data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didSchedule data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangePowerSave isPowerSave: Bool) {}
    func tracelet(_ sdk: TraceletSdk, didChangeConnectivity data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didChangeEnabled enabled: Bool) {}
    func tracelet(_ sdk: TraceletSdk, didAuthorize data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didEndTrip data: [String: Any]) {}
    func tracelet(_ sdk: TraceletSdk, didAdjustBudget data: [String: Any]) {}
}
