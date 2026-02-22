import BackgroundTasks
import Foundation

/// Schedule manager using BGTaskScheduler (iOS 13+).
///
/// Parses schedule strings in "dayStart-dayEnd HH:mm-HH:mm" format
/// and schedules BGAppRefreshTask for start/stop times.
final class ScheduleManager {
    private let configManager: ConfigManager
    private let stateManager: StateManager
    private let eventDispatcher: EventDispatcher

    private static let startTaskId = "com.tracelet.schedule.start"
    private static let stopTaskId = "com.tracelet.schedule.stop"

    /// Called when schedule says to start tracking.
    var onScheduleStart: (() -> Void)?
    /// Called when schedule says to stop tracking.
    var onScheduleStop: (() -> Void)?

    init(configManager: ConfigManager,
         stateManager: StateManager,
         eventDispatcher: EventDispatcher) {
        self.configManager = configManager
        self.stateManager = stateManager
        self.eventDispatcher = eventDispatcher
    }

    // MARK: - Public API

    func start() {
        stateManager.schedulerEnabled = true

        // Check if currently within schedule
        if isWithinSchedule() {
            onScheduleStart?()
            eventDispatcher.sendSchedule(["state": "on", "enabled": true])
        } else {
            onScheduleStop?()
            eventDispatcher.sendSchedule(["state": "off", "enabled": false])
        }

        scheduleNextTasks()
    }

    func stop() {
        stateManager.schedulerEnabled = false
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: ScheduleManager.startTaskId)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: ScheduleManager.stopTaskId)
        }
        eventDispatcher.sendSchedule(["state": "off", "enabled": false])
    }

    /// Register BGTask identifiers. Must be called in application:didFinishLaunching.
    static func registerBackgroundTasks(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: startTaskId, using: nil) { task in
                onStart()
                task.setTaskCompleted(success: true)
            }
            BGTaskScheduler.shared.register(forTaskWithIdentifier: stopTaskId, using: nil) { task in
                onStop()
                task.setTaskCompleted(success: true)
            }
        }
    }

    // MARK: - Schedule parsing

    /// Check if current time is within any configured schedule window.
    func isWithinSchedule() -> Bool {
        let schedule = configManager.getSchedule()
        guard !schedule.isEmpty else { return false }

        let now = Date()
        let calendar = Calendar.current
        let currentDay = calendar.component(.weekday, from: now) // 1=Sunday in Calendar

        for entry in schedule {
            if let window = parseScheduleEntry(entry) {
                // Convert Calendar weekday (1=Sunday) to ISO (1=Monday)
                let isoDay = currentDay == 1 ? 7 : currentDay - 1

                if isoDay >= window.dayStart && isoDay <= window.dayEnd {
                    let minutesSinceMidnight = calendar.component(.hour, from: now) * 60 +
                        calendar.component(.minute, from: now)
                    if minutesSinceMidnight >= window.startMinutes &&
                       minutesSinceMidnight < window.endMinutes {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Internal

    private struct ScheduleWindow {
        let dayStart: Int // ISO day-of-week (1=Monday)
        let dayEnd: Int
        let startMinutes: Int // Minutes since midnight
        let endMinutes: Int
    }

    /// Parses "dayStart-dayEnd HH:mm-HH:mm" format.
    private func parseScheduleEntry(_ entry: String) -> ScheduleWindow? {
        let parts = entry.split(separator: " ")
        guard parts.count == 2 else { return nil }

        let dayParts = parts[0].split(separator: "-")
        guard dayParts.count == 2,
              let dayStart = Int(dayParts[0]),
              let dayEnd = Int(dayParts[1]) else { return nil }

        let timeParts = parts[1].split(separator: "-")
        guard timeParts.count == 2 else { return nil }

        guard let startMinutes = parseTime(String(timeParts[0])),
              let endMinutes = parseTime(String(timeParts[1])) else { return nil }

        return ScheduleWindow(
            dayStart: dayStart,
            dayEnd: dayEnd,
            startMinutes: startMinutes,
            endMinutes: endMinutes
        )
    }

    /// Parses "HH:mm" to minutes since midnight.
    private func parseTime(_ str: String) -> Int? {
        let parts = str.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }
        return hours * 60 + minutes
    }

    private func scheduleNextTasks() {
        guard #available(iOS 13.0, *) else { return }

        // Schedule next start/stop using BGAppRefreshTask
        // This is best-effort; iOS controls actual execution timing
        let startRequest = BGAppRefreshTaskRequest(identifier: ScheduleManager.startTaskId)
        startRequest.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 15) // 15 min minimum

        let stopRequest = BGAppRefreshTaskRequest(identifier: ScheduleManager.stopTaskId)
        stopRequest.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 15)

        do {
            try BGTaskScheduler.shared.submit(startRequest)
            try BGTaskScheduler.shared.submit(stopRequest)
        } catch {
            NSLog("[Tracelet] Failed to schedule BGTask: \(error.localizedDescription)")
        }
    }
}
