/// The version of the `tracelet` package this build was compiled from.
///
/// Kept in lockstep with `packages/tracelet/pubspec.yaml` by
/// `scripts/sync_native_versions.py`, which the Melos version hook runs before
/// the release commit — so this cannot drift from the published package the way
/// a hand-maintained constant would.
///
/// Exists because a bug report had no way to say which version produced it. The
/// Doctor report opens with a generation timestamp and, optionally, the host
/// app's own version; triage then began by asking which Tracelet that was, and
/// a report pasted into an issue weeks later could not answer at all (#398).
library;

/// The `tracelet` package version, e.g. `3.8.7`.
const String traceletVersion = '3.8.8';
