import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #262 — `ready()` must not surface remote-config event registration
/// failure as an UNCAUGHT async error.
///
/// Since 3.6.10, [Tracelet.ready] subscribes to `remoteConfigEvents`, which
/// lazily registers the Pigeon event channel. That registration used to fire
/// `TraceletHostApi.requestStateFlush()` fire-and-forget (no `await`, no error
/// handler). When the platform side is unreachable — e.g. a headless
/// `flutter test` with no channels, or a temporarily detached engine — the
/// rejected future became an *uncaught* async error routed to the zone error
/// handler, instead of an error the caller's `await ready(...)` could catch.
/// In a ride-start path that is fatal: even though the caller wrapped `ready()`
/// in try/catch, the stray error tore down the whole start sequence.
///
/// The fix contains that best-effort flush inside the platform interface
/// (`PigeonTracelet._ensureEventsRegistered`): the flush is still
/// fire-and-forget, but its failure is now swallowed/logged internally so it
/// can never escape as an uncaught async error. Event registration itself
/// already succeeded, so nothing observable is lost.
///
/// The definitive reproduction is the headless test in the issue (no platform
/// channels available). On a real device/simulator the channel IS reachable,
/// so this card verifies the behavioral guarantee the fix provides: it runs
/// `ready()` inside a `runZonedGuarded` error zone (mirroring the reporter's
/// workaround) and asserts that (a) `ready()` is awaitable — it either returns
/// or throws at the call site — and (b) NO stray uncaught async error escapes
/// to the zone handler while the event channels register. Pre-fix, a
/// registration failure would land in the zone handler; post-fix the zone
/// stays clean on both Android and iOS.
class Issue262Card extends StatefulWidget {
  const Issue262Card({super.key});

  @override
  State<Issue262Card> createState() => _Issue262CardState();
}

class _Issue262CardState extends State<Issue262Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _test() async {
    setState(() => _running = true);
    try {
      _set(
        'Calling Tracelet.ready() inside a runZonedGuarded error zone and '
        'watching for stray uncaught async errors...',
      );

      final zoneErrors = <Object>[];
      final done = Completer<void>();
      var readyReturned = false;
      var caughtAtCallSite = false;
      Object? callSiteError;

      // Mirror the reporter's workaround as an assertion: run ready() in its
      // own error zone. A well-behaved ready() must complete the awaited path
      // (return OR throw here) and must NOT leak a fire-and-forget error into
      // the zone handler.
      runZonedGuarded(
        () async {
          try {
            // Accessing remoteConfigEvents inside ready() is what registers the
            // event channel and used to fire the unawaited requestStateFlush().
            await Tracelet.ready(const Config());
            readyReturned = true;
          } catch (e) {
            // A genuine failure is fine as long as it is catchable HERE rather
            // than escaping as an uncaught async error.
            caughtAtCallSite = true;
            callSiteError = e;
          } finally {
            if (!done.isCompleted) done.complete();
          }
        },
        (error, stack) {
          // Pre-fix, the fire-and-forget requestStateFlush() rejection lands
          // here as an UNCAUGHT async error — the #262 bug.
          zoneErrors.add(error);
        },
      );

      await done.future;

      // Give any stray fire-and-forget future a chance to reject into the zone
      // before we assert the zone stayed clean.
      await Future<void>.delayed(const Duration(seconds: 2));

      if (zoneErrors.isNotEmpty) {
        _set(
          '❌ FAILED: ${zoneErrors.length} uncaught async error(s) escaped to '
          'the zone handler during event-channel registration — the #262 bug. '
          'A fire-and-forget flush failure must be contained inside the '
          'platform interface, not routed to the zone. First: '
          '${zoneErrors.first}',
        );
        return;
      }

      if (!readyReturned && !caughtAtCallSite) {
        _set(
          '❌ FAILED: ready() neither returned nor threw at the call site, so '
          'its awaited path could not be observed.',
        );
        return;
      }

      final outcome = readyReturned
          ? 'ready() completed normally'
          : 'ready() threw a catchable error at the call site ($callSiteError)';
      _set(
        '✅ SUCCESS: $outcome and NO uncaught async error escaped the error '
        'zone. Remote-config event registration no longer routes a stray '
        'fire-and-forget failure to the zone handler, so a caller awaiting '
        'ready() (e.g. a ride-start path) can always recover.',
      );
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      try {
        await Tracelet.stop();
      } catch (_) {}
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'ready uncaught async error zone runzonedguarded remote config '
          'remoteconfigevents requeststateflush event channel registration '
          'fire and forget platform exception ride start',
      title: '#262: ready() must not surface registration failure as uncaught',
      description:
          'Runs Tracelet.ready() inside a runZonedGuarded error zone and '
          'asserts (a) ready() is awaitable — it returns or throws at the call '
          'site — and (b) no stray uncaught async error escapes to the zone '
          'handler while the remote-config event channel registers. Pre-fix, a '
          'fire-and-forget requestStateFlush() failure landed in the zone and '
          'took down a ride-start sequence. Runs on Android and iOS.',
      status: _status,
      running: _running,
      onRun: _test,
    );
  }
}
