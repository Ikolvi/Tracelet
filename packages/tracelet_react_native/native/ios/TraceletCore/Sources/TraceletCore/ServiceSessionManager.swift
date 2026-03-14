import CoreLocation
import Foundation

/// Manages a `CLServiceSession` (iOS 17+) to maintain the app's location
/// authorization state across background transitions and app relaunches.
///
/// ## Purpose
///
/// `CLServiceSession` is Apple's iOS 18+ mechanism for declaring that the
/// app has an ongoing need for location authorization. While a service
/// session is active:
///
/// - The system preserves the app's authorization level across app
///   lifecycle events (suspension, termination, relaunch).
///
/// - If "Always" authorization is granted, the app continues to receive
///   location callbacks even after being relaunched in the background.
///
/// - The session survives app restarts — if the app is killed and
///   relaunched (e.g., via significant-location change), creating a new
///   `CLServiceSession` re-establishes the authorization context.
///
/// ## Relationship to Other Mechanisms
///
/// - **`CLBackgroundActivitySession`**: Declares "I am doing background
///   location work RIGHT NOW." Auto-shows the blue indicator.
///
/// - **`CLServiceSession`**: Declares "I NEED location authorization to
///   remain valid." Does NOT auto-show the indicator.
///
/// Both can be active simultaneously and serve complementary purposes.
///
/// ## Behavior on iOS < 18
///
/// This manager is a no-op. Authorization state is managed differently
/// on older iOS versions (via `CLLocationManager` authorization APIs).
public final class ServiceSessionManager {

    /// The active service session (iOS 17+ only).
    private var session: AnyObject? // CLServiceSession

    /// Whether a session is currently active.
    public private(set) var isActive = false

    public init() {}

    /// Start a service session requesting full-accuracy authorization.
    ///
    /// On iOS 18+, creates a `CLServiceSession` with `.fullAccuracy`.
    /// On earlier iOS versions, this is a no-op.
    public func start() {
        guard !isActive else { return }

        if #available(iOS 18.0, *) {
            let svcSession = CLServiceSession(authorization: .always, fullAccuracyPurposeKey: "TraceletFullAccuracy")
            session = svcSession
            isActive = true
            NSLog("[Tracelet] CLServiceSession started (iOS 18+) — authorization=always, fullAccuracy")
        } else {
            NSLog("[Tracelet] CLServiceSession not available (iOS < 18)")
        }
    }

    /// Start a service session with "when in use" authorization.
    ///
    /// Used when the app only has foreground permission.
    public func startWhenInUse() {
        guard !isActive else { return }

        if #available(iOS 18.0, *) {
            let svcSession = CLServiceSession(authorization: .whenInUse)
            session = svcSession
            isActive = true
            NSLog("[Tracelet] CLServiceSession started (iOS 18+) — authorization=whenInUse")
        } else {
            NSLog("[Tracelet] CLServiceSession not available (iOS < 18)")
        }
    }

    /// Stop the service session.
    ///
    /// Signals to the system that the app no longer needs its
    /// authorization state to be preserved.
    public func stop() {
        guard isActive else { return }

        if #available(iOS 18.0, *) {
            if let svcSession = session as? CLServiceSession {
                svcSession.invalidate()
            }
        }

        session = nil
        isActive = false
        NSLog("[Tracelet] CLServiceSession stopped")
    }
}
