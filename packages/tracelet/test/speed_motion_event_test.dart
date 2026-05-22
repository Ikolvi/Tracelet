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

    test('toString includes state transition', () {
      const event = SpeedMotionEvent(
        state: SpeedMotionState.stationary,
        previousState: SpeedMotionState.slowing,
        trackingMode: SpeedMotionTrackingMode.periodic,
      );
      expect(event.toString(), contains('slowing'));
      expect(event.toString(), contains('stationary'));
    });
  });

  group('MotionConfig — Speed Mode Properties', () {
    test('MotionConfig speed-mode defaults', () {
      const config = MotionConfig();
      expect(config.motionDetectionMode, MotionDetectionMode.accelerometer);
      expect(config.speedMovingThreshold, 1.5);
      expect(config.speedStationaryDelay, 180);
      expect(config.stationaryTrackingMode, StationaryTrackingMode.periodic);
      expect(config.stationaryPeriodicInterval, 120);
      expect(config.stationaryPeriodicAccuracy, DesiredAccuracy.high);
      expect(config.speedWakeConfirmCount, 1);
    });

    test('MotionConfig speed-mode round-trip serialization', () {
      const config = MotionConfig(
        motionDetectionMode: MotionDetectionMode.speed,
        speedMovingThreshold: 2.5,
        speedStationaryDelay: 300,
        stationaryTrackingMode: StationaryTrackingMode.geofences,
        stationaryPeriodicInterval: 300,
        stationaryPeriodicAccuracy: DesiredAccuracy.medium,
        speedWakeConfirmCount: 3,
      );
      final map = config.toMap();
      expect(map['motionDetectionMode'], 'speed');
      expect(map['speedMovingThreshold'], 2.5);
      expect(map['speedStationaryDelay'], 300);
      expect(map['stationaryTrackingMode'], 'geofences');
      expect(map['stationaryPeriodicInterval'], 300);
      expect(map['stationaryPeriodicAccuracy'], DesiredAccuracy.medium.index);
      expect(map['speedWakeConfirmCount'], 3);

      final restored = MotionConfig.fromMap(map);
      expect(restored, equals(config));
    });

    test('MotionConfig speed-mode fields affect equality', () {
      const base = MotionConfig(motionDetectionMode: MotionDetectionMode.speed);
      const diffMode = MotionConfig();
      expect(base, isNot(equals(diffMode)));

      const diffThreshold = MotionConfig(
        motionDetectionMode: MotionDetectionMode.speed,
        speedMovingThreshold: 2.5,
      );
      expect(base, isNot(equals(diffThreshold)));

      const diffStationary = MotionConfig(
        motionDetectionMode: MotionDetectionMode.speed,
        stationaryTrackingMode: StationaryTrackingMode.geofences,
      );
      expect(base, isNot(equals(diffStationary)));
    });

    test('MotionConfig.fromMap accepts integer enum indices as fallback', () {
      final map = <String, Object?>{
        'motionDetectionMode': MotionDetectionMode.speed.index,
        'stationaryTrackingMode': StationaryTrackingMode.geofences.index,
      };
      final config = MotionConfig.fromMap(map);
      expect(config.motionDetectionMode, MotionDetectionMode.speed);
      expect(config.stationaryTrackingMode, StationaryTrackingMode.geofences);
    });

    test('MotionConfig.fromMap handles unknown enum strings with defaults', () {
      final config = MotionConfig.fromMap(<String, Object?>{
        'motionDetectionMode': 'bogus',
        'stationaryTrackingMode': 'unknown',
      });
      expect(config.motionDetectionMode, MotionDetectionMode.accelerometer);
      expect(config.stationaryTrackingMode, StationaryTrackingMode.periodic);
    });
  });
}
