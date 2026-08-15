import XCTest

@testable import TraceletSDK

/// #387 — `setOdometer()` must move the anchor, not just the total.
///
/// Distance is accumulated in the Rust `LocationProcessor`, which keeps its own
/// odometer anchor, separate from the tracking one, and advances it on every fix
/// that passes the accuracy gate. `setOdometer` wrote `stateManager.odometer`
/// and nothing else, so the next accepted fix added the whole span since the
/// previous one and the value the caller had just set survived exactly one fix.
///
/// The visible form is the common "reset to zero, then start tracking": the
/// phantom leg is however far the device was carried while untracked, booked
/// against the new trip.
///
/// Exercised at the processor rather than through `LocationEngine.setOdometer`,
/// which needs a live CoreLocation delegate to drive fixes; the engine's part is
/// the one-line call, and its Android twin is covered end to end by
/// `LocationEngineSetOdometerAnchorTest` — the same split
/// `DatabaseRetentionCapsTests` documents for #361.
final class LocationProcessorOdometerAnchorTests: XCTestCase {

    /// Metres per degree of latitude, so fixes below can be spaced in metres.
    private let metresPerDegree = 111_320.0
    private let baseLat = 52.0
    private let baseLng = 13.0

    private func makeProcessor() -> LocationProcessor {
        LocationProcessor(
            distanceFilter: 10,
            disableElasticity: true,
            elasticityMultiplier: 1,
            enableAdaptiveMode: false,
            trackingAccuracyThreshold: 0,
            filterPolicy: 0,
            maxImpliedSpeed: 80,
            odometerAccuracyThreshold: 0,
            rejectMockLocations: false,
            mockDetectionLevel: 0,
            enableSparseUpdates: false,
            sparseDistanceThreshold: 0,
            sparseMaxIdleSeconds: 0
        )
    }

    /// A fix `metres` north of the base point, `secondsIn` into the run.
    @discardableResult
    private func fix(
        _ processor: LocationProcessor, metres: Double, secondsIn: Int64
    ) -> LocationProcessorResult {
        processor.process(
            latitude: baseLat + metres / metresPerDegree,
            longitude: baseLng,
            accuracy: 5,
            speed: 0,
            timestampMs: 1_760_000_000_000 + secondsIn * 1_000,
            isMock: false,
            adaptiveContext: nil
        )
    }

    func testTheFixAfterAResetContributesNoDistance() {
        let p = makeProcessor()
        XCTAssertTrue(fix(p, metres: 0, secondsIn: 0).accepted)
        let moved = fix(p, metres: 100, secondsIn: 20)
        XCTAssertEqual(moved.odometerDelta, 100, accuracy: 2, "precondition: ordinary accumulation")

        // "This trip starts now, at zero."
        p.resetOdometerAnchor()

        let after = fix(p, metres: 200, secondsIn: 40)
        XCTAssertTrue(after.accepted, "the fix is still recorded — only its distance is dropped")
        XCTAssertEqual(
            after.odometerDelta, 0,
            "the first fix after a reset has nothing to measure from, exactly as the "
                + "first fix of a fresh processor has")

        XCTAssertEqual(
            fix(p, metres: 300, secondsIn: 60).odometerDelta, 100, accuracy: 2,
            "distance travelled since the reset must still be counted")
    }

    func testResettingTheAnchorDoesNotChangeWhichFixesAreRecorded() {
        // The distinction that makes this a separate call from `reset()`: the
        // tracking anchor decides whether the next fix clears the distance
        // filter, so setting a counter must not start recording fixes that were
        // being dropped.
        let p = makeProcessor()
        XCTAssertTrue(fix(p, metres: 0, secondsIn: 0).accepted)

        p.resetOdometerAnchor()

        let tooClose = fix(p, metres: 1, secondsIn: 20)
        XCTAssertFalse(tooClose.accepted)
        XCTAssertEqual(tooClose.reason, "DISTANCE_FILTER")
    }
}
