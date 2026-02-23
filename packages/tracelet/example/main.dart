// ignore_for_file: avoid_print

import 'package:tracelet/tracelet.dart' as tl;

/// Minimal example demonstrating Tracelet background geolocation.
Future<void> main() async {
  // 1. Subscribe to location events.
  tl.Tracelet.onLocation((location) {
    print(
      '📍 ${location.coords.latitude}, ${location.coords.longitude} '
      '· accuracy: ${location.coords.accuracy}m',
    );
  });

  // 2. Initialize the plugin with a configuration.
  final state = await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        distanceFilter: 10,
      ),
      logger: tl.LoggerConfig(logLevel: tl.LogLevel.verbose),
    ),
  );

  print(
    'Tracelet ready — enabled: ${state.enabled}, '
    'tracking: ${state.trackingMode}',
  );

  // 3. Start tracking.
  await tl.Tracelet.start();
}

// ---------------------------------------------------------------------------
// One-Shot Location Examples
// ---------------------------------------------------------------------------

/// Example: Single location fetch — no continuous tracking, no persistence.
///
/// This is the simplest way to get the device's current location without
/// starting background tracking or showing a foreground notification.
Future<void> singleLocationExample() async {
  // Initialize with foreground service DISABLED (Android).
  // No persistent notification will be shown.
  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(desiredAccuracy: tl.DesiredAccuracy.high),
      app: tl.AppConfig(
        stopOnTerminate: true,
        foregroundService: tl.ForegroundServiceConfig(
          enabled: false, // No foreground notification on Android.
        ),
      ),
    ),
  );

  // Fetch a single location — does NOT start continuous tracking.
  final location = await tl.Tracelet.getCurrentPosition(
    desiredAccuracy: tl.DesiredAccuracy.high,
    timeout: 30,
    persist: false, // Don't store in local database.
  );

  print(
    '📍 Single fix: ${location.coords.latitude}, '
    '${location.coords.longitude}  '
    'accuracy: ${location.coords.accuracy}m',
  );
}

/// Example: Best-of-N samples — collect multiple GPS fixes and return the
/// one with the best (lowest) horizontal accuracy.
///
/// Useful for check-in flows, geocoding, or any scenario where you need
/// high confidence in a single reading.
Future<void> bestOfThreeSamplesExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(desiredAccuracy: tl.DesiredAccuracy.high),
      app: tl.AppConfig(
        stopOnTerminate: true,
        foregroundService: tl.ForegroundServiceConfig(enabled: false),
      ),
    ),
  );

  // Collect 3 GPS samples, return the most accurate one.
  final location = await tl.Tracelet.getCurrentPosition(
    desiredAccuracy: tl.DesiredAccuracy.high,
    timeout: 30,
    samples: 3,
    persist: false,
  );

  print(
    '📍 Best of 3: ${location.coords.latitude}, '
    '${location.coords.longitude}  '
    'accuracy: ${location.coords.accuracy}m',
  );
}

/// Example: Last known location — instant retrieval from OS cache.
///
/// No GPS hardware is activated. Returns null if the OS has no cached
/// location (e.g. fresh device boot with no prior location providers used).
Future<void> lastKnownLocationExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(desiredAccuracy: tl.DesiredAccuracy.high),
      app: tl.AppConfig(
        stopOnTerminate: true,
        foregroundService: tl.ForegroundServiceConfig(enabled: false),
      ),
    ),
  );

  final location = await tl.Tracelet.getLastKnownLocation();

  if (location == null) {
    print('⚠️ No cached location available');
  } else {
    print(
      '📍 Last known: ${location.coords.latitude}, '
      '${location.coords.longitude}  '
      'accuracy: ${location.coords.accuracy}m',
    );
  }
}
