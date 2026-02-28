import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('LocationProcessor', () {
    late LocationProcessor processor;

    setUp(() {
      processor = LocationProcessor(distanceFilter: 10.0);
    });

    test('accepts first location (no previous reference)', () {
      final result = processor.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 1.5,
        timestampMs: 1000000,
      );

      expect(result.accepted, isTrue);
      expect(result.effectiveSpeed, 1.5);
      expect(result.odometerDelta, 0.0); // No distance for first point.
    });

    test('filters location below distanceFilter threshold', () {
      // First location — accepted.
      processor.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      // Second location — very close, should be filtered.
      final result = processor.process(
        latitude: 37.42201,
        longitude: -122.08411,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1001000,
      );

      expect(result.accepted, isFalse);
      expect(result.reason, 'DISTANCE_FILTER');
    });

    test('accepts location beyond distanceFilter threshold', () {
      processor.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      // ~111m north — well beyond 10m filter.
      final result = processor.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1010000,
      );

      expect(result.accepted, isTrue);
      expect(result.distance, greaterThan(10.0));
    });

    test('elasticity increases distance filter at higher speeds', () {
      final p = LocationProcessor(distanceFilter: 10.0);

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      // ~50m away, speed 30 m/s → speedFactor = 3.0 → effective = 30m.
      // 50m > 30m → should pass.
      final result = p.process(
        latitude: 37.42245,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 30.0,
        timestampMs: 1001000,
      );

      expect(result.accepted, isTrue);
    });

    test('elasticity disabled when disableElasticity is true', () {
      final p = LocationProcessor(
        distanceFilter: 10.0,
        disableElasticity: true,
      );

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      // 15m away with high speed. Without elasticity, 15m > 10m → accept.
      final result = p.process(
        latitude: 37.422135,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 50.0,
        timestampMs: 1001000,
      );

      expect(result.accepted, isTrue);
    });

    test('accuracy filter — discard policy returns error', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        trackingAccuracyThreshold: 20,
        filterPolicy: 2, // discard
      );

      // First location accepted.
      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      final result = p.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 50.0, // Exceeds threshold.
        speed: 0.0,
        timestampMs: 1010000,
      );

      expect(result.accepted, isFalse);
      expect(result.reason, 'ACCURACY_FILTER');
      expect(result.isError, isTrue);
      expect(result.errorMessage, contains('50.0'));
    });

    test('accuracy filter — ignore policy silently drops', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        trackingAccuracyThreshold: 20,
        filterPolicy: 1, // ignore
      );

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      final result = p.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 50.0,
        speed: 0.0,
        timestampMs: 1010000,
      );

      expect(result.accepted, isFalse);
      expect(result.reason, 'ACCURACY_FILTER');
      expect(result.isError, isFalse);
    });

    test('accuracy filter — adjust policy accepts first location', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        trackingAccuracyThreshold: 20,
        filterPolicy: 0, // adjust
      );

      // First location with bad accuracy — accepted because no previous.
      final result = p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 50.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      expect(result.accepted, isTrue);
    });

    test('speed filter rejects impossible speed', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        maxImpliedSpeed: 100, // 100 m/s max
      );

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      // ~1100m in 1 second = 1100 m/s → exceeds 100 m/s.
      final result = p.process(
        latitude: 37.4320,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1001000,
      );

      expect(result.accepted, isFalse);
      expect(result.reason, 'SPEED_FILTER');
    });

    test('speed filter accepts reasonable speed', () {
      final p = LocationProcessor(distanceFilter: 0.0, maxImpliedSpeed: 100);

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      // ~111m in 10 seconds = 11.1 m/s → within 100 m/s.
      final result = p.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1010000,
      );

      expect(result.accepted, isTrue);
    });

    test('odometer gating respects odometerAccuracyThreshold', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        odometerAccuracyThreshold: 20,
      );

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      // Good accuracy — should add to odometer.
      final r1 = p.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 15.0,
        speed: 0.0,
        timestampMs: 1010000,
      );

      expect(r1.accepted, isTrue);
      expect(r1.odometerDelta, greaterThan(0.0));

      // Bad accuracy — accepted but no odometer delta.
      final r2 = p.process(
        latitude: 37.4240,
        longitude: -122.0841,
        accuracy: 50.0,
        speed: 0.0,
        timestampMs: 1020000,
      );

      expect(r2.accepted, isTrue);
      expect(r2.odometerDelta, 0.0);
    });

    test('uses platform speed when available', () {
      final p = LocationProcessor(distanceFilter: 0.0);

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 5.0,
        timestampMs: 1000000,
      );

      final result = p.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 12.0,
        timestampMs: 1010000,
      );

      expect(result.effectiveSpeed, 12.0);
    });

    test('falls back to computed speed when platform speed is 0', () {
      final p = LocationProcessor(distanceFilter: 0.0);

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      final result = p.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1010000,
      );

      expect(result.effectiveSpeed, greaterThan(0.0));
    });

    test('reset clears internal state', () {
      final p = LocationProcessor(distanceFilter: 10.0);

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );
      expect(p.hasLastLocation, isTrue);

      p.reset();
      expect(p.hasLastLocation, isFalse);
    });

    test('copyWith preserves state but updates config', () {
      final p = LocationProcessor(distanceFilter: 10.0);

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 5.0,
        timestampMs: 1000000,
      );

      final p2 = p.copyWith(distanceFilter: 50.0);
      expect(p2.distanceFilter, 50.0);
      expect(p2.hasLastLocation, isTrue);
      expect(p2.lastEffectiveSpeed, 5.0);
    });

    test('elasticityMultiplier clamps to minimum 0.1', () {
      final p = LocationProcessor(
        distanceFilter: 100.0,
        elasticityMultiplier: 0.01, // Below minimum.
      );

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
      );

      // 15m away, speed 10 → factor=1, multiplier clamped to 0.1 → effective=10m.
      final result = p.process(
        latitude: 37.422135,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 10.0,
        timestampMs: 1001000,
      );

      // 15m > 10m → accepted.
      expect(result.accepted, isTrue);
    });

    // ========================================================================
    // Mock location filter
    // ========================================================================

    test('mock filter — disabled by default, mock locations pass through', () {
      final p = LocationProcessor(distanceFilter: 0.0);

      final result = p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
        isMock: true,
      );

      expect(result.accepted, isTrue);
    });

    test('mock filter — rejects mock location when enabled', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        rejectMockLocations: true,
      );

      final result = p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
        isMock: true,
      );

      expect(result.accepted, isFalse);
      expect(result.reason, 'MOCK_LOCATION');
      expect(result.isError, isFalse);
    });

    test('mock filter — discard policy returns error for mock location', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        rejectMockLocations: true,
        filterPolicy: 2, // discard
      );

      final result = p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
        isMock: true,
      );

      expect(result.accepted, isFalse);
      expect(result.reason, 'MOCK_LOCATION');
      expect(result.isError, isTrue);
      expect(result.errorMessage, contains('mock'));
    });

    test('mock filter — accepts real location when enabled', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        rejectMockLocations: true,
      );

      final result = p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 0.0,
        timestampMs: 1000000,
        isMock: false, // Real location
      );

      expect(result.accepted, isTrue);
    });

    test('copyWith preserves rejectMockLocations', () {
      final p = LocationProcessor(
        distanceFilter: 10.0,
        rejectMockLocations: true,
      );

      final p2 = p.copyWith(distanceFilter: 50.0);
      expect(p2.rejectMockLocations, isTrue);
    });

    // ─── P2 Heuristic tests ────────────────────────────────────────────────

    test(
      'timestamp monotonicity — rejects backward timestamp at heuristic level',
      () {
        final p = LocationProcessor(
          distanceFilter: 0.0,
          rejectMockLocations: true,
          mockDetectionLevel: 2, // heuristic
        );

        // First location — accepted.
        final r1 = p.process(
          latitude: 37.4220,
          longitude: -122.0841,
          accuracy: 10.0,
          speed: 1.0,
          timestampMs: 2000000,
        );
        expect(r1.accepted, isTrue);

        // Second location with earlier timestamp — should be rejected.
        final r2 = p.process(
          latitude: 37.4230,
          longitude: -122.0841,
          accuracy: 10.0,
          speed: 1.0,
          timestampMs: 1000000, // 1 second BEFORE the first
        );
        expect(r2.accepted, isFalse);
        expect(r2.reason, 'MOCK_LOCATION_TIMESTAMP');
      },
    );

    test('timestamp monotonicity — not checked at basic level', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        rejectMockLocations: true,
        mockDetectionLevel: 1, // basic
      );

      // First location — accepted.
      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 1.0,
        timestampMs: 2000000,
      );

      // Second location with earlier timestamp — NOT rejected at basic level.
      final r2 = p.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 1.0,
        timestampMs: 1000000,
      );
      expect(r2.accepted, isTrue);
    });

    test(
      'timestamp monotonicity — not checked when rejectMockLocations is false',
      () {
        final p = LocationProcessor(
          distanceFilter: 0.0,
          rejectMockLocations: false,
          mockDetectionLevel: 2, // heuristic but mock rejection disabled
        );

        p.process(
          latitude: 37.4220,
          longitude: -122.0841,
          accuracy: 10.0,
          speed: 1.0,
          timestampMs: 2000000,
        );

        final r2 = p.process(
          latitude: 37.4230,
          longitude: -122.0841,
          accuracy: 10.0,
          speed: 1.0,
          timestampMs: 1000000,
        );
        expect(r2.accepted, isTrue);
      },
    );

    test('timestamp monotonicity — discard policy returns error', () {
      final p = LocationProcessor(
        distanceFilter: 0.0,
        rejectMockLocations: true,
        mockDetectionLevel: 2,
        filterPolicy: 2, // discard
      );

      p.process(
        latitude: 37.4220,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 1.0,
        timestampMs: 2000000,
      );

      final r2 = p.process(
        latitude: 37.4230,
        longitude: -122.0841,
        accuracy: 10.0,
        speed: 1.0,
        timestampMs: 1000000,
      );
      expect(r2.accepted, isFalse);
      expect(r2.reason, 'MOCK_LOCATION_TIMESTAMP');
      expect(r2.isError, isTrue);
      expect(r2.errorMessage, contains('non-monotonic'));
    });

    test('copyWith preserves mockDetectionLevel', () {
      final p = LocationProcessor(distanceFilter: 10.0, mockDetectionLevel: 2);

      final p2 = p.copyWith(distanceFilter: 50.0);
      expect(p2.mockDetectionLevel, 2);
    });

    test('default mockDetectionLevel is basic (1)', () {
      final p = LocationProcessor();
      expect(p.mockDetectionLevel, 1);
    });
  });
}
