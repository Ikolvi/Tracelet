/// Tracelet — Production-grade background geolocation for Flutter.
///
/// Battery-conscious motion-detection intelligence, geofencing, SQLite
/// persistence, HTTP sync, and headless Dart execution for iOS & Android.
///
/// ```dart
/// import 'package:tracelet/tracelet.dart' as tl;
///
/// // 1. Listen to events
/// tl.Tracelet.onLocation((location) => print(location));
///
/// // 2. Configure & ready
/// await tl.Tracelet.ready(tl.Config(
///   geo: tl.GeoConfig(distanceFilter: 10),
/// ));
///
/// // 3. Start tracking
/// await tl.Tracelet.start();
/// ```
library;

// Re-export platform interface types
export 'package:tracelet_platform_interface/tracelet_platform_interface.dart'
    show
        TraceletEvents,
        DesiredAccuracy,
        LogLevel,
        ActivityType,
        ActivityConfidence,
        TrackingMode,
        GeofenceAction,
        AuthorizationStatus,
        AccuracyAuthorization,
        HttpMethod,
        LocationOrder,
        LocationActivityType;

// Models
export 'src/models/config.dart';
export 'src/models/location.dart';
export 'src/models/state.dart';
export 'src/models/geofence.dart';
export 'src/models/geofence_event.dart';
export 'src/models/geofences_change_event.dart';
export 'src/models/provider_change_event.dart';
export 'src/models/activity_change_event.dart';
export 'src/models/http_event.dart';
export 'src/models/heartbeat_event.dart';
export 'src/models/headless_event.dart';
export 'src/models/sensors.dart';
export 'src/models/device_info.dart';
export 'src/models/connectivity_change_event.dart';
export 'src/models/authorization_event.dart';
export 'src/models/sql_query.dart';

// Main API
export 'src/tracelet.dart';
