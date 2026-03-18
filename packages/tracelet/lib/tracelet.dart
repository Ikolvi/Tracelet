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

// Re-export only the public types apps need — no platform channel internals.
// TraceletPlatform, MethodChannelTracelet, and TraceletEvents are intentionally
// hidden. Apps interact exclusively through the [Tracelet] class.
export 'package:tracelet_platform_interface/tracelet_platform_interface.dart'
    show
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
        LocationActivityType,
        PersistMode,
        LocationFilterPolicy,
        MockDetectionLevel,
        LocationAuthorizationRequest,
        NotificationPriority,
        HashAlgorithm,
        // Shared algorithms (pure Dart — work on all platforms)
        KalmanLocationFilter,
        TripManager,
        GeoUtils,
        DeltaEncoder,
        CarbonEstimator,
        TripCarbonSummary,
        BatteryBudgetEngine,
        BudgetAdjustmentEvent,
        RTree;

// Models
export 'src/models/attestation_config.dart';
export 'src/models/audit_config.dart';
export 'src/models/audit_proof.dart';
export 'src/models/compliance_report.dart';
export 'src/models/config.dart';
export 'src/models/privacy_zone.dart';
export 'src/models/privacy_zone_config.dart';
export 'src/models/security_config.dart';
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
export 'src/models/health_check.dart';
export 'src/models/connectivity_change_event.dart';
export 'src/models/authorization_event.dart';
export 'src/models/sql_query.dart';
export 'src/models/trip_event.dart';

// Main API
export 'src/tracelet.dart';
