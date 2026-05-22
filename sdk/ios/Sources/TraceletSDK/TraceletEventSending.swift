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
    func sendBudgetAdjustment(_ data: [String: Any])
    func hasListener(eventName: String) -> Bool
}
