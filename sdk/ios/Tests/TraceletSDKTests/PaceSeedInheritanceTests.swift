import XCTest

@testable import TraceletSDK

/// A fresh `start()` that commits a stationary pace must not have it
/// overruled by the last speed the process happened to resolve.
///
/// `startSpeedMotionManager` seeds the speed machine with
/// `locationEngine.lastEffectiveSpeed`. The seed exists for one case: a resume
/// into a live process, where feeding a fabricated 0.0 told a session that had
/// just come back as MOVING that it was stopped, and it stood the stream down
/// while the user was still walking.
///
/// It can only ever push the machine *up*, though — one fix at or above
/// `speedMovingThreshold` wakes it, the pace is then read back off the machine,
/// and `stateManager.isMoving` is written true. A fresh `start()` that committed
/// `motion.isMoving: false` therefore came up *moving*, on the strength of a
/// reading it never asked about.
///
/// That is also why the first `start()` of a process and the second disagreed:
/// the first has no fix to seed with and stays stationary as asked; the second
/// seeds from the fix the first one acquired and comes up moving. Same call,
/// same config, two answers — which is how it was reported.
final class PaceSeedInheritanceTests: XCTestCase {

    /// The reported case: a fresh, stationary start owns its pace.
    func testAFreshStationaryStartIsNotSeeded() {
        XCTAssertFalse(
            TraceletSdk.paceWasInherited(isResume: false, forceMoving: false),
            "`motion.isMoving: false` is an explicit instruction from the "
                + "caller — a stale speed must not be allowed to answer it")
    }

    /// A relaunch has no record of its pace other than the one it restored, so
    /// the seed's original case still holds.
    func testAResumeIsSeeded() {
        XCTAssertTrue(
            TraceletSdk.paceWasInherited(isResume: true, forceMoving: false),
            "the resume is what the seed was written for — without it a walking "
                + "session is stood down by a fabricated 0.0 m/s")
    }

    /// A forced-moving start takes the pace the previous session ended in, so it
    /// inherits by the same reasoning.
    func testAForcedMovingStartIsSeeded() {
        XCTAssertTrue(
            TraceletSdk.paceWasInherited(isResume: false, forceMoving: true),
            "a start that begins moving took that pace from the last session, "
                + "not from a fresh decision")
    }

    func testAForcedMovingResumeIsSeeded() {
        XCTAssertTrue(
            TraceletSdk.paceWasInherited(isResume: true, forceMoving: true))
    }
}
