import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('CarbonEstimator', () {
    late CarbonEstimator estimator;

    setUp(() {
      estimator = CarbonEstimator();
    });

    test('starts inactive', () {
      expect(estimator.isActive, isFalse);
      expect(estimator.cumulativeCarbonGrams, 0.0);
      expect(estimator.cumulativeTrips, 0);
    });

    test('startTrip makes estimator active', () {
      estimator.startTrip();
      expect(estimator.isActive, isTrue);
    });

    test('endTrip when not active returns null', () {
      expect(estimator.endTrip(), isNull);
    });

    test('endTrip returns summary and deactivates', () {
      estimator.startTrip();
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);

      final summary = estimator.endTrip();
      expect(summary, isNotNull);
      expect(estimator.isActive, isFalse);
    });

    test('walking produces zero carbon', () {
      estimator.startTrip();
      estimator.setActivity('walking');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);

      final summary = estimator.endTrip()!;
      expect(summary.totalCarbonGrams, 0.0);
      expect(summary.totalDistanceMeters, greaterThan(0));
      expect(summary.dominantMode, 'walking');
    });

    test('cycling produces zero carbon', () {
      estimator.startTrip();
      estimator.setActivity('on_bicycle');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7949, -122.3994);

      final summary = estimator.endTrip()!;
      expect(summary.totalCarbonGrams, 0.0);
    });

    test('in_vehicle produces positive carbon', () {
      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);

      final summary = estimator.endTrip()!;
      expect(summary.totalCarbonGrams, greaterThan(0));
      expect(summary.dominantMode, 'in_vehicle');
      expect(summary.carbonByMode['in_vehicle'], greaterThan(0));
    });

    test('onLocationReceived is ignored when not active', () {
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);

      estimator.startTrip();
      final summary = estimator.endTrip()!;
      expect(summary.totalDistanceMeters, 0.0);
    });

    test('first location sets baseline without accumulating distance', () {
      estimator.startTrip();
      estimator.onLocationReceived(37.7749, -122.4194);

      final summary = estimator.endTrip()!;
      expect(summary.totalDistanceMeters, 0.0);
    });

    test('mode switching tracks distance per mode', () {
      estimator.startTrip();

      // Walk for a bit
      estimator.setActivity('walking');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7759, -122.4184);

      // Switch to vehicle
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(37.7849, -122.4094);

      final summary = estimator.endTrip()!;
      expect(summary.distanceByMode.containsKey('walking'), isTrue);
      expect(summary.distanceByMode.containsKey('in_vehicle'), isTrue);
      expect(summary.distanceByMode['walking'], greaterThan(0));
      expect(summary.distanceByMode['in_vehicle'], greaterThan(0));
    });

    test('dominant mode is the one with most distance', () {
      estimator.startTrip();

      // Short walk
      estimator.setActivity('walking');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7750, -122.4193);

      // Long drive
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(37.7850, -122.4094);
      estimator.onLocationReceived(37.7950, -122.3994);

      final summary = estimator.endTrip()!;
      expect(summary.dominantMode, 'in_vehicle');
    });

    test('cumulative state accumulates across trips', () {
      // Trip 1
      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);
      estimator.endTrip();

      expect(estimator.cumulativeTrips, 1);
      final carbonAfterTrip1 = estimator.cumulativeCarbonGrams;
      expect(carbonAfterTrip1, greaterThan(0));

      // Trip 2
      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);
      estimator.endTrip();

      expect(estimator.cumulativeTrips, 2);
      expect(estimator.cumulativeCarbonGrams, greaterThan(carbonAfterTrip1));
    });

    test('getCumulativeReport returns structured map', () {
      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);
      estimator.endTrip();

      final report = estimator.getCumulativeReport();
      expect(report['totalCarbonGrams'], isA<double>());
      expect(report['totalTrips'], 1);
      expect(report['carbonByMode'], isA<Map<String, double>>());
      expect(report['distanceByMode'], isA<Map<String, double>>());
    });

    test('resetCumulative clears cumulative state only', () {
      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);
      estimator.endTrip();

      estimator.resetCumulative();
      expect(estimator.cumulativeCarbonGrams, 0.0);
      expect(estimator.cumulativeTrips, 0);
    });

    test('reset clears everything', () {
      estimator.startTrip();
      estimator.setActivity('in_vehicle');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);
      estimator.endTrip();

      estimator.reset();
      expect(estimator.isActive, isFalse);
      expect(estimator.cumulativeCarbonGrams, 0.0);
      expect(estimator.cumulativeTrips, 0);
    });

    test('custom emission factors override defaults', () {
      final custom = CarbonEstimator(
        emissionFactors: {'walking': 10.0, 'unknown': 0.0},
      );

      custom.startTrip();
      custom.setActivity('walking');
      custom.onLocationReceived(37.7749, -122.4194);
      custom.onLocationReceived(37.7849, -122.4094);

      final summary = custom.endTrip()!;
      // Walking with custom factor produces carbon
      expect(summary.totalCarbonGrams, greaterThan(0));
    });

    test('unknown activity uses unknown emission factor', () {
      estimator.startTrip();
      estimator.setActivity('unknown');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);

      final summary = estimator.endTrip()!;
      // Default unknown factor is 96 g/km
      expect(summary.totalCarbonGrams, greaterThan(0));
      expect(summary.dominantMode, 'unknown');
    });

    test('unrecognized activity falls back to unknown factor', () {
      estimator.startTrip();
      estimator.setActivity('jetpack');
      estimator.onLocationReceived(37.7749, -122.4194);
      estimator.onLocationReceived(37.7849, -122.4094);

      final summary = estimator.endTrip()!;
      // Should use unknown factor since 'jetpack' isn't in defaults
      expect(summary.totalCarbonGrams, greaterThan(0));
    });
  });

  group('TripCarbonSummary', () {
    test('toMap returns structured map', () {
      const summary = TripCarbonSummary(
        totalCarbonGrams: 123.45,
        totalDistanceMeters: 5000.0,
        carbonByMode: {'in_vehicle': 123.45},
        distanceByMode: {'in_vehicle': 5000.0},
        dominantMode: 'in_vehicle',
      );

      final map = summary.toMap();
      expect(map['totalCarbonGrams'], 123.45);
      expect(map['totalDistanceMeters'], 5000.0);
      expect(map['dominantMode'], 'in_vehicle');
      expect(map['carbonByMode'], isA<Map<String, double>>());
      expect(map['distanceByMode'], isA<Map<String, double>>());
    });
  });

  group('kDefaultEmissionFactors', () {
    test('contains expected transport modes', () {
      expect(kDefaultEmissionFactors.containsKey('in_vehicle'), isTrue);
      expect(kDefaultEmissionFactors.containsKey('on_bicycle'), isTrue);
      expect(kDefaultEmissionFactors.containsKey('walking'), isTrue);
      expect(kDefaultEmissionFactors.containsKey('running'), isTrue);
      expect(kDefaultEmissionFactors.containsKey('on_foot'), isTrue);
      expect(kDefaultEmissionFactors.containsKey('bus'), isTrue);
      expect(kDefaultEmissionFactors.containsKey('train'), isTrue);
      expect(kDefaultEmissionFactors.containsKey('unknown'), isTrue);
    });

    test('zero-emission modes are zero', () {
      expect(kDefaultEmissionFactors['walking'], 0.0);
      expect(kDefaultEmissionFactors['on_bicycle'], 0.0);
      expect(kDefaultEmissionFactors['running'], 0.0);
      expect(kDefaultEmissionFactors['on_foot'], 0.0);
    });

    test('motorized modes have positive factors', () {
      expect(kDefaultEmissionFactors['in_vehicle']!, greaterThan(0));
      expect(kDefaultEmissionFactors['bus']!, greaterThan(0));
      expect(kDefaultEmissionFactors['train']!, greaterThan(0));
    });

    test('bus emits less than car', () {
      expect(
        kDefaultEmissionFactors['bus']!,
        lessThan(kDefaultEmissionFactors['in_vehicle']!),
      );
    });

    test('train emits less than bus', () {
      expect(
        kDefaultEmissionFactors['train']!,
        lessThan(kDefaultEmissionFactors['bus']!),
      );
    });
  });
}
