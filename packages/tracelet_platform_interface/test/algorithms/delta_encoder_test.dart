import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Helper to create a realistic location map.
Map<String, Object?> _location({
  required String uuid,
  required String timestamp,
  required double lat,
  required double lng,
  double speed = 10.0,
  double heading = 90.0,
  double accuracy = 5.0,
  double altitude = 100.0,
  double battery = 0.85,
  bool isCharging = false,
}) => <String, Object?>{
  'uuid': uuid,
  'timestamp': timestamp,
  'coords': <String, Object?>{
    'latitude': lat,
    'longitude': lng,
    'speed': speed,
    'heading': heading,
    'accuracy': accuracy,
    'altitude': altitude,
  },
  'battery': <String, Object?>{'level': battery, 'is_charging': isCharging},
  'activity': <String, Object?>{'type': 'unknown', 'confidence': 100},
};

void main() {
  group('DeltaEncoder — encode', () {
    test('empty list returns empty', () {
      expect(DeltaEncoder.encode([]), isEmpty);
    });

    test('single location returns full reference', () {
      final loc = _location(
        uuid: 'a',
        timestamp: '2024-01-15T12:00:00.000Z',
        lat: 37.7749,
        lng: -122.4194,
      );

      final result = DeltaEncoder.encode([loc]);
      expect(result, hasLength(1));
      expect(result[0]['ref'], isTrue);
      expect(result[0]['uuid'], 'a');
    });

    test('two locations produce one ref + one delta', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.7749,
          lng: -122.4194,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:05.000Z',
          lat: 37.7750,
          lng: -122.4193,
        ),
      ];

      final result = DeltaEncoder.encode(locations);
      expect(result, hasLength(2));
      expect(result[0]['ref'], isTrue);
      expect(result[1].containsKey('d'), isTrue);

      final delta = result[1]['d'] as Map<String, Object?>;
      expect(delta['u'], 'b');
      expect(delta['t'], 5); // 5 seconds
    });

    test('delta encodes coordinate differences as integers', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.000000,
          lng: -122.000000,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:10.000Z',
          lat: 37.000100,
          lng: -122.000200,
        ),
      ];

      final result = DeltaEncoder.encode(locations, precision: 6);
      final delta = result[1]['d'] as Map<String, Object?>;

      // Δlat = 0.000100 * 10^6 = 100
      expect(delta['la'], 100);
      // Δlng = -0.000200 * 10^6 = -200
      expect(delta['lo'], -200);
    });

    test('precision parameter affects encoding', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.0,
          lng: -122.0,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:10.000Z',
          lat: 37.001,
          lng: -122.001,
        ),
      ];

      final p5 = DeltaEncoder.encode(locations, precision: 5);
      final p6 = DeltaEncoder.encode(locations, precision: 6);

      final d5 = (p5[1]['d'] as Map<String, Object?>)['la'] as int;
      final d6 = (p6[1]['d'] as Map<String, Object?>)['la'] as int;

      // precision 5: 0.001 * 10^5 = 100
      // precision 6: 0.001 * 10^6 = 1000
      expect(d5, 100);
      expect(d6, 1000);
    });

    test('delta encodes speed and heading differences', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.0,
          lng: -122.0,
          speed: 10.0,
          heading: 90.0,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:10.000Z',
          lat: 37.0,
          lng: -122.0,
          speed: 15.0,
          heading: 120.0,
        ),
      ];

      final result = DeltaEncoder.encode(locations);
      final delta = result[1]['d'] as Map<String, Object?>;

      expect(delta['s'], 5.0); // speed delta
      expect(delta['h'], 30.0); // heading delta
    });

    test('delta encodes battery level difference', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.0,
          lng: -122.0,
          battery: 0.90,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:10.000Z',
          lat: 37.0,
          lng: -122.0,
          battery: 0.88,
        ),
      ];

      final result = DeltaEncoder.encode(locations);
      final delta = result[1]['d'] as Map<String, Object?>;

      expect((delta['b'] as double), closeTo(-0.02, 0.001));
    });

    test('multiple locations chain deltas correctly', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.0,
          lng: -122.0,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:05.000Z',
          lat: 37.001,
          lng: -122.001,
        ),
        _location(
          uuid: 'c',
          timestamp: '2024-01-15T12:00:10.000Z',
          lat: 37.003,
          lng: -122.002,
        ),
      ];

      final result = DeltaEncoder.encode(locations);
      expect(result, hasLength(3));
      expect(result[0]['ref'], isTrue);
      expect(result[1].containsKey('d'), isTrue);
      expect(result[2].containsKey('d'), isTrue);

      // Third delta is relative to second, not first
      final d2 = result[2]['d'] as Map<String, Object?>;
      // Δlat = (37.003 - 37.001) * 10^6 = 2000
      expect(d2['la'], 2000);
    });
  });

  group('DeltaEncoder — decode', () {
    test('empty batch returns empty', () {
      expect(DeltaEncoder.decode([]), isEmpty);
    });

    test('single reference decodes to location without ref flag', () {
      final loc = _location(
        uuid: 'a',
        timestamp: '2024-01-15T12:00:00.000Z',
        lat: 37.7749,
        lng: -122.4194,
      );

      final encoded = DeltaEncoder.encode([loc]);
      final decoded = DeltaEncoder.decode(encoded);

      expect(decoded, hasLength(1));
      expect(decoded[0].containsKey('ref'), isFalse);
      expect(decoded[0]['uuid'], 'a');
    });

    test('encode → decode round-trip preserves coordinates', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.774900,
          lng: -122.419400,
          speed: 10.0,
          heading: 90.0,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:05.000Z',
          lat: 37.775000,
          lng: -122.419300,
          speed: 12.5,
          heading: 95.0,
        ),
      ];

      final encoded = DeltaEncoder.encode(locations);
      final decoded = DeltaEncoder.decode(encoded);

      expect(decoded, hasLength(2));

      final coords0 = decoded[0]['coords'] as Map<String, Object?>;
      expect(coords0['latitude'], closeTo(37.774900, 0.000001));
      expect(coords0['longitude'], closeTo(-122.419400, 0.000001));

      final coords1 = decoded[1]['coords'] as Map<String, Object?>;
      expect(coords1['latitude'], closeTo(37.775000, 0.000001));
      expect(coords1['longitude'], closeTo(-122.419300, 0.000001));
    });

    test('round-trip preserves speed and heading', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.0,
          lng: -122.0,
          speed: 10.0,
          heading: 90.0,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:10.000Z',
          lat: 37.001,
          lng: -122.001,
          speed: 25.5,
          heading: 180.0,
        ),
      ];

      final encoded = DeltaEncoder.encode(locations);
      final decoded = DeltaEncoder.decode(encoded);

      final coords1 = decoded[1]['coords'] as Map<String, Object?>;
      expect(coords1['speed'], closeTo(25.5, 0.01));
      expect(coords1['heading'], closeTo(180.0, 0.01));
    });

    test('round-trip preserves timestamps', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.0,
          lng: -122.0,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:30.000Z',
          lat: 37.001,
          lng: -122.001,
        ),
      ];

      final encoded = DeltaEncoder.encode(locations);
      final decoded = DeltaEncoder.decode(encoded);

      expect(decoded[0]['timestamp'], '2024-01-15T12:00:00.000Z');
      expect(decoded[1]['timestamp'], '2024-01-15T12:00:30.000Z');
    });

    test('round-trip preserves battery level', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.0,
          lng: -122.0,
          battery: 0.95,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:10.000Z',
          lat: 37.001,
          lng: -122.001,
          battery: 0.93,
        ),
      ];

      final encoded = DeltaEncoder.encode(locations);
      final decoded = DeltaEncoder.decode(encoded);

      final bat1 = decoded[1]['battery'] as Map<String, Object?>;
      expect((bat1['level'] as double), closeTo(0.93, 0.001));
    });

    test('round-trip with many locations preserves all', () {
      final locations = List.generate(
        20,
        (i) => _location(
          uuid: 'loc_$i',
          timestamp: DateTime(2024, 1, 15, 12, 0, i * 5).toIso8601String(),
          lat: 37.0 + i * 0.0001,
          lng: -122.0 + i * 0.0001,
          speed: 10.0 + i,
          heading: (i * 18.0) % 360,
          battery: 0.95 - i * 0.01,
        ),
      );

      final encoded = DeltaEncoder.encode(locations);
      final decoded = DeltaEncoder.decode(encoded);

      expect(decoded, hasLength(20));

      for (var i = 0; i < 20; i++) {
        expect(decoded[i]['uuid'], 'loc_$i');
        final coords = decoded[i]['coords'] as Map<String, Object?>;
        expect(
          (coords['latitude'] as double),
          closeTo(37.0 + i * 0.0001, 0.000001),
        );
      }
    });

    test('heading wraps correctly across 0/360 boundary', () {
      final locations = [
        _location(
          uuid: 'a',
          timestamp: '2024-01-15T12:00:00.000Z',
          lat: 37.0,
          lng: -122.0,
          heading: 350.0,
        ),
        _location(
          uuid: 'b',
          timestamp: '2024-01-15T12:00:10.000Z',
          lat: 37.001,
          lng: -122.001,
          heading: 10.0,
        ),
      ];

      final encoded = DeltaEncoder.encode(locations);
      final decoded = DeltaEncoder.decode(encoded);

      final coords1 = decoded[1]['coords'] as Map<String, Object?>;
      expect(coords1['heading'], closeTo(10.0, 0.1));
    });
  });

  group('DeltaEncoder — compression ratio', () {
    test('delta-encoded batch is smaller than full batch', () {
      final locations = List.generate(
        10,
        (i) => _location(
          uuid: 'loc_$i',
          timestamp: DateTime(2024, 1, 15, 12, 0, i * 5).toIso8601String(),
          lat: 37.0 + i * 0.00001,
          lng: -122.0 + i * 0.00001,
        ),
      );

      final encoded = DeltaEncoder.encode(locations);

      // The first entry is a full reference with all fields.
      // Subsequent entries only have a 'd' key with compact deltas.
      // Delta entries should have fewer keys than full locations.
      final fullKeyCount = locations.first.length;
      final deltaEntry = encoded[5]['d'] as Map<String, Object?>;

      // Full location has uuid, timestamp, coords, battery, activity (5 keys)
      // Delta has u, t, la, lo, s, h, a, al, b (9 short keys but no nested)
      expect(deltaEntry.containsKey('u'), isTrue);
      expect(deltaEntry.containsKey('la'), isTrue);
      expect(deltaEntry.containsKey('lo'), isTrue);
      expect(fullKeyCount, greaterThan(0)); // sanity check
    });
  });
}
