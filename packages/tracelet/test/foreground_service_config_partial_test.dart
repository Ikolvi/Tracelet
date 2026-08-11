// Regression tests for #320.
//
// `setConfig()` merges into the configuration the platform has already
// persisted, and the merge skips fields that are absent. So the contract these
// tests pin down is: a field the caller never mentioned must not appear in the
// serialized payload at all, while a field the caller did supply must appear —
// including when the supplied value happens to equal the default.
//
// Before the fix every field was non-nullable with a default, so
// `const Config()` serialized a complete foreground-service section built
// entirely of defaults. The platform could not distinguish that from a
// deliberate configuration and wrote it over the stored values, which is why
// `showNotificationOnPauseOnly: true` stopped taking effect after any partial
// `setConfig()`.

import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

void main() {
  group('#320 unset foreground-service fields are not serialized', () {
    test('a default-constructed config serializes to an empty map', () {
      expect(const ForegroundServiceConfig().toMap(), isEmpty);
    });

    test('const Config() emits no foreground-service keys', () {
      final fg = const Config().toMap()['android'] as Map<String, Object?>?;
      final fgMap = fg?['foregroundService'] as Map<String, Object?>?;

      // This is the payload that used to overwrite the persisted notification
      // settings on every partial setConfig().
      //
      // #321 went two steps further than #320: it drops the sub-map rather
      // than sending an empty `{}`, and then drops the whole `android` section
      // rather than sending an empty section — so neither key is present now.
      // Every one of those shapes satisfies what this test is about: nothing
      // concerning the foreground service is transmitted.
      expect(fgMap ?? const <String, Object?>{}, isEmpty);
    });

    test('only the supplied field is serialized', () {
      final map = const ForegroundServiceConfig(
        showNotificationOnPauseOnly: true,
      ).toMap();

      expect(map, {'showNotificationOnPauseOnly': true});
      expect(map.containsKey('notificationTitle'), isFalse);
      expect(map.containsKey('channelId'), isFalse);
      expect(map.containsKey('enabled'), isFalse);
    });

    test('unset fields still read back as their documented defaults', () {
      const fg = ForegroundServiceConfig();

      expect(fg.enabled, isTrue);
      expect(fg.channelId, 'tracelet_channel');
      expect(fg.channelName, 'Tracelet');
      expect(fg.notificationTitle, 'Tracelet');
      expect(fg.notificationText, 'Tracking location in background');
      expect(fg.notificationPriority, NotificationPriority.defaultPriority);
      expect(fg.notificationOngoing, isTrue);
      expect(fg.showNotificationOnPauseOnly, isFalse);
      expect(fg.notificationStartedAt, isNull);
      expect(fg.notificationShowTimer, isFalse);
      expect(fg.notificationOnlyAlertOnce, isFalse);
      expect(fg.actions, isEmpty);
    });
  });

  group('#320 explicitly supplied values are always transmitted', () {
    test('a value equal to the default is still sent', () {
      // The distinction has to be "was it provided", not "does it differ from
      // the default" — otherwise a caller could never set a field back to its
      // default once it had been changed.
      final map = const ForegroundServiceConfig(
        showNotificationOnPauseOnly: false,
        enabled: true,
        channelId: 'tracelet_channel',
      ).toMap();

      expect(map['showNotificationOnPauseOnly'], isFalse);
      expect(map['enabled'], isTrue);
      expect(map['channelId'], 'tracelet_channel');
    });

    test('an explicitly empty action list is sent', () {
      expect(const ForegroundServiceConfig(actions: <String>[]).toMap(), {
        'actions': <String>[],
      });
    });

    test('explicit timer and alert-once false values are sent', () {
      final map = const ForegroundServiceConfig(
        notificationStartedAt: 4294967296,
        notificationShowTimer: false,
        notificationOnlyAlertOnce: false,
      ).toMap();

      expect(map, {
        'notificationStartedAt': 4294967296,
        'notificationShowTimer': false,
        'notificationOnlyAlertOnce': false,
      });
    });
  });

  group('#320 unset-ness survives round-tripping', () {
    test('toMap/fromMap preserves which fields were supplied', () {
      const original = ForegroundServiceConfig(
        showNotificationOnPauseOnly: true,
        notificationTitle: 'Tracking',
      );

      final restored = ForegroundServiceConfig.fromMap(original.toMap());

      expect(restored.toMap(), original.toMap());
      expect(restored, original);
    });

    test('an explicit default survives the round trip', () {
      const original = ForegroundServiceConfig(
        showNotificationOnPauseOnly: false,
      );

      final restored = ForegroundServiceConfig.fromMap(original.toMap());

      expect(restored.toMap(), {'showNotificationOnPauseOnly': false});
    });

    test('timer suppliedness survives the round trip', () {
      const original = ForegroundServiceConfig(
        notificationStartedAt: 4294967296,
        notificationShowTimer: false,
        notificationOnlyAlertOnce: false,
      );

      final restored = ForegroundServiceConfig.fromMap(original.toMap());

      expect(restored.toMap(), original.toMap());
      expect(restored, original);
      expect(restored.hasExplicitValues, isTrue);
    });

    test('copyWith does not resolve untouched fields to their defaults', () {
      // Config.fromMap(config.toMap()) with one key changed is the documented
      // way to build a partial update; copyWith must not turn every other field
      // into an explicit default along the way.
      final updated = const ForegroundServiceConfig(
        showNotificationOnPauseOnly: true,
      ).copyWith(notificationText: 'Paused');

      expect(updated.toMap(), {
        'showNotificationOnPauseOnly': true,
        'notificationText': 'Paused',
      });
    });
  });

  group('#320 equality distinguishes unset from explicit', () {
    test('unset is not equal to the same value supplied explicitly', () {
      const unset = ForegroundServiceConfig();
      const explicit = ForegroundServiceConfig(
        showNotificationOnPauseOnly: false,
      );

      // Both behave identically when read, but they serialize differently, and
      // collapsing them would let a cached-config comparison silently drop the
      // distinction the fix depends on.
      expect(
        unset.showNotificationOnPauseOnly,
        explicit.showNotificationOnPauseOnly,
      );
      expect(unset, isNot(explicit));
      expect(unset.hashCode, isNot(explicit.hashCode));
    });

    test('identical explicit configs are equal', () {
      expect(
        const ForegroundServiceConfig(
          notificationTitle: 'A',
          actions: ['Stop'],
        ),
        const ForegroundServiceConfig(
          notificationTitle: 'A',
          actions: ['Stop'],
        ),
      );
    });

    test('timer unset is not equal to explicit false', () {
      const unset = ForegroundServiceConfig();
      const explicit = ForegroundServiceConfig(notificationShowTimer: false);

      expect(unset.notificationShowTimer, explicit.notificationShowTimer);
      expect(unset, isNot(explicit));
      expect(unset.hashCode, isNot(explicit.hashCode));
    });

    test('alert-once unset is not equal to explicit false', () {
      const unset = ForegroundServiceConfig();
      const explicit = ForegroundServiceConfig(
        notificationOnlyAlertOnce: false,
      );

      expect(
        unset.notificationOnlyAlertOnce,
        explicit.notificationOnlyAlertOnce,
      );
      expect(unset, isNot(explicit));
      expect(unset.hashCode, isNot(explicit.hashCode));
    });
  });

  group('#320 mergedWith keeps the Dart mirror aligned with the platform', () {
    // Tracelet.activeConfig is a Dart-side mirror of the last Config passed in.
    // Now that a partial setConfig() no longer overwrites the persisted native
    // values, replacing the mirror wholesale would make it report defaults the
    // platform never stored — so setConfig() applies the same merge locally.
    const configured = ForegroundServiceConfig(
      notificationTitle: '📍 Tracking',
      channelId: 'demo_channel',
      showNotificationOnPauseOnly: true,
      enabled: false,
    );

    test('an update that sets nothing leaves every field as configured', () {
      final merged = configured.mergedWith(const ForegroundServiceConfig());

      expect(merged.toMap(), configured.toMap());
      expect(merged.showNotificationOnPauseOnly, isTrue);
      expect(merged.notificationTitle, '📍 Tracking');
      expect(merged.enabled, isFalse);
    });

    test('supplied fields win, untouched fields survive', () {
      final merged = configured.mergedWith(
        const ForegroundServiceConfig(notificationText: 'Paused'),
      );

      expect(merged.notificationText, 'Paused');
      expect(merged.notificationTitle, '📍 Tracking');
      expect(merged.channelId, 'demo_channel');
      expect(merged.showNotificationOnPauseOnly, isTrue);
    });

    test('an explicit value equal to the default still overrides', () {
      final merged = configured.mergedWith(
        const ForegroundServiceConfig(showNotificationOnPauseOnly: false),
      );

      expect(merged.showNotificationOnPauseOnly, isFalse);
      expect(merged.notificationTitle, '📍 Tracking');
    });

    test('timer values merge independently and later values win', () {
      const configured = ForegroundServiceConfig(
        notificationStartedAt: 1234,
        notificationShowTimer: true,
      );

      expect(
        configured.mergedWith(const ForegroundServiceConfig()).toMap(),
        configured.toMap(),
      );

      final disabled = configured.mergedWith(
        const ForegroundServiceConfig(notificationShowTimer: false),
      );
      expect(disabled.notificationStartedAt, 1234);
      expect(disabled.notificationShowTimer, isFalse);
      expect(disabled.toMap()['notificationShowTimer'], isFalse);

      final replaced = disabled.mergedWith(
        const ForegroundServiceConfig(notificationStartedAt: 5678),
      );
      expect(replaced.notificationStartedAt, 5678);
      expect(replaced.notificationShowTimer, isFalse);
    });

    test('alert-once explicit false overrides true', () {
      const configured = ForegroundServiceConfig(
        notificationOnlyAlertOnce: true,
      );

      final disabled = configured.mergedWith(
        const ForegroundServiceConfig(notificationOnlyAlertOnce: false),
      );

      expect(disabled.notificationOnlyAlertOnce, isFalse);
      expect(disabled.toMap()['notificationOnlyAlertOnce'], isFalse);
    });

    test('a start instant alone counts as an explicit value', () {
      expect(
        const ForegroundServiceConfig(
          notificationStartedAt: 1234,
        ).hasExplicitValues,
        isTrue,
      );
    });

    test('merging onto an unconfigured base keeps the payload minimal', () {
      // After a process restart the mirror is empty while the platform still
      // holds the persisted values; the merge must not invent defaults.
      final merged = const ForegroundServiceConfig().mergedWith(
        const ForegroundServiceConfig(showNotificationOnPauseOnly: true),
      );

      expect(merged.toMap(), {'showNotificationOnPauseOnly': true});
    });
  });

  group('#320 the Pigeon payload carries the absence', () {
    test('unset fields cross the channel as null', () {
      final tl = const ForegroundServiceConfig().toTlConfig();

      expect(tl.enabled, isNull);
      expect(tl.channelId, isNull);
      expect(tl.notificationTitle, isNull);
      expect(tl.notificationPriority, isNull);
      expect(tl.showNotificationOnPauseOnly, isNull);
      expect(tl.notificationStartedAt, isNull);
      expect(tl.notificationShowTimer, isNull);
      expect(tl.notificationOnlyAlertOnce, isNull);
      expect(tl.actions, isNull);
    });

    test('supplied fields cross the channel with their value', () {
      final tl = const ForegroundServiceConfig(
        showNotificationOnPauseOnly: true,
        notificationStartedAt: 4294967296,
        notificationShowTimer: false,
        notificationOnlyAlertOnce: false,
        notificationPriority: NotificationPriority.high,
      ).toTlConfig();

      expect(tl.showNotificationOnPauseOnly, isTrue);
      expect(tl.notificationPriority, isNotNull);
      expect(tl.notificationStartedAt, 4294967296);
      expect(tl.notificationShowTimer, isFalse);
      expect(tl.notificationOnlyAlertOnce, isFalse);
      expect(tl.enabled, isNull);
    });
  });
}
