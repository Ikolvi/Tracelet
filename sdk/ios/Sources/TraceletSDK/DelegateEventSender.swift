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
    /// When set, any events buffered while the delegate was nil are flushed.
    weak var delegate: TraceletDelegate? {
        didSet { flushPendingEvents() }
    }

    /// Optional headless dispatcher for background event delivery.
    var headlessDispatcher: HeadlessDispatching?

    /// Events buffered while no delegate was registered (e.g., cold launch
    /// from terminated state before the host app sets its delegate).
    private var pendingEvents: [(TraceletSdk, TraceletDelegate) -> Void] = []

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

    func sendTrip(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didEndTrip: data) }
    }

    func sendBudgetAdjustment(_ data: [String: Any]) {
        dispatch { sdk, delegate in delegate.tracelet(sdk, didAdjustBudget: data) }
    }

    func hasListener(eventName: String) -> Bool {
        return delegate != nil || headlessDispatcher?.isRegistered() == true
    }

    // MARK: - Private

    private func dispatch(_ block: @escaping (TraceletSdk, TraceletDelegate) -> Void) {
        guard let sdk = sdk else { return }

        if let delegate = delegate {
            if Thread.isMainThread {
                block(sdk, delegate)
            } else {
                DispatchQueue.main.async {
                    block(sdk, delegate)
                }
            }
            return
        }

        // Buffer event until delegate becomes available (cold-launch scenario).
        pendingEvents.append(block)
    }

    /// Delivers any events that arrived before the delegate was set.
    private func flushPendingEvents() {
        guard let sdk = sdk, let delegate = delegate, !pendingEvents.isEmpty else { return }
        let events = pendingEvents
        pendingEvents.removeAll()

        if Thread.isMainThread {
            for block in events { block(sdk, delegate) }
        } else {
            DispatchQueue.main.async {
                for block in events { block(sdk, delegate) }
            }
        }
    }
}
