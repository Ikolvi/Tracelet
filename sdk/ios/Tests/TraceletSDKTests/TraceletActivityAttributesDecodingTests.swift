import Foundation
import XCTest

@testable import TraceletSDK

#if canImport(ActivityKit)
@available(iOS 16.1, *)
final class TraceletActivityAttributesDecodingTests: XCTestCase {
    func testLegacyContentStatePayloadUsesTimerDefaults() throws {
        let payload = #"{"status":"Tracking active"}"#.data(using: .utf8)!

        let state = try JSONDecoder().decode(
            TraceletActivityAttributes.ContentState.self,
            from: payload
        )

        XCTAssertEqual(state.status, "Tracking active")
        XCTAssertFalse(state.showTimer)
        XCTAssertNil(state.startedAt)
    }
}
#endif
