import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for GPS-off fallback and iOS reduced accuracy features.
///
/// These tests verify Location and ProviderChangeEvent serialization for
/// the `reducedAccuracy`, `locationSource`, and `gpsFallback` fields.
/// Actual GPS/accuracy state changes require real hardware — these tests
/// validate the Dart model contract end-to-end.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Location — reducedAccuracy field', () {
    testWidgets('reducedAccuracy defaults to false', (tester) async {
      final loc = Location.fromMap(const {
        'uuid': 'int-ra-default',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      expect(loc.reducedAccuracy, isFalse);
    });

    testWidgets('reducedAccuracy parsed when true', (tester) async {
      final loc = Location.fromMap(const {
        'uuid': 'int-ra-true',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'reducedAccuracy': true,
        'coords': {'latitude': 37.0, 'longitude': -122.0, 'accuracy': 5000.0},
      });
      expect(loc.reducedAccuracy, isTrue);
    });

    testWidgets('reducedAccuracy round-trips through toMap/fromMap', (
      tester,
    ) async {
      final original = Location.fromMap(const {
        'uuid': 'int-ra-rt',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'reducedAccuracy': true,
        'locationSource': 'cell',
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });

      final map = original.toMap();
      expect(map['reducedAccuracy'], isTrue);

      final restored = Location.fromMap(map);
      expect(restored.reducedAccuracy, isTrue);
      expect(restored.locationSource, 'cell');
    });

    testWidgets('reducedAccuracy preserved in copyWithCoords', (tester) async {
      final original = Location.fromMap(const {
        'uuid': 'int-ra-copy',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'reducedAccuracy': true,
        'coords': {'latitude': 37.0, 'longitude': -122.0},
      });
      final copy = original.copyWithCoords(latitude: 38.0);
      expect(copy.reducedAccuracy, isTrue);
      expect(copy.coords.latitude, 38.0);
    });
  });

  group('Location — locationSource field', () {
    testWidgets('locationSource classifies GPS fix', (tester) async {
      final loc = Location.fromMap(const {
        'uuid': 'int-src-gps',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': true,
        'odometer': 100.0,
        'locationSource': 'gps',
        'coords': {'latitude': 37.0, 'longitude': -122.0, 'accuracy': 10.0},
      });
      expect(loc.locationSource, 'gps');
    });

    testWidgets('locationSource classifies Wi-Fi fix', (tester) async {
      final loc = Location.fromMap(const {
        'uuid': 'int-src-wifi',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'locationSource': 'wifi',
        'coords': {'latitude': 37.0, 'longitude': -122.0, 'accuracy': 100.0},
      });
      expect(loc.locationSource, 'wifi');
    });

    testWidgets('locationSource classifies cell fix', (tester) async {
      final loc = Location.fromMap(const {
        'uuid': 'int-src-cell',
        'timestamp': '2024-01-01T00:00:00Z',
        'is_moving': false,
        'odometer': 0.0,
        'locationSource': 'cell',
        'reducedAccuracy': true,
        'coords': {'latitude': 37.0, 'longitude': -122.0, 'accuracy': 5000.0},
      });
      expect(loc.locationSource, 'cell');
      expect(loc.reducedAccuracy, isTrue);
    });
  });

  group('ProviderChangeEvent — gpsFallback field', () {
    testWidgets('gpsFallback defaults to false', (tester) async {
      final evt = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'gps': true,
        'network': true,
      });
      expect(evt.gpsFallback, isFalse);
    });

    testWidgets('gpsFallback parsed as true when GPS off', (tester) async {
      final evt = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'gps': false,
        'network': true,
        'gpsFallback': true,
      });
      expect(evt.gpsFallback, isTrue);
      expect(evt.gps, isFalse);
      expect(evt.network, isTrue);
    });

    testWidgets('gpsFallback round-trips through toMap/fromMap', (
      tester,
    ) async {
      final original = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'gps': false,
        'network': true,
        'gpsFallback': true,
      });

      final map = original.toMap();
      expect(map['gpsFallback'], isTrue);

      final restored = ProviderChangeEvent.fromMap(map);
      expect(restored.gpsFallback, isTrue);
    });

    testWidgets('accuracyAuthorization parsed correctly', (tester) async {
      final evt = ProviderChangeEvent.fromMap(const {
        'enabled': true,
        'status': 3,
        'gps': true,
        'network': true,
        'accuracyAuthorization': 1, // reduced
      });
      expect(evt.accuracyAuthorization, AccuracyAuthorization.reduced);
    });
  });
}
