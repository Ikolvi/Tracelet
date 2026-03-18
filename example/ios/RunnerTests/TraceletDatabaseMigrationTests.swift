@testable import tracelet_ios
import SQLite3
import XCTest

/// Tests for ``TraceletDatabase`` migration — specifically the v3 → v4
/// addition of the `vertices` column to the `geofences` table.
///
/// Strategy: create a file-backed SQLite database with the old schema
/// (without `vertices`), insert data, close it, then open it via
/// `TraceletDatabase(path:)` which calls `createTables()` →
/// `migrateGeofencesTable()`. Verify the data survives and the new
/// column is usable.
final class TraceletDatabaseMigrationTests: XCTestCase {

    private var tempPath: String!

    override func setUp() {
        super.setUp()
        let tmpDir = NSTemporaryDirectory()
        tempPath = (tmpDir as NSString).appendingPathComponent("tracelet_migration_test_\(UUID().uuidString).db")
    }

    override func tearDown() {
        if let path = tempPath {
            try? FileManager.default.removeItem(atPath: path)
            // Also remove WAL/SHM files
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// Opens a raw sqlite3 database at `tempPath`, executes a block with the handle,
    /// then closes the database.
    private func withRawDatabase(_ block: (OpaquePointer) -> Void) {
        var rawDb: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempPath, &rawDb), SQLITE_OK, "Failed to open raw database")
        guard let db = rawDb else {
            XCTFail("Raw database pointer is nil")
            return
        }
        block(db)
        sqlite3_close(db)
    }

    /// Creates the v3 geofences table (WITHOUT `vertices` column).
    private func createV3GeofenceTable(_ db: OpaquePointer) {
        let sql = """
            CREATE TABLE geofences (
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
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK,
                       "Failed to create v3 geofences table")
    }

    /// Inserts a circular geofence into the raw database (v3 schema).
    private func insertRawCircularGeofence(_ db: OpaquePointer, identifier: String,
                                           latitude: Double, longitude: Double, radius: Double) {
        let sql = "INSERT INTO geofences (identifier, latitude, longitude, radius) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        sqlite3_bind_text(stmt, 1, (identifier as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, latitude)
        sqlite3_bind_double(stmt, 3, longitude)
        sqlite3_bind_double(stmt, 4, radius)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE, "Failed to insert raw geofence '\(identifier)'")
        sqlite3_finalize(stmt)
    }

    /// Checks whether the geofences table has a `vertices` column using PRAGMA table_info.
    private func hasVerticesColumn(_ db: OpaquePointer) -> Bool {
        var found = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(geofences)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(stmt, 1))
                if name == "vertices" {
                    found = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)
        return found
    }

    // MARK: - Migration Tests

    /// Verifies that opening a database with the old schema (no vertices column)
    /// through TraceletDatabase triggers migration and adds the column.
    func testMigration_addsVerticesColumn() {
        // Create old-schema database
        withRawDatabase { rawDb in
            createV3GeofenceTable(rawDb)
            XCTAssertFalse(hasVerticesColumn(rawDb), "v3 schema should NOT have vertices column")
        }

        // Open through TraceletDatabase — triggers migrateGeofencesTable()
        let db = TraceletDatabase(path: tempPath)

        // Verify the column was added by checking through a raw connection
        withRawDatabase { rawDb in
            XCTAssertTrue(hasVerticesColumn(rawDb), "Migration should add vertices column")
        }

        // Cleanup
        _ = db
    }

    /// Verifies that existing circular geofences survive the migration unchanged.
    func testMigration_preservesExistingCircularGeofences() {
        // Create old schema and insert a circular geofence
        withRawDatabase { rawDb in
            createV3GeofenceTable(rawDb)
            insertRawCircularGeofence(rawDb, identifier: "paris-fence",
                                      latitude: 48.8566, longitude: 2.3522, radius: 500.0)
        }

        // Open through TraceletDatabase — triggers migration
        let db = TraceletDatabase(path: tempPath)

        // Verify existing geofence survived
        let result = db.getGeofence("paris-fence")
        XCTAssertNotNil(result, "Existing geofence should survive migration")
        XCTAssertEqual(result?["identifier"] as? String, "paris-fence")
        XCTAssertEqual(result!["latitude"] as! Double, 48.8566, accuracy: 0.0001)
        XCTAssertEqual(result!["longitude"] as! Double, 2.3522, accuracy: 0.0001)
        XCTAssertEqual(result!["radius"] as! Double, 500.0, accuracy: 0.1)
        XCTAssertNil(result?["vertices"], "Pre-migration circular geofence should not have vertices")
    }

    /// Verifies that polygon geofences can be inserted after migration.
    func testMigration_allowsPolygonGeofenceAfterMigration() {
        // Create old schema
        withRawDatabase { rawDb in
            createV3GeofenceTable(rawDb)
        }

        // Open through TraceletDatabase — triggers migration
        let db = TraceletDatabase(path: tempPath)

        // Insert a polygon geofence
        let polygon: [String: Any] = [
            "identifier": "migrated-polygon",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 0.0,
            "vertices": [
                [37.78, -122.42],
                [37.77, -122.41],
                [37.76, -122.43],
            ] as [[Double]],
        ]
        XCTAssertTrue(db.insertGeofence(polygon))

        let result = db.getGeofence("migrated-polygon")
        XCTAssertNotNil(result)
        let v = result?["vertices"] as? [[Double]]
        XCTAssertNotNil(v, "Polygon vertices should persist after migration")
        XCTAssertEqual(v?.count, 3)
    }

    /// Verifies that multiple existing geofences all survive migration and
    /// a polygon can be inserted alongside them.
    func testMigration_multipleExistingGeofencesSurvive() {
        // Create old schema and insert multiple circular geofences
        withRawDatabase { rawDb in
            createV3GeofenceTable(rawDb)
            insertRawCircularGeofence(rawDb, identifier: "fence-a",
                                      latitude: 51.5074, longitude: -0.1278, radius: 100.0)
            insertRawCircularGeofence(rawDb, identifier: "fence-b",
                                      latitude: 35.6762, longitude: 139.6503, radius: 250.0)
            insertRawCircularGeofence(rawDb, identifier: "fence-c",
                                      latitude: -33.8688, longitude: 151.2093, radius: 750.0)
        }

        let db = TraceletDatabase(path: tempPath)

        // All three should survive
        let all = db.getGeofences()
        XCTAssertEqual(all.count, 3, "All 3 pre-migration geofences should survive")

        let identifiers = Set(all.compactMap { $0["identifier"] as? String })
        XCTAssertTrue(identifiers.contains("fence-a"))
        XCTAssertTrue(identifiers.contains("fence-b"))
        XCTAssertTrue(identifiers.contains("fence-c"))

        // Verify each geofence has no vertices
        for fence in all {
            XCTAssertNil(fence["vertices"], "Pre-migration geofences should not have vertices")
        }

        // Insert a polygon alongside them
        let polygon: [String: Any] = [
            "identifier": "polygon-after",
            "latitude": 0.0,
            "longitude": 0.0,
            "radius": 0.0,
            "vertices": [
                [0.01, 0.01],
                [0.02, 0.02],
                [0.03, 0.03],
            ] as [[Double]],
        ]
        XCTAssertTrue(db.insertGeofence(polygon))

        let updated = db.getGeofences()
        XCTAssertEqual(updated.count, 4, "Should have 3 circular + 1 polygon geofence")
    }

    /// Verifies that running migration on an already-migrated database
    /// (which already has the vertices column) is a no-op and doesn't cause errors.
    func testMigration_idempotent_doesNotFailOnSecondRun() {
        // First open — creates schema with vertices column
        _ = TraceletDatabase(path: tempPath)

        // Second open — migrateGeofencesTable() runs again, should be a no-op
        let db2 = TraceletDatabase(path: tempPath)

        // Insert and read a polygon to confirm the table is still functional
        let polygon: [String: Any] = [
            "identifier": "idempotent-test",
            "latitude": 10.0,
            "longitude": 20.0,
            "radius": 0.0,
            "vertices": [
                [10.01, 20.01],
                [10.02, 20.02],
                [10.03, 20.03],
            ] as [[Double]],
        ]
        XCTAssertTrue(db2.insertGeofence(polygon))

        let result = db2.getGeofence("idempotent-test")
        XCTAssertNotNil(result)
        XCTAssertNotNil(result?["vertices"] as? [[Double]])
    }

    /// Verifies fresh install (no pre-existing database) works correctly.
    func testFreshInstall_hasVerticesSupport() {
        let db = TraceletDatabase(path: tempPath)

        // Can insert both circular and polygon geofences
        let circular: [String: Any] = [
            "identifier": "fresh-circle",
            "latitude": 40.7128,
            "longitude": -74.0060,
            "radius": 300.0,
        ]
        XCTAssertTrue(db.insertGeofence(circular))

        let polygon: [String: Any] = [
            "identifier": "fresh-polygon",
            "latitude": 40.71,
            "longitude": -74.00,
            "radius": 0.0,
            "vertices": [
                [40.72, -74.01],
                [40.70, -74.02],
                [40.69, -73.99],
            ] as [[Double]],
        ]
        XCTAssertTrue(db.insertGeofence(polygon))

        let circResult = db.getGeofence("fresh-circle")
        XCTAssertNotNil(circResult)
        XCTAssertNil(circResult?["vertices"])

        let polyResult = db.getGeofence("fresh-polygon")
        XCTAssertNotNil(polyResult)
        let v = polyResult?["vertices"] as? [[Double]]
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.count, 3)
    }
}
