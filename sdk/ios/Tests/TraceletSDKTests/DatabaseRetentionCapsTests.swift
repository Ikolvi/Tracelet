import XCTest
@testable import TraceletSDK

/// #361 — `maxDaysToPersist` / `maxRecordsToPersist` accepted but never enforced.
///
/// Both keys round-tripped and were then read by nothing, so `location_events`
/// grew without bound. Enforcement was real up to 3.0 via `pruneOldLocations` /
/// `enforceMaxRecords` on the Swift `TraceletDatabase`; `2afc926f` ("prepare for
/// 3.1.0") migrated the persist path onto the shared Rust core and deleted the
/// retention calls along with the body they lived in, leaving `insertCountSincePrune`
/// and a docstring behind as the only trace.
///
/// **Scope.** This suite covers the retention primitives across the FFI boundary
/// — that the regenerated Swift bindings resolve, and that the delete semantics
/// hold on a real iOS build rather than only in the Rust unit tests. It does not
/// cover `TraceletSdk.enforceRetentionCaps`, whose `rustDatabase` is
/// `public private(set)` and so cannot be injected from a test; that wiring is a
/// mirror of the Android one covered by `TraceletSdkRetentionCapsTest`, and is
/// verified end-to-end on device by the #361 example card.
final class DatabaseRetentionCapsTests: XCTestCase {

    private var db: DatabaseManager!
    private var dbPath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("retention_\(UUID().uuidString).db").path
        db = try DatabaseManager(dbPath: dbPath)
        try? db.setEncryptionKey(key: "")
        try? db.destroyLocations()
    }

    override func tearDownWithError() throws {
        try? db.destroyLocations()
        db = nil
        try? FileManager.default.removeItem(atPath: dbPath)
        try super.tearDownWithError()
    }

    /// Inserts a location whose fix time is `daysAgo` days in the past.
    private func insert(_ uuid: String, daysAgo: Double = 0) throws {
        let ts = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-daysAgo * 86_400)
        )
        _ = try db.insertLocation(
            uuid: uuid, lat: 37.7749, lng: -122.4194, acc: 8.0, speed: 0.0,
            heading: 0.0, altitude: 0.0, isMock: false, isMoving: false,
            activity: "unknown", activityConfidence: -1, routeContext: nil,
            timestampOverride: ts, eventType: "location", eventPayload: nil,
            address: nil
        )
    }

    /// The reporter's `maxDaysToPersist` case: a two-day-old fixture must not
    /// survive a one-day window, and a fresh fix must.
    func testPruneLocationsOlderThanDeletesOnlyAgedRows() throws {
        try insert("fresh")
        try insert("stale", daysAgo: 2)

        let removed = try db.pruneLocationsOlderThan(maxDays: 1)

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try db.getLocationsCount(), 1)
    }

    /// `-1` is the documented "unlimited" sentinel, and `ready()` resolves it
    /// onto the wire for every app that never set the key. Reading it as a cap
    /// of zero is the failure mode that would turn this fix into data loss.
    func testNonPositiveWindowsAreNoOps() throws {
        try insert("ancient", daysAgo: 999)

        XCTAssertEqual(try db.pruneLocationsOlderThan(maxDays: 0), 0)
        XCTAssertEqual(try db.pruneLocationsOlderThan(maxDays: -1), 0)
        XCTAssertEqual(try db.enforceMaxLocationRecords(maxRecords: 0), 0)
        XCTAssertEqual(try db.enforceMaxLocationRecords(maxRecords: -1), 0)

        XCTAssertEqual(try db.getLocationsCount(), 1)
    }

    /// The reporter's `maxRecordsToPersist: 3` case: the queue is capped and the
    /// oldest rows go first.
    func testEnforceMaxLocationRecordsKeepsTheNewest() throws {
        for i in 0..<5 {
            // Descending fix times, so the newest row by insertion order claims
            // to be the oldest — a timestamp-ordered cap would evict the wrong
            // rows. Insertion order is what decides.
            try insert("rec-\(i)", daysAgo: Double(4 - i))
        }

        let removed = try db.enforceMaxLocationRecords(maxRecords: 3)

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(try db.getLocationsCount(), 3)
        let kept = try db.getLocationsBatch(query: nil).compactMap { $0.uuid }
        XCTAssertTrue(kept.contains("rec-4"), "newest must survive: \(kept)")
        XCTAssertFalse(kept.contains("rec-0"), "oldest must go: \(kept)")
    }

    /// Retention must take the audit-chain rows with the locations, or it just
    /// moves the unbounded growth into a table with no cap of its own whose
    /// orphans nothing can reach.
    func testRetentionTakesTheAuditChainWithTheLocations() throws {
        try insert("aged", daysAgo: 5)
        try insert("kept")
        try db.insertAuditTrail(uuid: "aged", hash: "h1", prevHash: "genesis", index: 0)
        try db.insertAuditTrail(uuid: "kept", hash: "h2", prevHash: "h1", index: 1)

        _ = try db.pruneLocationsOlderThan(maxDays: 1)

        let chain = try db.getAuditTrail()
        XCTAssertEqual(chain.count, 1)
        XCTAssertEqual(chain.first?.uuid, "kept")
    }
}
