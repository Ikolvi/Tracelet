import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the Periodic Mode feature.
///
/// These tests verify GeoConfig serialization for periodic mode properties,
/// tracking mode enum, and configuration combinations. Actual periodic
/// scheduling requires a real device with background execution.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('GeoConfig — Periodic Mode Properties', () {
    testWidgets('GeoConfig accepts periodic mode properties', (tester) async {
      const config = GeoConfig(
        periodicLocationInterval: 300,
        periodicDesiredAccuracy: DesiredAccuracy.high,
        periodicUseForegroundService: true,
        periodicUseExactAlarms: false,
      );

      expect(config.periodicLocationInterval, 300);
      expect(config.periodicDesiredAccuracy, DesiredAccuracy.high);
      expect(config.periodicUseForegroundService, isTrue);
      expect(config.periodicUseExactAlarms, isFalse);
    });

    testWidgets('GeoConfig periodic defaults are correct', (tester) async {
      const config = GeoConfig();

      expect(config.periodicLocationInterval, 900);
      expect(config.periodicDesiredAccuracy, DesiredAccuracy.medium);
      expect(config.periodicUseForegroundService, isFalse);
      expect(config.periodicUseExactAlarms, isFalse);
    });

    testWidgets('GeoConfig.toMap includes periodic fields', (tester) async {
      const config = GeoConfig(
        periodicLocationInterval: 1800,
        periodicDesiredAccuracy: DesiredAccuracy.low,
        periodicUseForegroundService: false,
        periodicUseExactAlarms: true,
      );
      final map = config.toMap();

      expect(map['periodicLocationInterval'], 1800);
      expect(map['periodicUseExactAlarms'], isTrue);
    });
  });

  group('Periodic Mode — Configuration Combinations', () {
    testWidgets('WorkManager config (default)', (tester) async {
      const config = GeoConfig(
        periodicLocationInterval: 900,
        periodicDesiredAccuracy: DesiredAccuracy.medium,
        periodicUseForegroundService: false,
        periodicUseExactAlarms: false,
      );

      // WorkManager: no notification, 15-min minimum
      expect(config.periodicUseForegroundService, isFalse);
      expect(config.periodicUseExactAlarms, isFalse);
      expect(config.periodicLocationInterval, greaterThanOrEqualTo(60));
    });

    testWidgets('Foreground Service config', (tester) async {
      const config = GeoConfig(
        periodicLocationInterval: 300, // 5 min — needs FG service
        periodicDesiredAccuracy: DesiredAccuracy.high,
        periodicUseForegroundService: true,
      );

      expect(config.periodicUseForegroundService, isTrue);
      expect(config.periodicLocationInterval, 300);
    });

    testWidgets('Exact Alarms config', (tester) async {
      const config = GeoConfig(
        periodicLocationInterval: 1800,
        periodicDesiredAccuracy: DesiredAccuracy.medium,
        periodicUseForegroundService: false,
        periodicUseExactAlarms: true,
      );

      expect(config.periodicUseExactAlarms, isTrue);
      expect(config.periodicUseForegroundService, isFalse);
    });

    testWidgets('min interval boundary (60s)', (tester) async {
      const config = GeoConfig(periodicLocationInterval: 60);
      expect(config.periodicLocationInterval, 60);
    });

    testWidgets('max interval boundary (43200s = 12hr)', (tester) async {
      const config = GeoConfig(periodicLocationInterval: 43200);
      expect(config.periodicLocationInterval, 43200);
    });
  });

  group('TrackingMode — Enum Values', () {
    testWidgets('TrackingMode.periodic exists', (tester) async {
      expect(TrackingMode.periodic, isNotNull);
      expect(TrackingMode.periodic, isA<TrackingMode>());
    });

    testWidgets('all tracking modes are available', (tester) async {
      expect(TrackingMode.location, isNotNull);
      expect(TrackingMode.geofences, isNotNull);
      expect(TrackingMode.periodic, isNotNull);
    });
  });

  group('Config — Full Periodic Config', () {
    testWidgets('Config round-trips periodic settings through toMap', (
      tester,
    ) async {
      final config = Config(
        geo: const GeoConfig(
          periodicLocationInterval: 600,
          periodicDesiredAccuracy: DesiredAccuracy.high,
          periodicUseForegroundService: true,
          periodicUseExactAlarms: false,
        ),
      );

      final map = config.toMap();
      final geoMap = map['geo'] as Map<String, Object?>;
      expect(geoMap['periodicLocationInterval'], 600);
      expect(geoMap['periodicUseForegroundService'], isTrue);
    });

    testWidgets('periodic config combined with app config', (tester) async {
      final config = Config(
        geo: const GeoConfig(
          periodicLocationInterval: 900,
          periodicUseForegroundService: true,
        ),
        app: const AppConfig(
          stopOnTerminate: false,
          startOnBoot: true,
          foregroundService: ForegroundServiceConfig(
            notificationTitle: 'Periodic Tracking',
            notificationText: 'Check-in every 15 min',
          ),
        ),
      );

      final map = config.toMap();
      expect(map.containsKey('geo'), isTrue);
      expect(map.containsKey('app'), isTrue);
    });
  });
}
