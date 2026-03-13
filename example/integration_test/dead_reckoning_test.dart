import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the Dead Reckoning feature.
///
/// These tests verify GeoConfig serialization of dead reckoning properties.
/// Actual IMU-based dead reckoning requires a real device with active tracking
/// and GPS signal loss — not testable in integration tests.
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
  });
}
