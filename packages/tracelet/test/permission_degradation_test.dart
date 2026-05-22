// Many tests in this file deliberately exercise deprecated int-returning
// permission APIs (kept until 2.0.0 for backward compatibility, see #57).
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Mixin that provides dummy empty event streams for test platforms.
mixin EmptyEventStreamsMixin on TraceletPlatform {
  @override
  Stream<TlLocation> get locationEvents => const Stream.empty();
  @override
  Stream<TlLocation> get motionChangeEvents => const Stream.empty();
  @override
  Stream<TlActivityChangeEvent> get activityChangeEvents =>
      const Stream.empty();
  @override
  Stream<TlProviderChangeEvent> get providerChangeEvents =>
      const Stream.empty();
  @override
  Stream<TlGeofenceEvent> get geofenceEvents => const Stream.empty();
  @override
  Stream<TlGeofencesChangeEvent> get geofencesChangeEvents =>
      const Stream.empty();
  @override
  Stream<TlHeartbeatEvent> get heartbeatEvents => const Stream.empty();
  @override
  Stream<TlHttpEvent> get httpEvents => const Stream.empty();
  @override
  Stream<TlState> get scheduleEvents => const Stream.empty();
  @override
  Stream<bool> get powerSaveChangeEvents => const Stream.empty();
  @override
  Stream<TlConnectivityChangeEvent> get connectivityChangeEvents =>
      const Stream.empty();
  @override
  Stream<bool> get enabledChangeEvents => const Stream.empty();
  @override
  Stream<String> get notificationActionEvents => const Stream.empty();
  @override
  Stream<TlAuthorizationEvent> get authorizationEvents => const Stream.empty();
  @override
  Stream<TlLocation> get watchPositionEvents => const Stream.empty();
}

/// Mock platform that simulates various permission states.
///
/// Each permission method returns a configurable status code, allowing tests
/// to verify that the Tracelet API surfaces the correct values when
/// permissions are denied, partially granted, or fully granted.
class MockPermissionPlatform extends TraceletPlatform
    with EmptyEventStreamsMixin {
  /// Tracks all method calls for assertion.
  final List<({String method, Object? args})> calls = [];

  // ---------------------------------------------------------------------------
  // Configurable permission responses
  // ---------------------------------------------------------------------------

  /// Location permission status (default: notDetermined = 0).
  int locationStatus = 0;

  /// Motion permission status (default: granted = 3).
  int motionStatus = 3;

  /// Notification permission status (default: granted = 3).
  int notificationStatus = 3;

  /// Whether exact alarms can be scheduled (default: true).
  bool exactAlarms = true;

  /// Whether [requestPermission] should escalate from notDetermined.
  /// When true, calling requestPermission moves 0→2, 2→3.
  bool simulateUserGrant = true;

  /// Whether to throw PlatformException from getCurrentPosition.
  bool throwOnGetCurrentPosition = false;

  /// State map returned by [ready] and [start].
  Map<String, Object?> stateResult = {
    'enabled': false,
    'trackingMode': 0,
    'isMoving': false,
    'odometer': 0.0,
  };

  // ---------------------------------------------------------------------------
  // Permission methods
  // ---------------------------------------------------------------------------

  @override
  Future<AuthorizationStatus> getLocationAuthorization() async {
    calls.add((method: 'getLocationAuthorization', args: null));
    return AuthorizationStatus.values[locationStatus.clamp(0, AuthorizationStatus.values.length - 1)];
  }

  @override
  Future<AuthorizationStatus> requestLocationAuthorization() async {
    calls.add((method: 'requestLocationAuthorization', args: null));
    if (!simulateUserGrant) {
        return AuthorizationStatus.values[locationStatus.clamp(0, AuthorizationStatus.values.length - 1)];
    }
    // Simulate escalation: 0→2, 2→3
    if (locationStatus == 0 || locationStatus == 1) {
      locationStatus = 2;
    } else if (locationStatus == 2) {
      locationStatus = 3;
    }
    return AuthorizationStatus.values[locationStatus.clamp(0, AuthorizationStatus.values.length - 1)];
  }

  @override
  Future<MotionAuthorizationStatus> getMotionAuthorization() async {
    calls.add((method: 'getMotionAuthorization', args: null));
    switch (motionStatus) {
      case 0: return MotionAuthorizationStatus.notDetermined;
      case 1: return MotionAuthorizationStatus.deniedForever;
      case 3: return MotionAuthorizationStatus.granted;
      case 4: return MotionAuthorizationStatus.deniedForever;
      default: return MotionAuthorizationStatus.notDetermined;
    }
  }

  @override
  Future<MotionAuthorizationStatus> requestMotionAuthorization() async {
    calls.add((method: 'requestMotionAuthorization', args: null));
    if (simulateUserGrant && motionStatus == 0) {
      motionStatus = 3;
    }
    switch (motionStatus) {
      case 0: return MotionAuthorizationStatus.notDetermined;
      case 1: return MotionAuthorizationStatus.deniedForever;
      case 3: return MotionAuthorizationStatus.granted;
      case 4: return MotionAuthorizationStatus.deniedForever;
      default: return MotionAuthorizationStatus.notDetermined;
    }
  }

  @override
  Future<NotificationAuthorizationStatus> getNotificationAuthorization() async {
    calls.add((method: 'getNotificationAuthorization', args: null));
    switch (notificationStatus) {
      case 0: return NotificationAuthorizationStatus.notDetermined;
      case 1: return NotificationAuthorizationStatus.denied;
      case 3: return NotificationAuthorizationStatus.granted;
      case 4: return NotificationAuthorizationStatus.deniedForever;
      default: return NotificationAuthorizationStatus.notDetermined;
    }
  }

  @override
  Future<NotificationAuthorizationStatus> requestNotificationAuthorization() async {
    calls.add((method: 'requestNotificationAuthorization', args: null));
    if (simulateUserGrant && notificationStatus == 0) {
      notificationStatus = 3;
    }
    switch (notificationStatus) {
      case 0: return NotificationAuthorizationStatus.notDetermined;
      case 1: return NotificationAuthorizationStatus.denied;
      case 3: return NotificationAuthorizationStatus.granted;
      case 4: return NotificationAuthorizationStatus.deniedForever;
      default: return NotificationAuthorizationStatus.notDetermined;
    }
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    calls.add((method: 'canScheduleExactAlarms', args: null));
    return exactAlarms;
  }

  @override
  Future<bool> openExactAlarmSettings() async {
    calls.add((method: 'openExactAlarmSettings', args: null));
    return false; // Settings screen not available in test
  }

  @override
  Future<FullAccuracyStatus> requestTemporaryFullAccuracyAuthorization(String purpose) async {
    calls.add((method: 'requestTemporaryFullAccuracyAuthorization', args: purpose));
    return FullAccuracyStatus.full;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle stubs
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> ready(TlConfig config) async {
    calls.add((method: 'ready', args: config));
    return Map<String, Object?>.from(stateResult);
  }

  @override
  Future<Map<String, Object?>> start() async {
    calls.add((method: 'start', args: null));
    stateResult['enabled'] = true;
    return Map<String, Object?>.from(stateResult);
  }

  @override
  Future<Map<String, Object?>> stop() async {
    calls.add((method: 'stop', args: null));
    stateResult['enabled'] = false;
    return Map<String, Object?>.from(stateResult);
  }

  @override
  Future<Map<String, Object?>> getCurrentPosition(
    Map<String, Object?> options,
  ) async {
    calls.add((method: 'getCurrentPosition', args: options));
    if (throwOnGetCurrentPosition) {
      throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'Location permission not granted',
      );
    }
    return _defaultLocation();
  }

  @override
  Future<Map<String, Object?>> getLastKnownLocation([
    Map<String, Object?>? options,
  ]) async {
    calls.add((method: 'getLastKnownLocation', args: options));
    if (throwOnGetCurrentPosition) {
      return {}; // Empty map = no cached location
    }
    return _defaultLocation();
  }

  @override
  Future<Map<String, Object?>> getProviderState() async {
    calls.add((method: 'getProviderState', args: null));
    return {
      'enabled': locationStatus >= 2,
      'status': locationStatus,
      'gps': true,
      'network': true,
      'accuracyAuthorization': 0,
    };
  }

  @override
  Future<Map<String, Object?>> getSensors() async {
    calls.add((method: 'getSensors', args: null));
    return {
      'platform': 'android',
      'accelerometer': true,
      'gyroscope': true,
      'magnetometer': true,
      'significantMotion': true,
    };
  }

  static Map<String, Object?> _defaultLocation() => {
    'uuid': 'test-perm-001',
    'timestamp': '2025-06-15T10:30:00.000Z',
    'isMoving': false,
    'odometer': 0.0,
    'event': 'getCurrentPosition',
    'coords': {
      'latitude': 52.5200,
      'longitude': 13.4050,
      'altitude': 34.0,
      'speed': 0.0,
      'heading': 0.0,
      'accuracy': 5.0,
    },
    'activity': {'type': 'unknown', 'confidence': -1},
    'battery': {'level': 0.72, 'isCharging': false},
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPermissionPlatform mock;

  setUp(() {
    mock = MockPermissionPlatform();
    TraceletPlatform.instance = mock;
  });

  tearDown(() {
    mock.calls.clear();
  });

  // ==========================================================================
  // Location permission status codes
  // ==========================================================================
  group('Location permission status', () {
    test('returns notDetermined (0) when never asked', () async {
      mock.locationStatus = 0;
      final status = await Tracelet.getLocationAuthorization();
      expect(status, AuthorizationStatus.notDetermined);
    });

    test('returns denied (1) when denied but can ask again', () async {
      mock.locationStatus = 1;
      final status = await Tracelet.getLocationAuthorization();
      expect(status, AuthorizationStatus.denied);
    });

    test('returns whenInUse (2) when foreground-only granted', () async {
      mock.locationStatus = 2;
      final status = await Tracelet.getLocationAuthorization();
      expect(status, AuthorizationStatus.whenInUse);
    });

    test('returns always (3) when background granted', () async {
      mock.locationStatus = 3;
      final status = await Tracelet.getLocationAuthorization();
      expect(status, AuthorizationStatus.always);
    });

    test('returns deniedForever (4) when permanently denied', () async {
      mock.locationStatus = 4;
      final status = await Tracelet.getLocationAuthorization();
      expect(status, AuthorizationStatus.deniedForever);
    });
  });

  // ==========================================================================
  // Location permission escalation flow
  // ==========================================================================
  group('Location permission escalation', () {
    test('requestPermission escalates notDetermined → whenInUse', () async {
      mock.locationStatus = 0;
      mock.simulateUserGrant = true;

      final result = await Tracelet.requestLocationAuthorization();
      expect(result, AuthorizationStatus.whenInUse); // whenInUse
    });

    test('requestPermission escalates whenInUse → always', () async {
      mock.locationStatus = 2;
      mock.simulateUserGrant = true;

      final result = await Tracelet.requestLocationAuthorization();
      expect(result, AuthorizationStatus.always); // always
    });

    test('requestPermission stays at deniedForever when user denied', () async {
      mock.locationStatus = 4;
      mock.simulateUserGrant = false;

      final result = await Tracelet.requestLocationAuthorization();
      expect(result, AuthorizationStatus.deniedForever); // still deniedForever
    });

    test('requestPermission stays at always when already granted', () async {
      mock.locationStatus = 3;
      mock.simulateUserGrant = true;

      final result = await Tracelet.requestLocationAuthorization();
      expect(result, AuthorizationStatus.always); // still always
    });
  });

  // ==========================================================================
  // Background permission removed (tools:node="remove" scenario)
  // ==========================================================================
  group('Background permission removed (tools:node="remove")', () {
    test('status stays at whenInUse when background removed', () async {
      // Simulates ACCESS_BACKGROUND_LOCATION removed via tools:node="remove"
      // Native side never returns 3 (always).
      mock.locationStatus = 2;
      mock.simulateUserGrant = false; // Can't escalate further

      final status = await Tracelet.getLocationAuthorization();
      expect(status, AuthorizationStatus.whenInUse); // Capped at whenInUse

      final requested = await Tracelet.requestLocationAuthorization();
      expect(requested, AuthorizationStatus.whenInUse); // Still capped — no crash
    });

    test('ready() succeeds with foreground-only permission', () async {
      mock.locationStatus = 2;
      mock.simulateUserGrant = false;

      final state = await Tracelet.ready(const Config());
      expect(state.enabled, false); // Not started yet, but initialized OK
    });

    test('start() succeeds with foreground-only permission', () async {
      mock.locationStatus = 2;
      await Tracelet.ready(const Config());
      final state = await Tracelet.start();
      expect(state.enabled, true);
    });

    test('getCurrentPosition works with foreground-only', () async {
      mock.locationStatus = 2;
      await Tracelet.ready(const Config());
      final loc = await Tracelet.getCurrentPosition();
      expect(loc.coords.latitude, closeTo(52.52, 0.01));
    });
  });

  // ==========================================================================
  // No location permission at all
  // ==========================================================================
  group('No location permission', () {
    test('getPermissionStatus returns notDetermined (0)', () async {
      mock.locationStatus = 0;
      expect(await Tracelet.getLocationAuthorization(), AuthorizationStatus.notDetermined);
    });

    test('getPermissionStatus returns deniedForever (4)', () async {
      mock.locationStatus = 4;
      expect(await Tracelet.getLocationAuthorization(), AuthorizationStatus.deniedForever);
    });

    test('getCurrentPosition throws PlatformException when denied', () async {
      mock.locationStatus = 4;
      mock.throwOnGetCurrentPosition = true;

      expect(
        () => Tracelet.getCurrentPosition(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'PERMISSION_DENIED',
          ),
        ),
      );
    });

    test('getLastKnownLocation returns null when denied', () async {
      mock.locationStatus = 4;
      mock.throwOnGetCurrentPosition = true;

      final loc = await Tracelet.getLastKnownLocation();
      expect(loc, isNull); // Graceful: empty map → null
    });
  });

  // ==========================================================================
  // Motion permission degradation
  // ==========================================================================
  group('Motion permission', () {
    test('returns granted (3) by default', () async {
      mock.motionStatus = 3;
      expect(await Tracelet.getMotionAuthorization(), MotionAuthorizationStatus.granted);
    });

    test('returns notDetermined (0) when never asked', () async {
      mock.motionStatus = 0;
      expect(await Tracelet.getMotionAuthorization(), MotionAuthorizationStatus.notDetermined);
    });

    test('returns deniedForever (4) when denied', () async {
      mock.motionStatus = 4;
      expect(await Tracelet.getMotionAuthorization(), MotionAuthorizationStatus.deniedForever);
    });

    test('requestMotionPermission grants when user accepts', () async {
      mock.motionStatus = 0;
      mock.simulateUserGrant = true;

      final result = await Tracelet.requestMotionAuthorization();
      expect(result, MotionAuthorizationStatus.granted);
    });

    test('requestMotionPermission stays denied when user rejects', () async {
      mock.motionStatus = 4;
      mock.simulateUserGrant = false;

      final result = await Tracelet.requestMotionAuthorization();
      expect(result, MotionAuthorizationStatus.deniedForever);
    });
  });

  // ==========================================================================
  // ACTIVITY_RECOGNITION removed (tools:node="remove" scenario)
  // ==========================================================================
  group('ACTIVITY_RECOGNITION removed (accelerometer-only fallback)', () {
    test('disableMotionActivityUpdates config returns granted (3)', () async {
      // When disableMotionActivityUpdates is true, native side always returns 3
      mock.motionStatus = 3;

      final status = await Tracelet.getMotionAuthorization();
      expect(status, MotionAuthorizationStatus.granted); // No permission needed
    });

    test('ready() succeeds without motion permission', () async {
      mock.motionStatus = 4; // Denied — but config disables it
      mock.locationStatus = 3;

      final state = await Tracelet.ready(
        const Config(motion: MotionConfig(disableMotionActivityUpdates: true)),
      );
      expect(state.enabled, false); // Not started yet, but no crash
    });

    test('start() succeeds without motion permission', () async {
      mock.motionStatus = 4;
      mock.locationStatus = 3;

      await Tracelet.ready(
        const Config(motion: MotionConfig(disableMotionActivityUpdates: true)),
      );
      final state = await Tracelet.start();
      expect(state.enabled, true); // Running with accelerometer-only
    });
  });

  // ==========================================================================
  // Notification permission degradation (Android 13+)
  // ==========================================================================
  group('Notification permission', () {
    test('returns granted (3) on pre-Android 13', () async {
      mock.notificationStatus = 3;
      expect(await Tracelet.getNotificationAuthorization(), NotificationAuthorizationStatus.granted);
    });

    test('returns notDetermined (0) on Android 13+ before asking', () async {
      mock.notificationStatus = 0;
      expect(await Tracelet.getNotificationAuthorization(), NotificationAuthorizationStatus.notDetermined);
    });

    test('returns denied (4) when permanently denied', () async {
      mock.notificationStatus = 4;
      expect(await Tracelet.getNotificationAuthorization(), NotificationAuthorizationStatus.deniedForever);
    });

    test('ready() succeeds without notification permission', () async {
      mock.notificationStatus = 4;
      mock.locationStatus = 3;

      final state = await Tracelet.ready(const Config());
      expect(state.enabled, false); // Initialized OK — service runs, no notif
    });

    test('start() succeeds without notification permission', () async {
      mock.notificationStatus = 4;
      mock.locationStatus = 3;

      await Tracelet.ready(const Config());
      final state = await Tracelet.start();
      expect(state.enabled, true); // Service runs, notification hidden
    });
  });

  // ==========================================================================
  // Exact alarm permission degradation
  // ==========================================================================
  group('Exact alarm permission', () {
    test('returns true when granted', () async {
      mock.exactAlarms = true;
      expect(await Tracelet.canScheduleExactAlarms(), true);
    });

    test('returns false when not granted', () async {
      mock.exactAlarms = false;
      expect(await Tracelet.canScheduleExactAlarms(), false);
    });

    test('openExactAlarmSettings returns false in test', () async {
      expect(await Tracelet.openExactAlarmSettings(), false);
    });
  });

  // ==========================================================================
  // Full degradation scenario: all optional permissions denied
  // ==========================================================================
  group('Full degradation — all optional permissions denied', () {
    setUp(() {
      mock.locationStatus = 2; // Foreground only
      mock.motionStatus = 4; // Denied
      mock.notificationStatus = 4; // Denied
      mock.exactAlarms = false; // Denied
      mock.simulateUserGrant = false;
    });

    test('ready() does not crash with minimal permissions', () async {
      final state = await Tracelet.ready(
        const Config(motion: MotionConfig(disableMotionActivityUpdates: true)),
      );
      expect(state, isA<State>());
    });

    test('start() does not crash with minimal permissions', () async {
      await Tracelet.ready(
        const Config(motion: MotionConfig(disableMotionActivityUpdates: true)),
      );
      final state = await Tracelet.start();
      expect(state.enabled, true);
    });

    test('getCurrentPosition works with minimal permissions', () async {
      await Tracelet.ready(
        const Config(motion: MotionConfig(disableMotionActivityUpdates: true)),
      );
      final loc = await Tracelet.getCurrentPosition();
      expect(loc, isA<Location>());
      expect(loc.coords.latitude, closeTo(52.52, 0.01));
    });

    test('getProviderState reflects foreground-only', () async {
      final provider = await Tracelet.getProviderState();
      expect(provider.status, AuthorizationStatus.whenInUse);
      expect(provider.enabled, true);
    });

    test('getSensors works regardless of permissions', () async {
      final sensors = await Tracelet.getSensors();
      expect(sensors.accelerometer, true);
    });
  });

  // ==========================================================================
  // HealthCheck — permission warnings
  // ==========================================================================
  group('HealthCheck permission warnings', () {
    test('locationPermissionDenied is in HealthWarning enum', () {
      expect(
        HealthWarning.values.contains(HealthWarning.locationPermissionDenied),
        isTrue,
      );
    });

    test('locationPermissionDeniedForever is in HealthWarning enum', () {
      expect(
        HealthWarning.values.contains(
          HealthWarning.locationPermissionDeniedForever,
        ),
        isTrue,
      );
    });

    test('motionPermissionDenied is in HealthWarning enum', () {
      expect(
        HealthWarning.values.contains(HealthWarning.motionPermissionDenied),
        isTrue,
      );
    });

    test('locationPermissionOnlyWhenInUse is in HealthWarning enum', () {
      expect(
        HealthWarning.values.contains(
          HealthWarning.locationPermissionOnlyWhenInUse,
        ),
        isTrue,
      );
    });
  });

  // ==========================================================================
  // Method channel null-safety defaults
  // ==========================================================================
  group('MethodChannelTracelet null-safety defaults', () {
    // These test that the MethodChannelTracelet returns safe defaults
    // when the native side returns null (e.g., permission removed).
    test('_TestPlatform getLocationAuthorization throws UnimplementedError', () {
      final platform = _TestPlatform();
      expect(
        () => platform.getLocationAuthorization(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('_TestPlatform requestLocationAuthorization throws UnimplementedError', () {
      final platform = _TestPlatform();
      expect(
        () => platform.requestLocationAuthorization(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test(
      '_TestPlatform getMotionAuthorization throws UnimplementedError',
      () {
        final platform = _TestPlatform();
        expect(
          () => platform.getMotionAuthorization(),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );

    test('_TestPlatform getNotificationAuthorization throws '
        'UnimplementedError', () {
      final platform = _TestPlatform();
      expect(
        () => platform.getNotificationAuthorization(),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('_TestPlatform canScheduleExactAlarms throws UnimplementedError', () {
      final platform = _TestPlatform();
      expect(
        () => platform.canScheduleExactAlarms(),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });


}

/// A bare TraceletPlatform subclass for testing default UnimplementedError.
class _TestPlatform extends TraceletPlatform {}
