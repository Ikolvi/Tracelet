import Foundation
import SQLite3

/// SQLite database for persisting locations, geofences, and log entries.
///
/// Uses the sqlite3 C API directly. All write operations are serialized
/// on a dedicated serial queue for thread safety.
public final class TraceletDatabase {
    public static let shared = TraceletDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.tracelet.db", qos: .utility)

    private init() {
        openDatabase()
        createTables()
    }

    /// Internal initializer for testing — opens an in-memory SQLite database.
    /// Only accessible via `@testable import`.
    public init(inMemory: Bool) {
        if inMemory {
            if sqlite3_open(":memory:", &db) != SQLITE_OK {
                NSLog("[Tracelet] Failed to open in-memory database")
            }
        } else {
            openDatabase()
        }
        createTables()
    }

    /// Internal initializer for testing — opens a database at a specific file path.
    /// Useful for migration tests where a pre-populated database exists on disk.
    /// Only accessible via `@testable import`.
    public init(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("[Tracelet] Failed to open database at \(path)")
        }
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
                extras TEXT,
                vertices TEXT
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

        // Audit trail table (Enterprise)
        exec("""
            CREATE TABLE IF NOT EXISTS audit_trail (
                uuid TEXT PRIMARY KEY,
                hash TEXT NOT NULL,
                previous_hash TEXT NOT NULL,
                chain_index INTEGER NOT NULL UNIQUE,
                created_at TEXT DEFAULT (datetime('now'))
            )
        """)
        exec("""
            CREATE INDEX IF NOT EXISTS idx_audit_chain_index ON audit_trail(chain_index)
        """)

        // Privacy zones table (Enterprise)
        exec("""
            CREATE TABLE IF NOT EXISTS privacy_zones (
                identifier TEXT PRIMARY KEY,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                radius REAL NOT NULL,
                action INTEGER NOT NULL DEFAULT 0,
                degraded_accuracy REAL DEFAULT 1000.0
            )
        """)

        // Migrate existing geofences table — add vertices column if missing
        migrateGeofencesTable()
    }

    /// Adds the `vertices` column to the geofences table for existing installs.
    /// Uses PRAGMA table_info to check if the column already exists before altering.
    private func migrateGeofencesTable() {
        var hasVertices = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(geofences)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(stmt, 1))
                if name == "vertices" {
                    hasVertices = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)
        if !hasVertices {
            exec("ALTER TABLE geofences ADD COLUMN vertices TEXT")
        }
    }

    // MARK: - Location CRUD

    public func insertLocation(_ data: [String: Any]) -> String {
        let uuid = data["uuid"] as? String ?? Self.generateUUID()

        // Pre-compute JSON serialization outside the DB queue to avoid blocking
        // the serial queue during potentially slow encoding (I-H5).
        let coords = data["coords"] as? [String: Any] ?? data
        let activity = data["activity"] as? [String: Any]
        let battery = data["battery"] as? [String: Any]
        let extras = data["extras"] as? [String: Any]
        let extrasJson = extras.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { String(data: $0, encoding: .utf8) }

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

    public func getLocations(limit: Int = -1, offset: Int = 0, orderAsc: Bool = true, startTime: Int64? = nil, endTime: Int64? = nil) -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            let order = orderAsc ? "ASC" : "DESC"
            var conditions: [String] = []
            if startTime != nil { conditions.append("l.timestamp >= ?") }
            if endTime != nil { conditions.append("l.timestamp <= ?") }
            let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
            var sql = """
                SELECT l.*, a.hash AS audit_hash, a.previous_hash AS audit_previous_hash, a.chain_index AS audit_chain_index
                FROM locations l LEFT JOIN audit_trail a ON l.uuid = a.uuid
                \(whereClause) ORDER BY l.timestamp \(order)
            """
            if limit > 0 {
                sql += " LIMIT \(limit) OFFSET \(offset)"
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            var bindIndex: Int32 = 1
            if let start = startTime {
                sqlite3_bind_int64(stmt, bindIndex, start)
                bindIndex += 1
            }
            if let end = endTime {
                sqlite3_bind_int64(stmt, bindIndex, end)
                bindIndex += 1
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(locationRowToMap(stmt!))
            }
        }
        return results
    }

    public func getUnsyncedLocations(limit: Int = 100) -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            let sql = """
                SELECT l.*, a.hash AS audit_hash, a.previous_hash AS audit_previous_hash, a.chain_index AS audit_chain_index
                FROM locations l LEFT JOIN audit_trail a ON l.uuid = a.uuid
                WHERE l.synced = 0 ORDER BY l.timestamp ASC LIMIT ?
            """
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

    public func getLocationCount(startTime: Int64? = nil, endTime: Int64? = nil) -> Int {
        var count = 0
        queue.sync {
            var conditions: [String] = []
            if startTime != nil { conditions.append("timestamp >= ?") }
            if endTime != nil { conditions.append("timestamp <= ?") }
            let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
            let sql = "SELECT COUNT(*) FROM locations \(whereClause)"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            var bindIndex: Int32 = 1
            if let start = startTime {
                sqlite3_bind_int64(stmt, bindIndex, start)
                bindIndex += 1
            }
            if let end = endTime {
                sqlite3_bind_int64(stmt, bindIndex, end)
                bindIndex += 1
            }

            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        return count
    }

    /// Generates a UUID string using C-level functions directly.
    /// Avoids Foundation UUID struct + uppercase formatting overhead.
    private static func generateUUID() -> String {
        var uuid: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutablePointer(to: &uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                uuid_generate_random($0)
            }
        }
        var cString = [CChar](repeating: 0, count: 37)
        withUnsafePointer(to: uuid) {
            $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                uuid_unparse_lower($0, &cString)
            }
        }
        return String(cString: cString)
    }

    /// Max placeholders per chunked SQL statement. Keeps statement cache hits
    /// high and avoids SQLite's variable limit (default 999).
    private static let markSyncedChunkSize = 500

    public func markSynced(uuids: [String]) {
        guard !uuids.isEmpty else { return }
        queue.sync {
            var offset = 0
            while offset < uuids.count {
                let end = min(offset + Self.markSyncedChunkSize, uuids.count)
                let chunk = uuids[offset..<end]
                let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
                let sql = "UPDATE locations SET synced = 1 WHERE uuid IN (\(placeholders))"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    offset = end
                    continue
                }
                for (i, uuid) in chunk.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 1), nsString(uuid), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
                offset = end
            }
        }
    }

    public func deleteAllLocations() -> Bool {
        queue.sync {
            return exec("DELETE FROM locations")
        }
    }

    public func deleteLocation(_ uuid: String) -> Bool {
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

    /// Prune locations older than maxDays.
    public func pruneOldLocations(maxDays: Int) {
        guard maxDays > 0 else { return }
        queue.sync {
            let sql = "DELETE FROM locations WHERE created_at < datetime('now', '-\(maxDays) days')"
            exec(sql)
        }
    }

    /// Enforce max record count by deleting oldest records.
    public func enforceMaxRecords(maxRecords: Int) {
        guard maxRecords > 0 else { return }
        let count = getLocationCount()
        if count > maxRecords {
            let excess = count - maxRecords
            queue.sync {
                let sql = "DELETE FROM locations WHERE uuid IN (SELECT uuid FROM locations ORDER BY created_at ASC LIMIT \(excess))"
                exec(sql)
            }
        }
    }

    // MARK: - Geofence CRUD

    public func insertGeofence(_ data: [String: Any]) -> Bool {
        var success = false
        queue.sync {
            success = _insertGeofenceUnsync(data)
        }
        return success
    }

    /// Internal geofence insert without queue synchronization.
    /// Caller must already be on `queue`.
    private func _insertGeofenceUnsync(_ data: [String: Any]) -> Bool {
            let sql = """
                INSERT OR REPLACE INTO geofences
                (identifier, latitude, longitude, radius, notify_on_entry, notify_on_exit,
                 notify_on_dwell, loitering_delay, extras, vertices)
                VALUES (?,?,?,?,?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
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

            // Serialize vertices as JSON: [[lat,lng],[lat,lng],...]
            if let verticesRaw = data["vertices"] as? [Any], !verticesRaw.isEmpty {
                var verticesArray: [[Double]] = []
                for item in verticesRaw {
                    guard let vertex = item as? [Any], vertex.count >= 2,
                          let lat = (vertex[0] as? NSNumber)?.doubleValue,
                          let lng = (vertex[1] as? NSNumber)?.doubleValue else {
                        continue
                    }
                    verticesArray.append([lat, lng])
                }
                if verticesArray.count >= 3,
                   let verticesData = try? JSONSerialization.data(withJSONObject: verticesArray),
                   let verticesJson = String(data: verticesData, encoding: .utf8) {
                    sqlite3_bind_text(stmt, 10, nsString(verticesJson), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, 10)
                }
            } else {
                sqlite3_bind_null(stmt, 10)
            }

            return sqlite3_step(stmt) == SQLITE_DONE
    }

    /// Batch-inserts geofences within a single transaction (I-H3).
    /// Avoids N separate fsyncs for N geofences.
    public func insertGeofencesBatch(_ geofences: [[String: Any]]) -> Bool {
        guard !geofences.isEmpty else { return true }
        var success = true
        queue.sync {
            exec("BEGIN TRANSACTION")
            for g in geofences {
                if !_insertGeofenceUnsync(g) { success = false }
            }
            exec("COMMIT")
        }
        return success
    }

    public func getGeofences() -> [[String: Any]] {
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

    public func getGeofence(_ identifier: String) -> [String: Any]? {
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

    public func geofenceExists(_ identifier: String) -> Bool {
        return getGeofence(identifier) != nil
    }

    public func deleteGeofence(_ identifier: String) -> Bool {
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

    public func deleteAllGeofences() -> Bool {
        queue.sync {
            return exec("DELETE FROM geofences")
        }
    }

    // MARK: - Log CRUD

    public func insertLog(level: String, message: String, source: String = "plugin") {
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

    public func getLogs(query: [String: Any]? = nil) -> [[String: Any]] {
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

    public func getLogForEmail() -> String {
        let logs = getLogs(query: ["limit": 2000])
        return logs.map { "[\($0["timestamp"] ?? "")] [\($0["level"] ?? "")] \($0["message"] ?? "")" }
            .joined(separator: "\n")
    }

    public func pruneOldLogs(maxDays: Int) {
        queue.sync {
            let sql = "DELETE FROM logs WHERE timestamp < datetime('now', '-\(maxDays) days')"
            exec(sql)
        }
    }

    public func deleteAllLogs() -> Bool {
        queue.sync {
            return exec("DELETE FROM logs")
        }
    }

    // MARK: - Audit Trail CRUD

    /// Insert an audit trail record.
    public func insertAuditRecord(uuid: String, hash: String, previousHash: String, chainIndex: Int) {
        queue.sync {
            let sql = """
                INSERT OR REPLACE INTO audit_trail (uuid, hash, previous_hash, chain_index)
                VALUES (?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                NSLog("[Tracelet] insertAuditRecord prepare failed: \(lastError())")
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, nsString(uuid), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, nsString(hash), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 3, nsString(previousHash), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(stmt, 4, Int32(chainIndex))

            if sqlite3_step(stmt) != SQLITE_DONE {
                NSLog("[Tracelet] insertAuditRecord step failed: \(lastError())")
            }
        }
    }

    /// Get all audit trail records ordered by chain_index ASC.
    public func getAuditTrail() -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            let sql = "SELECT uuid, hash, previous_hash, chain_index, created_at FROM audit_trail ORDER BY chain_index ASC"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append([
                    "uuid": columnText(stmt, 0),
                    "hash": columnText(stmt, 1),
                    "previous_hash": columnText(stmt, 2),
                    "chain_index": Int(sqlite3_column_int(stmt, 3)),
                    "created_at": columnText(stmt, 4),
                ])
            }
        }
        return results
    }

    /// Get a single audit record by UUID, including the location's timestamp.
    public func getAuditRecord(uuid: String) -> [String: Any]? {
        var result: [String: Any]?
        queue.sync {
            let sql = """
                SELECT a.uuid, a.hash, a.previous_hash, a.chain_index, a.created_at, l.timestamp
                FROM audit_trail a LEFT JOIN locations l ON a.uuid = l.uuid
                WHERE a.uuid = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, nsString(uuid), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = [
                    "uuid": columnText(stmt, 0),
                    "hash": columnText(stmt, 1),
                    "previous_hash": columnText(stmt, 2),
                    "chain_index": Int(sqlite3_column_int(stmt, 3)),
                    "timestamp": columnText(stmt, 5),
                ]
            }
        }
        return result
    }

    /// Get a flat location map suitable for hash re-computation during verification.
    ///
    /// Returns a dict with top-level keys: uuid, timestamp, latitude, longitude,
    /// altitude, speed, heading, accuracy, odometer, is_moving. This matches
    /// the canonical format expected by `AuditTrailManager.buildCanonicalString`.
    public func getLocationForAudit(uuid: String) -> [String: Any]? {
        var result: [String: Any]?
        queue.sync {
            let sql = """
                SELECT uuid, timestamp, latitude, longitude, altitude, speed, heading,
                       accuracy, odometer, is_moving
                FROM locations WHERE uuid = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, nsString(uuid), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = [
                    "uuid": columnText(stmt, 0),
                    "timestamp": columnText(stmt, 1),
                    "latitude": sqlite3_column_double(stmt, 2),
                    "longitude": sqlite3_column_double(stmt, 3),
                    "altitude": sqlite3_column_double(stmt, 4),
                    "speed": sqlite3_column_double(stmt, 5),
                    "heading": sqlite3_column_double(stmt, 6),
                    "accuracy": sqlite3_column_double(stmt, 7),
                    "odometer": sqlite3_column_double(stmt, 8),
                    "is_moving": sqlite3_column_int(stmt, 9) == 1,
                ]
            }
        }
        return result
    }

    /// Delete all audit trail records.
    @discardableResult
    public func deleteAllAuditRecords() -> Bool {
        queue.sync {
            return exec("DELETE FROM audit_trail")
        }
    }

    // MARK: - Privacy Zone CRUD

    /// Inserts or replaces a privacy zone.
    @discardableResult
    public func insertPrivacyZone(_ data: [String: Any]) -> Bool {
        var success = false
        queue.sync {
            let sql = """
                INSERT OR REPLACE INTO privacy_zones
                (identifier, latitude, longitude, radius, action, degraded_accuracy)
                VALUES (?,?,?,?,?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let identifier = data["identifier"] as? String ?? ""
            let lat = (data["latitude"] as? NSNumber)?.doubleValue ?? 0.0
            let lng = (data["longitude"] as? NSNumber)?.doubleValue ?? 0.0
            let radius = (data["radius"] as? NSNumber)?.doubleValue ?? 200.0
            let action = (data["action"] as? NSNumber)?.intValue ?? 0
            let degradedAccuracy = (data["degradedAccuracyMeters"] as? NSNumber)?.doubleValue ?? 1000.0

            sqlite3_bind_text(stmt, 1, nsString(identifier), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(stmt, 2, lat)
            sqlite3_bind_double(stmt, 3, lng)
            sqlite3_bind_double(stmt, 4, radius)
            sqlite3_bind_int(stmt, 5, Int32(action))
            sqlite3_bind_double(stmt, 6, degradedAccuracy)

            success = sqlite3_step(stmt) == SQLITE_DONE
        }
        return success
    }

    /// Retrieves all privacy zones.
    public func getPrivacyZones() -> [[String: Any]] {
        var results: [[String: Any]] = []
        queue.sync {
            let sql = "SELECT * FROM privacy_zones"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(privacyZoneRowToMap(stmt!))
            }
        }
        return results
    }

    /// Deletes a privacy zone by identifier.
    @discardableResult
    public func deletePrivacyZone(_ identifier: String) -> Bool {
        var success = false
        queue.sync {
            let sql = "DELETE FROM privacy_zones WHERE identifier = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, nsString(identifier), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            success = sqlite3_step(stmt) == SQLITE_DONE
        }
        return success
    }

    /// Deletes all privacy zones.
    @discardableResult
    public func deleteAllPrivacyZones() -> Bool {
        queue.sync {
            return exec("DELETE FROM privacy_zones")
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

    /// Cached ISO 8601 formatter — creating one per call is expensive.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func iso8601Now() -> String {
        return TraceletDatabase.isoFormatter.string(from: Date())
    }

    private func locationRowToMap(_ stmt: OpaquePointer) -> [String: Any] {
        let extrasStr = columnText(stmt, 18)
        let extras: [String: Any]? = extrasStr.isEmpty ? nil :
            (try? JSONSerialization.jsonObject(with: Data(extrasStr.utf8)) as? [String: Any])

        var map: [String: Any] = [
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

        // Append audit fields from LEFT JOIN (columns 22, 23, 24)
        // locations has 22 columns (0-21), audit columns start at 22
        let colCount = sqlite3_column_count(stmt)
        if colCount > 22 {
            if sqlite3_column_type(stmt, 22) != SQLITE_NULL {
                map["audit_hash"] = columnText(stmt, 22)
            }
            if sqlite3_column_type(stmt, 23) != SQLITE_NULL {
                map["audit_previous_hash"] = columnText(stmt, 23)
            }
            if sqlite3_column_type(stmt, 24) != SQLITE_NULL {
                map["audit_chain_index"] = Int(sqlite3_column_int(stmt, 24))
            }
        }

        return map
    }

    private func geofenceRowToMap(_ stmt: OpaquePointer) -> [String: Any] {
        let extrasStr = columnText(stmt, 8)
        let extras: [String: Any]? = extrasStr.isEmpty ? nil :
            (try? JSONSerialization.jsonObject(with: Data(extrasStr.utf8)) as? [String: Any])

        // Parse vertices from JSON, casting through NSNumber for correct bridging
        let verticesStr = columnText(stmt, 9)
        var vertices: [[Double]]? = nil
        if !verticesStr.isEmpty {
            if let verticesData = verticesStr.data(using: .utf8),
               let rawVertices = try? JSONSerialization.jsonObject(with: verticesData) as? [[NSNumber]] {
                let parsed = rawVertices.map { $0.map { $0.doubleValue } }
                if parsed.count >= 3 {
                    vertices = parsed
                }
            }
        }

        var map: [String: Any] = [
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
        if let vertices = vertices {
            map["vertices"] = vertices
        }
        return map
    }

    private func privacyZoneRowToMap(_ stmt: OpaquePointer) -> [String: Any] {
        return [
            "identifier": columnText(stmt, 0),
            "latitude": sqlite3_column_double(stmt, 1),
            "longitude": sqlite3_column_double(stmt, 2),
            "radius": sqlite3_column_double(stmt, 3),
            "action": Int(sqlite3_column_int(stmt, 4)),
            "degradedAccuracyMeters": sqlite3_column_double(stmt, 5),
        ]
    }
}
