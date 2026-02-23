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

  // Ensure location permission is granted before requesting.
  final authStatus = await tl.Tracelet.requestPermission();
  if (authStatus != 2 && authStatus != 3) {
    print('⚠️ Location permission denied (status=$authStatus)');
    return;
  }

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

  // Ensure location permission is granted before requesting.
  final authStatus = await tl.Tracelet.requestPermission();
  if (authStatus != 2 && authStatus != 3) {
    print('⚠️ Location permission denied (status=$authStatus)');
    return;
  }

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

  // Ensure location permission is granted before requesting.
  final authStatus = await tl.Tracelet.requestPermission();
  if (authStatus != 2 && authStatus != 3) {
    print('⚠️ Location permission denied (status=$authStatus)');
    return;
  }

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

// ---------------------------------------------------------------------------
// Advanced Configuration Examples — New Features
// ---------------------------------------------------------------------------

/// Example: Elasticity control — disable speed-based distance filter scaling.
///
/// By default, Tracelet dynamically adjusts the distance filter based on
/// speed. Disable elasticity for a fixed `distanceFilter` regardless of speed.
Future<void> elasticityExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        distanceFilter: 50,
        // Disable elasticity: record at exactly every 50m regardless of speed.
        disableElasticity: true,
        // When elasticity is enabled, this multiplier scales the dynamic
        // adjustment (higher = fewer points at high speed). Defaults to 1.0.
        elasticityMultiplier: 1.0,
      ),
    ),
  );
  await tl.Tracelet.start();
}

/// Example: Location filtering — reject GPS spikes and low-accuracy readings.
///
/// The [LocationFilter] denoises raw GPS samples before they are recorded.
/// This helps eliminate noise, phantom jumps, and low-quality readings.
Future<void> locationFilterExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        distanceFilter: 10,
        filter: tl.LocationFilter(
          // Reject locations with horizontal accuracy worse than 100m.
          trackingAccuracyThreshold: 100,
          // Reject locations that imply speed > 80 m/s (~290 km/h).
          maxImpliedSpeed: 80,
          // Only count locations with accuracy < 50m toward the odometer.
          odometerAccuracyThreshold: 50,
          // How rejected locations are handled:
          //   adjust  — smooth/correct (default)
          //   ignore  — silently drop
          //   discard — drop and fire an error event
          policy: tl.LocationFilterPolicy.adjust,
        ),
      ),
    ),
  );
  await tl.Tracelet.start();
}

/// Example: Auto-stop — automatically stop tracking after N minutes.
///
/// Useful for time-boxed tracking sessions (e.g., a 30-minute workout).
Future<void> autoStopExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        distanceFilter: 10,
        // Automatically stop tracking after 30 minutes. Use -1 to disable.
        stopAfterElapsedMinutes: 30,
      ),
    ),
  );
  await tl.Tracelet.start();
  print('Tracking will auto-stop after 30 minutes');
}

/// Example: Persistence control — choose what to persist and retention limits.
///
/// Fine-tune what goes into the SQLite database and how long records are kept.
Future<void> persistenceConfigExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      persistence: tl.PersistenceConfig(
        // What to persist: all | location | geofence | none
        persistMode: tl.PersistMode.all,
        // Auto-prune records older than 7 days. Use -1 for unlimited.
        maxDaysToPersist: 7,
        // Auto-prune when exceeding 5000 records. Use -1 for unlimited.
        maxRecordsToPersist: 5000,
        // Skip recording provider-change events (GPS→network transitions).
        disableProviderChangeRecord: false,
      ),
    ),
  );
  await tl.Tracelet.start();
}

/// Example: Geofence high-accuracy mode — use continuous GPS in geofence-only mode.
///
/// By default, `startGeofences()` uses the platform's passive geofence monitoring
/// (battery friendly but less precise). Enable high-accuracy mode to run the
/// full GPS + motion pipeline even in geofence-only mode.
Future<void> geofenceHighAccuracyExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        // Enable high-accuracy geofence monitoring (Android only).
        geofenceModeHighAccuracy: true,
      ),
    ),
  );

  // Add a geofence first
  await tl.Tracelet.addGeofence(
    tl.Geofence(
      identifier: 'office',
      latitude: 37.4220,
      longitude: -122.0841,
      radius: 200,
      notifyOnEntry: true,
      notifyOnExit: true,
    ),
  );

  // Start geofence-only mode with high-accuracy GPS active.
  await tl.Tracelet.startGeofences();
}

/// Example: Timestamp metadata — append extra timing info to each location.
///
/// When enabled, each location record includes additional timestamp fields
/// useful for debugging timing issues and analyzing location pipeline latency.
Future<void> timestampMetaExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        distanceFilter: 10,
        enableTimestampMeta: true,
      ),
    ),
  );

  tl.Tracelet.onLocation((loc) {
    print('📍 ${loc.coords.latitude}, ${loc.coords.longitude}');
    // With enableTimestampMeta: true, the location record contains
    // additional fields for arrival time at the platform layer.
  });

  await tl.Tracelet.start();
}

/// Example: Motion detection tuning — adjust activity recognition sensitivity.
///
/// Fine-tune how aggressively Tracelet detects motion state changes.
Future<void> motionTuningExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      motion: tl.MotionConfig(
        // Minutes of stillness before transitioning to stationary.
        stopTimeout: 5,
        // Minimum confidence (0–100) for an activity to trigger motion change.
        // Higher = fewer false positives, but slower detection.
        minimumActivityRecognitionConfidence: 75,
        // Disable automatic stop detection (never go stationary automatically).
        disableStopDetection: false,
        // Extra delay (minutes) after stop-timeout before engaging detection.
        stopDetectionDelay: 0,
        // Automatically call stop() instead of just transitioning to stationary.
        stopOnStationary: false,
      ),
    ),
  );
  await tl.Tracelet.start();
}

/// Example: iOS prevent suspend — keep the app alive in background.
///
/// Plays a silent audio clip to prevent iOS from suspending the app.
/// Uses minimal battery but ensures continuous background execution.
Future<void> preventSuspendExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      app: tl.AppConfig(
        stopOnTerminate: false,
        startOnBoot: true,
        // iOS only: prevent iOS from suspending the app.
        preventSuspend: true,
      ),
    ),
  );
  await tl.Tracelet.start();
}

/// Example: Android schedule with AlarmManager — exact-time scheduling.
///
/// Uses AlarmManager for precise schedule execution instead of the default
/// JobScheduler/WorkManager which may defer execution.
Future<void> scheduleAlarmManagerExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      app: tl.AppConfig(
        stopOnTerminate: false,
        startOnBoot: true,
        // Android only: use AlarmManager for exact schedule timing.
        scheduleUseAlarmManager: true,
        // Define a schedule: Mon-Fri, 9am-5pm
        schedule: ['1-5 09:00-17:00'],
      ),
    ),
  );
  // The schedule will auto-start/stop tracking at the defined times.
}

/// Example: Wi-Fi-only sync — disable auto-sync on cellular connections.
///
/// Useful for bandwidth-conscious apps that should only sync on Wi-Fi.
Future<void> wifiOnlySyncExample() async {
  await tl.Tracelet.ready(
    tl.Config(
      http: tl.HttpConfig(
        url: 'https://example.com/locations',
        autoSync: true,
        // Only sync when connected to Wi-Fi, not on cellular.
        disableAutoSyncOnCellular: true,
      ),
    ),
  );
  await tl.Tracelet.start();
}

/// Example: Dart-side permission flow — check, request, handle denial.
///
/// No native dialogs are shown. The OS permission prompt is the only native
/// UI. If permanently denied, guide the user to Settings from Dart.
Future<void> permissionFlowExample() async {
  // 1. Check current status without triggering any dialog.
  final status = await tl.Tracelet.getPermissionStatus();
  print('Current permission status: $status');

  if (status == 0 || status == 1) {
    // notDetermined or denied (can ask again) → request foreground.
    final result = await tl.Tracelet.requestPermission();
    print('After request: $result');

    if (result == 4) {
      // Permanently denied — show YOUR OWN Dart dialog here, e.g.:
      // showDialog(context, builder: (_) => AlertDialog(
      //   title: Text('Permission Required'),
      //   content: Text('Open Settings to enable location access.'),
      //   actions: [
      //     TextButton(onPressed: () => Tracelet.openAppSettings(), ...),
      //   ],
      // ));
      print('Permanently denied — open settings');
      await tl.Tracelet.openAppSettings();
      return;
    }

    if (result == 2) {
      // Foreground granted — request background upgrade.
      final bgResult = await tl.Tracelet.requestPermission();
      print('Background request: $bgResult');
    }
  } else if (status == 4) {
    // Already permanently denied — guide user to settings.
    await tl.Tracelet.openAppSettings();
    return;
  }

  // Permission is now whenInUse (2) or always (3) — safe to start.
  await tl.Tracelet.ready(
    tl.Config(app: tl.AppConfig(stopOnTerminate: false, startOnBoot: true)),
  );
  await tl.Tracelet.start();
}

/// Example: Full-featured config — combining all new features.
///
/// Demonstrates how all configuration options work together.
Future<void> fullFeaturedExample() async {
  tl.Tracelet.onLocation((loc) {
    print(
      '📍 ${loc.coords.latitude}, ${loc.coords.longitude} '
      'acc=${loc.coords.accuracy}m',
    );
  });

  await tl.Tracelet.ready(
    tl.Config(
      geo: tl.GeoConfig(
        desiredAccuracy: tl.DesiredAccuracy.high,
        distanceFilter: 10,
        stationaryRadius: 25,
        disableElasticity: false,
        elasticityMultiplier: 1.0,
        enableTimestampMeta: true,
        stopAfterElapsedMinutes: -1,
        geofenceModeHighAccuracy: false,
        filter: tl.LocationFilter(
          trackingAccuracyThreshold: 100,
          maxImpliedSpeed: 80,
          odometerAccuracyThreshold: 50,
        ),
      ),
      app: tl.AppConfig(
        stopOnTerminate: false,
        startOnBoot: true,
        heartbeatInterval: 60,
        preventSuspend: false,
        scheduleUseAlarmManager: false,
      ),
      motion: tl.MotionConfig(
        stopTimeout: 5,
        minimumActivityRecognitionConfidence: 75,
        disableStopDetection: false,
        stopDetectionDelay: 0,
        stopOnStationary: false,
      ),
      http: tl.HttpConfig(
        url: 'https://example.com/locations',
        autoSync: true,
        disableAutoSyncOnCellular: true,
      ),
      persistence: tl.PersistenceConfig(
        persistMode: tl.PersistMode.all,
        maxDaysToPersist: 7,
        maxRecordsToPersist: 5000,
        disableProviderChangeRecord: false,
      ),
      logger: tl.LoggerConfig(logLevel: tl.LogLevel.verbose, debug: true),
    ),
  );

  await tl.Tracelet.start();
}
