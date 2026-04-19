import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the speed-based motion detection mode.
///
/// These tests verify MotionConfig serialization for the new speed-mode
/// properties, the SpeedMotionEvent model, and common configuration
/// presets. Full end-to-end state-machine behavior requires a real device
/// with background execution and is covered by native unit tests.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MotionConfig — Speed Mode Properties', () {
    testWidgets('MotionConfig accepts speed-mode properties', (tester) async {
      const config = MotionConfig(
        motionDetectionMode: MotionDetectionMode.speed,
        speedMovingThreshold: 2.0,
        speedStationaryDelay: 240,
        stationaryTrackingMode: StationaryTrackingMode.periodic,
        stationaryPeriodicInterval: 180,
        stationaryPeriodicAccuracy: DesiredAccuracy.high,
        speedWakeConfirmCount: 2,
      );

      expect(config.motionDetectionMode, MotionDetectionMode.speed);
      expect(config.speedMovingThreshold, 2.0);
      expect(config.speedStationaryDelay, 240);
      expect(config.stationaryTrackingMode, StationaryTrackingMode.periodic);
      expect(config.stationaryPeriodicInterval, 180);
      expect(config.stationaryPeriodicAccuracy, DesiredAccuracy.high);
      expect(config.speedWakeConfirmCount, 2);
    });

    testWidgets('MotionConfig speed-mode defaults are correct', (tester) async {
      const config = MotionConfig();

      expect(config.motionDetectionMode, MotionDetectionMode.accelerometer);
      expect(config.speedMovingThreshold, 1.5);
      expect(config.speedStationaryDelay, 180);
      expect(config.stationaryTrackingMode, StationaryTrackingMode.periodic);
      expect(config.stationaryPeriodicInterval, 120);
      expect(config.stationaryPeriodicAccuracy, DesiredAccuracy.high);
      expect(config.speedWakeConfirmCount, 1);
    });

    testWidgets('MotionConfig.toMap includes speed-mode fields', (
      tester,
    ) async {
      const config = MotionConfig(
        motionDetectionMode: MotionDetectionMode.speed,
        speedMovingThreshold: 2.5,
        speedStationaryDelay: 300,
        stationaryTrackingMode: StationaryTrackingMode.geofences,
      );
      final map = config.toMap();

      expect(map['motionDetectionMode'], 'speed');
      expect(map['speedMovingThreshold'], 2.5);
      expect(map['speedStationaryDelay'], 300);
      expect(map['stationaryTrackingMode'], 'geofences');
    });
  });

  group('MotionConfig — Preset Combinations', () {
    testWidgets('Life360-style always-on tracking preset', (tester) async {
      const config = MotionConfig(
        motionDetectionMode: MotionDetectionMode.speed,
        speedMovingThreshold: 1.5, // 5.4 km/h
        speedStationaryDelay: 180, // 3 min red-light buffer
        stationaryPeriodicInterval: 120, // 2 min fixes when parked
        stationaryPeriodicAccuracy: DesiredAccuracy.high,
        speedWakeConfirmCount: 1, // instant wake
      );

      expect(config.motionDetectionMode, MotionDetectionMode.speed);
      expect(config.stationaryPeriodicAccuracy, DesiredAccuracy.high);
      expect(config.speedWakeConfirmCount, 1);
    });

    testWidgets('Fleet tracking preset with conservative wake', (tester) async {
      const config = MotionConfig(
        motionDetectionMode: MotionDetectionMode.speed,
        speedMovingThreshold: 2.5, // 9 km/h — ignore lot crawl
        speedStationaryDelay: 300, // 5 min buffer
        stationaryPeriodicInterval: 300,
        stationaryPeriodicAccuracy: DesiredAccuracy.medium,
        speedWakeConfirmCount: 3, // require 3 confirms at medium accuracy
      );

      expect(config.motionDetectionMode, MotionDetectionMode.speed);
      expect(config.stationaryPeriodicAccuracy, DesiredAccuracy.medium);
      expect(config.speedWakeConfirmCount, 3);
    });

    testWidgets('Accelerometer mode is still the default', (tester) async {
      const config = MotionConfig();
      final map = config.toMap();

      expect(config.motionDetectionMode, MotionDetectionMode.accelerometer);
      expect(map['motionDetectionMode'], 'accelerometer');
    });
  });

  group('SpeedMotionEvent', () {
    testWidgets('parses canonical map payload from native', (tester) async {
      final event = SpeedMotionEvent.fromMap(const {
        'state': 'stationary',
        'previousState': 'slowing',
        'trackingMode': 'periodic',
      });

      expect(event.state, SpeedMotionState.stationary);
      expect(event.previousState, SpeedMotionState.slowing);
      expect(event.trackingMode, SpeedMotionTrackingMode.periodic);
    });

    testWidgets('round-trips through toMap/fromMap', (tester) async {
      const original = SpeedMotionEvent(
        state: SpeedMotionState.moving,
        previousState: SpeedMotionState.stationary,
        trackingMode: SpeedMotionTrackingMode.continuous,
      );
      final restored = SpeedMotionEvent.fromMap(original.toMap());
      expect(restored, equals(original));
    });
  });
}
