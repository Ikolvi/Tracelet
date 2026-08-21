import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// #402: trip identity, and the reconciliation between the two trip managers.
///
/// Trips are detected twice — natively, which is what stamps `trip_id` onto
/// database rows, and again here, which computes waypoints and distance and
/// feeds `onTrip`. Both run the same state machine, so both mint an id. These
/// tests pin the rule that makes them agree: when the native layer reports its
/// id, this manager adopts it rather than publishing its own.
void main() async {
  await RustLib.init();

  late TripManager tripManager;
  late List<Map<String, Object?>> starts;
  late List<Map<String, Object?>> ends;

  setUp(() {
    tripManager = TripManager();
    starts = <Map<String, Object?>>[];
    ends = <Map<String, Object?>>[];
    tripManager.onTripStart = starts.add;
    tripManager.onTripEnd = ends.add;
  });

  group('trip start', () {
    test('is reported at all', () {
      // Before #402 a trip only became observable once it had ended.
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 1,
        longitude: 2,
      );

      expect(starts, hasLength(1));
      expect(starts.single['tripId'], isA<String>());
      expect(starts.single['tripId'], isNotEmpty);
      expect(starts.single['startedAt'], isA<int>());
      expect(ends, isEmpty);
    });

    test('a motion change that crosses no boundary reports nothing', () {
      tripManager.onMotionStateChanged(isMoving: false);
      expect(starts, isEmpty);
      expect(ends, isEmpty);

      tripManager.onMotionStateChanged(isMoving: true);
      tripManager.onMotionStateChanged(isMoving: true);
      expect(starts, hasLength(1), reason: 'moving twice is one boundary');
    });
  });

  group('native id adoption', () {
    test('the native id is published instead of the locally minted one', () {
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 1,
        longitude: 2,
        nativeTripId: 'native-trip-1',
      );

      expect(starts.single['tripId'], 'native-trip-1');
      expect(tripManager.currentTripId, 'native-trip-1');
    });

    test('the summary keeps the native id after the trip ends', () {
      // The native side clears its own id at trip end, so this manager has to
      // hold it to be able to label the summary — that is what makes the
      // summary joinable to the rows written during the trip.
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 1,
        longitude: 2,
        nativeTripId: 'native-trip-1',
      );
      tripManager.onMotionStateChanged(
        isMoving: false,
        latitude: 1.1,
        longitude: 2.1,
      );

      expect(ends.single['tripId'], 'native-trip-1');
      expect(ends.single['startedAt'], isA<int>());
      expect(ends.single['endedAt'], isA<int>());
    });

    test('a second trip does not inherit the first trip id', () {
      tripManager
        ..onMotionStateChanged(
          isMoving: true,
          latitude: 1,
          longitude: 2,
          nativeTripId: 'native-trip-1',
        )
        ..onMotionStateChanged(isMoving: false, latitude: 1, longitude: 2)
        ..onMotionStateChanged(
          isMoving: true,
          latitude: 3,
          longitude: 4,
          nativeTripId: 'native-trip-2',
        );

      expect(tripManager.currentTripId, 'native-trip-2');
      expect(starts.map((Map<String, Object?> s) => s['tripId']), <String>[
        'native-trip-1',
        'native-trip-2',
      ]);
    });

    test('the id is released at trip end', () {
      tripManager
        ..onMotionStateChanged(
          isMoving: true,
          latitude: 1,
          longitude: 2,
          nativeTripId: 'native-trip-1',
        )
        ..onMotionStateChanged(isMoving: false, latitude: 1, longitude: 2);

      expect(
        tripManager.currentTripId,
        isNull,
        reason: 'records written between trips must carry no trip id',
      );
    });

    test('falls back to the local id when native reports none', () {
      // A platform that does not report its trip still gets a usable id rather
      // than null — it just will not match the stored rows.
      tripManager.onMotionStateChanged(
        isMoving: true,
        latitude: 1,
        longitude: 2,
      );

      final local = starts.single['tripId'] as String?;
      expect(local, isNotNull);
      expect(local, isNotEmpty);
      expect(tripManager.currentTripId, local);
    });
  });

  test('reset discards the adopted id', () {
    tripManager.onMotionStateChanged(
      isMoving: true,
      latitude: 1,
      longitude: 2,
      nativeTripId: 'native-trip-1',
    );
    expect(tripManager.currentTripId, 'native-trip-1');

    tripManager.reset();

    expect(tripManager.currentTripId, isNull);
    expect(ends, isEmpty, reason: 'a reset trip produces no summary');
  });
}
