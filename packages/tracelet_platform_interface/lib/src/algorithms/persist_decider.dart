/// Pure-Dart persistence decision logic.
///
/// Replaces the `persistLocationIfAllowed` and `persistMode` checks
/// previously duplicated in native Kotlin and Swift.
///
/// **This is a pure Dart implementation** — no native code required. It runs
/// identically on Android, iOS, web, macOS, Linux, and Windows.
///
/// ```dart
/// if (PersistDecider.shouldPersistLocation(PersistMode.all)) {
///   database.insert(location);
/// }
/// ```
class PersistDecider {
  PersistDecider._(); // Prevent instantiation.

  /// Whether a location should be persisted based on [persistMode].
  ///
  /// Persist modes:
  /// - `0` (all): Persist everything.
  /// - `1` (location): Persist locations only (not geofence events).
  /// - `2` (geofence): Persist geofence events only (not locations).
  /// - `3` (none): Persist nothing.
  ///
  /// If [disableProviderChangeRecord] is `true` and [event] is
  /// `'providerchange'`, the location is not persisted.
  static bool shouldPersistLocation(
    int persistMode, {
    String event = '',
    bool disableProviderChangeRecord = false,
  }) {
    // Mode 3 (none) or mode 2 (geofence only) → don't persist locations.
    if (persistMode == 3 || persistMode == 2) return false;

    // Skip provider-change records if configured.
    if (disableProviderChangeRecord && event == 'providerchange') return false;

    return true; // Mode 0 (all) or mode 1 (location).
  }

  /// Whether a geofence event should be persisted based on [persistMode].
  ///
  /// - `0` (all): Persist.
  /// - `1` (location): Don't persist geofence events.
  /// - `2` (geofence): Persist.
  /// - `3` (none): Don't persist.
  static bool shouldPersistGeofence(int persistMode) {
    if (persistMode == 3 || persistMode == 1) return false;
    return true; // Mode 0 (all) or mode 2 (geofence).
  }
}
