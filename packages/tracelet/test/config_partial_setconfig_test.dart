// Regression tests for #321 — the whole Config model, not just the
// foreground service (#320).
//
// `setConfig()` merges into the configuration the platform already persisted,
// and that merge skips fields it does not receive. So the contract is: a field
// the caller never mentioned must not appear in the serialized payload, while a
// field the caller did supply must appear — including when the supplied value
// happens to equal the default.
//
// Before the fix every field of every section was non-nullable with a default,
// so `const Config()` serialized a complete configuration built entirely of
// defaults and reset everything the platform had stored: `stopOnTerminate`,
// `distanceFilter`, the HTTP settings, the iOS keep-alive flags, all of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

/// Every section of a default `Config`, keyed by name, with the serialized
/// section map. Used to assert the whole model at once rather than a sample.
Map<String, Map<String, Object?>> _sections(Config c) {
  final m = c.toMap();
  return <String, Map<String, Object?>>{
    for (final e in m.entries)
      if (e.value is Map<String, Object?>)
        e.key: e.value! as Map<String, Object?>,
  };
}

void main() {
  group('#321 an unset Config serializes to nothing', () {
    test('every section of const Config() is empty', () {
      final sections = _sections(const Config());

      expect(sections, isNotEmpty, reason: 'sanity: sections were found');
      sections.forEach((name, body) {
        // Asserted strictly, with no tolerance for empty nested maps. An
        // earlier version of this test stripped them first, which hid `geo`
        // emitting `'filter': {}` and `android` emitting
        // `'foregroundService': {}` on a config that set nothing — harmless to
        // the platform merge, but not a minimal payload, and the #321 example
        // card caught it precisely because it did not make that allowance.
        expect(
          body,
          isEmpty,
          reason:
              'section "$name" still emits ${body.keys.join(', ')} — '
              'a setConfig() that configures nothing must send nothing',
        );
      });
    });

    test('nested sub-config maps are omitted entirely when unset', () {
      final android =
          const Config().toMap()['android']! as Map<String, Object?>;
      expect(android.containsKey('foregroundService'), isFalse);

      final geo = const Config().toMap()['geo']! as Map<String, Object?>;
      expect(geo.containsKey('filter'), isFalse);
    });

    test('a nested sub-config is emitted as soon as it carries a field', () {
      final android =
          const Config(
                android: AndroidConfig(
                  foregroundService: ForegroundServiceConfig(
                    showNotificationOnPauseOnly: true,
                  ),
                ),
              ).toMap()['android']!
              as Map<String, Object?>;
      expect(android['foregroundService'], {
        'showNotificationOnPauseOnly': true,
      });

      final geo =
          const Config(
                geo: GeoConfig(filter: LocationFilter(useKalmanFilter: true)),
              ).toMap()['geo']!
              as Map<String, Object?>;
      expect(geo['filter'], {'useKalmanFilter': true});
    });
  });

  group('#321 supplied values are always transmitted', () {
    test('a value equal to the default is still sent', () {
      // "Unset" must mean *not provided*, never *equal to the default* —
      // otherwise a field could never be set back to its default once changed.
      final app =
          const Config(app: AppConfig(stopOnTerminate: true)).toMap()['app']!
              as Map<String, Object?>;
      expect(app['stopOnTerminate'], isTrue);

      final ios =
          const Config(ios: IosConfig(preventSuspend: false)).toMap()['ios']!
              as Map<String, Object?>;
      expect(ios.containsKey('preventSuspend'), isTrue);
      expect(ios['preventSuspend'], isFalse);
    });

    test('only the supplied field of a section is sent', () {
      final geo =
          const Config(geo: GeoConfig(distanceFilter: 25)).toMap()['geo']!
              as Map<String, Object?>;

      expect(geo['distanceFilter'], 25);
      expect(geo.containsKey('desiredAccuracy'), isFalse);
      expect(geo.containsKey('stationaryRadius'), isFalse);
    });
  });

  group('#321 toMap/fromMap round-trips preserve unset-ness', () {
    // This is the invariant that catches a fromMap which resolves defaults
    // instead of leaving absent keys unset — it silently converts "the caller
    // said nothing" into "the caller asked for the default", which is exactly
    // the clobbering being fixed. Config.fromMap(config.toMap()) is a real code
    // path: the battery-budget engine and remote config both use it.
    void roundTrips(String name, Config original) {
      test(name, () {
        final restored = Config.fromMap(original.toMap());
        expect(
          restored.toMap(),
          equals(original.toMap()),
          reason: 'round-tripping $name changed the payload',
        );
      });
    }

    roundTrips('a fully unset config', const Config());
    roundTrips(
      'a partially set config',
      const Config(
        geo: GeoConfig(distanceFilter: 25),
        app: AppConfig(stopOnTerminate: false),
        ios: IosConfig(preventSuspend: true),
        motion: MotionConfig(motionDetectionMode: MotionDetectionMode.speed),
        android: AndroidConfig(
          foregroundService: ForegroundServiceConfig(
            showNotificationOnPauseOnly: true,
          ),
        ),
      ),
    );
    roundTrips('a fully resolved config', const Config().resolved());
  });

  group('#321 mergedWith preserves what the update did not mention', () {
    test('an empty update changes nothing', () {
      const configured = Config(
        geo: GeoConfig(distanceFilter: 25),
        app: AppConfig(stopOnTerminate: false, startOnBoot: true),
        http: HttpConfig(url: 'https://example.com/sync'),
        ios: IosConfig(
          preventSuspend: true,
          showsBackgroundLocationIndicator: true,
        ),
        android: AndroidConfig(
          foregroundService: ForegroundServiceConfig(
            notificationTitle: 'Tracking',
            showNotificationOnPauseOnly: true,
          ),
        ),
      );

      final merged = configured.mergedWith(const Config());

      expect(merged.toMap(), equals(configured.toMap()));
      expect(merged.geo.distanceFilter, 25);
      expect(merged.app.stopOnTerminate, isFalse);
      expect(merged.http.url, 'https://example.com/sync');
      expect(merged.ios.preventSuspend, isTrue);
      expect(merged.ios.showsBackgroundLocationIndicator, isTrue);
      expect(
        merged.android.foregroundService.showNotificationOnPauseOnly,
        isTrue,
      );
      expect(merged.android.foregroundService.notificationTitle, 'Tracking');
    });

    test('supplied fields win, untouched fields survive', () {
      const configured = Config(
        geo: GeoConfig(
          distanceFilter: 25,
          desiredAccuracy: DesiredAccuracy.high,
        ),
        ios: IosConfig(preventSuspend: true),
      );

      final merged = configured.mergedWith(
        const Config(geo: GeoConfig(distanceFilter: 50)),
      );

      expect(merged.geo.distanceFilter, 50);
      expect(merged.geo.desiredAccuracy, DesiredAccuracy.high);
      expect(merged.ios.preventSuspend, isTrue);
    });

    test('an explicit value equal to the default still overrides', () {
      const configured = Config(ios: IosConfig(preventSuspend: true));

      final merged = configured.mergedWith(
        const Config(ios: IosConfig(preventSuspend: false)),
      );

      expect(merged.ios.preventSuspend, isFalse);
    });
  });

  group('#321 resolved() pins every field for the ready() baseline', () {
    test('a resolved config emits every section fully', () {
      final sections = _sections(const Config().resolved());

      sections.forEach((name, body) {
        expect(
          body,
          isNotEmpty,
          reason:
              'section "$name" is empty after resolved(); ready() would leave '
              'the platform to guess, which is what resolved() exists to avoid',
        );
      });
    });

    test('resolved values match the documented getters', () {
      final resolved = const Config().resolved();

      expect(resolved.geo.distanceFilter, const GeoConfig().distanceFilter);
      expect(resolved.app.stopOnTerminate, const AppConfig().stopOnTerminate);
      expect(resolved.ios.preventSuspend, const IosConfig().preventSuspend);
      expect(resolved.logger.logLevel, const LoggerConfig().logLevel);
      expect(resolved.motion.stopTimeout, const MotionConfig().stopTimeout);
    });

    test('the per-platform motion thresholds are NOT resolved', () {
      // These three are the exception to `resolved()`. Every other field has
      // one default that all platforms agree on, so pinning it is free. These
      // deliberately differ — 2.5 m/s² vs 0.35 g, 0.4 m/s² vs 0.15 g, 25
      // samples at ~5 Hz vs 50 at 10 Hz — and unset is the signal that each
      // platform should keep its own. iOS reads them as g and divides by 9.81,
      // so pinning Dart's Android numbers makes 0.4 arrive as 0.04 g, about
      // four times stricter than the iOS default.
      final tl = const Config().resolved().toTlConfig().motion;

      expect(tl.shakeThreshold, isNull);
      expect(tl.stillThreshold, isNull);
      expect(tl.stillSampleCount, isNull);
      // Everything else in the same section is still pinned.
      expect(tl.stopTimeout, isNotNull);
      expect(tl.motionDetectionMode, isNotNull);
    });

    test('an explicitly set motion threshold survives resolving', () {
      final tl = const Config(
        motion: MotionConfig(shakeThreshold: 3),
      ).resolved().toTlConfig().motion;

      expect(tl.shakeThreshold, 3);
      expect(tl.stillThreshold, isNull);
    });

    test('resolving does not change any effective value', () {
      const configured = Config(
        geo: GeoConfig(distanceFilter: 25),
        motion: MotionConfig(motionDetectionMode: MotionDetectionMode.speed),
      );
      final resolved = configured.resolved();

      expect(resolved.geo.distanceFilter, configured.geo.distanceFilter);
      expect(
        resolved.motion.motionDetectionMode,
        configured.motion.motionDetectionMode,
      );
      expect(resolved.motion.stopTimeout, configured.motion.stopTimeout);
    });
  });

  group('#321 the Pigeon payload carries the absence', () {
    test('unset leaf fields cross the channel as null', () {
      final tl = const Config().toTlConfig();

      expect(tl.geo.distanceFilter, isNull);
      expect(tl.geo.desiredAccuracy, isNull);
      expect(tl.app.stopOnTerminate, isNull);
      expect(tl.ios.preventSuspend, isNull);
      expect(tl.ios.showsBackgroundLocationIndicator, isNull);
      expect(tl.android.foregroundService?.showNotificationOnPauseOnly, isNull);
      expect(tl.logger.logLevel, isNull);
    });

    test('supplied leaf fields cross with their value', () {
      final tl = const Config(
        ios: IosConfig(preventSuspend: true),
        geo: GeoConfig(distanceFilter: 25),
      ).toTlConfig();

      expect(tl.ios.preventSuspend, isTrue);
      expect(tl.geo.distanceFilter, 25);
      expect(tl.app.stopOnTerminate, isNull);
    });

    test('a resolved config sends every leaf field', () {
      final tl = const Config().resolved().toTlConfig();

      expect(tl.geo.distanceFilter, isNotNull);
      expect(tl.geo.desiredAccuracy, isNotNull);
      expect(tl.app.stopOnTerminate, isNotNull);
      expect(tl.ios.preventSuspend, isNotNull);
      expect(
        tl.android.foregroundService?.showNotificationOnPauseOnly,
        isNotNull,
      );
      expect(tl.logger.logLevel, isNotNull);
    });
  });

  group('#321 equality distinguishes unset from explicit', () {
    test('unset is not equal to the same value supplied explicitly', () {
      const unset = Config();
      const explicit = Config(ios: IosConfig(preventSuspend: false));

      expect(unset.ios.preventSuspend, explicit.ios.preventSuspend);
      expect(unset, isNot(explicit));
    });

    test('hashCode agrees with ==', () {
      // The two must be derived from the same fields; comparing backing fields
      // in one and resolved getters in the other silently breaks Map/Set usage.
      const a = Config(geo: GeoConfig(distanceFilter: 25));
      const b = Config(geo: GeoConfig(distanceFilter: 25));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      const unset = Config();
      const explicitDefault = Config(geo: GeoConfig(distanceFilter: 10));
      if (unset != explicitDefault) {
        expect(unset.hashCode, isNot(explicitDefault.hashCode));
      }
    });
  });
}
