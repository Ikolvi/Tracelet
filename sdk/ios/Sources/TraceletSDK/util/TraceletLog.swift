import Foundation

/// Process-wide entry point for Tracelet logging.
///
/// Routes every log line through the configured `TraceletLogger` (which respects
/// the configured log level and persists to the Rust SQLite log store) once the
/// SDK has `attach`ed one. Before the SDK is initialized — e.g. inside a
/// background relaunch or a manager that spins up early — it falls back to
/// `NSLog` so nothing is silently dropped.
///
/// Use this instead of `NSLog` everywhere. The only place that legitimately
/// calls `NSLog` directly is `TraceletLogger` itself (the sink) and this
/// fallback.
public enum TraceletLog {
    private static let lock = NSLock()
    private static var delegate: TraceletLogger?

    /// Wire the real logger once the SDK is initialized.
    public static func attach(_ logger: TraceletLogger) {
        lock.lock(); delegate = logger; lock.unlock()
    }

    /// Drop the logger reference (e.g. on reset/teardown).
    public static func detach() {
        lock.lock(); delegate = nil; lock.unlock()
    }

    private static var current: TraceletLogger? {
        lock.lock(); defer { lock.unlock() }; return delegate
    }

    public static func error(_ message: @autoclosure () -> String) {
        if let d = current { d.error(message()) } else { NSLog("[Tracelet] [ERROR] \(message())") }
    }

    public static func warning(_ message: @autoclosure () -> String) {
        if let d = current { d.warning(message()) } else { NSLog("[Tracelet] [WARNING] \(message())") }
    }

    public static func info(_ message: @autoclosure () -> String) {
        if let d = current { d.info(message()) } else { NSLog("[Tracelet] [INFO] \(message())") }
    }

    public static func debug(_ message: @autoclosure () -> String) {
        if let d = current { d.debug(message()) } else { NSLog("[Tracelet] [DEBUG] \(message())") }
    }

    public static func verbose(_ message: @autoclosure () -> String) {
        if let d = current { d.verbose(message()) } else { NSLog("[Tracelet] [VERBOSE] \(message())") }
    }

    /// Records an always-on **lifecycle** event — see
    /// ``TraceletLogger/lifecycle(_:)`` for what belongs here and why it bypasses
    /// `logLevel` (#318).
    ///
    /// Before the SDK has attached a logger this falls back to the console,
    /// exactly like the level-based methods. That gap is why
    /// ``TraceletLogger/lifecycle(_:)`` buffers: entries recorded through the
    /// real logger while its database is still opening are flushed once it is
    /// available, so a relaunch that never finished resuming still leaves a
    /// trail.
    public static func lifecycle(_ message: String) {
        if let d = current {
            d.lifecycle(message)
        } else {
            NSLog("[Tracelet] [\(TraceletLogger.lifecycleLevelName)] \(message)")
        }
    }
}
