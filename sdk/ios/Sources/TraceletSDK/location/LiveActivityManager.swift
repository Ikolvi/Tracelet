import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Manages the lifecycle of the Tracelet Live Activity.
///
/// ## Concurrency model
///
/// All mutable state (`currentActivity`, `isStarting`, `generation`) is
/// confined to the main thread. Public entry points hop to main if called
/// from another thread, and the asynchronous ActivityKit work (request/end)
/// runs in `@MainActor` tasks, so the state is never touched concurrently.
///
/// A monotonically-increasing `generation` token guards the start/stop race:
/// if `stopLiveActivity()` runs while a `startLiveActivity()` request is still
/// in flight, the freshly-created activity is ended immediately instead of
/// leaking as an orphan that nothing holds a reference to.
@available(iOS 16.1, *)
internal final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// The currently-tracked activity. Only ever touched on the main thread.
    private var currentActivity: Activity<TraceletActivityAttributes>?

    /// `true` while a start request is in flight; prevents duplicate starts.
    private var isStarting = false

    /// Bumped on every stop; invalidates any start request still in flight.
    private var generation = 0

    private init() {}

    // MARK: - Public API (safe to call from any thread)

    func startLiveActivity(title: String, body: String, startedAt: Date? = nil, showTimer: Bool = false) {
        onMain { self.startOnMain(title: title, body: body, startedAt: startedAt, showTimer: showTimer) }
    }

    func stopLiveActivity() {
        onMain { self.stopOnMain() }
    }

    /// Refreshes the content of the currently-running Live Activity so it
    /// reflects the latest `liveActivityConfig`. This is the iOS analogue of
    /// refreshing the Android foreground-service notification (#257).
    ///
    /// Only the dynamic `body` (ContentState.status) can be updated on a
    /// running activity — the `title` lives in the immutable ActivityAttributes
    /// and cannot change without ending and re-requesting the activity, so a
    /// title change is reported but not applied here. No-op if no activity is
    /// currently running (nothing to refresh).
    func updateLiveActivity(title: String, body: String, startedAt: Date? = nil, showTimer: Bool = false) {
        onMain { self.updateOnMain(title: title, body: body, startedAt: startedAt, showTimer: showTimer) }
    }

    /// Ensures the Live Activity reflects the latest `liveActivityConfig` while
    /// a tracking session is active: updates the running activity in place, or
    /// **(re)starts** one if none is currently shown. Used by
    /// `updateNotification()` (#257).
    ///
    /// Re-presenting matters because the activity is bound to the moving
    /// sub-state (it is ended on `LocationEngine.stop()`), so it may not be on
    /// screen at the moment the app asks to refresh it (e.g. after a transient
    /// stop/restart). Starting it here guarantees the newest content is shown
    /// rather than silently doing nothing.
    func refreshLiveActivity(title: String, body: String, startedAt: Date? = nil, showTimer: Bool = false) {
        onMain {
            if self.currentActivity != nil {
                self.updateOnMain(title: title, body: body, startedAt: startedAt, showTimer: showTimer)
            } else if !self.isStarting {
                self.startOnMain(title: title, body: body, startedAt: startedAt, showTimer: showTimer)
            }
        }
    }

    // MARK: - Main-thread implementation

    private func startOnMain(title: String, body: String, startedAt: Date? = nil, showTimer: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            TraceletLog.debug("[Tracelet-LiveActivity] Live Activities not enabled; skipping start.")
            return
        }
        guard currentActivity == nil, !isStarting else {
            TraceletLog.debug("[Tracelet-LiveActivity] Activity already active or starting; skipping start.")
            return
        }

        isStarting = true
        let requestGeneration = generation

        Task { @MainActor [weak self] in
            // Clear any orphaned activities (e.g. left over from a prior launch)
            // before requesting a fresh one.
            await LiveActivityManager.endAllActivities()

            do {
                let activity = try LiveActivityManager.requestActivity(
                    title: title,
                    body: body,
                    startedAt: startedAt,
                    showTimer: showTimer
                )

                guard let self = self else {
                    // Owner deallocated mid-flight — don't leak the activity.
                    await activity.endImmediately()
                    return
                }
                self.isStarting = false

                if self.generation != requestGeneration {
                    // stop() was called while the request was in flight.
                    TraceletLog.debug("[Tracelet-LiveActivity] Start superseded by stop; ending new activity.")
                    await activity.endImmediately()
                } else {
                    self.currentActivity = activity
                    TraceletLog.debug("[Tracelet-LiveActivity] Live Activity started: \(activity.id)")
                }
            } catch {
                self?.isStarting = false
                TraceletLog.error("[Tracelet-LiveActivity] Failed to start Live Activity: \(error.localizedDescription)")
            }
        }
    }

    private func updateOnMain(title: String, body: String, startedAt: Date? = nil, showTimer: Bool = false) {
        guard let activity = currentActivity else {
            TraceletLog.debug("[Tracelet-LiveActivity] No active Live Activity to refresh; skipping update.")
            return
        }

        if title != activity.attributes.title {
            TraceletLog.debug(
                "[Tracelet-LiveActivity] Live Activity title is immutable on a running activity; " +
                "only the body was refreshed. Restart tracking to apply a new title."
            )
        }

        Task { @MainActor in
            let newState = LiveActivityManager.contentState(
                body: body,
                startedAt: startedAt,
                showTimer: showTimer
            )
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: newState, staleDate: nil))
            } else {
                await activity.update(using: newState)
            }
            TraceletLog.debug("[Tracelet-LiveActivity] Live Activity refreshed: \(activity.id)")
        }
    }

    private func stopOnMain() {
        // Invalidate any in-flight start so it tears itself down on completion.
        generation &+= 1
        isStarting = false

        let activity = currentActivity
        currentActivity = nil

        Task { @MainActor in
            if let activity = activity {
                await activity.endImmediately()
            }
            // Defensively end any orphans (e.g. relaunch after termination).
            await LiveActivityManager.endAllActivities()
        }
    }

    // MARK: - Helpers

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private static func requestActivity(
        title: String,
        body: String,
        startedAt: Date? = nil,
        showTimer: Bool = false
    ) throws -> Activity<TraceletActivityAttributes> {
        let attributes = TraceletActivityAttributes(title: title)
        let state = contentState(body: body, startedAt: startedAt, showTimer: showTimer)
        if #available(iOS 16.2, *) {
            return try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } else {
            return try Activity.request(
                attributes: attributes,
                contentState: state,
                pushType: nil
            )
        }
    }

    private static func endAllActivities() async {
        for activity in Activity<TraceletActivityAttributes>.activities {
            await activity.endImmediately()
        }
    }

    private static func contentState(
        body: String,
        startedAt: Date?,
        showTimer: Bool
    ) -> TraceletActivityAttributes.ContentState {
        if showTimer && startedAt == nil {
            TraceletLog.debug("showTimer is set but startedAt is not — no timer shown")
        }
        return TraceletActivityAttributes.ContentState(
            status: body,
            startedAt: startedAt.map { min($0, Date()) },
            showTimer: showTimer
        )
    }
}

@available(iOS 16.1, *)
private extension Activity where Attributes == TraceletActivityAttributes {
    /// Ends the activity immediately with a terminal "stopped" state.
    func endImmediately() async {
        // Deliberately omit timer state so the terminal card never keeps ticking.
        let finalState = TraceletActivityAttributes.ContentState(status: "Tracking stopped")
        if #available(iOS 16.2, *) {
            await end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        } else {
            await end(using: finalState, dismissalPolicy: .immediate)
        }
    }
}
#endif
