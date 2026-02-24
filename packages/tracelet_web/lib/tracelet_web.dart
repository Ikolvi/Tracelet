/// Web implementation of the Tracelet background geolocation plugin.
///
/// This package provides a foreground-only implementation of Tracelet
/// for Flutter web apps. It uses the Web Geolocation API, IndexedDB,
/// and `fetch()` to implement as much of the Tracelet API surface as
/// possible within browser constraints.
///
/// **Limitations:**
/// - No background location tracking (Geolocation API is foreground-only)
/// - No headless Dart execution (Service Workers are JS-only)
/// - No system settings access (cannot open OS settings from browser)
/// - Geofencing is emulated via distance computation on each position fix
library;

export 'src/tracelet_web_plugin.dart';
