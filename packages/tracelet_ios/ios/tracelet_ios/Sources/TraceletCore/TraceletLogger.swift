import Foundation

/// Dual (console + SQLite) logger for the Tracelet plugin.
///
/// Respects configured log level. Provides getLog, pruneOldLogs, and email export.
public final class TraceletLogger {
    private let configManager: ConfigManager
    private let database: TraceletDatabase

    /// Log levels: OFF(0), ERROR(1), WARNING(2), INFO(3), DEBUG(4), VERBOSE(5)
    enum Level: Int, Comparable {
        case off = 0, error = 1, warning = 2, info = 3, debug = 4, verbose = 5

        var label: String {
            switch self {
            case .off: return "OFF"
            case .error: return "ERROR"
            case .warning: return "WARNING"
            case .info: return "INFO"
            case .debug: return "DEBUG"
            case .verbose: return "VERBOSE"
            }
        }

        static func from(_ string: String) -> Level {
            switch string.uppercased() {
            case "ERROR": return .error
            case "WARNING", "WARN": return .warning
            case "INFO": return .info
            case "DEBUG": return .debug
            case "VERBOSE": return .verbose
            default: return .info
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    public init(configManager: ConfigManager, database: TraceletDatabase) {
        self.configManager = configManager
        self.database = database
    }

    // MARK: - Logging methods

    public func error(_ message: String) {
        log(.error, message)
    }

    public func warning(_ message: String) {
        log(.warning, message)
    }

    public func info(_ message: String) {
        log(.info, message)
    }

    public func debug(_ message: String) {
        log(.debug, message)
    }

    public func verbose(_ message: String) {
        log(.verbose, message)
    }

    /// Log from Dart side with string level.
    public func log(levelString: String, message: String) {
        let level = Level.from(levelString)
        log(level, message, source: "dart")
    }

    // MARK: - Query

    public func getLog(query: [String: Any]? = nil) -> [[String: Any]] {
        return database.getLogs(query: query)
    }

    public func getLogForEmail() -> String {
        return database.getLogForEmail()
    }

    public func destroyLog() -> Bool {
        return database.deleteAllLogs()
    }

    public func pruneOldLogs() {
        let maxDays = configManager.getLogMaxDays()
        database.pruneOldLogs(maxDays: maxDays)
    }

    // MARK: - Core

    private func log(_ level: Level, _ message: String, source: String = "plugin") {
        let configLevel = Level(rawValue: configManager.getLogLevel()) ?? .verbose

        // Skip if level is above configured threshold
        guard level.rawValue <= configLevel.rawValue, level != .off else { return }

        // Console log
        NSLog("[Tracelet] [\(level.label)] \(message)")

        // SQLite log
        database.insertLog(level: level.label, message: message, source: source)
    }
}
