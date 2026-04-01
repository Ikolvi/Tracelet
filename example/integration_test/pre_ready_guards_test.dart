import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for pre-ready guard safety (issue #46).
///
/// Verifies that calling any SDK method before `Tracelet.ready()` does NOT
/// crash the app. Every method must return a safe default value rather than
/// triggering a force-unwrap on uninitialised native subsystems.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Pre-ready guards — Lifecycle', () {
    testWidgets('getState before ready returns disabled state', (tester) async {
      final state = await Tracelet.getState();

      expect(state.enabled, isFalse);
      expect(state.isMoving, isFalse);
      expect(state.trackingMode, TrackingMode.location);
      expect(state.odometer, 0.0);
    });

    testWidgets('stop before ready returns safely without throwing', (
      tester,
    ) async {
      // Since issue #46 fix, stop() before ready() returns silently
      // with a safe default state instead of throwing NOT_READY.
      final state = await Tracelet.stop();
      expect(state.enabled, isFalse);
    });

    testWidgets('getState then conditional stop mirrors issue #46 flow', (
      tester,
    ) async {
      // Exact reproduction of the reporter's code:
      //   isRunning = (await getState()).enabled
      //   if (isRunning) stop()
      final state = await Tracelet.getState();
      final isRunning = state.enabled;
      expect(isRunning, isFalse);

      // Because isRunning is false, stop() is never called — no crash.
      if (isRunning) {
        await Tracelet.stop();
      }
    });
  });

  group('Pre-ready guards — Location', () {
    testWidgets('getOdometer before ready returns zero', (tester) async {
      final odometer = await Tracelet.getOdometer();
      expect(odometer, 0.0);
    });
  });

  group('Pre-ready guards — Geofencing', () {
    testWidgets('getGeofences before ready returns empty list', (tester) async {
      final geofences = await Tracelet.getGeofences();
      expect(geofences, isEmpty);
    });

    testWidgets('geofenceExists before ready returns false', (tester) async {
      final exists = await Tracelet.geofenceExists('test-fence');
      expect(exists, isFalse);
    });
  });

  group('Pre-ready guards — Persistence', () {
    testWidgets('getLocations before ready returns empty list', (tester) async {
      final locations = await Tracelet.getLocations();
      expect(locations, isEmpty);
    });

    testWidgets('getCount before ready returns zero', (tester) async {
      final count = await Tracelet.getCount();
      expect(count, 0);
    });
  });

  group('Pre-ready guards — Logging', () {
    testWidgets('getLog before ready returns empty string', (tester) async {
      final log = await Tracelet.getLog();
      expect(log, isEmpty);
    });
  });
}
