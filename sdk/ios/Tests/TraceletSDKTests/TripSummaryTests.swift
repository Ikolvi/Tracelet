import XCTest

@testable import TraceletSDK

/// #401: a completed trip produces exactly one summary, carrying the id its
/// locations were stamped with; it is stored once, offered until a successful
/// flush marks it, and serialized in the payload shape both platforms share.
final class TripSummaryTests: XCTestCase {

    private var dbPath: String!
    private var db: DatabaseManager!

    override func setUpWithError() throws {
        dbPath = NSTemporaryDirectory() + "trip-summary-\(UUID().uuidString).db"
        db = try DatabaseManager(dbPath: dbPath)
    }

    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func driveOneTrip(_ manager: TraceletTripManager) -> String? {
        manager.onMotionStateChanged(isMoving: true, latitude: 24.81, longitude: 67.05)
        let tripId = manager.currentTripId
        manager.onLocationReceived(latitude: 24.83, longitude: 67.03)
        manager.onMotionStateChanged(isMoving: false, latitude: 24.8607, longitude: 67.0011)
        return tripId
    }

    func testTheSummaryHookFiresOnceWithTheTripsId() throws {
        let manager = TraceletTripManager()
        var summaries: [TripData] = []
        var endEvents = 0
        manager.onTripSummary = { summaries.append($0) }
        manager.onTripEnd = { _ in endEvents += 1 }

        let tripId = try XCTUnwrap(driveOneTrip(manager))

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(endEvents, 1)
        XCTAssertEqual(summaries.first?.tripId, tripId)
        XCTAssertGreaterThan(summaries.first?.distanceMeters ?? 0, 0)
    }

    func testATripIsStoredOnceAndSettledOnlyWhenMarked() throws {
        let manager = TraceletTripManager()
        var summary: TripData?
        manager.onTripSummary = { summary = $0 }
        _ = driveOneTrip(manager)
        let trip = try XCTUnwrap(summary)

        XCTAssertTrue(try db.insertTrip(trip: trip))
        XCTAssertFalse(try db.insertTrip(trip: trip), "a trip is recorded exactly once")

        let pending = try db.getUnsyncedTrips(limit: 10)
        XCTAssertEqual(pending.map { $0.tripId }, [trip.tripId])

        try db.markTripsSynced(maxId: try XCTUnwrap(pending.first?.id))
        XCTAssertTrue(try db.getUnsyncedTrips(limit: 10).isEmpty)
        XCTAssertEqual(try db.getTrips(limit: 10).first?.synced, true, "marked, not deleted")
    }

    func testThePayloadShapeIsShared() throws {
        let manager = TraceletTripManager()
        var summary: TripData?
        manager.onTripSummary = { summary = $0 }
        _ = driveOneTrip(manager)
        _ = try db.insertTrip(trip: try XCTUnwrap(summary))

        let json = tripsSyncJson(trips: try db.getUnsyncedTrips(limit: 10))
        let list = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let item = try XCTUnwrap(list.first)
        XCTAssertEqual(item["trip_id"] as? String, summary?.tripId)
        XCTAssertNotNil(item["started_at"] as? String)
        XCTAssertEqual((item["start_location"] as? [String: Any])?["latitude"] as? Double, 24.81)
        XCTAssertEqual(item["synced"] as? Bool, false)
    }
}
