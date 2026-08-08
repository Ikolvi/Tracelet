import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #321 — a partial `setConfig()` reset *every* section, not just the
/// foreground service.
///
/// `setConfig()` merges into the configuration the platform already persisted,
/// and both native merges skip fields they do not receive. Android says so in
/// as many words — *"a partial setConfig() must not overwrite existing non-null
/// config with defaults"* — and iOS has the identical guard. Both were correct
/// and unreachable: every field of the Dart `Config` model was non-nullable
/// with a default, so `toMap()` emitted all of them and a `null` was never
/// sent. `setConfig(const Config())` therefore serialised a complete
/// configuration built entirely of defaults and wrote it over everything
/// stored — `stopOnTerminate`, `distanceFilter`, the HTTP URL, the iOS
/// keep-alive flags, all of it — then persisted the result.
///
/// #320 fixed this for `foregroundService` on Android. This is the rest of the
/// model, on every platform. On iOS the damage was worse in kind: the bridge
/// builds one flat dictionary with no section boundaries, and the fields it
/// reset — `showsBackgroundLocationIndicator`, `preventSuspend`,
/// `useBackgroundActivitySession` — are the ones that keep background tracking
/// alive.
///
/// Each field now records whether it was *supplied*, separately from its value.
/// The getters still return non-nullable values with the same defaults, so
/// reading a config is unchanged; `toMap()`/`toTlConfig()` omit what was never
/// set. `ready()` sends a fully **resolved** baseline while `setConfig()` sends
/// only what the caller set — that split is what makes omission safe, because
/// the platforms' own defaults never have to match Dart's for correctness.
///
/// Passing a value equal to the default is still an explicit write, so a flag
/// can always be set back. "Unset" means *not provided*, never *equal to the
/// default* — the latter test would make a default unreachable once changed.
class Issue321Card extends StatefulWidget {
  const Issue321Card({super.key});

  @override
  State<Issue321Card> createState() => _Issue321CardState();
}

class _Issue321CardState extends State<Issue321Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      // ---------------------------------------------------------------------
      // The serialization contract — platform-independent, so it runs on web.
      // ---------------------------------------------------------------------
      // Checked strictly: the payload must be empty, not "every section
      // present and empty", and not "empty apart from an empty nested map".
      // Each allowance in turn was where something hid — first `geo` shipping
      // `filter: {}` and `android` shipping `foregroundService: {}`, then all
      // sixteen sections shipping `{}` themselves. None of it reaches the
      // merge, but a partial update that changes nothing should not look like
      // it touched anything.
      final emptyPayload = const Config().toMap();
      final leftover = emptyPayload.entries
          .map(
            (e) => e.value is Map<String, Object?>
                ? '${e.key} (${(e.value! as Map<String, Object?>).keys.join(', ')})'
                : e.key,
          )
          .toList();
      check(
        'const Config() serializes to nothing at all',
        emptyPayload.isEmpty,
        emptyPayload.isEmpty
            ? 'the payload is empty — a setConfig() that configures nothing '
                  'now sends nothing at all'
            : 'REGRESSED — still emits ${leftover.join(', ')}',
      );

      // The counterpart: empty because nothing was supplied, not because
      // toMap() stopped emitting. Without this the row above passes on a
      // serializer that returns {} unconditionally.
      final appOnly = const Config(
        app: AppConfig(heartbeatInterval: 30),
      ).toMap();
      final onlyAppSection =
          appOnly.length == 1 &&
          (appOnly['app'] as Map<String, Object?>?)?['heartbeatInterval'] == 30;
      check(
        'a section appears as soon as it carries a field',
        onlyAppSection,
        onlyAppSection
            ? 'setting one field emits exactly one section carrying exactly '
                  'that field'
            : 'REGRESSED — emits ${appOnly.keys.join(', ')}; the empty payload '
                  'above may just be a serializer that emits nothing',
      );

      final geoOnly =
          const Config(geo: GeoConfig(distanceFilter: 25)).toMap()['geo']!
              as Map<String, Object?>;
      check(
        'only the field you set is transmitted',
        geoOnly.length == 1 && geoOnly['distanceFilter'] == 25,
        geoOnly.length == 1
            ? 'the geo section carries distanceFilter and nothing else'
            : 'REGRESSED — also carries ${geoOnly.keys.where((k) => k != 'distanceFilter').join(', ')}',
      );

      final explicitDefault =
          const Config(ios: IosConfig(preventSuspend: false)).toMap()['ios']!
              as Map<String, Object?>;
      check(
        'an explicit value equal to the default is still sent',
        explicitDefault.containsKey('preventSuspend'),
        explicitDefault.containsKey('preventSuspend')
            ? 'a flag can always be set back to its default'
            : 'REGRESSED — default-valued fields are being dropped, so a flag '
                  'could never be turned back off',
      );

      // ready() must still pin everything, or the platform is left guessing.
      final resolvedIos =
          const Config().resolved().toMap()['ios']! as Map<String, Object?>;
      check(
        'ready() still sends a complete baseline',
        resolvedIos.isNotEmpty,
        resolvedIos.isNotEmpty
            ? '${resolvedIos.length} iOS fields resolved — omission is safe '
                  'because ready() establishes every value explicitly'
            : 'REGRESSED — resolved() emits nothing, so a fresh install would '
                  'depend on the native defaults matching Dart exactly',
      );

      // A round trip must not turn "unset" into "explicitly the default";
      // Config.fromMap(toMap()) is a real path (battery budget, remote config).
      const partial = Config(
        geo: GeoConfig(distanceFilter: 25),
        ios: IosConfig(preventSuspend: true),
      );
      final roundTripped = Config.fromMap(partial.toMap()).toMap().toString();
      check(
        'a toMap/fromMap round trip preserves unset-ness',
        roundTripped == partial.toMap().toString(),
        roundTripped == partial.toMap().toString()
            ? 'the payload is unchanged by a round trip'
            : 'REGRESSED — round-tripping inflated unset fields into explicit '
                  'defaults, which is the clobbering being fixed',
      );

      if (kIsWeb) {
        _set(
          '${allPass ? '✅ SUCCESS' : '❌ FAILED'}\n\n${results.join('\n')}\n\n'
          'ℹ️ Web stops here: there is no persisted native config to merge '
          'into, so the end-to-end half below does not apply.',
        );
        return;
      }

      // ---------------------------------------------------------------------
      // End-to-end: configure, then issue a setConfig() about something else.
      // ---------------------------------------------------------------------
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(distanceFilter: 25),
          app: AppConfig(stopOnTerminate: false, startOnBoot: true),
          ios: IosConfig(
            preventSuspend: true,
            showsBackgroundLocationIndicator: true,
          ),
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              notificationTitle: '📍 Issue 321',
              showNotificationOnPauseOnly: true,
            ),
          ),
        ),
      );

      // The repro. Before the fix this reset every one of the fields above.
      await Tracelet.setConfig(const Config());

      final c = Tracelet.activeConfig;
      check(
        '#321 geo and app survived a bare setConfig(Config())',
        c.geo.distanceFilter == 25 &&
            !c.app.stopOnTerminate &&
            c.app.startOnBoot,
        c.geo.distanceFilter == 25 &&
                !c.app.stopOnTerminate &&
                c.app.startOnBoot
            ? 'distanceFilter=25, stopOnTerminate=false, startOnBoot=true — '
                  'all as configured'
            : 'REGRESSED — distanceFilter=${c.geo.distanceFilter}, '
                  'stopOnTerminate=${c.app.stopOnTerminate}, '
                  'startOnBoot=${c.app.startOnBoot}',
      );

      final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      if (isIos) {
        check(
          '#321 the iOS keep-alive flags survived',
          c.ios.preventSuspend && c.ios.showsBackgroundLocationIndicator,
          c.ios.preventSuspend && c.ios.showsBackgroundLocationIndicator
              ? 'preventSuspend and showsBackgroundLocationIndicator both '
                    'still true — background tracking is not silently degraded'
              : 'REGRESSED — preventSuspend=${c.ios.preventSuspend}, '
                    'showsBackgroundLocationIndicator='
                    '${c.ios.showsBackgroundLocationIndicator}',
        );
      } else {
        check(
          '#320 the foreground-service config survived',
          c.android.foregroundService.showNotificationOnPauseOnly &&
              c.android.foregroundService.notificationTitle == '📍 Issue 321',
          c.android.foregroundService.showNotificationOnPauseOnly &&
                  c.android.foregroundService.notificationTitle ==
                      '📍 Issue 321'
              ? 'the flag and the title are both intact'
              : 'REGRESSED — pauseOnly='
                    '${c.android.foregroundService.showNotificationOnPauseOnly}, '
                    'title=${c.android.foregroundService.notificationTitle}',
        );
      }

      // A field the caller *does* set must still take effect.
      await Tracelet.setConfig(
        const Config(geo: GeoConfig(distanceFilter: 50)),
      );
      final after = Tracelet.activeConfig;
      check(
        'a supplied field still updates, alongside the preserved ones',
        after.geo.distanceFilter == 50 && !after.app.stopOnTerminate,
        after.geo.distanceFilter == 50 && !after.app.stopOnTerminate
            ? 'distanceFilter moved to 50 while stopOnTerminate stayed false — '
                  'a merge, not a replace'
            : 'distanceFilter=${after.geo.distanceFilter}, '
                  'stopOnTerminate=${after.app.stopOnTerminate}',
      );

      final header = allPass
          ? '✅ SUCCESS: a partial setConfig() no longer resets any section.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'How to read this: setConfig() is now a genuine partial update on '
        'every platform. Only the fields you actually set are transmitted; '
        'everything else keeps whatever the platform persisted. Use ready() '
        '(or reset()) when you want to replace the whole baseline.\n\n'
        'The one thing to keep in mind: passing a value that happens to equal '
        'the default is still an explicit write. That is deliberate — the '
        'alternative, dropping default-valued fields, would make it impossible '
        'to set a flag back to its default once you had changed it.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'setConfig config merge partial replace clobber overwrite defaults '
          'unset resolved ready baseline preventSuspend '
          'showsBackgroundLocationIndicator useBackgroundActivitySession '
          'stopOnTerminate distanceFilter pigeon nullable 321 320',
      title: '#321: setConfig() is a partial update in every section',
      description:
          'Verifies that a setConfig() which does not mention a field leaves '
          'the persisted value alone across the whole Config model — geo, app, '
          'http, iOS keep-alive flags and the Android foreground service — '
          'while a field that is supplied still takes effect, and ready() '
          'still sends a complete baseline.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
