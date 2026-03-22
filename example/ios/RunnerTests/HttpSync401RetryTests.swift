import XCTest
@testable import tracelet_ios

// MARK: - Mock event dispatcher

private final class MockEventDispatcher: TraceletEventSending {
    var httpEvents: [[String: Any]] = []

    func sendLocation(_ data: [String: Any]) {}
    func sendMotionChange(_ data: [String: Any]) {}
    func sendActivityChange(_ data: [String: Any]) {}
    func sendProviderChange(_ data: [String: Any]) {}
    func sendGeofence(_ data: [String: Any]) {}
    func sendGeofencesChange(_ data: [String: Any]) {}
    func sendHeartbeat(_ data: [String: Any]) {}
    func sendHttp(_ data: [String: Any]) { httpEvents.append(data) }
    func sendSchedule(_ data: [String: Any]) {}
    func sendPowerSaveChange(_ isPowerSave: Bool) {}
    func sendConnectivityChange(_ data: [String: Any]) {}
    func sendEnabledChange(_ enabled: Bool) {}
    func sendNotificationAction(_ data: [String: Any]) {}
    func sendAuthorization(_ data: [String: Any]) {}
    func sendWatchPosition(_ data: [String: Any]) {}
    func sendRemoteConfigEvent(_ data: [String: Any]) {}
    func hasListener(eventName: String) -> Bool { true }
}

// MARK: - Mock URL protocol for intercepting HTTP requests

private final class MockURLProtocol: URLProtocol {
    /// Response handler set per-test. Returns (statusCode, body).
    static var requestHandler: ((URLRequest) -> (Int, String))?
    /// Records all requests for assertion.
    static var receivedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.receivedRequests.append(request)

        let (statusCode, body) = MockURLProtocol.requestHandler?(request)
            ?? (200, "{\"ok\":true}")

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        let data = body.data(using: .utf8)!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

/// Tests the 401-aware retry mechanism in `HttpSyncManager`.
///
/// Uses `MockURLProtocol` to intercept `URLSession` requests and simulate
/// server responses. Validates that on 401 the `onAuthorizationRequired`
/// callback fires, headers refresh, and the request retries once.
final class HttpSync401RetryTests: XCTestCase {

    private var configManager: ConfigManager!
    private var database: TraceletDatabase!
    private var eventDispatcher: MockEventDispatcher!
    private var syncManager: HttpSyncManager!

    override func setUp() {
        super.setUp()
        MockURLProtocol.receivedRequests = []
        MockURLProtocol.requestHandler = nil

        configManager = ConfigManager()
        configManager.reset(nil)
        _ = configManager.setConfig([
            "http": [
                "url": "https://test.tracelet.dev/locations",
                "autoSync": false,
                "batchSync": true,
            ] as [String: Any]
        ])

        database = TraceletDatabase(inMemory: true)
        eventDispatcher = MockEventDispatcher()

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]

        syncManager = HttpSyncManager(configManager: configManager,
                                       eventDispatcher: eventDispatcher,
                                       database: database,
                                       sessionConfiguration: sessionConfig)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.receivedRequests = []
        super.tearDown()
    }

    /// Inserts a test location into the in-memory database.
    private func insertTestLocation() {
        _ = database.insertLocation([
            "coords": [
                "latitude": 37.7749,
                "longitude": -122.4194,
                "accuracy": 10.0,
            ] as [String: Any],
            "timestamp": "2025-01-01T00:00:00.000Z",
            "is_moving": true,
        ] as [String: Any])
    }

    // MARK: - onAuthorizationRequired callback

    func testOnAuthorizationRequired_calledOn401() {
        var callbackInvoked = false
        syncManager.onAuthorizationRequired = {
            callbackInvoked = true
            return false
        }

        // Simulate 401 response
        MockURLProtocol.requestHandler = { _ in (401, "{\"error\":\"unauthorized\"}") }

        insertTestLocation()

        let expectation = self.expectation(description: "sync completes")
        syncManager.sync { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertTrue(callbackInvoked, "onAuthorizationRequired should be called on 401")
    }

    func testOnAuthorizationRequired_notCalledOnSuccess() {
        var callbackInvoked = false
        syncManager.onAuthorizationRequired = {
            callbackInvoked = true
            return false
        }

        MockURLProtocol.requestHandler = { _ in (200, "{\"ok\":true}") }

        insertTestLocation()

        let expectation = self.expectation(description: "sync completes")
        syncManager.sync { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertFalse(callbackInvoked, "onAuthorizationRequired should NOT be called on 200")
    }

    func testOnAuthorizationRequired_notCalledOn500() {
        var callbackInvoked = false
        syncManager.onAuthorizationRequired = {
            callbackInvoked = true
            return false
        }

        // 500 is a transient error, not an auth error
        MockURLProtocol.requestHandler = { _ in (500, "Internal Server Error") }

        // Set maxRetries to 0 so it doesn't retry forever
        _ = configManager.setConfig(["http": ["maxRetries": 0]])

        insertTestLocation()

        let expectation = self.expectation(description: "sync completes")
        syncManager.sync { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertFalse(callbackInvoked, "onAuthorizationRequired should NOT be called on 500")
    }

    // MARK: - Retry after refresh

    func testRetryWithRefreshedHeaders_succeeds() {
        var requestCount = 0

        syncManager.onAuthorizationRequired = { [weak self] in
            // Simulate token refresh by setting new dynamic headers
            self?.configManager.setDynamicHeaders(["Authorization": "Bearer new-token"])
            return true
        }

        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            if requestCount == 1 {
                return (401, "{\"error\":\"unauthorized\"}")
            }
            return (200, "{\"ok\":true}")
        }

        insertTestLocation()

        let expectation = self.expectation(description: "sync completes")
        syncManager.sync { synced in
            // Should have synced successfully after retry
            XCTAssertFalse(synced.isEmpty, "Locations should be synced after retry")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertEqual(requestCount, 2, "Should have made 2 requests (initial + retry)")
    }

    func testRetryOnlyOnce_secondFailureIsPermanent() {
        var callbackCount = 0

        syncManager.onAuthorizationRequired = {
            callbackCount += 1
            return true // claim refresh succeeded, but server still returns 401
        }

        // Always return 401
        MockURLProtocol.requestHandler = { _ in (401, "{\"error\":\"unauthorized\"}") }

        insertTestLocation()

        let expectation = self.expectation(description: "sync completes")
        syncManager.sync { synced in
            // Should fail after second 401 — no infinite loop
            XCTAssertTrue(synced.isEmpty, "Locations should NOT be synced when retry also fails")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertEqual(callbackCount, 1, "onAuthorizationRequired should be called only once")
    }

    func testRefreshFailed_treatedAsPermanentFailure() {
        var callbackInvoked = false

        syncManager.onAuthorizationRequired = {
            callbackInvoked = true
            return false // refresh failed
        }

        MockURLProtocol.requestHandler = { _ in (401, "{\"error\":\"unauthorized\"}") }

        insertTestLocation()

        let expectation = self.expectation(description: "sync completes")
        syncManager.sync { synced in
            XCTAssertTrue(synced.isEmpty, "Should fail immediately when refresh returns false")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertTrue(callbackInvoked)
    }

    // MARK: - No callback wired

    func testNoCallbackWired_401TreatedAsPermanentFailure() {
        // onAuthorizationRequired is nil
        syncManager.onAuthorizationRequired = nil

        MockURLProtocol.requestHandler = { _ in (401, "{\"error\":\"unauthorized\"}") }

        insertTestLocation()

        let expectation = self.expectation(description: "sync completes")
        syncManager.sync { synced in
            XCTAssertTrue(synced.isEmpty, "Should fail when no callback is wired")
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)
    }

    // MARK: - HTTP events

    func testHttpEvent_containsRetryFlagAfterRefresh() {
        var requestCount = 0

        syncManager.onAuthorizationRequired = { [weak self] in
            self?.configManager.setDynamicHeaders(["Authorization": "Bearer refreshed"])
            return true
        }

        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            if requestCount == 1 {
                return (401, "{\"error\":\"unauthorized\"}")
            }
            return (200, "{\"ok\":true}")
        }

        insertTestLocation()

        let expectation = self.expectation(description: "sync completes")
        syncManager.sync { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        // Should have at least 2 HTTP events: the 401 failure and the 200 success
        XCTAssertGreaterThanOrEqual(eventDispatcher.httpEvents.count, 2)

        // The successful retry event should have isRetry = true
        let successEvent = eventDispatcher.httpEvents.last!
        XCTAssertEqual(successEvent["success"] as? Bool, true)
        XCTAssertEqual(successEvent["isRetry"] as? Bool, true)
    }
}
