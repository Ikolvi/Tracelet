import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

void main() {
  group('SpeedMotionEvent', () {
    test('fromMap parses canonical string values', () {
      final event = SpeedMotionEvent.fromMap(const {
        'state': 'stationary',
        'previousState': 'slowing',
        'trackingMode': 'periodic',
      });
      expect(event.state, SpeedMotionState.stationary);
      expect(event.previousState, SpeedMotionState.slowing);
      expect(event.trackingMode, SpeedMotionTrackingMode.periodic);
    });

    test('fromMap defaults unknown state to moving', () {
      final event = SpeedMotionEvent.fromMap(const {
        'state': 'bogus',
        'previousState': 'also-bogus',
        'trackingMode': 'nope',
      });
      expect(event.state, SpeedMotionState.moving);
      expect(event.previousState, SpeedMotionState.moving);
      expect(event.trackingMode, SpeedMotionTrackingMode.continuous);
    });

    test('fromMap accepts integer enum indices', () {
      final event = SpeedMotionEvent.fromMap(<String, Object?>{
        'state': SpeedMotionState.stationary.index,
        'previousState': SpeedMotionState.slowing.index,
        'trackingMode': SpeedMotionTrackingMode.geofences.index,
      });
      expect(event.state, SpeedMotionState.stationary);
      expect(event.previousState, SpeedMotionState.slowing);
      expect(event.trackingMode, SpeedMotionTrackingMode.geofences);
    });

    test('toMap round-trips via fromMap', () {
      const original = SpeedMotionEvent(
        state: SpeedMotionState.slowing,
        previousState: SpeedMotionState.moving,
        trackingMode: SpeedMotionTrackingMode.continuous,
      );
      final restored = SpeedMotionEvent.fromMap(original.toMap());
      expect(restored, equals(original));
    });

    test('equality and hashCode', () {
      const a = SpeedMotionEvent(
        state: SpeedMotionState.moving,
        previousState: SpeedMotionState.stationary,
        trackingMode: SpeedMotionTrackingMode.continuous,
      );
      const b = SpeedMotionEvent(
        state: SpeedMotionState.moving,
        previousState: SpeedMotionState.stationary,
        trackingMode: SpeedMotionTrackingMode.continuous,
      );
      const c = SpeedMotionEvent(
        state: SpeedMotionState.moving,
        previousState: SpeedMotionState.slowing,
        trackingMode: SpeedMotionTrackingMode.continuous,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
