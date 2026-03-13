import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the Carbon Estimator.
///
/// These tests verify the pure-Dart [CarbonEstimator] lifecycle, emission
/// calculations, and [TripCarbonSummary] model correctness.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('CarbonEstimator — Trip Lifecycle', () {
    testWidgets('startTrip and endTrip with no locations returns null', (
      tester,
    ) async {
      final estimator = CarbonEstimator();
      estimator.startTrip();
      final summary = estimator.endTrip();

      // No locations fed — no summary
      expect(summary, isNull);
    });

    testWidgets('startTrip → locations → endTrip returns summary', (
      tester,
    ) async {
      final estimator = CarbonEstimator();
      estimator.startTrip();

      // Feed a sequence of locations ~100m apart (approx London coordinates)
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(51.5074, -0.1278);
      estimator.onLocationReceived(51.5084, -0.1278); // ~111m north

      final summary = estimator.endTrip();
      expect(summary, isNotNull);
      expect(summary!.totalDistanceMeters, greaterThan(0));
      expect(summary.totalCarbonGrams, greaterThan(0));
      expect(summary.dominantMode, 'in_vehicle');
    });

    testWidgets('zero-emission activities produce zero carbon', (tester) async {
      final estimator = CarbonEstimator();
      estimator.startTrip();
      estimator.setActivity('walking');
      estimator.onLocationReceived(51.5074, -0.1278);
      estimator.onLocationReceived(51.5084, -0.1278);

      final summary = estimator.endTrip();
      expect(summary, isNotNull);
      expect(summary!.totalDistanceMeters, greaterThan(0));
      expect(summary.totalCarbonGrams, 0.0);
      expect(summary.dominantMode, 'walking');
    });
  });

  group('CarbonEstimator — Multi-Mode Tracking', () {
    testWidgets('tracks carbon by mode correctly', (tester) async {
      final estimator = CarbonEstimator();
      estimator.startTrip();

      // Walk first segment
      estimator.setActivity('walking');
      estimator.onLocationReceived(51.5074, -0.1278);
      estimator.onLocationReceived(51.5084, -0.1278);

      // Drive second segment
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(51.5094, -0.1278);
      estimator.onLocationReceived(51.5104, -0.1278);

      final summary = estimator.endTrip();
      expect(summary, isNotNull);
      expect(summary!.carbonByMode.containsKey('walking'), isTrue);
      expect(summary.carbonByMode.containsKey('in_vehicle'), isTrue);
      expect(summary.carbonByMode['walking'], 0.0);
      expect(summary.carbonByMode['in_vehicle']!, greaterThan(0));
    });
  });

  group('CarbonEstimator — Custom Emission Factors', () {
    testWidgets('custom factors override defaults', (tester) async {
      final estimator = CarbonEstimator(
        emissionFactors: {
          'in_vehicle': 0.0, // Electric vehicle — zero emissions
        },
      );

      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(51.5074, -0.1278);
      estimator.onLocationReceived(51.5084, -0.1278);

      final summary = estimator.endTrip();
      expect(summary, isNotNull);
      expect(summary!.totalCarbonGrams, 0.0);
    });
  });

  group('CarbonEstimator — Cumulative Reporting', () {
    testWidgets('cumulative report aggregates across trips', (tester) async {
      final estimator = CarbonEstimator();

      // Trip 1
      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(51.5074, -0.1278);
      estimator.onLocationReceived(51.5084, -0.1278);
      estimator.endTrip();

      // Trip 2
      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(51.5094, -0.1278);
      estimator.onLocationReceived(51.5104, -0.1278);
      estimator.endTrip();

      final report = estimator.getCumulativeReport();
      expect(report['totalTrips'], 2);
      expect((report['totalCarbonGrams'] as double), greaterThan(0));
    });

    testWidgets('resetCumulative clears totals', (tester) async {
      final estimator = CarbonEstimator();

      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(51.5074, -0.1278);
      estimator.onLocationReceived(51.5084, -0.1278);
      estimator.endTrip();

      estimator.resetCumulative();
      final report = estimator.getCumulativeReport();
      expect(report['totalTrips'], 0);
      expect(report['totalCarbonGrams'], 0.0);
    });
  });

  group('TripCarbonSummary — Model', () {
    testWidgets('TripCarbonSummary has all required fields', (tester) async {
      final estimator = CarbonEstimator();
      estimator.startTrip();
      estimator.setActivity('bus');
      estimator.onLocationReceived(51.5074, -0.1278);
      estimator.onLocationReceived(51.5084, -0.1278);
      final summary = estimator.endTrip()!;

      expect(summary.totalCarbonGrams, isA<double>());
      expect(summary.totalDistanceMeters, isA<double>());
      expect(summary.carbonByMode, isA<Map<String, double>>());
      expect(summary.distanceByMode, isA<Map<String, double>>());
      expect(summary.dominantMode, isA<String>());
    });
  });
}
