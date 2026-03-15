import BackgroundTasks
import Foundation

/// Schedules `BGAppRefreshTask` wake-ups for periodic location tracking.
///
/// Supplements the in-memory `Timer` in `LocationEngine.startPeriodic()`.
/// When iOS suspends the app, the timer dies. This scheduler requests that
/// iOS wake the app via `BGAppRefreshTask` at approximately the configured
/// `periodicLocationInterval`. iOS may delay the wake-up, but it is far
/// more reliable than hoping the Timer survives suspension.
///
/// ## How It Works
///
/// 1. `start(interval:)` submits a `BGAppRefreshTaskRequest` with
///    `earliestBeginDate = now + interval`.
/// 2. When the task fires, the `onWakeUp` callback performs a one-shot
///    location fix and re-schedules the next task.
/// 3. `stop()` cancels any pending requests.
///
/// ## Requirements
///
/// - **Info.plist**: Must include `BGTaskSchedulerPermittedIdentifiers`
///   with `com.tracelet.periodic.refresh` **and** `UIBackgroundModes`
///   must contain `fetch`.
/// - **Registration**: `registerTask()` must be called early in the app
///   lifecycle (before `applicationDidFinishLaunching` returns).
///
/// ## Limitations
///
/// - iOS controls when `BGAppRefreshTask` actually fires. The
///   `earliestBeginDate` is a *hint*, not a guarantee.
/// - Typical latency: iOS may delay 5–30+ minutes depending on battery
///   state, user engagement patterns, and system load.
/// - Still better than nothing when the app is suspended and the Timer
///   has been killed.
public final class PeriodicRefreshScheduler {

    public static let taskIdentifier = "com.tracelet.periodic.refresh"

    /// Called when BGAppRefreshTask fires. The callback should perform a
    /// one-shot location fix and then call `scheduleNext(interval:)` to
    /// re-schedule.
    public var onWakeUp: (() -> Void)?

    private var currentInterval: TimeInterval = 900 // 15 min default
    private var isActive = false

    public init() {}

    // MARK: - Task Registration

    /// Register the `BGAppRefreshTask` handler with `BGTaskScheduler`.
    ///
    /// Must be called during `application(_:didFinishLaunchingWithOptions:)`
    /// — before the method returns.
    public func registerTask() {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: PeriodicRefreshScheduler.taskIdentifier,
                using: nil
            ) { [weak self] task in
                guard let self = self else {
                    task.setTaskCompleted(success: true)
                    return
                }
                self.handleTaskFired(task)
            }
        }
    }

    // MARK: - Start / Stop

    /// Start scheduling periodic refresh wake-ups.
    ///
    /// - Parameter interval: Desired wake-up interval in seconds.
    ///   iOS may not honor this exactly — it's an `earliestBeginDate` hint.
    public func start(interval: TimeInterval) {
        currentInterval = max(interval, 60) // floor at 1 minute
        isActive = true
        scheduleNext()
        NSLog("[Tracelet] PeriodicRefreshScheduler started (interval=\(Int(currentInterval))s)")
    }

    /// Stop scheduling periodic refresh wake-ups and cancel pending requests.
    public func stop() {
        isActive = false
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.cancel(
                taskRequestWithIdentifier: PeriodicRefreshScheduler.taskIdentifier
            )
        }
        NSLog("[Tracelet] PeriodicRefreshScheduler stopped")
    }

    // MARK: - Scheduling

    /// Schedule the next `BGAppRefreshTask`.
    public func scheduleNext() {
        guard isActive else { return }
        guard #available(iOS 13.0, *) else { return }

        let request = BGAppRefreshTaskRequest(
            identifier: PeriodicRefreshScheduler.taskIdentifier
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: currentInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[Tracelet] Scheduled next periodic refresh in \(Int(currentInterval))s")
        } catch {
            NSLog("[Tracelet] Failed to schedule periodic refresh: \(error.localizedDescription)")
        }
    }

    // MARK: - Task Handler

    private func handleTaskFired(_ task: Any) {
        guard isActive else {
            if #available(iOS 13.0, *) {
                (task as? BGTask)?.setTaskCompleted(success: true)
            }
            return
        }

        NSLog("[Tracelet] BGAppRefreshTask fired — performing periodic location fix")

        // Request background execution time for the location fix
        let bgTaskId = BackgroundTaskHelper.shared.begin("periodicRefreshFix")

        // Set expiration handler so iOS can reclaim the task gracefully.
        if #available(iOS 13.0, *) {
            (task as? BGTask)?.expirationHandler = {
                BackgroundTaskHelper.shared.end(bgTaskId)
            }
        }

        // Invoke the callback (performs one-shot location fix)
        onWakeUp?()

        // Re-schedule the next wake-up
        scheduleNext()

        // Defer BGTask completion to give the async location fix time to
        // return results (I-M4). Previously setTaskCompleted was called
        // synchronously, allowing iOS to suspend the app before the fix.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if #available(iOS 13.0, *) {
                (task as? BGTask)?.setTaskCompleted(success: true)
            }
            BackgroundTaskHelper.shared.end(bgTaskId)
        }
    }
}
