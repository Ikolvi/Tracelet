import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_doctor/src/doctor_theme.dart';
import 'package:tracelet_doctor/src/widgets/foreground_service_card.dart';

/// Pins how [ForegroundServiceCard] reports a service that is deliberately
/// demoted (#378).
///
/// `showNotificationOnPauseOnly` hides the notification by demoting the
/// service, so `serviceForeground` is legitimately false while the app is on
/// screen. Read off that boolean alone it is indistinguishable from a promotion
/// the OS refused — and the card used to say "Tracking requested but the
/// foreground service is not confirmed yet", which is a false alarm about a
/// configured behaviour. `lastForegroundPromotionResult: suppressed` is what
/// separates the two.
void main() {
  Map<String, Object?> health({
    required bool serviceForeground,
    String? result,
  }) => <String, Object?>{
    'desiredEnabled': true,
    'foregroundServiceEnabled': true,
    'serviceRunning': true,
    'serviceForeground': serviceForeground,
    'foregroundNotificationId': serviceForeground ? 7701 : null,
    'lastForegroundPromotionResult': result,
    'lastForegroundPromotionFailureClass': null,
    'lastForegroundPromotionFailureMessage': null,
    'lastForegroundTransitionAt': 1_760_000_000_000,
    'platform': 'android',
  };

  Future<void> pump(WidgetTester tester, Map<String, Object?> map) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: DoctorTheme.sheetBackground,
          body: SingleChildScrollView(
            child: ForegroundServiceCard(health: map),
          ),
        ),
      ),
    );
  }

  Color? chipColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label.toUpperCase())).style?.color;

  group('ForegroundServiceCard', () {
    testWidgets('a suppressed notification is not reported as a failure', (
      tester,
    ) async {
      await pump(
        tester,
        health(serviceForeground: false, result: 'suppressed'),
      );

      expect(chipColor(tester, 'Suppressed'), DoctorTheme.accent);
      expect(
        find.textContaining('showNotificationOnPauseOnly'),
        findsOneWidget,
        reason: 'the reader has to be told why the notification is gone',
      );
      expect(
        find.textContaining('not confirmed yet'),
        findsNothing,
        reason: 'nothing is pending — the demotion was asked for',
      );
    });

    testWidgets('a demotion still explains that it is refused under '
        'stopOnTerminate: false', (tester) async {
      await pump(
        tester,
        health(serviceForeground: false, result: 'suppressed'),
      );

      expect(find.textContaining('#378'), findsOneWidget);
    });

    testWidgets('an unexplained missing promotion is still a warning', (
      tester,
    ) async {
      await pump(tester, health(serviceForeground: false));

      expect(chipColor(tester, 'Pending'), DoctorTheme.warning);
      expect(find.textContaining('not confirmed yet'), findsOneWidget);
    });

    testWidgets('a failed promotion is still an error', (tester) async {
      await pump(tester, health(serviceForeground: false, result: 'failed'));

      expect(chipColor(tester, 'Failed'), DoctorTheme.error);
      expect(
        find.textContaining('NOT operational'),
        findsOneWidget,
        reason: 'the suppressed branch must not swallow a real failure',
      );
    });
  });
}
