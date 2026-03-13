import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the Sparse Updates feature.
///
/// These tests verify GeoConfig serialization and default values for sparse
/// update properties. Actual filtering behavior requires active tracking
/// with real location events.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('GeoConfig — Sparse Update Properties', () {
    testWidgets('GeoConfig accepts sparse update properties', (tester) async {
      const config = GeoConfig(
        enableSparseUpdates: true,
        sparseDistanceThreshold: 100.0,
        sparseMaxIdleSeconds: 600,
      );

      expect(config.enableSparseUpdates, isTrue);
      expect(config.sparseDistanceThreshold, 100.0);
      expect(config.sparseMaxIdleSeconds, 600);
    });

    testWidgets('GeoConfig sparse update defaults are correct', (tester) async {
      const config = GeoConfig();

      expect(config.enableSparseUpdates, isFalse);
      expect(config.sparseDistanceThreshold, 50.0);
      expect(config.sparseMaxIdleSeconds, 300);
    });

    testWidgets('GeoConfig.toMap includes sparse update fields', (
      tester,
    ) async {
      const config = GeoConfig(
        enableSparseUpdates: true,
        sparseDistanceThreshold: 200.0,
        sparseMaxIdleSeconds: 0,
      );
      final map = config.toMap();

      expect(map['enableSparseUpdates'], isTrue);
      expect(map['sparseDistanceThreshold'], 200.0);
      expect(map['sparseMaxIdleSeconds'], 0);
    });

    testWidgets('sparse updates can disable idle timeout with 0', (
      tester,
    ) async {
      const config = GeoConfig(
        enableSparseUpdates: true,
        sparseMaxIdleSeconds: 0,
      );
      expect(config.sparseMaxIdleSeconds, 0);
    });

    testWidgets('sparse updates work with distanceFilter combination', (
      tester,
    ) async {
      const config = GeoConfig(
        distanceFilter: 10.0,
        enableSparseUpdates: true,
        sparseDistanceThreshold: 50.0,
      );

      // distanceFilter controls GPS radio wake (platform-level)
      // sparseDistanceThreshold controls recording (app-level)
      expect(config.distanceFilter, 10.0);
      expect(config.sparseDistanceThreshold, 50.0);
      expect(
        config.sparseDistanceThreshold,
        greaterThan(config.distanceFilter),
      );
    });
  });

  group('Config — Full Config with Sparse Updates', () {
    testWidgets('Config round-trips sparse updates through toMap', (
      tester,
    ) async {
      final config = Config(
        geo: const GeoConfig(
          enableSparseUpdates: true,
          sparseDistanceThreshold: 75.0,
          sparseMaxIdleSeconds: 120,
        ),
      );

      final map = config.toMap();
      final geoMap = map['geo'] as Map<String, Object?>;
      expect(geoMap['enableSparseUpdates'], isTrue);
      expect(geoMap['sparseDistanceThreshold'], 75.0);
      expect(geoMap['sparseMaxIdleSeconds'], 120);
    });
  });
}
