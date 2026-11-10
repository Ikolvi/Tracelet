import XCTest

@testable import TraceletSDK

/// #446: `MotionDetector`'s sampler reads ConfigManager getters on a background
/// queue while `setConfig` merges and `saveToDisk` JSON-bridges the same
/// dictionary on main. Unsynchronised, that crashed with EXC_BAD_ACCESS in
/// `getDisableStopDetection()`. This hammers both sides at once; without the
/// lock it crashes or trips ThreadSanitizer, with it it must finish.
final class ConfigManagerConcurrencyTests: XCTestCase {

    func testGettersAreSafeWhileSetConfigMutates() {
        let cm = ConfigManager()
        cm.reset(nil)
        let readers = DispatchGroup()
        let stop = DispatchSemaphore(value: 0)
        var done = false
        let flag = NSLock()

        for _ in 0..<4 {
            DispatchQueue.global().async(group: readers) {
                while true {
                    flag.lock(); let finished = done; flag.unlock()
                    if finished { return }
                    _ = cm.getDisableStopDetection()
                    _ = cm.getStopTimeout()
                    _ = cm.getDistanceFilter()
                }
            }
        }
        DispatchQueue.global().async {
            for i in 0..<2_000 {
                _ = cm.setConfig(["motion": ["stopTimeout": i % 10], "liveActivityConfig": ["title": "t\(i)"]])
            }
            stop.signal()
        }
        stop.wait()
        flag.lock(); done = true; flag.unlock()
        readers.wait()
        XCTAssertEqual(cm.getStopTimeout(), 1999 % 10)
    }
}
