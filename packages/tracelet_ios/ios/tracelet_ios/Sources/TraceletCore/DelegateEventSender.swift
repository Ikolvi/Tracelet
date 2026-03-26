import Foundation

/// Concrete ``TraceletEventSending`` implementation that forwards all events
/// to a ``TraceletDelegate`` on the main thread.
///
/// This is the standalone-SDK equivalent of Flutter's EventChannel-based
/// event sender. Framework bridges (Flutter, React Native) provide their
/// own ``TraceletEventSending`` implementation instead.
final class DelegateEventSender: TraceletEventSending {

    /// The SDK instance passed to every delegate callback.
    weak var sdk: TraceletSdk?

    /// The delegate that receives all events.
    weak var delegate: TraceletDelegate?

    /// Optional headless dispatcher for background event delivery.
    var headlessDispatcher: HeadlessDispatching?

    // MARK: - TraceletEventSending

    func sendLocation(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didUpdateLocation: data) }
    }

    func sendMotionChange(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didChangeMotion: data) }
    }

    func sendActivityChange(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didChangeActivity: data) }
    }

    func sendProviderChange(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didChangeProvider: data) }
    }

    func sendGeofence(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didTriggerGeofence: data) }
    }

    func sendGeofencesChange(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didChangeGeofences: data) }
    }

    func sendHeartbeat(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didHeartbeat: data) }
    }

    func sendHttp(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didSyncHttp: data) }
    }

    func sendSchedule(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didSchedule: data) }
    }

    func sendPowerSaveChange(_ isPowerSave: Bool) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didChangePowerSave: isPowerSave) }
    }

    func sendConnectivityChange(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didChangeConnectivity: data) }
    }

    func sendEnabledChange(_ enabled: Bool) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didChangeEnabled: enabled) }
    }

    func sendNotificationAction(_ data: [String: Any]) {
        // No-op on iOS — notification actions are Android-only.
    }

    func sendAuthorization(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didAuthorize: data) }
    }

    func sendWatchPosition(_ data: [String: Any]) {
        // Watch position events are delivered via getCurrentPosition callbacks,
        // not through the delegate pattern in standalone SDK mode.
    }

    func sendRemoteConfigEvent(_ data: [String: Any]) {
        // Remote config events — delegate extension point for future use.
    }

    func hasListener(eventName: String) -> Bool {
        return delegate != nil || headlessDispatcher?.isRegistered() == true
    }

    // MARK: - Private

    private func dispatch(_ block: @escaping (TraceletSdk, TraceletDelegate) -> Void) {
        guard let sdk = sdk, let delegate = delegate else {
            // If no delegate, try headless dispatcher
            return
        }
        if Thread.isMainThread {
            block(sdk, delegate)
        } else {
            DispatchQueue.main.async {
                block(sdk, delegate)
            }
        }
    }
}
