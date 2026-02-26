import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('KalmanLocationFilter', () {
    late KalmanLocationFilter filter;

    setUp(() {
      filter = KalmanLocationFilter();
    });

    test('starts uninitialized', () {
      expect(filter.isInitialized, isFalse);
      expect(filter.estimatedSpeed, 0.0);
    });

    test('first measurement initializes and returns same coords', () {
      final result = filter.process(
        latitude: 37.4219983,
        longitude: -122.084,
        accuracy: 16.0,
        timestampMs: 1000000,
      );

      expect(filter.isInitialized, isTrue);
      expect(result.latitude, 37.4219983);
      expect(result.longitude, -122.084);
    });

    test('subsequent measurements produce smoothed output', () {
      // First fix — initializes
      filter.process(
        latitude: 37.4220,
        longitude: -122.0840,
        accuracy: 10.0,
        timestampMs: 1000000,
      );

      // Second fix — should produce smoothed output
      final result = filter.process(
        latitude: 37.4221,
        longitude: -122.0841,
        accuracy: 10.0,
        timestampMs: 1001000, // 1 second later
      );

      expect(result.latitude, isNot(37.4221));
      expect(result.longitude, isNot(-122.0841));
      // Should be between origin and measurement
      expect(result.latitude, greaterThan(37.4220));
      expect(result.latitude, lessThan(37.4221));
    });

    test('reset clears state', () {
      filter.process(
        latitude: 37.4220,
        longitude: -122.0840,
        accuracy: 10.0,
        timestampMs: 1000000,
      );
      expect(filter.isInitialized, isTrue);

      filter.reset();

      expect(filter.isInitialized, isFalse);
      expect(filter.estimatedSpeed, 0.0);
    });

    test('identical timestamp returns previous result', () {
      filter.process(
        latitude: 37.4220,
        longitude: -122.0840,
        accuracy: 10.0,
        timestampMs: 1000000,
      );

      final result1 = filter.process(
        latitude: 37.4221,
        longitude: -122.0841,
        accuracy: 10.0,
        timestampMs: 1001000,
      );

      // Same timestamp — should return last smoothed value, not process again
      final result2 = filter.process(
        latitude: 37.4222,
        longitude: -122.0842,
        accuracy: 10.0,
        timestampMs: 1001000,
      );

      expect(result2.latitude, result1.latitude);
      expect(result2.longitude, result1.longitude);
    });

    test('accuracy clamped to minimum 1.0', () {
      final result = filter.process(
        latitude: 37.4220,
        longitude: -122.0840,
        accuracy: 0.0, // below min
        timestampMs: 1000000,
      );

      expect(result.latitude, 37.4220);
      expect(result.longitude, -122.0840);
      expect(filter.isInitialized, isTrue);
    });

    test('estimatedSpeed increases with movement', () {
      filter.process(
        latitude: 37.4220,
        longitude: -122.0840,
        accuracy: 5.0,
        timestampMs: 1000000,
      );
      expect(filter.estimatedSpeed, 0.0);

      // Move ~100m north over 1 second = ~100 m/s
      filter.process(
        latitude: 37.4229,
        longitude: -122.0840,
        accuracy: 5.0,
        timestampMs: 1001000,
      );
      expect(filter.estimatedSpeed, greaterThan(0.0));
    });

    test('poor accuracy shifts output less', () {
      filter.process(
        latitude: 37.4220,
        longitude: -122.0840,
        accuracy: 5.0,
        timestampMs: 1000000,
      );

      // With poor accuracy measurement should shift less
      final poorAccuracy = filter.process(
        latitude: 37.4230,
        longitude: -122.0840,
        accuracy: 500.0,
        timestampMs: 1001000,
      );

      filter.reset();

      filter.process(
        latitude: 37.4220,
        longitude: -122.0840,
        accuracy: 5.0,
        timestampMs: 1000000,
      );

      // With good accuracy measurement should shift more
      final goodAccuracy = filter.process(
        latitude: 37.4230,
        longitude: -122.0840,
        accuracy: 5.0,
        timestampMs: 1001000,
      );

      // Good accuracy should pull filter output closer to measurement
      expect(
        (goodAccuracy.latitude - 37.4230).abs(),
        lessThan((poorAccuracy.latitude - 37.4230).abs()),
      );
    });

    test('multiple measurements converge toward path', () {
      // Simulate walking north at ~1m/s
      const startLat = 37.4220;
      const lon = -122.0840;
      final latStep = 1.0 / 111320; // ~1 meter in latitude degrees

      ({double latitude, double longitude})? lastResult;

      for (var i = 0; i < 10; i++) {
        lastResult = filter.process(
          latitude: startLat + latStep * i,
          longitude: lon,
          accuracy: 10.0,
          timestampMs: 1000000 + i * 1000,
        );
      }

      // After 10 measurements, output should be close to last input
      final result = lastResult!;
      expect(result.latitude, closeTo(startLat + latStep * 9, latStep * 3));
      expect(result.longitude, closeTo(lon, 0.001));
    });
  });
}
