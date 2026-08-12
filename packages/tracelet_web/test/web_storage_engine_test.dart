import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_web/src/web_storage_engine.dart';

void main() {
  late WebStorageEngine storage;

  setUp(() {
    storage = WebStorageEngine();
  });

  group('WebStorageEngine — Locations', () {
    test('insertLocation stores and returns uuid', () async {
      final uuid = await storage.insertLocation(<String, Object?>{
        'coords': <String, Object?>{'latitude': 37.0, 'longitude': -122.0},
      });

      expect(uuid, isNotEmpty);
      expect(await storage.getCount(), 1);
    });

    test('insertLocation uses provided uuid', () async {
      final uuid = await storage.insertLocation(<String, Object?>{
        'uuid': 'custom-uuid-123',
        'coords': <String, Object?>{'latitude': 1.0, 'longitude': 2.0},
      });

      expect(uuid, 'custom-uuid-123');
    });

    test('getLocations returns all locations', () async {
      for (var i = 0; i < 5; i++) {
        await storage.insertLocation(<String, Object?>{
          'coords': <String, Object?>{
            'latitude': i.toDouble(),
            'longitude': i.toDouble(),
          },
        });
      }

      final locations = await storage.getLocations();
      expect(locations, hasLength(5));
    });

    test('getLocations with limit', () async {
      for (var i = 0; i < 10; i++) {
        await storage.insertLocation(<String, Object?>{
          'coords': <String, Object?>{
            'latitude': i.toDouble(),
            'longitude': i.toDouble(),
          },
        });
      }

      final limited = await storage.getLocations(<String, Object?>{'limit': 3});
      expect(limited, hasLength(3));
    });

    test('destroyLocation removes specific location', () async {
      await storage.insertLocation(<String, Object?>{
        'uuid': 'keep',
        'coords': <String, Object?>{'latitude': 1.0, 'longitude': 1.0},
      });
      await storage.insertLocation(<String, Object?>{
        'uuid': 'remove',
        'coords': <String, Object?>{'latitude': 2.0, 'longitude': 2.0},
      });

      final result = await storage.destroyLocation('remove');
      expect(result, isTrue);
      expect(await storage.getCount(), 1);

      final remaining = await storage.getLocations();
      expect(remaining.first['uuid'], 'keep');
    });

    test('destroyLocation returns false for non-existent uuid', () async {
      final result = await storage.destroyLocation('nonexistent');
      expect(result, isFalse);
    });

    test('destroyLocations clears all', () async {
      await storage.insertLocation(<String, Object?>{
        'uuid': 'a',
        'coords': <String, Object?>{'latitude': 1.0, 'longitude': 1.0},
      });
      await storage.insertLocation(<String, Object?>{
        'uuid': 'b',
        'coords': <String, Object?>{'latitude': 2.0, 'longitude': 2.0},
      });

      expect(await storage.destroyLocations(), isTrue);
      expect(await storage.getCount(), 0);
    });

    test('drainLocations returns all and clears', () async {
      for (var i = 0; i < 3; i++) {
        await storage.insertLocation(<String, Object?>{
          'coords': <String, Object?>{
            'latitude': i.toDouble(),
            'longitude': i.toDouble(),
          },
        });
      }

      final drained = storage.drainLocations();
      expect(drained, hasLength(3));
      expect(await storage.getCount(), 0);
    });
  });

  group('WebStorageEngine — Logs', () {
    test('log stores entry', () async {
      await storage.log('info', 'Test message');
      final log = await storage.getLog();
      expect(log, contains('Test message'));
      expect(log, contains('[info]'));
    });

    test('destroyLog clears all logs', () async {
      await storage.log('info', 'message 1');
      await storage.log('error', 'message 2');
      await storage.destroyLog();
      final log = await storage.getLog();
      expect(log, isEmpty);
    });
  });

  group('WebStorageEngine — Config', () {
    test('applyConfig sets maxRecords', () async {
      storage.applyConfig(<String, Object?>{
        'persistence': <String, Object?>{'maxRecordsToPersist': 3},
      });

      for (var i = 0; i < 10; i++) {
        await storage.insertLocation(<String, Object?>{
          'coords': <String, Object?>{
            'latitude': i.toDouble(),
            'longitude': i.toDouble(),
          },
        });
      }

      expect(await storage.getCount(), 3);
    });

    // #361: `-1` is the documented "unlimited" sentinel, and `ready()` resolves
    // it onto the wire for every app that never set the key — so the old
    // `while (length > _maxRecords)` cap drained the store and then threw
    // RangeError off the end of it on the first insert of every session.
    test('a -1 record cap means unlimited, not a crash', () async {
      storage.applyConfig(<String, Object?>{
        'persistence': <String, Object?>{
          'maxRecordsToPersist': -1,
          'maxDaysToPersist': -1,
        },
      });

      for (var i = 0; i < 5; i++) {
        await storage.insertLocation(<String, Object?>{'uuid': 'unlimited-$i'});
      }

      expect(await storage.getCount(), 5);
    });

    test('a 0 record cap means unlimited too', () async {
      storage.applyConfig(<String, Object?>{
        'persistence': <String, Object?>{'maxRecordsToPersist': 0},
      });

      await storage.insertLocation(<String, Object?>{'uuid': 'zero-cap'});

      expect(await storage.getCount(), 1);
    });

    // #361: maxDaysToPersist was read by nothing on web.
    test('applyConfig enforces maxDaysToPersist', () async {
      storage.applyConfig(<String, Object?>{
        'persistence': <String, Object?>{'maxDaysToPersist': 1},
      });

      await storage.insertLocation(<String, Object?>{
        'uuid': 'aged',
        'timestamp': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
      });
      await storage.insertLocation(<String, Object?>{'uuid': 'fresh'});

      final kept = await storage.getLocations();
      expect(kept.map((Map<String, Object?> l) => l['uuid']), <String>[
        'fresh',
      ]);
    });

    test('a record with no usable timestamp is kept, not guessed at', () async {
      storage.applyConfig(<String, Object?>{
        'persistence': <String, Object?>{'maxDaysToPersist': 1},
      });

      await storage.insertLocation(<String, Object?>{
        'uuid': 'undateable',
        'timestamp': 'not a date',
      });

      expect(await storage.getCount(), 1);
    });
  });
}
