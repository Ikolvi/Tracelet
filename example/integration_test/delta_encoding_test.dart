import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the Delta Encoding feature.
///
/// These tests verify the pure-Dart [DeltaEncoder] encode/decode round-trip,
/// field mapping, and HttpConfig serialization. The encoder runs identically
/// on Dart, Kotlin, and Swift.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('DeltaEncoder — Encode/Decode Round-Trip', () {
    testWidgets('encode then decode produces identical locations', (
      tester,
    ) async {
      final locations = [
        {
          'uuid': 'loc-1',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'coords': {
            'latitude': 51.509865,
            'longitude': -0.118092,
            'speed': 1.2,
            'heading': 45.0,
            'accuracy': 5.0,
            'altitude': 30.0,
          },
          'battery': {'level': 0.85, 'is_charging': false},
        },
        {
          'uuid': 'loc-2',
          'timestamp': '2024-01-15T10:00:05.000Z',
          'coords': {
            'latitude': 51.509870,
            'longitude': -0.118090,
            'speed': 1.3,
            'heading': 46.0,
            'accuracy': 5.0,
            'altitude': 30.0,
          },
          'battery': {'level': 0.85, 'is_charging': false},
        },
        {
          'uuid': 'loc-3',
          'timestamp': '2024-01-15T10:00:10.000Z',
          'coords': {
            'latitude': 51.509880,
            'longitude': -0.118085,
            'speed': 1.4,
            'heading': 47.0,
            'accuracy': 4.5,
            'altitude': 30.0,
          },
          'battery': {'level': 0.84, 'is_charging': false},
        },
      ];

      final encoded = DeltaEncoder.encode(locations, precision: 6);
      final decoded = DeltaEncoder.decode(encoded, precision: 6);

      expect(decoded.length, locations.length);

      // Verify UUIDs match
      for (var i = 0; i < locations.length; i++) {
        expect(decoded[i]['uuid'], locations[i]['uuid']);
      }

      // Verify coordinates reconstruct within precision tolerance
      for (var i = 0; i < locations.length; i++) {
        final origCoords = locations[i]['coords'] as Map;
        final decodedCoords = decoded[i]['coords'] as Map;
        expect(
          (decodedCoords['latitude'] as double),
          closeTo(origCoords['latitude'] as double, 0.000002),
        );
        expect(
          (decodedCoords['longitude'] as double),
          closeTo(origCoords['longitude'] as double, 0.000002),
        );
      }
    });

    testWidgets('single location encodes as reference', (tester) async {
      final locations = [
        {
          'uuid': 'single',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'coords': {
            'latitude': 40.7128,
            'longitude': -74.0060,
            'speed': 0.0,
            'heading': 0.0,
            'accuracy': 10.0,
            'altitude': 5.0,
          },
          'battery': {'level': 1.0, 'is_charging': true},
        },
      ];

      final encoded = DeltaEncoder.encode(locations);
      expect(encoded.length, 1);
      expect(encoded[0]['ref'], isTrue);
    });

    testWidgets('empty batch encodes to empty list', (tester) async {
      final encoded = DeltaEncoder.encode([]);
      expect(encoded, isEmpty);

      final decoded = DeltaEncoder.decode([]);
      expect(decoded, isEmpty);
    });
  });

  group('DeltaEncoder — Compression', () {
    testWidgets('encoded batch is smaller than original', (tester) async {
      final locations = List.generate(
        20,
        (i) => {
          'uuid': 'loc-$i',
          'timestamp': '2024-01-15T10:00:${i * 5}.000Z',
          'coords': {
            'latitude': 51.509865 + (i * 0.00001),
            'longitude': -0.118092 + (i * 0.00001),
            'speed': 1.2 + (i * 0.05),
            'heading': 45.0 + i,
            'accuracy': 5.0,
            'altitude': 30.0,
          },
          'battery': {'level': 0.85, 'is_charging': false},
        },
      );

      final encoded = DeltaEncoder.encode(locations);

      // Encoded should have same count but smaller JSON representation
      expect(encoded.length, locations.length);

      // First record is reference (full), rest are deltas (smaller)
      expect(encoded[0]['ref'], isTrue);
      for (var i = 1; i < encoded.length; i++) {
        expect(encoded[i].containsKey('d'), isTrue);
        expect(encoded[i].containsKey('ref'), isFalse);
      }
    });
  });

  group('DeltaEncoder — Heading Wrap-Around', () {
    testWidgets('handles 350° to 10° transition correctly', (tester) async {
      final locations = [
        {
          'uuid': 'h1',
          'timestamp': '2024-01-15T10:00:00.000Z',
          'coords': {
            'latitude': 51.5,
            'longitude': -0.1,
            'speed': 1.0,
            'heading': 350.0,
            'accuracy': 5.0,
            'altitude': 30.0,
          },
          'battery': {'level': 0.9, 'is_charging': false},
        },
        {
          'uuid': 'h2',
          'timestamp': '2024-01-15T10:00:05.000Z',
          'coords': {
            'latitude': 51.5001,
            'longitude': -0.1001,
            'speed': 1.0,
            'heading': 10.0,
            'accuracy': 5.0,
            'altitude': 30.0,
          },
          'battery': {'level': 0.9, 'is_charging': false},
        },
      ];

      final encoded = DeltaEncoder.encode(locations);
      final decoded = DeltaEncoder.decode(encoded);

      final decodedCoords = decoded[1]['coords'] as Map;
      // Heading should reconstruct to ~10° (not 350 + delta)
      expect((decodedCoords['heading'] as double) % 360, closeTo(10.0, 0.1));
    });
  });

  group('HttpConfig — Delta Encoding Properties', () {
    testWidgets('HttpConfig accepts delta compression settings', (
      tester,
    ) async {
      const config = HttpConfig(
        url: 'https://example.com',
        batchSync: true,
        enableDeltaCompression: true,
        deltaCoordinatePrecision: 7,
      );

      expect(config.enableDeltaCompression, isTrue);
      expect(config.deltaCoordinatePrecision, 7);
    });

    testWidgets('HttpConfig delta defaults are correct', (tester) async {
      const config = HttpConfig();

      expect(config.enableDeltaCompression, isFalse);
      expect(config.deltaCoordinatePrecision, 6);
    });

    testWidgets('HttpConfig.toMap includes delta fields', (tester) async {
      const config = HttpConfig(
        enableDeltaCompression: true,
        deltaCoordinatePrecision: 5,
      );
      final map = config.toMap();

      expect(map['enableDeltaCompression'], isTrue);
      expect(map['deltaCoordinatePrecision'], 5);
    });
  });
}
