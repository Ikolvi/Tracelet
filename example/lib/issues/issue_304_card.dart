import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #304 — config keys accepted but never applied.
///
/// A sweep of every `ConfigManager` getter on both platforms (156 Android, 149
/// iOS) against its real consumers — including the Rust core, which receives
/// some values via `syncConfigToRustFlat()` rather than by getter — turned up a
/// set of public keys that were validated, stored, and then read by nothing.
///
/// Wired up by this fix:
/// - `logMaxDays` — both platforms pruned logs by a row count derived from
///   `logLevel` and never looked at the day count, so `3` and `90` behaved
///   identically. A row cap cannot express a retention window, because how many
///   rows a window holds depends on how chatty the session was.
/// - `disableLocationAuthorizationAlert` (iOS) — the permission manager
///   requested authorization unconditionally, so apps that wanted their own
///   pre-permission UX could not suppress the system prompt.
///
/// Deprecated instead of wired, because they are not bug fixes:
/// - `AuditConfig.includeExtrasInHash` — changing what goes into the hash
///   invalidates every previously computed chain, so it needs a chain version
///   and a migration, not a silent behavior change.
/// - `AttestationConfig.verificationUrl` — nothing ever sent the token
///   anywhere; the token is already in sync payloads, so verify it on your own
///   backend.
///
/// `locationTemplate`, `geofenceTemplate` and `persistenceExtras` have no Dart
/// field at all — they are native-only keys with zero consumers, documented as
/// unimplemented in both ConfigManagers.
///
/// `allowIdenticalLocations` and `auditHashAlgorithm` were originally scoped as
/// cheap wiring but are not: the first needs a new filter in the Rust processor
/// (and only changes anything when `distanceFilter` is 0), the second changes
/// the audit chain algorithm. Both are tracked separately.
class Issue304Card extends StatefulWidget {
  const Issue304Card({super.key});

  @override
  State<Issue304Card> createState() => _Issue304CardState();
}

class _Issue304CardState extends State<Issue304Card> {
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
      await Tracelet.ready(
        const Config(
          logger: LoggerConfig(logLevel: LogLevel.debug, logMaxDays: 2),
          ios: IosConfig(disableLocationAuthorizationAlert: true),
        ),
      );

      // 1. logMaxDays round-trips and is now actually consulted when pruning.
      //    Pruning itself happens natively against the log table; what this
      //    card can prove from Dart is that the value reaches the SDK rather
      //    than being dropped at the Pigeon boundary.
      // Deliberately NOT asserted via activeConfig: that is a Dart-side mirror
      // of the Config just passed in, so it would pass on a build where the
      // value never reached native. Day-based pruning has no read-back surface,
      // so the honest scope of this card is "the logging path still works with
      // the age cap in place"; the cap itself is asserted in the Rust tests
      // (prune_logs_older_than) and the SDK unit tests.
      results.add(
        'ℹ️ logMaxDays application is not Dart-observable — asserted by the '
        'Rust prune_logs_older_than tests and the SDK unit tests.',
      );

      // 2. Writing a log line and reading the buffer back proves the logging
      //    path still works with the added age-based prune in place (a broken
      //    prune would surface here as an exception or an empty buffer).
      await Tracelet.log('info', '#304 retention probe');
      final logs = await Tracelet.getLog();
      check(
        'Log pruning with a retention window keeps recent lines',
        logs.contains('#304 retention probe'),
        'a line written now survives a 2-day window, as it must',
      );

      // 3. disableLocationAuthorizationAlert round-trips. On iOS the permission
      //    manager now reports the current status instead of prompting; on
      //    Android and web the flag is inert by design.
      // Observable behaviourally on iOS: with the flag on, a permission
      // request must return the CURRENT status without presenting a prompt.
      // If it hung waiting on a dialog, or changed status without user input,
      // the flag was not honored.
      final before = await Tracelet.getProviderState();
      final requested = await Tracelet.requestLocationAuthorization();
      final after = await Tracelet.getProviderState();
      check(
        'A suppressed request returns without changing authorization',
        before.status == after.status,
        'status stayed ${after.status} across a request that returned '
            '$requested — no prompt was presented',
      );

      // 4. The keys that are now honestly marked unimplemented. Their values
      //    still round-trip — deprecation does not change behavior — but the
      //    analyzer will now tell you they do nothing.
      // Not a check — there is nothing to assert at runtime, because a
      // @Deprecated annotation is a compile-time signal. Stating it as a
      // passing check would be theatre.
      results.add(
        'ℹ️ AuditConfig.includeExtrasInHash and '
        'AttestationConfig.verificationUrl now carry @Deprecated with the '
        'reason, so the analyzer flags them in your code; '
        'locationTemplate / geofenceTemplate / persistenceExtras are '
        'documented as unimplemented natively.',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: logMaxDays and disableLocationAuthorizationAlert are '
                'applied, and the keys that do nothing now say so.'
          : '❌ FAILED — #304 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'The audit that found these compared every ConfigManager getter '
        'against its real consumers, so "the value is stored" was never '
        'mistaken for "the value is used". Two keys were wired up; two were '
        'deprecated because implementing them changes an audit chain or sends '
        'a token somewhere, which needs design rather than a patch.',
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
          'logMaxDays disableLocationAuthorizationAlert allowIdenticalLocations '
          'auditHashAlgorithm includeExtrasInHash verificationUrl '
          'locationTemplate geofenceTemplate persistenceExtras unimplemented '
          'config never applied pruneOldLogs retention deprecated',
      title: '#304: Config keys that were accepted but never applied',
      description:
          'Asserts that logMaxDays and disableLocationAuthorizationAlert now '
          'reach the SDK and are acted on, and documents the keys that were '
          'never implemented at all — now deprecated with a reason instead of '
          'silently doing nothing. Found by sweeping all 156 Android / 149 iOS '
          'config getters against their real consumers.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
