import Foundation

/// Dual (console + SQLite) logger for the Tracelet plugin.
///
/// Respects configured log level. Provides getLog, pruneOldLogs, and email export.
public final class TraceletLogger {
    private let configManager: ConfigManager
    public var rustDatabase: DatabaseManager? = nil

    /// Serial queue for log persistence so callers (including high-frequency
    /// motion callbacks) never block on a synchronous SQLite write. Serial
    /// execution preserves persisted log ordering (#130).
    private let persistQueue = DispatchQueue(label: "com.tracelet.logger.persist")

    /// Writes since the last prune. Confined to `persistQueue`. See `log(_:_:source:)`.
    private var writesSincePrune = 0

    /// Amortization window for log pruning.
    ///
    /// Retention is 500-2000 rows, so letting the table run this many rows past
    /// the limit between prunes is harmless and removes a DELETE from every
    /// single log write.
    private static let pruneIntervalWrites = 50

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

    public init(configManager: ConfigManager) {
        self.configManager = configManager
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

    /// `@autoclosure` so the message — including any `String(format:…)` — is
    /// only built when the level passes the configured threshold. Avoids
    /// formatting cost on filtered hot-path logs (#130).
    public func debug(_ message: @autoclosure () -> String) {
        log(.debug, message())
    }

    public func verbose(_ message: @autoclosure () -> String) {
        log(.verbose, message())
    }

    /// Log from Dart side with string level.
    public func log(levelString: String, message: String) {
        let level = Level.from(levelString)
        log(level, message, source: "dart")
    }

    // MARK: - Query

    public func getLog(query: [String: Any]? = nil) -> String {
        do {
            let limit = (query?["limit"] as? NSNumber)?.int32Value ?? 500
            let logs = try rustDatabase?.getLogs(limit: limit) ?? []
            return logs.map { "[\($0.timestamp)] [\($0.level)] \($0.message)" }.joined(separator: "\n")
        } catch {
            return "Failed to retrieve logs: \(error.localizedDescription)"
        }
    }

    public func getLogForEmail() -> String {
        return getLog(query: ["limit": 2000])
    }

    public func destroyLog() -> Bool {
        do {
            try rustDatabase?.clearLogs()
            return true
        } catch {
            return false
        }
    }

    /// Prune old logs based on config.
    ///
    /// Two independent caps, both of which must hold:
    /// - a row count derived from the log level (a chatty verbose session keeps
    ///   more lines than an error-only one), and
    /// - `logMaxDays`, the retention window (#304). This was documented and
    ///   configurable but never implemented — only the row cap existed, so the
    ///   configured number of days was accepted and discarded. A row cap alone
    ///   cannot express "keep two weeks", because how many rows that is depends
    ///   entirely on how chatty the session was.
    ///
    /// `logMaxDays <= 0` disables the age cap and leaves the row cap in force.
    public func pruneOldLogs() {
        do {
            let limit: Int32
            switch configManager.getLogLevel() {
            case Level.error.rawValue, Level.off.rawValue:
                limit = 500
            case Level.warning.rawValue, Level.info.rawValue:
                limit = 1000
            case Level.debug.rawValue, Level.verbose.rawValue:
                limit = 2000
            default:
                limit = 1000
            }
            try rustDatabase?.pruneLogs(limit: limit)
            try rustDatabase?.pruneLogsOlderThan(maxDays: Int32(configManager.getLogMaxDays()))
        } catch {
            NSLog("[Tracelet] Failed to prune logs: \(error.localizedDescription)")
        }
    }

    // MARK: - Core

    private func log(_ level: Level, _ message: @autoclosure () -> String, source: String = "plugin") {
        let configLevel = Level(rawValue: configManager.getLogLevel()) ?? .verbose

        // Skip if level is above configured threshold — message() is never
        // evaluated, so filtered hot-path logs cost nothing to format.
        guard level.rawValue <= configLevel.rawValue, level != .off else { return }

        let built = message()

        // Console log
        NSLog("[Tracelet] [\(level.label)] \(built)")

        // SQLite log — persisted off the caller thread so motion callbacks (and
        // any other hot path) never block on a synchronous DB write (#130).
        let db = rustDatabase
        persistQueue.async { [weak self] in
            do {
                try db?.insertLog(level: level.label, message: built, source: source)
                // Prune old logs to maintain dynamic limits.
                //
                // Previously ran a DELETE after every single insert. Retention is
                // 500-2000 rows, so pruning per write is pure overhead — amortize
                // it. Matters more now that geofence transitions log at INFO.
                //
                // `writesSincePrune` is only ever touched inside this serial
                // queue, so it needs no additional synchronization.
                guard let self else { return }
                self.writesSincePrune += 1
                if self.writesSincePrune >= TraceletLogger.pruneIntervalWrites {
                    self.writesSincePrune = 0
                    self.pruneOldLogs()
                }
            } catch {
                NSLog("[Tracelet] Failed to persist log to Rust Database: \(error.localizedDescription)")
            }
        }
    }
}

