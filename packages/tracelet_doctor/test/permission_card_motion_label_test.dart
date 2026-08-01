import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/permission_card.dart';

/// Pins the motion-activity label rendered by [PermissionCard].
///
/// `HealthCheck.motionPermission` carries a `MotionAuthorizationStatus` index
/// (`notDetermined`, `granted`, `deniedForever` → 0, 1, 2), but the card decoded
/// it against CoreMotion's `CMAuthorizationStatus` scale, where index 1 is
/// `restricted`. A device with motion activity **granted** therefore showed a red
/// "Restricted", while the warning list beside it correctly said "All Clear" —
/// the warning path uses `== 2`, so it was unaffected.
///
/// The old switch also had a `3 => 'Granted'` branch that could never be reached,
/// since the enum has no index 3.
void main() {
  HealthCheck healthWithMotion(MotionAuthorizationStatus status) => HealthCheck(
    trackingEnabled: true,
    trackingMode: TrackingMode.location,
    timestamp: DateTime.utc(2026, 8, 2),
    locationPermission: AuthorizationStatus.always,
    motionPermission: status.index,
  );

  Future<void> pump(WidgetTester tester, HealthCheck health) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: DoctorTheme.sheetBackground,
          body: SingleChildScrollView(child: PermissionCard(health: health)),
        ),
      ),
    );
  }

  /// The colour the card applied to the motion value.
  Color? motionValueColor(WidgetTester tester, String label) {
    final text = tester.widget<Text>(find.text(label));
    return text.style?.color;
  }

  group('PermissionCard motion activity label', () {
    testWidgets('granted renders as Granted, never Restricted', (tester) async {
      await pump(tester, healthWithMotion(MotionAuthorizationStatus.granted));

      expect(find.text('Granted'), findsOneWidget);
      expect(
        find.text('Restricted'),
        findsNothing,
        reason: 'a granted motion permission must not read as Restricted',
      );
    });

    testWidgets('granted is coloured as success, not error', (tester) async {
      await pump(tester, healthWithMotion(MotionAuthorizationStatus.granted));

      expect(
        motionValueColor(tester, 'Granted'),
        DoctorTheme.success,
        reason: 'granted was previously rendered in the error colour',
      );
    });

    testWidgets('notDetermined renders as Not Determined', (tester) async {
      await pump(
        tester,
        healthWithMotion(MotionAuthorizationStatus.notDetermined),
      );

      expect(find.text('Not Determined'), findsOneWidget);
      expect(motionValueColor(tester, 'Not Determined'), DoctorTheme.warning);
    });

    testWidgets('deniedForever renders as Denied in the error colour', (
      tester,
    ) async {
      await pump(
        tester,
        healthWithMotion(MotionAuthorizationStatus.deniedForever),
      );

      expect(find.text('Denied'), findsOneWidget);
      expect(motionValueColor(tester, 'Denied'), DoctorTheme.error);
    });

    testWidgets('every enum value renders a label and none say Restricted', (
      tester,
    ) async {
      // Guards the whole mapping rather than one case: if the enum gains a
      // value, this fails until the card handles it. "Restricted" is not a
      // member of MotionAuthorizationStatus at all, so it must never appear.
      for (final status in MotionAuthorizationStatus.values) {
        await pump(tester, healthWithMotion(status));

        expect(
          find.text('Unknown'),
          findsNothing,
          reason: '$status fell through to Unknown',
        );
        expect(
          find.text('Restricted'),
          findsNothing,
          reason: '$status rendered as Restricted',
        );
      }
    });

    testWidgets('an out-of-range value degrades to Unknown', (tester) async {
      await pump(
        tester,
        HealthCheck(
          trackingEnabled: true,
          trackingMode: TrackingMode.location,
          timestamp: DateTime.utc(2026, 8, 2),
          locationPermission: AuthorizationStatus.always,
          motionPermission: 99,
        ),
      );

      expect(find.text('Unknown'), findsOneWidget);
    });
  });
}
