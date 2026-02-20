import Foundation
import SQLite3

/// SQLite database for persisting locations, geofences, and log entries.
///
/// Uses the sqlite3 C API directly. All write operations are serialized
/// on a dedicated serial queue for thread safety.
final class TraceletDatabase {
    static let shared = TraceletDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.tracelet.db", qos: .utility)

    private init() {
        openDatabase()
        createTables()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Setup

    private func openDatabase() {
        let fileURL = getDBPath()
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            NSLog("[Tracelet] Failed to open database: \(String(cString: sqlite3_errmsg(db!)))")
        }
        // Enable WAL mode for better concurrent read performance
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA foreign_keys=ON")
    }

    private func getDBPath() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let traceletDir = dir.appendingPathComponent("com.tracelet")
        try? FileManager.default.createDirectory(at: traceletDir, withIntermediateDirectories: true)
        return traceletDir.appendingPathComponent("tracelet.db")
    }

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS locations (
                uuid TEXT PRIMARY KEY,
                timestamp TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL DEFAULT 0,
                speed REAL DEFAULT -1,
                speed_accuracy REAL DEFAULT -1,
                heading REAL DEFAULT -1,
                heading_accuracy REAL DEFAULT -1,
                accuracy REAL DEFAULT -1,
                vertical_accuracy REAL DEFAULT -1,
                floor_level INTEGER,
                is_moving INTEGER DEFAULT 0,
                odometer REAL DEFAULT 0,
                activity_type TEXT DEFAULT 'unknown',
                activity_confidence INTEGER DEFAULT -1,
                battery_level REAL DEFAULT -1,
                battery_is_charging INTEGER DEFAULT 0,
                extras TEXT,
                event TEXT,
                synced INTEGER DEFAULT 0,
                created_at TEXT DEFAULT (datetime('now'))
            )
        """)

        exec("""
            CREATE INDEX IF NOT EXISTS idx_locations_synced ON locations(synced)
        """)
        exec("""
            CREATE INDEX IF NOT EXISTS idx_locations_timestamp ON locations(timestamp)
        """)

        exec("""
            CREATE TABLE IF NOT EXISTS geofences (
                identifier TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                radius REAL NOT NULL,
                notify_on_entry INTEGER DEFAULT 1,
                notify_on_exit INTEGER DEFAULT 1,
                notify_on_dwell INTEGER DEFAULT 0,
                loitering_delay INTEGER DEFAULT 0,
                extras TEXT
            )
        """)

        exec("""
            CREATE TABLE IF NOT EXISTS logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                level TEXT NOT NULL,
                message TEXT NOT NULL,
                timestamp TEXT DEFAULT (datetime('now')),
                source TEXT DEFAULT 'plugin'
            )
        """)
    }

    // MARK: - Location CRUD

    func insertLocation(_ data: [String: Any]) -> String {
        let uuid = data["uuid"] as? String ?? UUID().uuidString
        queue.sync {
            let sql = """
                INSERT OR REPLACE INTO locations
                (uuid, timestamp, latitude, longitude, altitude, speed, speed_accuracy,
                 heading, heading_accuracy, accuracy, vertical_accuracy, floor_level,
                 is_moving, odometer, activity_type, activity_confidence,
                 battery_level, battery_is_charging, extras, event, synced)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("[Tracelet] insertLocation prepare failed: \(lastError())")
                return
            }
            defer { sqlite3_finalize(stmt) }

            let coords = data["coords"] as? [String: Any] ?? data
            let activity = data["activity"] as? [String: Any]
            let battery = data["battery"] as? [String: Any]
            let extras = data["extras"] as? [String: Any]
            let extrasJson = extras.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { String(data: $0, encoding: .utf8) }

            sqlite3_bind_text(stmt, 1, nsString(uuid), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, nsString(data["timestamp"] as? String ?? iso8601Now()), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(stmt, 3, coords["latitude"] as? Double ?? 0)
            sqlite3_bind_double(stmt, 4, coords["longitude"] as? Double ?? 0)
            sqlite3_bind_double(stmt, 5, coords["altitude"] as? Double ?? 0)
            sqlite3_bind_double(stmt, 6, coords["speed"] as? Double ?? -1)
            sqlite3_bind_double(stmt, 7, coords["speed_accuracy"] as? Double ?? -1)
            sqlite3_bind_double(stmt, 8, coords["heading"] as? Double ?? -1)
            sqlite3_bind_double(stmt, 9, coords["heading_accuracy"] as? Double ?? -1)
            sqlite3_bind_double(stmt, 10, coords["accuracy"] as? Double ?? -1)
            sqlite3_bind_double(stmt, 11, coords["altitude_accuracy"] as? Double ?? -1)
            if let floor = coords["floor"] as? Int32 {
                sqlite3_bind_int(stmt, 12, floor)
            } else {
                sqlite3_bind_null(stmt, 12)
            }
            sqlite3_bind_int(stmt, 13, (data["is_moving"] as? Bool ?? false) ? 1 : 0)
            sqlite3_bind_double(stmt, 14, data["odometer"] as? Double ?? 0)
            sqlite3_bind_text(stmt, 15, nsString(activity?["type"] as? String ?? "unknown"), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(stmt, 16, Int32(activity?["confidence"] as? Int ?? -1))
            sqlite3_bind_double(stmt, 17, battery?["level"] as? Double ?? Double(BatteryUtils.getBatteryLevel()))
            sqlite3_bind_int(stmt, 18, (battery?["is_charging"] as? Bool ?? BatteryUtils.isCharging()) ? 1 : 0)
            sqlite3_bind_text(stmt, 19, nsString(extrasJson ?? ""), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 20, nsString(data["event"] as? String ?? ""), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("[Tracelet] insertLocation step failed: \(lastError())")
            }
        }
        return uuid
    }

    func getLocations(limit: Int = -1, offset: Int = 0, orderAsc: Bool = true) -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            let order = orderAsc ? "ASC" : "DESC"
            var sql = "SELECT * FROM locations ORDER BY timestamp \(order)"
            if limit > 0 {
                sql += " LIMIT \(limit) OFFSET \(offset)"
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(locationRowToMap(stmt!))
            }
        }
        return results
    }

    func getUnsyncedLocations(limit: Int = 100) -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            let sql = "SELECT * FROM locations WHERE synced = 0 ORDER BY timestamp ASC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(locationRowToMap(stmt!))
            }
        }
        return results
    }

    func getLocationCount() -> Int {
        var count = 0
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM locations", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        return count
    }

    func markSynced(uuids: [String]) {
        queue.sync {
            let placeholders = uuids.map { _ in "?" }.joined(separator: ",")
            let sql = "UPDATE locations SET synced = 1 WHERE uuid IN (\(placeholders))"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for (i, uuid) in uuids.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), nsString(uuid), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            sqlite3_step(stmt)
        }
    }

    func deleteAllLocations() -> Bool {
        queue.sync {
            return exec("DELETE FROM locations")
        }
    }

    func deleteLocation(_ uuid: String) -> Bool {
        var success = false
        queue.sync {
            let sql = "DELETE FROM locations WHERE uuid = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, nsString(uuid), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            success = sqlite3_step(stmt) == SQLITE_DONE
        }
        return success
    }

    // MARK: - Geofence CRUD

    func insertGeofence(_ data: [String: Any]) -> Bool {
        var success = false
        queue.sync {
            let sql = """
                INSERT OR REPLACE INTO geofences
                (identifier, latitude, longitude, radius, notify_on_entry, notify_on_exit,
                 notify_on_dwell, loitering_delay, extras)
                VALUES (?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, nsString(data["identifier"] as? String ?? ""), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(stmt, 2, data["latitude"] as? Double ?? 0)
            sqlite3_bind_double(stmt, 3, data["longitude"] as? Double ?? 0)
            sqlite3_bind_double(stmt, 4, data["radius"] as? Double ?? 100)
            sqlite3_bind_int(stmt, 5, (data["notifyOnEntry"] as? Bool ?? true) ? 1 : 0)
            sqlite3_bind_int(stmt, 6, (data["notifyOnExit"] as? Bool ?? true) ? 1 : 0)
            sqlite3_bind_int(stmt, 7, (data["notifyOnDwell"] as? Bool ?? false) ? 1 : 0)
            sqlite3_bind_int(stmt, 8, Int32(data["loiteringDelay"] as? Int ?? 0))
            let extras = data["extras"] as? [String: Any]
            let extrasJson = extras.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { String(data: $0, encoding: .utf8) }
            sqlite3_bind_text(stmt, 9, nsString(extrasJson ?? ""), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            success = sqlite3_step(stmt) == SQLITE_DONE
        }
        return success
    }

    func getGeofences() -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT * FROM geofences", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(geofenceRowToMap(stmt!))
            }
        }
        return results
    }

    func getGeofence(_ identifier: String) -> [String: Any]? {
        var result: [String: Any]?
        queue.sync {
            let sql = "SELECT * FROM geofences WHERE identifier = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, nsString(identifier), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = geofenceRowToMap(stmt!)
            }
        }
        return result
    }

    func geofenceExists(_ identifier: String) -> Bool {
        return getGeofence(identifier) != nil
    }

    func deleteGeofence(_ identifier: String) -> Bool {
        var success = false
        queue.sync {
            let sql = "DELETE FROM geofences WHERE identifier = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, nsString(identifier), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            success = sqlite3_step(stmt) == SQLITE_DONE
        }
        return success
    }

    func deleteAllGeofences() -> Bool {
        queue.sync {
            return exec("DELETE FROM geofences")
        }
    }

    // MARK: - Log CRUD

    func insertLog(level: String, message: String, source: String = "plugin") {
        queue.sync {
            let sql = "INSERT INTO logs (level, message, source) VALUES (?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, nsString(level), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, nsString(message), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 3, nsString(source), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(stmt)
        }
    }

    func getLogs(query: [String: Any]? = nil) -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            let limit = query?["limit"] as? Int ?? 500
            var stmt: OpaquePointer?
            let sql = "SELECT * FROM logs ORDER BY id DESC LIMIT ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append([
                    "id": Int(sqlite3_column_int(stmt, 0)),
                    "level": columnText(stmt, 1),
                    "message": columnText(stmt, 2),
                    "timestamp": columnText(stmt, 3),
                    "source": columnText(stmt, 4),
                ])
            }
        }
        return results
    }

    func getLogForEmail() -> String {
        let logs = getLogs(query: ["limit": 2000])
        return logs.map { "[\($0["timestamp"] ?? "")] [\($0["level"] ?? "")] \($0["message"] ?? "")" }
            .joined(separator: "\n")
    }

    func pruneOldLogs(maxDays: Int) {
        queue.sync {
            let sql = "DELETE FROM logs WHERE timestamp < datetime('now', '-\(maxDays) days')"
            exec(sql)
        }
    }

    func deleteAllLogs() -> Bool {
        queue.sync {
            return exec("DELETE FROM logs")
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            if let msg = errMsg {
                NSLog("[Tracelet] SQL error: \(String(cString: msg))")
                sqlite3_free(msg)
            }
            return false
        }
        return true
    }

    private func lastError() -> String {
        guard let db = db else { return "no database" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func nsString(_ str: String) -> UnsafePointer<CChar> {
        return (str as NSString).utf8String!
    }

    private func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cStr)
    }

    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func locationRowToMap(_ stmt: OpaquePointer) -> [String: Any] {
        let extrasStr = columnText(stmt, 18)
        let extras: [String: Any]? = extrasStr.isEmpty ? nil :
            (try? JSONSerialization.jsonObject(with: Data(extrasStr.utf8)) as? [String: Any])

        return [
            "uuid": columnText(stmt, 0),
            "timestamp": columnText(stmt, 1),
            "coords": [
                "latitude": sqlite3_column_double(stmt, 2),
                "longitude": sqlite3_column_double(stmt, 3),
                "altitude": sqlite3_column_double(stmt, 4),
                "speed": sqlite3_column_double(stmt, 5),
                "speed_accuracy": sqlite3_column_double(stmt, 6),
                "heading": sqlite3_column_double(stmt, 7),
                "heading_accuracy": sqlite3_column_double(stmt, 8),
                "accuracy": sqlite3_column_double(stmt, 9),
                "altitude_accuracy": sqlite3_column_double(stmt, 10),
                "floor": sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 11)),
            ] as [String: Any?],
            "is_moving": sqlite3_column_int(stmt, 12) == 1,
            "odometer": sqlite3_column_double(stmt, 13),
            "activity": [
                "type": columnText(stmt, 14),
                "confidence": Int(sqlite3_column_int(stmt, 15)),
            ],
            "battery": [
                "level": sqlite3_column_double(stmt, 16),
                "is_charging": sqlite3_column_int(stmt, 17) == 1,
            ],
            "extras": extras as Any,
            "event": columnText(stmt, 19),
        ]
    }

    private func geofenceRowToMap(_ stmt: OpaquePointer) -> [String: Any] {
        let extrasStr = columnText(stmt, 8)
        let extras: [String: Any]? = extrasStr.isEmpty ? nil :
            (try? JSONSerialization.jsonObject(with: Data(extrasStr.utf8)) as? [String: Any])

        return [
            "identifier": columnText(stmt, 0),
            "latitude": sqlite3_column_double(stmt, 1),
            "longitude": sqlite3_column_double(stmt, 2),
            "radius": sqlite3_column_double(stmt, 3),
            "notifyOnEntry": sqlite3_column_int(stmt, 4) == 1,
            "notifyOnExit": sqlite3_column_int(stmt, 5) == 1,
            "notifyOnDwell": sqlite3_column_int(stmt, 6) == 1,
            "loiteringDelay": Int(sqlite3_column_int(stmt, 7)),
            "extras": extras as Any,
        ]
    }
}
