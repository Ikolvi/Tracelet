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

    // MARK: - TripManager

    func testTripStartsOnMovingTransition() {
        let tm = TripManager()
        XCTAssertFalse(tm.isTripActive)
        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)
        XCTAssertTrue(tm.isTripActive)
    }

    func testTripEndsOnStationaryTransition() {
        let tm = TripManager()
        var tripData: [String: Any?]?
        tm.onTripEnd = { data in tripData = data }

        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)
        tm.onMotionStateChanged(isMoving: false, latitude: 37.43, longitude: -122.07)

        XCTAssertFalse(tm.isTripActive)
        XCTAssertNotNil(tripData)
        XCTAssertEqual(tripData?["isMoving"] as? Bool, false)
    }

    func testTripCollectsStartAndStopLocations() {
        let tm = TripManager()
        var tripData: [String: Any?]?
        tm.onTripEnd = { data in tripData = data }

        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)
        tm.onMotionStateChanged(isMoving: false, latitude: 37.43, longitude: -122.07)

        let start = tripData?["startLocation"] as? [String: Any?]
        let stop = tripData?["stopLocation"] as? [String: Any?]
        XCTAssertEqual(start?["latitude"] as? Double, 37.42)
        XCTAssertEqual(start?["longitude"] as? Double, -122.08)
        XCTAssertEqual(stop?["latitude"] as? Double, 37.43)
        XCTAssertEqual(stop?["longitude"] as? Double, -122.07)
    }

    func testTripAccumulatesDistance() {
        let tm = TripManager()
        var tripData: [String: Any?]?
        tm.onTripEnd = { data in tripData = data }

        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)
        tm.onLocationReceived(latitude: 37.421, longitude: -122.079)
        tm.onLocationReceived(latitude: 37.422, longitude: -122.078)
        tm.onMotionStateChanged(isMoving: false, latitude: 37.423, longitude: -122.077)

        let distance = tripData?["distance"] as? Double ?? 0
        XCTAssertGreaterThan(distance, 0)
    }

    func testTripIgnoresLocationsWhenInactive() {
        let tm = TripManager()
        tm.onLocationReceived(latitude: 37.42, longitude: -122.08) // No trip active
        XCTAssertFalse(tm.isTripActive)
    }

    func testTripResetClearsState() {
        let tm = TripManager()
        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)
        XCTAssertTrue(tm.isTripActive)
        tm.reset()
        XCTAssertFalse(tm.isTripActive)
    }

    func testTripResetDoesNotFireCallback() {
        let tm = TripManager()
        var fired = false
        tm.onTripEnd = { _ in fired = true }
        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)
        tm.reset()
        XCTAssertFalse(fired)
    }

    func testTripWithNullCoordinates() {
        let tm = TripManager()
        var tripData: [String: Any?]?
        tm.onTripEnd = { data in tripData = data }

        tm.onMotionStateChanged(isMoving: true)
        tm.onMotionStateChanged(isMoving: false)
        XCTAssertNotNil(tripData)
        XCTAssertEqual(tripData?["distance"] as? Double, 0)
    }

    func testMultipleConsecutiveTrips() {
        let tm = TripManager()
        var trips: [[String: Any?]] = []
        tm.onTripEnd = { data in trips.append(data) }

        tm.onMotionStateChanged(isMoving: true, latitude: 37.42, longitude: -122.08)
        tm.onMotionStateChanged(isMoving: false, latitude: 37.43, longitude: -122.07)
        tm.onMotionStateChanged(isMoving: true, latitude: 37.44, longitude: -122.06)
        tm.onMotionStateChanged(isMoving: false, latitude: 37.45, longitude: -122.05)

        XCTAssertEqual(trips.count, 2)
        let start1 = trips[0]["startLocation"] as? [String: Any?]
        let start2 = trips[1]["startLocation"] as? [String: Any?]
        XCTAssertEqual(start1?["latitude"] as? Double, 37.42)
        XCTAssertEqual(start2?["latitude"] as? Double, 37.44)
    }

    // MARK: - BatteryBudgetEngine

    func testBudgetFirstSampleReturnsNil() {
        let engine = BatteryBudgetEngine(targetBudgetPerHour: 5.0)
        let result = engine.processSample(0.85)
        XCTAssertNil(result, "First sample should be baseline")
    }

    func testBudgetChargingReturnsNil() {
        let engine = BatteryBudgetEngine(targetBudgetPerHour: 5.0)
        engine.processSample(0.80)
        setPrevSampleTime(engine, offsetMs: -300_000) // 5 min ago
        let result = engine.processSample(0.85) // Battery went UP
        XCTAssertNil(result, "Charging should not trigger adjustment")
    }

    func testBudgetThrottleWhenOverBudget() {
        let engine = BatteryBudgetEngine(
            targetBudgetPerHour: 5.0,
            initialDistanceFilter: 50.0,
            initialAccuracyIndex: 0
        )
        engine.processSample(0.90)
        setPrevSampleTime(engine, offsetMs: -300_000) // 5 min ago
        let result = engine.processSample(0.80) // 10% in 5min = 120%/hr
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.newDistanceFilter, 50.0) // Should throttle
        XCTAssertGreaterThan(result!.newDesiredAccuracy, 0) // Should degrade
    }

    func testBudgetBoostWhenUnderBudget() {
        let engine = BatteryBudgetEngine(
            targetBudgetPerHour: 50.0, // Very generous
            initialDistanceFilter: 100.0,
            initialAccuracyIndex: 2
        )
        engine.processSample(0.999)
        setPrevSampleTime(engine, offsetMs: -300_000)
        let result = engine.processSample(0.998) // Tiny drain
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.newDistanceFilter, 100.0) // Should boost
    }

    func testBudgetResetClearsState() {
        let engine = BatteryBudgetEngine(targetBudgetPerHour: 5.0)
        engine.processSample(0.90)
        engine.reset()
        let result = engine.processSample(0.89)
        XCTAssertNil(result, "After reset, first sample should be baseline")
    }

    func testBudgetPeriodicIntervalAdjusted() {
        let engine = BatteryBudgetEngine(
            targetBudgetPerHour: 5.0,
            initialDistanceFilter: 50.0,
            initialAccuracyIndex: 0,
            initialPeriodicInterval: 900
        )
        engine.processSample(0.90)
        setPrevSampleTime(engine, offsetMs: -300_000)
        let result = engine.processSample(0.80) // Big drain → throttle
        XCTAssertNotNil(result?.newPeriodicInterval)
        XCTAssertGreaterThan(result!.newPeriodicInterval!, 900)
    }

    func testBudgetEventContainsCorrectTarget() {
        let engine = BatteryBudgetEngine(targetBudgetPerHour: 5.0)
        engine.processSample(0.90)
        setPrevSampleTime(engine, offsetMs: -300_000)
        let result = engine.processSample(0.80)
        XCTAssertEqual(result?.targetBudget, 5.0)
    }

    // MARK: - Helpers

    /// Manipulate prevSampleTime to simulate elapsed time.
    private func setPrevSampleTime(_ engine: BatteryBudgetEngine, offsetMs: Int) {
        engine.prevSampleTime = Date(timeIntervalSinceNow: Double(offsetMs) / 1000.0)
    }

    // =========================================================================
    // MARK: - RTree Tests
    // =========================================================================

    func testRTreeEmptyReturnsNoResults() {
        let tree = RTree<String>(maxEntries: 4)
        XCTAssertTrue(tree.isEmpty)
        XCTAssertEqual(tree.size, 0)
        XCTAssertEqual(tree.queryCircle(lat: 37.0, lng: -122.0, radiusMeters: 1000.0).count, 0)
    }

    func testRTreeInsertIncrementsSize() {
        let tree = RTree<String>(maxEntries: 4)
        tree.insert(lat: 37.0, lng: -122.0, radius: 100.0, data: "a")
        XCTAssertEqual(tree.size, 1)
        XCTAssertFalse(tree.isEmpty)
        tree.insert(lat: 38.0, lng: -121.0, radius: 200.0, data: "b")
        XCTAssertEqual(tree.size, 2)
    }

    func testRTreeQueryCircleFindsNearby() {
        let tree = RTree<String>(maxEntries: 4)
        tree.insert(lat: 37.7749, lng: -122.4194, radius: 100.0, data: "home")
        tree.insert(lat: 40.7128, lng: -74.0060, radius: 500.0, data: "nyc")
        let results = tree.queryCircle(lat: 37.7750, lng: -122.4190, radiusMeters: 1000.0)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "home")
    }

    func testRTreeQueryCircleExcludesDistant() {
        let tree = RTree<String>(maxEntries: 4)
        tree.insert(lat: 37.7749, lng: -122.4194, radius: 100.0, data: "sf")
        tree.insert(lat: 40.7128, lng: -74.0060, radius: 100.0, data: "nyc")
        let results = tree.queryCircle(lat: 40.7130, lng: -74.0065, radiusMeters: 1000.0)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "nyc")
    }

    func testRTreeClearEmptiesTree() {
        let tree = RTree<String>(maxEntries: 4)
        tree.insert(lat: 37.0, lng: -122.0, radius: 100.0, data: "a")
        tree.insert(lat: 38.0, lng: -121.0, radius: 200.0, data: "b")
        tree.clear()
        XCTAssertTrue(tree.isEmpty)
        XCTAssertEqual(tree.size, 0)
    }

    func testRTreeHandlesSplitting() {
        let tree = RTree<String>(maxEntries: 4)
        for i in 0..<20 {
            tree.insert(lat: 37.0 + Double(i) * 0.01, lng: -122.0 + Double(i) * 0.01, radius: 100.0, data: "item\(i)")
        }
        XCTAssertEqual(tree.size, 20)
        let results = tree.queryBBox(minLat: 36.0, minLng: -123.0, maxLat: 38.0, maxLng: -121.0)
        XCTAssertEqual(results.count, 20)
    }

    func testRTreeRemove() {
        let tree = RTree<String>(maxEntries: 4)
        tree.insert(lat: 37.0, lng: -122.0, radius: 100.0, data: "a")
        tree.insert(lat: 38.0, lng: -121.0, radius: 200.0, data: "b")
        XCTAssertTrue(tree.remove("a"))
        XCTAssertEqual(tree.size, 1)
        XCTAssertFalse(tree.remove("nonexistent"))
    }

    // =========================================================================
    // MARK: - GeofenceEvaluator Tests
    // =========================================================================

    func testEnterCircularGeofence() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            ["identifier": "office", "latitude": 37.422, "longitude": -122.084, "radius": 200]
        ]
        // Outside
        var t = eval.evaluateProximity(latitude: 37.425, longitude: -122.084, geofences: gf)
        XCTAssertTrue(t.isEmpty)
        // Inside
        t = eval.evaluateProximity(latitude: 37.4225, longitude: -122.084, geofences: gf)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].identifier, "office")
        XCTAssertEqual(t[0].action, "ENTER")
    }

    func testExitCircularGeofence() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            ["identifier": "home", "latitude": 37.7749, "longitude": -122.4194, "radius": 100]
        ]
        // Enter
        let _ = eval.evaluateProximity(latitude: 37.7749, longitude: -122.4194, geofences: gf)
        // Exit
        let t = eval.evaluateProximity(latitude: 37.78, longitude: -122.42, geofences: gf)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].action, "EXIT")
    }

    func testNoTransitionStayingInside() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            ["identifier": "zone", "latitude": 37.0, "longitude": -122.0, "radius": 500]
        ]
        let _ = eval.evaluateProximity(latitude: 37.0, longitude: -122.0, geofences: gf)
        let t = eval.evaluateProximity(latitude: 37.001, longitude: -122.001, geofences: gf)
        XCTAssertTrue(t.isEmpty)
    }

    func testEnterPolygonGeofence() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            [
                "identifier": "park",
                "latitude": 37.0,
                "longitude": -122.0,
                "vertices": [
                    [36.99, -122.01],
                    [36.99, -121.99],
                    [37.01, -121.99],
                    [37.01, -122.01],
                ] as [[Double]],
            ]
        ]
        let t = eval.evaluateProximity(latitude: 37.0, longitude: -122.0, geofences: gf)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].identifier, "park")
        XCTAssertEqual(t[0].action, "ENTER")
        XCTAssertNil(t[0].distance)
    }

    func testExitPolygonGeofence() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            [
                "identifier": "park",
                "latitude": 37.0,
                "longitude": -122.0,
                "vertices": [
                    [36.99, -122.01],
                    [36.99, -121.99],
                    [37.01, -121.99],
                    [37.01, -122.01],
                ] as [[Double]],
            ]
        ]
        let _ = eval.evaluateProximity(latitude: 37.0, longitude: -122.0, geofences: gf)
        let t = eval.evaluateProximity(latitude: 37.05, longitude: -122.0, geofences: gf)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].action, "EXIT")
    }

    func testClearResetsState() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            ["identifier": "g", "latitude": 37.0, "longitude": -122.0, "radius": 500]
        ]
        let _ = eval.evaluateProximity(latitude: 37.0, longitude: -122.0, geofences: gf)
        XCTAssertTrue(eval.insideGeofenceIds.contains("g"))
        eval.clear()
        XCTAssertTrue(eval.insideGeofenceIds.isEmpty)
    }

    func testRemoveGeofence() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            ["identifier": "g", "latitude": 37.0, "longitude": -122.0, "radius": 500]
        ]
        let _ = eval.evaluateProximity(latitude: 37.0, longitude: -122.0, geofences: gf)
        eval.removeGeofence("g")
        XCTAssertFalse(eval.insideGeofenceIds.contains("g"))
    }

    func testIndexedEvaluation() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            ["identifier": "a", "latitude": 37.0, "longitude": -122.0, "radius": 200],
            ["identifier": "b", "latitude": 38.0, "longitude": -121.0, "radius": 200],
        ]
        eval.indexGeofences(gf)
        XCTAssertTrue(eval.isIndexed)
        let t = eval.evaluateProximity(latitude: 37.0, longitude: -122.0, geofences: gf)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].identifier, "a")
        XCTAssertEqual(t[0].action, "ENTER")
    }

    func testDefaultRadiusWhenNotSpecified() {
        let eval = GeofenceEvaluator()
        let gf: [[String: Any?]] = [
            ["identifier": "g", "latitude": 37.0, "longitude": -122.0]
        ]
        let t = eval.evaluateProximity(latitude: 37.0, longitude: -122.0, geofences: gf)
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].action, "ENTER")
    }
}
