import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #255 — authoritative foreground-service health exposed to Dart.
///
/// `Tracelet.getState().enabled` reports the *desired* tracking state: it is
/// set to `true` before `LocationService.start()` is even called. It therefore
/// cannot tell you whether the service is actually running, whether it was
/// promoted to the foreground, or whether that promotion was deferred or
/// rejected by the OS — all of which happen in the real world on aggressive
/// OEMs and under Android 12+ foreground-service start restrictions.
///
/// `getForegroundServiceHealth()` reports what is actually true, so an app can
/// detect "tracking is requested but the service is not up" and recover, rather
/// than trusting `enabled` and silently collecting nothing.
///
/// The interesting assertion is the *relationship* between the fields, not any
/// single value: while tracking with a foreground service configured, a healthy
/// device must show the service running, and a promotion that did not succeed
/// must carry a reason.
class Issue255Card extends StatefulWidget {
  const Issue255Card({super.key});

  @override
  State<Issue255Card> createState() => _Issue255CardState();
}

class _Issue255CardState extends State<Issue255Card>
    with IssueCardRun<Issue255Card> {
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
      final isAndroid = !kIsWeb && Platform.isAndroid;

      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              notificationTitle: 'Issue #255',
              notificationText: 'Verifying foreground-service health',
            ),
          ),
        ),
      );

      // The auto-stop paths (stopOnStationary, stopAfterElapsedMinutes) are
      // off by default and deliberately left alone — but they are not the only
      // thing that can flip tracking state mid-run, which is why the intent
      // assertion below reads immediately rather than after a delay.
      //
      // Establish a deterministic baseline. The example app is a single
      // process and every card shares one tracking session, so without this
      // the "before tracking" reading is whatever the last card left behind —
      // which is exactly how this card first reported serviceRunning=true
      // under the label "before tracking starts".
      await Tracelet.stop();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // 1. Idle: the API must answer, and must not claim the service is up.
      //    This is the state where `enabled` alone told you nothing.
      final idle = await Tracelet.getForegroundServiceHealth();
      check(
        'Health reports a stopped service as stopped',
        idle['platform'] != null &&
            idle['desiredEnabled'] != true &&
            idle['serviceRunning'] != true,
        'platform=${idle['platform']}, '
            'serviceRunning=${idle['serviceRunning']}, '
            'desiredEnabled=${idle['desiredEnabled']}',
      );

      // 2. The contract that motivated the issue: desiredEnabled reflects the
      //    requested state, reported separately from whether the service
      //    actually came up.
      //
      //    Read immediately — `desiredEnabled` is intent, which is set
      //    synchronously by start(). Waiting first would let an unrelated stop
      //    (another card, a schedule, a motion trigger) race the assertion.
      await Tracelet.start();
      final intent = await Tracelet.getForegroundServiceHealth();
      check(
        'desiredEnabled tracks the requested state',
        intent['desiredEnabled'] == true,
        'desiredEnabled=${intent['desiredEnabled']} immediately after start()',
      );

      // Promotion is asynchronous, so the service fields need a settle window
      // — unlike the intent flag above.
      await Future<void>.delayed(const Duration(seconds: 3));
      final live = await Tracelet.getForegroundServiceHealth();

      // If tracking stopped during the settle window, that is informational,
      // not a failure of #255 — the API is still reporting correctly.
      if (live['desiredEnabled'] != true) {
        results.add(
          'ℹ️ Tracking stopped during the 3s settle window '
          '(desiredEnabled=${live['desiredEnabled']}). The health API is still '
          'reporting truthfully; the service rows below describe that stopped '
          'state.',
        );
      }

      if (isAndroid) {
        // 3. Android only: with a foreground service configured and tracking
        //    on, the service must actually be running. If it is not, the health
        //    map must say WHY — that is the whole point of the API.
        final running = live['serviceRunning'] == true;
        final foreground = live['serviceForeground'] == true;
        final result = live['lastForegroundPromotionResult'];
        check(
          'Service state is reported authoritatively',
          running || result != null,
          running
              ? 'serviceRunning=true, serviceForeground=$foreground, '
                    'notificationId=${live['foregroundNotificationId']}'
              : 'service is NOT running and the reason is recorded: '
                    'result=$result '
                    'class=${live['lastForegroundPromotionFailureClass']} '
                    'message=${live['lastForegroundPromotionFailureMessage']}',
        );

        // 4. A failed or deferred promotion must be diagnosable, not just a
        //    boolean. A successful one needs no failure detail.
        final diagnosable =
            result == null ||
            result == 'success' ||
            live['lastForegroundPromotionFailureClass'] != null ||
            live['lastForegroundPromotionFailureMessage'] != null;
        check(
          'A non-success promotion carries a diagnosable reason',
          diagnosable,
          result == 'success' || result == null
              ? 'promotion result is ${result ?? "not yet attempted"} — no '
                    'failure detail expected'
              : 'result=$result with class/message populated',
        );

        check(
          'Transition timestamp is present once promoted',
          !foreground || live['lastForegroundTransitionAt'] != null,
          'lastForegroundTransitionAt='
              '${live['lastForegroundTransitionAt']}',
        );
      } else {
        results.add(
          'ℹ️ Android-only fields skipped — this platform has no foreground '
          'service. iOS reports the promotion fields as null/false by design, '
          'and web returns a minimal disabled map.',
        );
      }

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: foreground-service health is reported authoritatively, '
                'separately from the desired tracking state.'
          : '❌ FAILED — #255 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'getState().enabled is set before LocationService.start() is called, '
        'so it only ever expressed intent. getForegroundServiceHealth() '
        'reports whether the service is actually running and foreground, and '
        'when a promotion is deferred or rejected it records the exception '
        'class and message — enough to detect silent tracking loss on '
        'aggressive OEMs and recover instead of trusting a stale flag.',
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
          'getForegroundServiceHealth foreground service health promotion '
          'serviceRunning serviceForeground desiredEnabled '
          'lastForegroundPromotionResult deferred failed notification id '
          'android tracking loss authoritative state',
      title: '#255: Authoritative foreground-service health in Dart',
      description:
          'Asserts that getForegroundServiceHealth() distinguishes the desired '
          'tracking state from the actual Android foreground-service state — '
          'whether the service is running and promoted, and when a promotion '
          'was deferred or failed, the exception class and message behind it. '
          'Android-only fields are skipped on other platforms.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
