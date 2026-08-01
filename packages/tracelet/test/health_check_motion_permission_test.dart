import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

/// Pins the meaning of [HealthCheck.motionPermission].
///
/// The field is populated from `MotionAuthorizationStatus.index`
/// (`notDetermined`, `granted`, `deniedForever` → 0, 1, 2) but was documented as
/// CoreMotion's `CMAuthorizationStatus` scale, which orders the cases
/// differently and has an extra `restricted` value. Doctor implemented the
/// documented contract, so a device with motion activity **granted** displayed a
/// red "Restricted" while the warning list simultaneously reported "All Clear".
///
/// The two scales disagreeing is the actual defect, so these tests assert the
/// decoding against the enum itself rather than against hardcoded integers.
void main() {
  group('HealthCheck.motionAuthorization', () {
    HealthCheck withMotion(int value) => HealthCheck(
      trackingEnabled: true,
      trackingMode: TrackingMode.location,
      timestamp: DateTime.utc(2026, 8, 2),
      motionPermission: value,
    );

    test('decodes each index to its MotionAuthorizationStatus', () {
      for (final status in MotionAuthorizationStatus.values) {
        expect(
          withMotion(status.index).motionAuthorization,
          status,
          reason: 'index ${status.index} must decode to $status',
        );
      }
    });

    test('index 1 is granted, not restricted', () {
      // The regression itself. CMAuthorizationStatus puts `restricted` at 1;
      // this enum puts `granted` there.
      expect(
        withMotion(1).motionAuthorization,
        MotionAuthorizationStatus.granted,
      );
    });

    test('returns null for an out-of-range value', () {
      // A newer or malformed payload must not throw or silently alias onto a
      // valid case.
      expect(withMotion(-1).motionAuthorization, isNull);
      expect(
        withMotion(MotionAuthorizationStatus.values.length).motionAuthorization,
        isNull,
      );
    });

    test('the denied warning threshold matches deniedForever', () {
      // _computeWarnings hardcodes `motionPermission == 2`. If the enum ever
      // gains or reorders a case, that constant silently stops meaning "denied".
      expect(MotionAuthorizationStatus.deniedForever.index, 2);
    });

    test('granted does not raise the motion-permission warning', () {
      final health = HealthCheck.fromMaps(
        state: const <String, Object?>{},
        provider: const <String, Object?>{},
        settingsHealth: const <String, Object?>{},
        sensors: const <String, Object?>{
          'accelerometer': true,
          'significantMotion': true,
        },
        deviceInfo: const <String, Object?>{},
        isPowerSave: false,
        ignoringBatteryOpt: true,
        locationPermissionStatus: AuthorizationStatus.always.index,
        motionPermissionStatus: MotionAuthorizationStatus.granted.index,
        dbCount: 0,
      );

      expect(health.motionAuthorization, MotionAuthorizationStatus.granted);
      expect(
        health.warnings,
        isNot(contains(HealthWarning.motionPermissionDenied)),
        reason: 'a granted permission must not be reported as denied',
      );
    });

    test('deniedForever does raise the motion-permission warning', () {
      final health = HealthCheck.fromMaps(
        state: const <String, Object?>{},
        provider: const <String, Object?>{},
        settingsHealth: const <String, Object?>{},
        sensors: const <String, Object?>{
          'accelerometer': true,
          'significantMotion': true,
        },
        deviceInfo: const <String, Object?>{},
        isPowerSave: false,
        ignoringBatteryOpt: true,
        locationPermissionStatus: AuthorizationStatus.always.index,
        motionPermissionStatus: MotionAuthorizationStatus.deniedForever.index,
        dbCount: 0,
      );

      expect(health.warnings, contains(HealthWarning.motionPermissionDenied));
    });
  });
}
