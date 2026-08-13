import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #320 — a partial `setConfig()` overwrote the persisted
/// foreground-service configuration with defaults.
///
/// `setConfig()` merges into the configuration the platform has already
/// persisted, and that merge skips fields it does not receive. But every field
/// of `ForegroundServiceConfig` was non-nullable with a default, so
/// `Config.toMap()` emitted a value for all of them: `const Config()`
/// serialised a complete foreground-service section built entirely of defaults.
/// The platform could not tell that apart from a deliberate configuration and
/// wrote it over the stored values — then persisted the result, so it survived
/// process death.
///
/// The reported symptom was `showNotificationOnPauseOnly: true` quietly
/// reverting, so the tracking notification appeared while the app was
/// foregrounded. It looked like a regression because `ready()` re-sends the
/// full config: a fresh install always looked right, and only a later partial
/// `setConfig()` — the Low-Accuracy GF button calls `setConfig(const Config())`
/// — broke it. The same call also reset the title, text, channel and priority.
///
/// Each field now records whether it was *supplied*, separately from its
/// value. The getters still return non-nullable values with the same defaults,
/// so reading a config is unchanged; but `toMap()`/`toTlConfig()` omit fields
/// that were never set, and the platform's null-skip — which was always
/// correct and simply never reached — does the rest.
///
/// The card checks the one field the platform reports back. `enabled` is
/// surfaced natively through `getForegroundServiceHealth()`, so setting it to a
/// **non-default** value and then issuing an unrelated `setConfig()` proves the
/// *persisted native* value survived, not merely the Dart mirror.
/// `showNotificationOnPauseOnly` has no such readback, so it is checked through
/// `activeConfig` — the same mirror `TraceletDoctor`'s config review reads.
class Issue320Card extends StatefulWidget {
  const Issue320Card({super.key});

  @override
  State<Issue320Card> createState() => _Issue320CardState();
}

class _Issue320CardState extends State<Issue320Card>
    with IssueCardRun<Issue320Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (kIsWeb) {
        _set(
          'ℹ️ Not applicable on web — there is no foreground service and no '
          'persisted native config to clobber.',
        );
        return;
      }

      // ---------------------------------------------------------------------
      // The serialization contract, which is the actual fix.
      // ---------------------------------------------------------------------
      const unset = ForegroundServiceConfig();
      check(
        'an unset foreground-service config serializes to nothing',
        unset.toMap().isEmpty,
        unset.toMap().isEmpty
            ? 'toMap() is empty — a setConfig() that says nothing about the '
                  'notification now sends nothing about it'
            : 'REGRESSED — emits ${unset.toMap().keys.join(', ')}, which the '
                  'platform will write over the persisted values',
      );

      // #321 went one step further than #320: rather than sending an empty
      // `'foregroundService': {}`, it drops the sub-map altogether, so the key
      // is now absent. Both shapes satisfy the claim this row actually makes —
      // nothing about the foreground service is transmitted — so it asserts on
      // the keys, not on which of the two shapes carries none of them. Pinned
      // to "present and empty", it failed against the stronger payload while
      // printing the passing text, because the predicate and the message
      // disagreed about whether absent counted.
      final fgSection =
          (const Config().toMap()['android']
                  as Map<String, Object?>?)?['foregroundService']
              as Map<String, Object?>?;
      final fgKeys = fgSection?.keys.toList() ?? const <String>[];
      check(
        'const Config() carries no foreground-service keys',
        fgKeys.isEmpty,
        fgKeys.isEmpty
            ? 'the section is '
                  '${fgSection == null ? 'absent entirely' : 'present but empty'}'
                  ' — this is the exact payload the Low-Accuracy GF button sends'
            : 'REGRESSED — still carries ${fgKeys.length} default '
                  'field(s): ${fgKeys.join(', ')}',
      );

      // "Unset" must mean *not provided*, never *equal to the default* —
      // otherwise a field could never be set back to its default once changed.
      const explicitDefault = ForegroundServiceConfig(
        showNotificationOnPauseOnly: false,
      );
      final sendsExplicitDefault = explicitDefault.toMap().containsKey(
        'showNotificationOnPauseOnly',
      );
      check(
        'an explicit value equal to the default is still transmitted',
        sendsExplicitDefault,
        sendsExplicitDefault
            ? 'setting the flag back to false still reaches the platform'
            : 'REGRESSED — a default-valued field is being dropped, so the flag '
                  'can never be turned back off',
      );

      // ---------------------------------------------------------------------
      // End-to-end: configure, then issue an unrelated setConfig().
      // ---------------------------------------------------------------------
      await Tracelet.requestLocationAuthorization();

      // `enabled: false` is deliberately the non-default value: it is the one
      // field the platform reports back, so it is the only way to observe the
      // persisted native config from Dart. Before the fix, the setConfig()
      // below reverted it to the default `true`.
      await Tracelet.ready(
        const Config(
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              enabled: false,
              notificationTitle: '📍 Issue 320',
              channelId: 'issue_320_channel',
              showNotificationOnPauseOnly: true,
            ),
          ),
        ),
      );

      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

      if (isAndroid) {
        final before = await Tracelet.getForegroundServiceHealth();
        check(
          'the configured value reached the platform',
          before['foregroundServiceEnabled'] == false,
          before['foregroundServiceEnabled'] == false
              ? 'native reports foregroundServiceEnabled=false as configured'
              : 'native reports ${before['foregroundServiceEnabled']} — the '
                    'configuration never landed, so the rest of this card '
                    'cannot mean anything',
        );
      }

      // The repro: a setConfig() about something else entirely. This is what
      // the Low-Accuracy GF button does.
      await Tracelet.setConfig(
        const Config(app: AppConfig(heartbeatInterval: 30)),
      );

      if (isAndroid) {
        final after = await Tracelet.getForegroundServiceHealth();
        final survived = after['foregroundServiceEnabled'] == false;
        check(
          '#320 the persisted native config survived a partial setConfig()',
          survived,
          survived
              ? 'native still reports foregroundServiceEnabled=false — the '
                    'unrelated update left it alone'
              : 'REGRESSED — reverted to '
                    '${after['foregroundServiceEnabled']}. An unrelated '
                    'setConfig() overwrote the stored foreground-service config '
                    'with defaults.',
        );
      } else {
        results.add(
          'ℹ️ iOS — there is no foreground service, so there is no native '
          'readback to assert. The serialization checks above are the '
          'platform-independent half of the fix.',
        );
      }

      final fg = Tracelet.activeConfig.android.foregroundService;
      check(
        '#320 showNotificationOnPauseOnly survived',
        fg.showNotificationOnPauseOnly,
        fg.showNotificationOnPauseOnly
            ? 'still true — the notification stays hidden while the app is '
                  'foregrounded, as configured'
            : 'REGRESSED — reverted to false. Pressing Start would now show the '
                  'tracking notification with the app open.',
      );

      check(
        '#320 the other notification fields survived',
        fg.notificationTitle == '📍 Issue 320' &&
            fg.channelId == 'issue_320_channel',
        fg.notificationTitle == '📍 Issue 320' &&
                fg.channelId == 'issue_320_channel'
            ? 'title and channel intact — the whole section was preserved, not '
                  'just the reported flag'
            : 'REGRESSED — title=${fg.notificationTitle}, '
                  'channel=${fg.channelId}',
      );

      // A field the caller *does* set must still take effect.
      await Tracelet.setConfig(
        const Config(
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              notificationText: 'Updated by #320 card',
            ),
          ),
        ),
      );
      final updated = Tracelet.activeConfig.android.foregroundService;
      check(
        'a supplied field still updates, alongside the preserved ones',
        updated.notificationText == 'Updated by #320 card' &&
            updated.showNotificationOnPauseOnly &&
            updated.notificationTitle == '📍 Issue 320',
        updated.notificationText == 'Updated by #320 card' &&
                updated.showNotificationOnPauseOnly &&
                updated.notificationTitle == '📍 Issue 320'
            ? 'text updated while the flag and title were left as configured — '
                  'a merge, not a replace'
            : 'text=${updated.notificationText}, '
                  'pauseOnly=${updated.showNotificationOnPauseOnly}, '
                  'title=${updated.notificationTitle}',
      );

      final header = allPass
          ? '✅ SUCCESS: a partial setConfig() no longer resets the '
                'foreground-service configuration.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'To see the original bug by hand: press Initialize (which configures '
        'showNotificationOnPauseOnly: true), then Low-Accuracy GF (which calls '
        'setConfig(const Config())), then Start. Before this fix the tracking '
        'notification appeared with the app open, under the default title, and '
        'stayed that way until Initialize ran again.\n\n'
        'Scope: this covers the foregroundService section. Every other section '
        'of Config still replaces rather than merges — setConfig(const '
        'Config()) resets stopOnTerminate, distanceFilter, the HTTP settings '
        'and the rest. That is tracked separately as #321; fixing it means '
        'making the whole public Config model unset-aware across all four '
        'platforms.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'setConfig config merge partial foreground service notification '
          'showNotificationOnPauseOnly channel title default clobber overwrite '
          'persisted sharedpreferences pigeon nullable unset 320',
      title: '#320: a partial setConfig() keeps the notification config',
      description:
          'Verifies that a setConfig() which does not mention the foreground '
          'service leaves the persisted notification settings alone — '
          'showNotificationOnPauseOnly, title, text and channel — instead of '
          'overwriting them with defaults, while a field that is supplied still '
          'takes effect.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
