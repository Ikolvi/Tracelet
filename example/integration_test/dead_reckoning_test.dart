import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the Dead Reckoning feature.
///
/// These tests verify GeoConfig serialization, fromMap round-trips,
/// method channel calls, and edge cases. Actual IMU-based dead reckoning
/// requires a real device with active tracking and GPS signal loss.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('GeoConfig — Dead Reckoning Properties', () {
    testWidgets('GeoConfig accepts dead reckoning properties', (tester) async {
      const config = GeoConfig(
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 15,
        deadReckoningMaxDuration: 180,
      );

      expect(config.enableDeadReckoning, isTrue);
      expect(config.deadReckoningActivationDelay, 15);
      expect(config.deadReckoningMaxDuration, 180);
    });

    testWidgets('GeoConfig dead reckoning defaults are correct', (
      tester,
    ) async {
      const config = GeoConfig();

      expect(config.enableDeadReckoning, isFalse);
      expect(config.deadReckoningActivationDelay, 10);
      expect(config.deadReckoningMaxDuration, 120);
    });

    testWidgets('GeoConfig.toMap includes dead reckoning fields', (
      tester,
    ) async {
      const config = GeoConfig(
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 5,
        deadReckoningMaxDuration: 60,
      );
      final map = config.toMap();

      expect(map['enableDeadReckoning'], isTrue);
      expect(map['deadReckoningActivationDelay'], 5);
      expect(map['deadReckoningMaxDuration'], 60);
    });

    testWidgets('dead reckoning can be combined with other geo settings', (
      tester,
    ) async {
      const config = GeoConfig(
        desiredAccuracy: DesiredAccuracy.high,
        distanceFilter: 10.0,
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 10,
        deadReckoningMaxDuration: 120,
      );

      expect(config.desiredAccuracy, DesiredAccuracy.high);
      expect(config.distanceFilter, 10.0);
      expect(config.enableDeadReckoning, isTrue);
    });
  });

  group('GeoConfig — Dead Reckoning fromMap Round-Trip', () {
    testWidgets('fromMap restores all dead reckoning fields', (tester) async {
      const original = GeoConfig(
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 25,
        deadReckoningMaxDuration: 300,
      );
      final restored = GeoConfig.fromMap(original.toMap());

      expect(restored.enableDeadReckoning, isTrue);
      expect(restored.deadReckoningActivationDelay, 25);
      expect(restored.deadReckoningMaxDuration, 300);
    });

    testWidgets('fromMap uses fallback defaults for missing DR keys', (
      tester,
    ) async {
      final config = GeoConfig.fromMap(const <String, Object?>{});

      expect(config.enableDeadReckoning, isFalse);
      expect(config.deadReckoningActivationDelay, 10);
      expect(config.deadReckoningMaxDuration, 120);
    });

    testWidgets('fromMap handles null DR values gracefully', (tester) async {
      final config = GeoConfig.fromMap(const <String, Object?>{
        'enableDeadReckoning': null,
        'deadReckoningActivationDelay': null,
        'deadReckoningMaxDuration': null,
      });

      expect(config.enableDeadReckoning, isFalse);
      expect(config.deadReckoningActivationDelay, 10);
      expect(config.deadReckoningMaxDuration, 120);
    });

    testWidgets('fromMap round-trip preserves disabled state', (tester) async {
      const original = GeoConfig(
        enableDeadReckoning: false,
        deadReckoningActivationDelay: 10,
        deadReckoningMaxDuration: 120,
      );
      final restored = GeoConfig.fromMap(original.toMap());

      expect(restored.enableDeadReckoning, isFalse);
      expect(restored.deadReckoningActivationDelay, 10);
      expect(restored.deadReckoningMaxDuration, 120);
    });

    testWidgets('fromMap round-trip with extreme values', (tester) async {
      const original = GeoConfig(
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 1,
        deadReckoningMaxDuration: 3600,
      );
      final map = original.toMap();
      final restored = GeoConfig.fromMap(map);

      expect(restored.enableDeadReckoning, isTrue);
      expect(restored.deadReckoningActivationDelay, 1);
      expect(restored.deadReckoningMaxDuration, 3600);
    });
  });

  group('Config — Full Config with Dead Reckoning', () {
    testWidgets('Config round-trips dead reckoning through toMap', (
      tester,
    ) async {
      final config = Config(
        geo: const GeoConfig(
          enableDeadReckoning: true,
          deadReckoningActivationDelay: 20,
          deadReckoningMaxDuration: 90,
        ),
      );

      final map = config.toMap();
      final geoMap = map['geo'] as Map<String, Object?>;
      expect(geoMap['enableDeadReckoning'], isTrue);
      expect(geoMap['deadReckoningActivationDelay'], 20);
      expect(geoMap['deadReckoningMaxDuration'], 90);
    });

    testWidgets('Config combines DR with enterprise features', (tester) async {
      final config = Config(
        geo: const GeoConfig(
          enableDeadReckoning: true,
          deadReckoningActivationDelay: 15,
          deadReckoningMaxDuration: 240,
          enableSparseUpdates: true,
          sparseDistanceThreshold: 100.0,
        ),
      );

      final map = config.toMap();
      final geoMap = map['geo'] as Map<String, Object?>;

      // Dead reckoning fields
      expect(geoMap['enableDeadReckoning'], isTrue);
      expect(geoMap['deadReckoningActivationDelay'], 15);
      expect(geoMap['deadReckoningMaxDuration'], 240);

      // Sparse updates fields co-exist
      expect(geoMap['enableSparseUpdates'], isTrue);
      expect(geoMap['sparseDistanceThreshold'], 100.0);
    });
  });

  group('GeoConfig — Dead Reckoning Equality', () {
    testWidgets('configs with same DR values are equal', (tester) async {
      const a = GeoConfig(
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 10,
        deadReckoningMaxDuration: 120,
      );
      const b = GeoConfig(
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 10,
        deadReckoningMaxDuration: 120,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    testWidgets('configs with different DR values are not equal', (
      tester,
    ) async {
      const a = GeoConfig(
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 10,
      );
      const b = GeoConfig(
        enableDeadReckoning: true,
        deadReckoningActivationDelay: 20,
      );

      expect(a, isNot(equals(b)));
    });
  });

  group('Tracelet — Dead Reckoning API', () {
    testWidgets('getDeadReckoningState returns null when not tracking', (
      tester,
    ) async {
      final state = await Tracelet.getDeadReckoningState();
      expect(state, isNull);
    });
  });
}
