import Foundation

/// The timeout every `wait(for:timeout:)` in this suite uses (#329).
///
/// These timeouts are **liveness bounds, not correctness bounds**. Every
/// expectation in the suite is fulfilled by an explicit `fulfill()` — from a
/// delegate callback, or from a `DispatchQueue.main.asyncAfter` block that also
/// carries the assertion — and no test uses `isInverted`. So the window a test
/// actually observes is the `asyncAfter` deadline it schedules, never this
/// value: raising it cannot weaken an assertion, and lowering it cannot
/// strengthen one. All it decides is how far behind schedule the machine is
/// allowed to fall before a correct test is reported as a failure.
///
/// At 1.0 second that margin was too thin for a loaded CI runner.
/// `MotionDetectorTests.testIntermittentNoiseDuringStopTimeoutDoesNotAbort`
/// failed on `main` with *"Exceeded timeout of 1 seconds, with unfulfilled
/// expectations: Timeout started"* — an expectation whose only job was to wait
/// 0.1 s, on a run where the whole `xcodebuild` operation took 181 s to execute
/// 62 s of tests. The behaviour under test had worked: the log for that very
/// run shows `startStopTimeoutCountdown: Starting timer for 60.0 seconds`. Only
/// the main queue was starved past the bound.
///
/// Nothing is paid for the larger value in the passing case — `wait` returns as
/// soon as the expectation is fulfilled, so this is reached only on a genuine
/// failure, where waiting five seconds to report it costs nothing.
let asyncWaitTimeout: TimeInterval = 5.0
