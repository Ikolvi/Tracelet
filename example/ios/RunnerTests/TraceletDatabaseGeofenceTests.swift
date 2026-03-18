@testable import tracelet_ios
import XCTest

/// Tests for ``TraceletDatabase`` geofence CRUD — focusing on
/// the `vertices` column for polygon geofences.
///
/// Uses an in-memory SQLite database for isolation.
final class TraceletDatabaseGeofenceTests: XCTestCase {

    private var db: TraceletDatabase!

    override func setUp() {
        super.setUp()
        db = TraceletDatabase(inMemory: true)
    }

    override func tearDown() {
        db = nil
        super.tearDown()
    }

    // MARK: - Circular geofence (no vertices)

    func testInsertCircularGeofence_roundTripsCorrectly() {
        let geofence: [String: Any] = [
            "identifier": "circle-1",
            "latitude": 37.7749,
            "longitude": -122.4194,
            "radius": 200.0,
            "notifyOnEntry": true,
            "notifyOnExit": true,
            "notifyOnDwell": false,
            "loiteringDelay": 0,
        ]
        XCTAssertTrue(db.insertGeofence(geofence))

        let result = db.getGeofence("circle-1")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["identifier"] as? String, "circle-1")
        XCTAssertEqual(result?["latitude"] as! Double, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(result?["longitude"] as! Double, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(result?["radius"] as! Double, 200.0, accuracy: 0.1)
        // Circular geofence: vertices key should NOT be present
        XCTAssertNil(result?["vertices"], "Circular geofence should not have 'vertices' key")
    }

    // MARK: - Polygon geofence (vertices)

    func testInsertPolygonGeofence_verticesPersistAndRoundTrip() {
        let vertices: [[Any]] = [
            [37.78, -122.42],
            [37.77, -122.41],
            [37.76, -122.43],
            [37.78, -122.42],  // closed ring
        ]
        let geofence: [String: Any] = [
            "identifier": "polygon-1",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 0.0,
            "vertices": vertices,
        ]
        XCTAssertTrue(db.insertGeofence(geofence))

        let result = db.getGeofence("polygon-1")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["identifier"] as? String, "polygon-1")

        let resultVertices = result?["vertices"] as? [[Double]]
        XCTAssertNotNil(resultVertices, "Polygon geofence should have 'vertices'")
        XCTAssertEqual(resultVertices?.count, 4)
        XCTAssertEqual(resultVertices![0][0], 37.78, accuracy: 0.0001)
        XCTAssertEqual(resultVertices![0][1], -122.42, accuracy: 0.0001)
        XCTAssertEqual(resultVertices![2][0], 37.76, accuracy: 0.0001)
        XCTAssertEqual(resultVertices![2][1], -122.43, accuracy: 0.0001)
    }

    func testInsertPolygonGeofence_withFewerThan3Vertices_storesNull() {
        let vertices: [[Any]] = [
            [37.78, -122.42],
            [37.77, -122.41],
        ]
        let geofence: [String: Any] = [
            "identifier": "polygon-2-vert",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 100.0,
            "vertices": vertices,
        ]
        XCTAssertTrue(db.insertGeofence(geofence))

        let result = db.getGeofence("polygon-2-vert")
        XCTAssertNotNil(result)
        XCTAssertNil(result?["vertices"], "Geofence with <3 vertices should not have 'vertices' key")
    }

    func testInsertPolygonGeofence_withEmptyVertices_storesNull() {
        let geofence: [String: Any] = [
            "identifier": "polygon-empty",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 100.0,
            "vertices": [] as [[Any]],
        ]
        XCTAssertTrue(db.insertGeofence(geofence))

        let result = db.getGeofence("polygon-empty")
        XCTAssertNotNil(result)
        XCTAssertNil(result?["vertices"])
    }

    func testInsertPolygonGeofence_withoutVerticesKey_storesNull() {
        let geofence: [String: Any] = [
            "identifier": "polygon-nokey",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 100.0,
        ]
        XCTAssertTrue(db.insertGeofence(geofence))

        let result = db.getGeofence("polygon-nokey")
        XCTAssertNotNil(result)
        XCTAssertNil(result?["vertices"])
    }

    func testInsertPolygonGeofence_skipsInvalidVertexEntries() {
        // Mix of valid and invalid vertex entries
        let vertices: [Any] = [
            [37.78, -122.42],       // valid
            "not a list",           // invalid
            [37.77, -122.41],       // valid
            [37.76] as [Double],    // invalid (too few elements)
            [37.75, -122.44],       // valid
        ]
        let geofence: [String: Any] = [
            "identifier": "polygon-mixed",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 0.0,
            "vertices": vertices,
        ]
        XCTAssertTrue(db.insertGeofence(geofence))

        let result = db.getGeofence("polygon-mixed")
        XCTAssertNotNil(result)

        let resultVertices = result?["vertices"] as? [[Double]]
        XCTAssertNotNil(resultVertices, "Should have 3 valid vertices")
        XCTAssertEqual(resultVertices?.count, 3)
    }

    func testInsertPolygonGeofence_invalidVerticesBelowMinimum_storesNull() {
        // Only 2 valid vertices among invalid ones → null
        let vertices: [Any] = [
            [37.78, -122.42],
            "invalid",
            [37.77, -122.41],
        ]
        let geofence: [String: Any] = [
            "identifier": "polygon-too-few-valid",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 100.0,
            "vertices": vertices,
        ]
        XCTAssertTrue(db.insertGeofence(geofence))

        let result = db.getGeofence("polygon-too-few-valid")
        XCTAssertNotNil(result)
        XCTAssertNil(result?["vertices"])
    }

    // MARK: - Update (replace) preserves vertices

    func testInsertOrReplace_updatesVertices() {
        // First insert: circular
        let circular: [String: Any] = [
            "identifier": "geo-upgrade",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 100.0,
        ]
        XCTAssertTrue(db.insertGeofence(circular))
        let result1 = db.getGeofence("geo-upgrade")
        XCTAssertNotNil(result1)
        XCTAssertNil(result1?["vertices"])

        // Second insert: upgrade to polygon
        let polygon: [String: Any] = [
            "identifier": "geo-upgrade",
            "latitude": 37.77,
            "longitude": -122.42,
            "radius": 0.0,
            "vertices": [
                [37.78, -122.42],
                [37.77, -122.41],
                [37.76, -122.43],
            ] as [[Any]],
        ]
        XCTAssertTrue(db.insertGeofence(polygon))
        let result2 = db.getGeofence("geo-upgrade")
        XCTAssertNotNil(result2)

        let v = result2?["vertices"] as? [[Double]]
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.count, 3)
    }

    // MARK: - getGeofences (list all) includes vertices

    func testGetGeofences_returnsPolygonAndCircular() {
        let _ = db.insertGeofence([
            "identifier": "c1",
            "latitude": 37.0,
            "longitude": -122.0,
            "radius": 100.0,
        ] as [String: Any])
        let _ = db.insertGeofence([
            "identifier": "p1",
            "latitude": 38.0,
            "longitude": -121.0,
            "radius": 0.0,
            "vertices": [
                [38.01, -121.01],
                [38.02, -121.02],
                [38.03, -121.03],
            ] as [[Any]],
        ] as [String: Any])

        let all = db.getGeofences()
        XCTAssertEqual(all.count, 2)

        let circular = all.first { ($0["identifier"] as? String) == "c1" }
        XCTAssertNotNil(circular)
        XCTAssertNil(circular?["vertices"])

        let polygon = all.first { ($0["identifier"] as? String) == "p1" }
        XCTAssertNotNil(polygon)
        let v = polygon?["vertices"] as? [[Double]]
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.count, 3)
    }

    // MARK: - Delete geofence

    func testDeleteGeofence_removesPolygon() {
        let _ = db.insertGeofence([
            "identifier": "to-delete",
            "latitude": 37.0,
            "longitude": -122.0,
            "radius": 0.0,
            "vertices": [
                [37.01, -122.01],
                [37.02, -122.02],
                [37.03, -122.03],
            ] as [[Any]],
        ] as [String: Any])
        XCTAssertTrue(db.geofenceExists("to-delete"))
        XCTAssertTrue(db.deleteGeofence("to-delete"))
        XCTAssertNil(db.getGeofence("to-delete"))
    }
}
