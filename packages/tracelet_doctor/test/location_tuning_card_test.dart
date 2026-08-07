import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/location_tuning_card.dart';

/// Pins the verdict [LocationTuningCard] reaches when the configured
/// thresholds and the ones in force disagree.
///
/// The disagreement itself is not the signal — it is expected while a
/// committed transport mode is auto-tuning the filter, and a bug (#303) when
/// auto-tuning is off. The card has to tell those apart, because they are the
/// same numbers on screen.
void main() {
  const configured = Config(
    geo: GeoConfig(
      distanceFilter: 20,
      filter: LocationFilter(
        trackingAccuracyThreshold: 30,
        odometerAccuracyThreshold: 25,
        maxImpliedSpeed: 60,
      ),
    ),
  );

  /// [configured] with auto-tuning from transport mode switched on.
  final autoTuning = configured.copyWith(
    classifier: const ClassifierConfig(autoTuneFromTransportMode: true),
  );

  /// The tuning that matches [configured] exactly.
  const matching = LocationTuning(
    distanceFilter: 20,
    trackingAccuracyThreshold: 30,
    odometerAccuracyThreshold: 25,
    maxImpliedSpeed: 60,
  );

  /// A vehicle-style tune: looser distance, tighter accuracy, faster ceiling.
  const tuned = LocationTuning(
    distanceFilter: 50,
    trackingAccuracyThreshold: 100,
    odometerAccuracyThreshold: 25,
    maxImpliedSpeed: 60,
  );

  Future<void> pump(
    WidgetTester tester, {
    required LocationTuning? tuning,
    Config config = configured,
    String platform = 'android',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: DoctorTheme.sheetBackground,
          body: SingleChildScrollView(
            child: LocationTuningCard(
              tuning: tuning,
              platform: platform,
              config: config,
            ),
          ),
        ),
      ),
    );
  }

  /// The colour of the [StatusChip] label — the card's verdict at a glance.
  Color? chipColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label.toUpperCase())).style?.color;

  group('LocationTuningCard', () {
    testWidgets('reports N/A when there is no processor yet', (tester) async {
      await pump(tester, tuning: null);

      expect(find.text('N/A'), findsOneWidget);
      expect(find.textContaining('No location processor yet'), findsOneWidget);
    });

    testWidgets('explains web has no filter state at all', (tester) async {
      await pump(tester, tuning: null, platform: 'web');

      expect(
        find.textContaining('browser Geolocation API'),
        findsOneWidget,
        reason: 'on web a null tuning is permanent, not "start tracking"',
      );
    });

    testWidgets('matching values read as configured, with no arrow', (
      tester,
    ) async {
      await pump(tester, tuning: matching);

      expect(chipColor(tester, 'As configured'), DoctorTheme.success);
      expect(
        find.textContaining('→'),
        findsNothing,
        reason: 'an unchanged threshold rendering `30 → 30 m` is noise',
      );
    });

    testWidgets(
      'a tune with auto-tuning ON is reported as expected, not a bug',
      (tester) async {
        await pump(tester, tuning: tuned, config: autoTuning);

        expect(chipColor(tester, 'Auto-tuned'), DoctorTheme.accent);
        expect(find.text('Mismatch'.toUpperCase()), findsNothing);
        expect(
          find.textContaining('committed transport mode is overriding'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the same numbers with auto-tuning OFF are a mismatch', (
      tester,
    ) async {
      await pump(tester, tuning: tuned);

      expect(
        chipColor(tester, 'Mismatch'),
        DoctorTheme.error,
        reason: 'nothing should be moving these thresholds — this is #303',
      );
      expect(
        find.textContaining('did not reach the native processor'),
        findsOneWidget,
      );
    });

    testWidgets('drifted thresholds show configured → in force', (
      tester,
    ) async {
      await pump(tester, tuning: tuned, config: autoTuning);

      // Distance filter and tracking accuracy moved; the other two did not.
      expect(find.text('20 → 50 m'), findsOneWidget);
      expect(find.text('30 → 100 m'), findsOneWidget);
      expect(find.text('25 m'), findsOneWidget);
      expect(find.text('60 m/s'), findsOneWidget);
    });

    testWidgets('surfaces whether auto-tuning is on at all', (tester) async {
      await pump(tester, tuning: matching, config: autoTuning);

      expect(find.text('Auto-tune from transport mode'), findsOneWidget);
    });
  });
}
