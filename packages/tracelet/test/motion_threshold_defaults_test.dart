import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

/// Regression tests for sensor thresholds silently overriding platform tuning.
///
/// Android compares raw gravity-subtracted residuals in m/s² at ~5 Hz; iOS reads
/// clean user-acceleration in g at 10 Hz. Each platform therefore ships its own
/// tuned defaults (Android 2.5 / 0.4 m/s² and 25 samples; iOS 0.35 / 0.15 g and
/// 50 samples). `MotionConfig` exposes a single cross-platform scalar, and it used
/// to send Dart's defaults — the Android numbers — unconditionally. Any app that
/// set *any* motion field therefore pushed `stillThreshold: 0.4` to iOS, which
/// divides by 9.81 and got 0.041 g: roughly four times stricter than the iOS
/// default it was supposed to keep.
///
/// The fix: an unset threshold is not transmitted, so each platform falls back to
/// its own tuned value. Reading the property still reports the documented Dart
/// default, so this is not a breaking change for callers.
void main() {
  group('unset thresholds are not transmitted', () {
    test('a default MotionConfig omits all three sensor keys', () {
      final map = const MotionConfig().toMap();

      expect(map.containsKey('shakeThreshold'), isFalse);
      expect(map.containsKey('stillThreshold'), isFalse);
      expect(map.containsKey('stillSampleCount'), isFalse);
      // Other motion keys are always sent.
      expect(map['stopTimeout'], 5);
      expect(map['speedStationaryDelay'], 180);
    });

    test('setting an unrelated field still omits them', () {
      final map = const MotionConfig(
        motionDetectionMode: MotionDetectionMode.smart,
        stopTimeout: 1,
      ).toMap();

      expect(map.containsKey('shakeThreshold'), isFalse);
      expect(map.containsKey('stillThreshold'), isFalse);
      expect(map.containsKey('stillSampleCount'), isFalse);
    });

    test('reading an unset threshold still reports the documented default', () {
      const config = MotionConfig();

      expect(config.shakeThreshold, 2.5);
      expect(config.stillThreshold, 0.4);
      expect(config.stillSampleCount, 25);
      expect(config.hasExplicitShakeThreshold, isFalse);
      expect(config.hasExplicitStillThreshold, isFalse);
      expect(config.hasExplicitStillSampleCount, isFalse);
    });

    test('the Pigeon payload carries null for unset thresholds', () {
      final tl = const MotionConfig().toTlConfig();

      expect(tl.shakeThreshold, isNull);
      expect(tl.stillThreshold, isNull);
      expect(tl.stillSampleCount, isNull);
      expect(tl.stopTimeout, 5);
    });
  });

  group('explicit thresholds are transmitted', () {
    test('an explicitly set threshold is sent and marked explicit', () {
      const config = MotionConfig(
        shakeThreshold: 2,
        stillThreshold: 0.3,
        stillSampleCount: 40,
      );
      final map = config.toMap();

      expect(map['shakeThreshold'], 2.0);
      expect(map['stillThreshold'], 0.3);
      expect(map['stillSampleCount'], 40);
      expect(config.hasExplicitShakeThreshold, isTrue);
      expect(config.hasExplicitStillThreshold, isTrue);
      expect(config.hasExplicitStillSampleCount, isTrue);
    });

    test('setting a value equal to the default is still explicit', () {
      // Opting in to the Android number on purpose must survive: the value is
      // indistinguishable from the default, so only explicitness can carry it.
      const config = MotionConfig(shakeThreshold: 2.5);

      expect(config.hasExplicitShakeThreshold, isTrue);
      expect(config.toMap()['shakeThreshold'], 2.5);
      expect(config.toTlConfig().shakeThreshold, 2.5);
    });

    test('one explicit threshold does not make the others explicit', () {
      const config = MotionConfig(stillSampleCount: 40);
      final map = config.toMap();

      expect(map['stillSampleCount'], 40);
      expect(map.containsKey('shakeThreshold'), isFalse);
      expect(map.containsKey('stillThreshold'), isFalse);
    });
  });

  group('round-trip through fromMap preserves explicitness', () {
    test('an absent key stays unset', () {
      final restored = MotionConfig.fromMap(const MotionConfig().toMap());

      expect(restored.hasExplicitShakeThreshold, isFalse);
      expect(restored.hasExplicitStillThreshold, isFalse);
      expect(restored.hasExplicitStillSampleCount, isFalse);
      // …so re-sending it cannot promote a platform default into an override.
      expect(restored.toMap().containsKey('shakeThreshold'), isFalse);
    });

    test('a present key stays explicit with its value', () {
      final restored = MotionConfig.fromMap(
        const MotionConfig(stillThreshold: 0.25).toMap(),
      );

      expect(restored.hasExplicitStillThreshold, isTrue);
      expect(restored.stillThreshold, 0.25);
      expect(restored.toMap()['stillThreshold'], 0.25);
    });

    test('equality distinguishes unset from explicitly-default', () {
      expect(
        const MotionConfig(),
        isNot(equals(const MotionConfig(shakeThreshold: 2.5))),
      );
      expect(const MotionConfig(), equals(const MotionConfig()));
    });
  });
}
