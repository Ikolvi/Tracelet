import XCTest

@testable import TraceletSDK

/// #439: the unlock request reports the running app's bundle id, so the
/// license server can refuse a prod license bound to another app.
final class CrashModelUnlockBodyTests: XCTestCase {

    func testReportsPlatformAndBundleId() {
        let body = CrashModelLoader.unlockBody(
            licenseKey: "key.sig", integrityToken: nil, bundleId: "com.pamamap.app")
        XCTAssertEqual(body["licenseKey"] as? String, "key.sig")
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["pkg"] as? String, "com.pamamap.app")
        XCTAssertNil(body["integrityToken"])
        XCTAssertNil(body["certSha256"], "iOS has no signing cert to report")
    }

    func testWithoutABundleIdTheBodyIsWhat388Sent() {
        let body = CrashModelLoader.unlockBody(
            licenseKey: "k", integrityToken: nil, bundleId: nil)
        XCTAssertEqual(Array(body.keys), ["licenseKey"])
    }

    func testKeepsAnIntegrityTokenWhenGiven() {
        let body = CrashModelLoader.unlockBody(
            licenseKey: "k", integrityToken: "tok", bundleId: "com.a")
        XCTAssertEqual(body["integrityToken"] as? String, "tok")
    }
}
