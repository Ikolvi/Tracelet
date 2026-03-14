import UIKit

/// Thread-safe manager for `UIApplication.beginBackgroundTask` / `endBackgroundTask`.
///
/// Provides a centralized, safe way to request background execution time from iOS.
/// Each task is identified by a name (for logging/debugging) and automatically
/// handles the expiration callback to prevent the app from being killed.
///
/// ## Usage
///
/// ```swift
/// let taskId = BackgroundTaskHelper.shared.begin("httpSync")
/// // ... async work ...
/// BackgroundTaskHelper.shared.end(taskId)
/// ```
///
/// ## Safety Guarantees
///
/// - **Expiration handler**: Every task gets an expiration handler that calls
///   `endBackgroundTask` + logs a warning if iOS is about to expire the task.
/// - **Idempotent end**: Calling `end()` multiple times with the same ID is safe.
/// - **Invalid check**: Returns `nil` if `beginBackgroundTask` fails.
/// - **Thread-safe**: All mutations are serialized on a dedicated queue.
public final class BackgroundTaskHelper {

    /// Shared singleton instance.
    public static let shared = BackgroundTaskHelper()

    /// Serial queue protecting the active-tasks dictionary.
    private let queue = DispatchQueue(label: "com.tracelet.backgroundTask", qos: .utility)

    /// Active background tasks: taskId → name.
    private var activeTasks: [UIBackgroundTaskIdentifier: String] = [:]

    private init() {}

    /// Begin a background task with the given name.
    ///
    /// - Parameter name: A human-readable identifier for debugging/logging.
    /// - Returns: The task identifier, or `nil` if iOS denied the request.
    @discardableResult
    public func begin(_ name: String) -> UIBackgroundTaskIdentifier? {
        var taskId: UIBackgroundTaskIdentifier = .invalid

        taskId = UIApplication.shared.beginBackgroundTask(withName: "com.tracelet.\(name)") { [weak self] in
            // Expiration handler — iOS is about to kill us.
            // We MUST call endBackgroundTask here.
            NSLog("[Tracelet] ⚠️ Background task '\(name)' expired by iOS — ending")
            self?.end(taskId)
        }

        guard taskId != .invalid else {
            NSLog("[Tracelet] Background task '\(name)' denied by iOS")
            return nil
        }

        queue.sync {
            activeTasks[taskId] = name
        }

        NSLog("[Tracelet] Background task '\(name)' started (id=\(taskId.rawValue))")
        return taskId
    }

    /// End a background task.
    ///
    /// Safe to call multiple times — subsequent calls with the same ID are no-ops.
    ///
    /// - Parameter taskId: The identifier returned by `begin(_:)`.
    public func end(_ taskId: UIBackgroundTaskIdentifier?) {
        guard let taskId = taskId, taskId != .invalid else { return }

        let name: String? = queue.sync {
            activeTasks.removeValue(forKey: taskId)
        }

        guard name != nil else {
            // Already ended (idempotent)
            return
        }

        UIApplication.shared.endBackgroundTask(taskId)
        NSLog("[Tracelet] Background task '\(name!)' ended (id=\(taskId.rawValue))")
    }

    /// Convenience: execute a synchronous block within a background task.
    ///
    /// The background task is automatically ended when the block returns.
    public func run(_ name: String, block: () -> Void) {
        let taskId = begin(name)
        block()
        end(taskId)
    }

    /// Convenience: execute an asynchronous operation within a background task.
    ///
    /// The caller MUST invoke the `done` closure when the async work finishes.
    public func beginAsync(_ name: String, work: (@escaping () -> Void) -> Void) {
        let taskId = begin(name)
        work {
            self.end(taskId)
        }
    }

    /// Number of currently active background tasks (for testing/debugging).
    public var activeCount: Int {
        queue.sync { activeTasks.count }
    }
}
