import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

void main() {
  group('TelematicsConfig', () {
    test('defaults are off and match engine defaults', () {
      const c = TelematicsConfig();
      expect(c.enableDrivingEvents, isFalse);
      expect(c.harshBrakingG, 0.40);
      expect(c.harshAccelerationG, 0.35);
      expect(c.harshCorneringG, 0.40);
      expect(c.speedLimitKmh, 0.0);
      expect(c.speedingMinDurationMs, 3000);
      expect(c.eventDebounceMs, 2000);
    });

    test('round-trips through map', () {
      const c = TelematicsConfig(
        enableDrivingEvents: true,
        harshBrakingG: 0.5,
        speedLimitKmh: 50,
      );
      final back = TelematicsConfig.fromMap(c.toMap());
      expect(back, c);
      expect(back.enableDrivingEvents, isTrue);
      expect(back.speedLimitKmh, 50);
    });

    test('toTlConfig carries values', () {
      const c = TelematicsConfig(enableDrivingEvents: true, harshBrakingG: 0.6);
      final tl = c.toTlConfig();
      expect(tl.enableDrivingEvents, isTrue);
      expect(tl.harshBrakingG, 0.6);
    });
  });

  group('ClassifierConfig', () {
    test('defaults off + annotate', () {
      const c = ClassifierConfig();
      expect(c.enableFusedClassifier, isFalse);
      expect(c.fusedClassifierAuthoritative, isFalse);
      expect(c.modeSwitchDwellMs, 8000);
      expect(c.minModeConfidence, 0.6);
      // Off by default: existing integrations keep the thresholds they set.
      expect(c.autoTuneFromTransportMode, isFalse);
    });

    test('round-trips through map', () {
      const c = ClassifierConfig(
        enableFusedClassifier: true,
        fusedClassifierAuthoritative: true,
        modeSwitchDwellMs: 5000,
        autoTuneFromTransportMode: true,
      );
      final back = ClassifierConfig.fromMap(c.toMap());
      expect(back, c);
      expect(back.autoTuneFromTransportMode, isTrue);
    });

    test('auto-tune survives the pigeon conversion', () {
      // The native side reads this off TlClassifierConfig, so a gap here would
      // silently disable auto-tuning on device while the Dart config looked right.
      const c = ClassifierConfig(
        enableFusedClassifier: true,
        autoTuneFromTransportMode: true,
      );
      expect(c.toTlConfig().autoTuneFromTransportMode, isTrue);
    });
  });

  group('ImpactConfig', () {
    test('defaults off', () {
      const c = ImpactConfig();
      expect(c.enableCrashDetection, isFalse);
      expect(c.enableFallDetection, isFalse);
      expect(c.crashGThreshold, 2.0);
      expect(c.crashMinSpeedKmh, 25.0);
      expect(c.confirmWindowMs, 15000);
    });

    test('round-trips through map', () {
      const c = ImpactConfig(
        enableCrashDetection: true,
        crashGThreshold: 4,
        confirmWindowMs: 10000,
      );
      final back = ImpactConfig.fromMap(c.toMap());
      expect(back, c);
      expect(back.enableCrashDetection, isTrue);
      expect(back.crashGThreshold, 4);
    });

    test('ML model fields default off and round-trip (#183)', () {
      const def = ImpactConfig();
      expect(def.crashModelUrl, isNull);
      expect(def.crashModelSha256, isNull);
      expect(def.crashModelThreshold, 0.5);

      const c = ImpactConfig(
        enableCrashDetection: true,
        crashModelUrl: 'https://cdn.example.com/crash.enc',
        crashModelSha256: 'abc123',
        crashModelThreshold: 0.307,
      );
      final back = ImpactConfig.fromMap(c.toMap());
      expect(back, c);
      expect(back.crashModelUrl, 'https://cdn.example.com/crash.enc');
      expect(back.crashModelSha256, 'abc123');
      expect(back.crashModelThreshold, 0.307);
      // Pigeon conversion carries the fields.
      final tl = c.toTlConfig();
      expect(tl.crashModelUrl, 'https://cdn.example.com/crash.enc');
      expect(tl.crashModelThreshold, 0.307);
    });
  });

  group('Config integration', () {
    test('defaults include the three new blocks, all off', () {
      const cfg = Config();
      expect(cfg.telematics.enableDrivingEvents, isFalse);
      expect(cfg.classifier.enableFusedClassifier, isFalse);
      expect(cfg.impact.enableCrashDetection, isFalse);
    });

    test('round-trips telematics/classifier/impact through Config map', () {
      const cfg = Config(
        telematics: TelematicsConfig(enableDrivingEvents: true),
        classifier: ClassifierConfig(enableFusedClassifier: true),
        impact: ImpactConfig(enableCrashDetection: true),
      );
      final back = Config.fromMap(cfg.toMap());
      expect(back.telematics.enableDrivingEvents, isTrue);
      expect(back.classifier.enableFusedClassifier, isTrue);
      expect(back.impact.enableCrashDetection, isTrue);
    });

    test('copyWith replaces only the targeted block', () {
      const cfg = Config();
      final updated = cfg.copyWith(
        telematics: const TelematicsConfig(enableDrivingEvents: true),
      );
      expect(updated.telematics.enableDrivingEvents, isTrue);
      expect(updated.classifier.enableFusedClassifier, isFalse);
      expect(updated.impact, cfg.impact);
    });

    test('toTlConfig builds the new Pigeon blocks', () {
      const cfg = Config(impact: ImpactConfig(enableFallDetection: true));
      final tl = cfg.toTlConfig();
      expect(tl.impact.enableFallDetection, isTrue);
      // #321: telematics was never mentioned, so it crosses as unset rather
      // than as an explicit `false` that would overwrite the stored value.
      expect(tl.telematics.enableDrivingEvents, isNull);
      expect(
        cfg.resolved().toTlConfig().telematics.enableDrivingEvents,
        isFalse,
      );
    });
  });
}
