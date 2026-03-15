import CoreLocation
import Foundation

/// Manages a `CLBackgroundActivitySession` (iOS 17+) to inform the system
/// that the app is performing a legitimate background location activity.
///
/// On iOS 17+, `CLBackgroundActivitySession` replaces the need for
/// `allowsBackgroundLocationUpdates` on `CLLocationManager`. When a session
/// is active, the app continues to receive location updates in the background
/// and displays the blue location indicator in the status bar.
///
/// On iOS < 17, this manager is a no-op — background location is handled
/// via the traditional `allowsBackgroundLocationUpdates = true` approach.
///
/// ## Key Behaviors
///
/// - **Session lifecycle**: Started with `start()`, stopped with `stop()`.
///   Only one session should be active at a time.
///
/// - **Automatic re-creation**: If the system invalidates the session
///   (e.g., the app is suspended and relaunched via significant-location
///   change), call `start()` again to create a new session.
///
/// - **Authorization**: Requires at least "When In Use" authorization.
///   If the app has "Always" authorization, the session keeps location
///   delivery active even when the app has no foreground presence.
///
/// - **No permission prompt**: This does not trigger any permission dialog.
///   It only declares intent to use location in the background.
public final class BackgroundActivitySessionManager {

    /// The active background activity session (iOS 17+ only).
    private var session: AnyObject? // CLBackgroundActivitySession, typed as AnyObject for < iOS 17

    /// Whether a session is currently active.
    public private(set) var isActive = false

    public init() {}

    /// Start a background activity session.
    ///
    /// On iOS 17+, creates a `CLBackgroundActivitySession`. On earlier
    /// iOS versions, this is a no-op (background is handled via
    /// `allowsBackgroundLocationUpdates`).
    public func start() {
        guard !isActive else { return }

        if #available(iOS 17.0, *) {
            let bgSession = CLBackgroundActivitySession()
            session = bgSession
            isActive = true
            NSLog("[Tracelet] CLBackgroundActivitySession started (iOS 17+)")
        } else {
            // iOS < 17: no-op, background handled via allowsBackgroundLocationUpdates
            NSLog("[Tracelet] CLBackgroundActivitySession not available (iOS < 17)")
        }
    }

    /// Stop the background activity session.
    ///
    /// Invalidates the session, signaling to the system that the app
    /// no longer needs background location updates.
    public func stop() {
        guard isActive else { return }

        if #available(iOS 17.0, *) {
            // Invalidate by calling invalidate() on the session
            if let bgSession = session as? CLBackgroundActivitySession {
                bgSession.invalidate()
            }
        }

        session = nil
        isActive = false
        NSLog("[Tracelet] CLBackgroundActivitySession stopped")
    }
}
