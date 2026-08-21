import XCTest
@testable import TraceletSDK

/// #402: the trip identity `TraceletTripManager` mints, and the trip-start edge
/// it now reports.
///
/// Note this is a *new* file rather than an addition to `AlgorithmTests.swift`:
/// that one is not listed in `Package.swift`'s `sources:`, so it never compiles
/// and never runs — which is why it still calls the type by its pre-rename name.
final class TripIdentityTests: XCTestCase {

    func testTripStartIsReportedWithAMintedId() {
        // Before #402 a trip only became observable once it was over.
        let tm = TraceletTripManager()
        var start: [String: Any?]?
        tm.onTripStart = { data in start = data }

        XCTAssertNil(tm.currentTripId)
        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)

        XCTAssertNotNil(start, "onTripStart did not fire")
        let tripId = start?["tripId"] as? String
        XCTAssertNotNil(tripId)
        XCTAssertFalse(tripId?.isEmpty ?? true)
        XCTAssertEqual(tm.currentTripId, tripId)
        XCTAssertNotNil(start?["startedAt"] as? Int64)
    }

    func testSummaryCarriesTheIdMintedAtStart() {
        let tm = TraceletTripManager()
        var ended: [String: Any?]?
        tm.onTripEnd = { data in ended = data }

        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)
        let startedId = tm.currentTripId
        tm.onMotionStateChanged(isMoving: false, latitude: 37.43, longitude: -122.07)

        XCTAssertNotNil(ended)
        XCTAssertEqual(
            ended?["tripId"] as? String,
            startedId,
            "the summary must be joinable to the records written during the trip"
        )
        XCTAssertNotNil(ended?["startedAt"] as? Int64, "absolute bounds accompany the summary")
        XCTAssertNotNil(ended?["endedAt"] as? Int64)
    }

    func testIdIsClearedAtEndAndNeverReused() {
        let tm = TraceletTripManager()

        tm.onMotionStateChanged(isMoving: true, latitude: 1.0, longitude: 1.0)
        let first = tm.currentTripId
        tm.onMotionStateChanged(isMoving: false, latitude: 1.1, longitude: 1.1)
        XCTAssertNil(tm.currentTripId, "the id must not survive trip end")

        tm.onMotionStateChanged(isMoving: true, latitude: 2.0, longitude: 2.0)
        let second = tm.currentTripId

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second, "a second journey was handed the first journey's id")
    }

    func testMotionChangeWithoutABoundaryReportsNothing() {
        let tm = TraceletTripManager()
        var startCount = 0
        var endCount = 0
        tm.onTripStart = { _ in startCount += 1 }
        tm.onTripEnd = { _ in endCount += 1 }

        tm.onMotionStateChanged(isMoving: false, latitude: 1.0, longitude: 1.0)
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(endCount, 0)

        tm.onMotionStateChanged(isMoving: true, latitude: 1.0, longitude: 1.0)
        tm.onMotionStateChanged(isMoving: true, latitude: 1.0, longitude: 1.0)
        XCTAssertEqual(startCount, 1, "moving while already moving is not a boundary")
    }

    func testResetDiscardsTheActiveTripId() {
        let tm = TraceletTripManager()
        var endCount = 0
        tm.onTripEnd = { _ in endCount += 1 }

        tm.onMotionStateChanged(isMoving: true, latitude: 1.0, longitude: 1.0)
        XCTAssertNotNil(tm.currentTripId)

        tm.reset()

        XCTAssertNil(tm.currentTripId, "reset must not leave a stale trip id")
        XCTAssertFalse(tm.isTripActive)
        XCTAssertEqual(endCount, 0, "a reset trip produces no summary")
    }
}
