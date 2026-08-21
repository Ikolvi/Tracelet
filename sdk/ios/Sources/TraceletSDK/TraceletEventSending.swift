import Foundation

/// Abstraction for dispatching Tracelet events from engine code to the
/// host framework (Flutter EventChannel, React Native NativeEventEmitter, etc.).
///
/// All method implementations must be safe to call from any thread —
/// the implementation is responsible for marshalling to the correct thread.
public protocol TraceletEventSending: AnyObject {
    func sendLocation(_ params: [String: Any])
    func sendSpeedMotionEvent(_ params: [String: Any])
    func sendMotionChange(_ params: [String: Any])
    func sendActivityChange(_ data: [String: Any])
    func sendProviderChange(_ data: [String: Any])
    func sendGeofence(_ data: [String: Any])
    func sendGeofencesChange(_ data: [String: Any])
    func sendHeartbeat(_ data: [String: Any])
    func sendHttp(_ data: [String: Any])
    func sendSchedule(_ data: [String: Any])
    func sendPowerSaveChange(_ isPowerSave: Bool)
    func sendConnectivityChange(_ data: [String: Any])
    func sendEnabledChange(_ enabled: Bool)
    func sendNotificationAction(_ data: [String: Any])
    func sendAuthorization(_ data: [String: Any])
    func sendWatchPosition(_ data: [String: Any])
    func sendRemoteConfigEvent(_ data: [String: Any])
    func sendTrip(_ data: [String: Any])

    /// Emitted when a trip begins, carrying the id every record written during
    /// it will be stamped with (#402).
    func sendTripStart(_ data: [String: Any])
    func sendBudgetAdjustment(_ data: [String: Any])
    func sendDrivingEvent(_ data: [String: Any])
    func sendImpact(_ data: [String: Any])
    func sendModeChange(_ data: [String: Any])
    /// ML crash-model lifecycle status (download/load), so apps can show the user
    /// that the model is being prepared. `data` carries `status` (`unlocking`,
    /// `downloading`, `decrypting`, `ready`, `failed`, `disabled`) and an optional
    /// `detail` string.
    func sendCrashModelStatus(_ data: [String: Any])
    func hasListener(eventName: String) -> Bool
}

public extension TraceletEventSending {
    /// Default no-op for hosts that don't surface crash-model status.
    func sendCrashModelStatus(_ data: [String: Any]) {}
}

/// Defaults for surface added after the protocol shipped, so an implementation
/// outside the SDK keeps compiling across the addition (#402).
extension TraceletEventSending {
    func sendTripStart(_ data: [String: Any]) {}
}
