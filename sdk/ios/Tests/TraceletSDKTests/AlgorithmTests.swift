import XCTest
@testable import TraceletSDK

final class AlgorithmTests: XCTestCase {

    // MARK: - GeoUtils

    func testHaversineZeroDistance() {
        let d = GeoUtils.haversine(37.422, -122.084, 37.422, -122.084)
        XCTAssertEqual(d, 0, accuracy: 0.01)
    }

    func testHaversineKnownDistance() {
        // ~157m between two nearby points
        let d = GeoUtils.haversine(37.421, -122.084, 37.422, -122.083)
        XCTAssertGreaterThan(d, 100)
        XCTAssertLessThan(d, 200)
    }

    func testHaversineLongDistance() {
        // SF to NYC ≈ 4,130 km
        let d = GeoUtils.haversine(37.7749, -122.4194, 40.7128, -74.0060)
        XCTAssertGreaterThan(d, 4_000_000)
        XCTAssertLessThan(d, 4_200_000)
    }

    func testPointInPolygonInside() {
        let square: [[Double]] = [
            [37.421, -122.085],
            [37.423, -122.085],
            [37.423, -122.083],
            [37.421, -122.083],
        ]
        XCTAssertTrue(GeoUtils.isPointInPolygon(
            lat: 37.422, lng: -122.084, vertices: square))
    }

    func testPointInPolygonOutside() {
        let square: [[Double]] = [
            [37.421, -122.085],
            [37.423, -122.085],
            [37.423, -122.083],
            [37.421, -122.083],
        ]
        XCTAssertFalse(GeoUtils.isPointInPolygon(
            lat: 37.420, lng: -122.086, vertices: square))
    }

    func testPointInPolygonDegenerateVertices() {
        // Fewer than 3 vertices
        XCTAssertFalse(GeoUtils.isPointInPolygon(
            lat: 0, lng: 0, vertices: [[0, 0], [1, 1]]))
    }

    // MARK: - KalmanLocationFilter

    func testKalmanInitialMeasurementPassesThrough() {
        let kalman = KalmanLocationFilter()
        XCTAssertFalse(kalman.isInitialized)
        let result = kalman.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 16.0, timestampMs: 1000)
        XCTAssertTrue(kalman.isInitialized)
        XCTAssertEqual(result.latitude, 37.422)
        XCTAssertEqual(result.longitude, -122.084)
    }

    func testKalmanSecondMeasurementSmooths() {
        let kalman = KalmanLocationFilter()
        _ = kalman.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 16.0, timestampMs: 1000)
        // Second point very close — output should be between input and first
        let result = kalman.process(
            latitude: 37.4221, longitude: -122.0839,
            accuracy: 16.0, timestampMs: 2000)
        XCTAssertGreaterThanOrEqual(result.latitude, 37.422)
        XCTAssertLessThanOrEqual(result.latitude, 37.4221)
    }

    func testKalmanDuplicateTimestampReturnsLastState() {
        let kalman = KalmanLocationFilter()
        _ = kalman.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 16.0, timestampMs: 1000)
        let r1 = kalman.process(
            latitude: 37.423, longitude: -122.083,
            accuracy: 16.0, timestampMs: 2000)
        // Same timestamp should return the state without update
        let r2 = kalman.process(
            latitude: 37.424, longitude: -122.082,
            accuracy: 16.0, timestampMs: 2000)
        XCTAssertEqual(r1.latitude, r2.latitude, accuracy: 1e-10)
        XCTAssertEqual(r1.longitude, r2.longitude, accuracy: 1e-10)
    }

    func testKalmanReset() {
        let kalman = KalmanLocationFilter()
        _ = kalman.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 16.0, timestampMs: 1000)
        XCTAssertTrue(kalman.isInitialized)
        kalman.reset()
        XCTAssertFalse(kalman.isInitialized)
    }

    func testKalmanEstimatedSpeedAfterMovement() {
        let kalman = KalmanLocationFilter()
        _ = kalman.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 10.0, timestampMs: 0)
        // Move ~111m north over 10 seconds
        _ = kalman.process(
            latitude: 37.423, longitude: -122.084,
            accuracy: 10.0, timestampMs: 10000)
        XCTAssertGreaterThan(kalman.estimatedSpeed, 0)
    }

    // MARK: - LocationProcessor

    func testProcessorFirstLocationAlwaysAccepted() {
        let proc = LocationProcessor(distanceFilter: 100)
        let result = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        XCTAssertTrue(result.accepted)
    }

    func testProcessorDistanceFilterRejectsClose() {
        let proc = LocationProcessor(distanceFilter: 100)
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        // ~11m away, below 100m threshold
        let result = proc.process(
            latitude: 37.4221, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 2000)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.reason, "DISTANCE_FILTER")
    }

    func testProcessorDistanceFilterAcceptsFar() {
        let proc = LocationProcessor(distanceFilter: 10)
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        // ~222m away, well above 10m threshold
        let result = proc.process(
            latitude: 37.424, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 2000)
        XCTAssertTrue(result.accepted)
        XCTAssertGreaterThan(result.distance, 0)
    }

    func testProcessorAccuracyFilterDiscard() {
        let proc = LocationProcessor(
            distanceFilter: 0,
            trackingAccuracyThreshold: 50,
            filterPolicy: 2  // discard
        )
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        let result = proc.process(
            latitude: 37.424, longitude: -122.082,
            accuracy: 100, speed: 0, timestampMs: 2000)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.reason, "ACCURACY_FILTER")
        XCTAssertTrue(result.isError)
        XCTAssertNotNil(result.errorMessage)
    }

    func testProcessorAccuracyFilterIgnore() {
        let proc = LocationProcessor(
            distanceFilter: 0,
            trackingAccuracyThreshold: 50,
            filterPolicy: 1  // ignore
        )
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        let result = proc.process(
            latitude: 37.424, longitude: -122.082,
            accuracy: 100, speed: 0, timestampMs: 2000)
        XCTAssertFalse(result.accepted)
        XCTAssertFalse(result.isError)
    }

    func testProcessorSpeedFilterRejects() {
        let proc = LocationProcessor(
            distanceFilter: 0,
            maxImpliedSpeed: 10  // 10 m/s
        )
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        // ~4.4km in 1 second = 4400 m/s — way above 10 m/s
        let result = proc.process(
            latitude: 37.462, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 2000)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.reason, "SPEED_FILTER")
    }

    func testProcessorMockLocationRejected() {
        let proc = LocationProcessor(
            distanceFilter: 0,
            rejectMockLocations: true
        )
        let result = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000, isMock: true)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.reason, "MOCK_LOCATION")
    }

    func testProcessorMockTimestampMonotonic() {
        let proc = LocationProcessor(
            distanceFilter: 0,
            rejectMockLocations: true,
            mockDetectionLevel: 2
        )
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 5000)
        // Time goes backward
        let result = proc.process(
            latitude: 37.424, longitude: -122.082,
            accuracy: 5, speed: 0, timestampMs: 3000)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.reason, "MOCK_LOCATION_TIMESTAMP")
    }

    func testProcessorOdometerGating() {
        let proc = LocationProcessor(
            distanceFilter: 0,
            odometerAccuracyThreshold: 20
        )
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        // Good accuracy — odometer counts
        let good = proc.process(
            latitude: 37.424, longitude: -122.084,
            accuracy: 10, speed: 0, timestampMs: 2000)
        XCTAssertTrue(good.accepted)
        XCTAssertGreaterThan(good.odometerDelta, 0)

        // Bad accuracy — accepted but odometer doesn't count
        let bad = proc.process(
            latitude: 37.426, longitude: -122.084,
            accuracy: 50, speed: 0, timestampMs: 3000)
        XCTAssertTrue(bad.accepted)
        XCTAssertEqual(bad.odometerDelta, 0)
    }

    func testProcessorReset() {
        let proc = LocationProcessor(distanceFilter: 10)
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        XCTAssertTrue(proc.hasLastLocation)
        proc.reset()
        XCTAssertFalse(proc.hasLastLocation)
    }

    func testProcessorSparseFilter() {
        let proc = LocationProcessor(
            distanceFilter: 0,
            enableSparseUpdates: true,
            sparseDistanceThreshold: 50,
            sparseMaxIdleSeconds: 300
        )
        // First location accepted
        let r1 = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        XCTAssertTrue(r1.accepted)

        // Very close location within timeout — filtered
        let r2 = proc.process(
            latitude: 37.4221, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 5000)
        XCTAssertFalse(r2.accepted)
        XCTAssertEqual(r2.reason, "SPARSE_FILTER")
    }

    // MARK: - AdaptiveSamplingEngine

    func testAdaptiveStaticSource() {
        let engine = AdaptiveSamplingEngine(baseDistanceFilter: 10)
        let result = engine.compute(AdaptiveContext(speed: 0))
        XCTAssertEqual(result.source, .static)
        XCTAssertEqual(result.effectiveDistanceFilter, 10)
    }

    func testAdaptiveSpeedSource() {
        let engine = AdaptiveSamplingEngine(baseDistanceFilter: 10)
        let result = engine.compute(AdaptiveContext(speed: 20))
        XCTAssertEqual(result.source, .speed)
        XCTAssertGreaterThan(result.effectiveDistanceFilter, 10)
    }

    func testAdaptiveActivitySource() {
        let engine = AdaptiveSamplingEngine(baseDistanceFilter: 10)
        let result = engine.compute(AdaptiveContext(
            activityType: .inVehicle,
            activityConfidence: .high,
            speed: 20
        ))
        XCTAssertEqual(result.source, .activity)
    }

    func testAdaptiveBatteryScaling() {
        let engine = AdaptiveSamplingEngine(baseDistanceFilter: 10)
        let full = engine.compute(AdaptiveContext(batteryLevel: 0.8))
        let low = engine.compute(AdaptiveContext(batteryLevel: 0.05))
        // Low battery should produce a larger distance filter
        XCTAssertGreaterThan(
            low.effectiveDistanceFilter,
            full.effectiveDistanceFilter
        )
    }

    func testAdaptiveBatteryNoScalingWhenCharging() {
        let engine = AdaptiveSamplingEngine(baseDistanceFilter: 10)
        let charging = engine.compute(AdaptiveContext(
            batteryLevel: 0.05, isCharging: true))
        let full = engine.compute(AdaptiveContext(batteryLevel: 0.8))
        XCTAssertEqual(
            charging.effectiveDistanceFilter,
            full.effectiveDistanceFilter
        )
    }

    func testAdaptiveWalkingProfile() {
        let engine = AdaptiveSamplingEngine(baseDistanceFilter: 10)
        let result = engine.compute(AdaptiveContext(
            activityType: .walking,
            activityConfidence: .medium
        ))
        // Walking target is 50m, base is 10m → factor 5.0
        XCTAssertEqual(result.activityFactor, 5.0, accuracy: 0.01)
    }

    func testAdaptiveStillProfile() {
        let engine = AdaptiveSamplingEngine(baseDistanceFilter: 10)
        let result = engine.compute(AdaptiveContext(
            activityType: .still,
            activityConfidence: .high
        ))
        // Still target is 500m, base is 10m → factor 50.0
        XCTAssertEqual(result.activityFactor, 50.0, accuracy: 0.01)
    }

    func testAdaptiveLowConfidenceFallsBackToSpeed() {
        let engine = AdaptiveSamplingEngine(baseDistanceFilter: 10)
        let result = engine.compute(AdaptiveContext(
            activityType: .walking,
            activityConfidence: .low,
            speed: 5
        ))
        // Low confidence should not use activity → falls back to speed
        XCTAssertEqual(result.source, .speed)
    }

    // MARK: - LocationProcessor + Elasticity

    func testProcessorElasticityScalesWithSpeed() {
        let proc = LocationProcessor(distanceFilter: 10)
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        // ~222m away, with high speed
        let result = proc.process(
            latitude: 37.424, longitude: -122.084,
            accuracy: 5, speed: 50, timestampMs: 2000)
        // High speed should increase effective distance, but 222m should
        // still clear it at speed=50 (factor = min(50/10,10)=5 → 50m)
        XCTAssertTrue(result.accepted)
    }

    func testProcessorDisabledElasticity() {
        let proc = LocationProcessor(
            distanceFilter: 10,
            disableElasticity: true
        )
        _ = proc.process(
            latitude: 37.422, longitude: -122.084,
            accuracy: 5, speed: 0, timestampMs: 1000)
        // 15m away, above base 10m
        let result = proc.process(
            latitude: 37.42214, longitude: -122.084,
            accuracy: 5, speed: 50, timestampMs: 2000)
        // With elasticity disabled, 15m > 10m should pass
        XCTAssertTrue(result.accepted)
    }
}
