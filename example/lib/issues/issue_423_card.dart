import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #423 — continuous mode opened a `CLBackgroundActivitySession` with
/// `useBackgroundActivitySession: false`, so the blue location bar showed on an
/// Always-authorized app that had done everything the docs said to hide it.
///
/// The session shows the system indicator for as long as it exists, whatever
/// `showsBackgroundLocationIndicator` says. `IosConfig.useBackgroundActivitySession`
/// is documented as opt-in and defaults to `false` — but only
/// `LocationEngine.start()` ever read it. Every transition to *moving* went
/// through `TraceletSdk.startBackgroundActivitySessionIfNeeded()`, which checked
/// `useSignificantChangesOnly` (#261) and nothing else. So the exact
/// configuration the #210 resolution told users to adopt showed the bar for the
/// length of every trip, and it went away on its own some minutes after the
/// device parked — which is what made it look like an OS quirk rather than the
/// SDK. A customer spent three weeks on it.
///
/// Under Always the session buys nothing: `allowsBackgroundLocationUpdates` and
/// the `location` background mode already keep the stream delivering. It now
/// opens only with the opt-in — or under When-In-Use authorization, where it is
/// what lets the stream survive suspension and the OS shows the indicator
/// regardless, so nothing the flag protects is lost.
///
/// **What this card proves**, from the debug log, with the app on screen:
///
///  * with the flag off and the session moving, no
///    `CLBackgroundActivitySession started` line appears and the decline is
///    logged with its reason;
///  * with the flag on, the same start opens the session — the opt-in is the
///    thing that changed, so it must be the thing that opens it.
///
/// Under When-In-Use the first half is expected to open the session; the card
/// says so instead of failing.
class Issue423Card extends StatefulWidget {
  const Issue423Card({super.key});

  @override
  State<Issue423Card> createState() => _Issue423CardState();
}

class _Issue423CardState extends State<Issue423Card>
    with IssueCardRun<Issue423Card> {
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  IssueRunner? get cardRunner => _run;

  static const _started = 'CLBackgroundActivitySession started';
  static const _declined = 'Not starting CLBackgroundActivitySession';

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (!_isIOS) {
        setStatus(
          'ℹ️ iOS only. CLBackgroundActivitySession is an iOS 17+ API; Android '
          'has no equivalent and no indicator tied to one.',
        );
        return;
      }

      final auth = await Tracelet.requestLocationAuthorization();
      final whenInUse = auth == AuthorizationStatus.whenInUse;

      Future<List<LogEntry>> startAndCollect({required bool optIn}) async {
        await Tracelet.ready(
          Config(
            geo: const GeoConfig(distanceFilter: 0),
            // Start moving so start() takes the branch that used to open the
            // session unconditionally.
            motion: const MotionConfig(isMoving: true),
            http: const HttpConfig(autoSync: false),
            // The customer's configuration, stated in full.
            ios: IosConfig(
              showsBackgroundLocationIndicator: false,
              useBackgroundActivitySession: optIn,
            ),
            // Both the start and the decline are debug lines.
            logger: const LoggerConfig(logLevel: LogLevel.debug),
          ),
        );
        await Tracelet.destroyLog();
        await Tracelet.start();
        await Future<void>.delayed(const Duration(seconds: 3));
        final logs = await Tracelet.getLogs(300);
        await Tracelet.stop();
        return logs;
      }

      // ---------------------------------------------------------------------
      // 1. Opted out: no session.
      // ---------------------------------------------------------------------
      setStatus('⏳ Starting with useBackgroundActivitySession: false…');
      final optedOut = await startAndCollect(optIn: false);
      final openedWithoutOptIn = optedOut.any(
        (l) => l.message.contains(_started),
      );
      final declineLine = optedOut
          .where((l) => l.message.contains(_declined))
          .map((l) => l.message)
          .toList();

      if (whenInUse) {
        check(
          'When-In-Use: the session opens regardless of the flag',
          pass: openedWithoutOptIn,
          detail: openedWithoutOptIn
              ? 'opened — it is what keeps the stream alive through '
                    'suspension here, and the OS shows the indicator anyway'
              : 'not opened — a When-In-Use app would lose tracking on '
                    'suspension',
        );
      } else {
        check(
          'opted out: no CLBackgroundActivitySession is opened',
          pass: !openedWithoutOptIn,
          detail: !openedWithoutOptIn
              ? 'no "$_started" line — the indicator has nothing to hold it on'
              : 'the session opened with the flag off; this is the bug',
        );
        check(
          'the decline is logged with its reason',
          pass: declineLine.isNotEmpty,
          detail: declineLine.isNotEmpty
              ? declineLine.first
              : 'no decline line — a reader could not tell the flag was '
                    'honoured from the log',
        );
      }

      // ---------------------------------------------------------------------
      // 2. Opted in: the session opens.
      // ---------------------------------------------------------------------
      setStatus('⏳ Starting with useBackgroundActivitySession: true…');
      final optedIn = await startAndCollect(optIn: true);
      final openedWithOptIn = optedIn.any((l) => l.message.contains(_started));
      check(
        'opted in: the session still opens',
        pass: openedWithOptIn,
        detail: openedWithOptIn
            ? '"$_started" present — the flag is what opens it'
            : 'no session with the flag on (iOS < 17 logs "not available" '
                  'instead, which is expected there)',
      );

      final header = allPass
          ? '✅ SUCCESS: the session is opened by the opt-in, not by moving.'
          : '❌ FAILED — #423 not satisfied on this build.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'Authorization during this run: ${auth.name}. Under Always the session '
        'buys nothing — background delivery already continues without it — '
        'so leaving useBackgroundActivitySession false is what hides the '
        'indicator. Under When-In-Use the SDK opens it regardless, because it '
        'is what lets the stream survive suspension and the OS shows the '
        'indicator in that state anyway.\n\n'
        'To see the original symptom: on a build before this fix, background '
        'the app with the flag off and walk — the blue bar appears when the '
        'motion state flips to moving and stays until some minutes after the '
        'device parks.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'ios blue bar location indicator dynamic island pill '
          'CLBackgroundActivitySession useBackgroundActivitySession '
          'showsBackgroundLocationIndicator always continuous moving 423 210 261',
      title: '#423: the blue bar honours useBackgroundActivitySession',
      description:
          'Continuous mode opened a CLBackgroundActivitySession on every moving '
          'transition regardless of the opt-in, so an Always-authorized app with '
          'the flag off showed the blue location bar for every trip. Starts '
          'twice — flag off, then on — and reads the log to check the session '
          'is opened by the flag, not by moving.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
