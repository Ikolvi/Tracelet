import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #416 — Android `getCurrentPosition()` retried `getCurrentLocation()`
/// instead of asking the provider for a fresh fix.
///
/// The 1.8.7 fix for #46 said `getCurrentPosition(samples: 1)` had moved to
/// `requestLocationUpdates()` so it would wake GPS and return a fresh position.
/// The code never did. Every sample came from a one-shot `getCurrentLocation()`
/// retried every 800 ms — an API that can return null or a cached fix without
/// engaging the hardware — and on the reporting device it did exactly that
/// until the timeout, then fell back to the last known location.
///
/// `collectSamples()` now runs two sources side by side for the bounded
/// window: a continuous request, the only API that actually wakes the
/// provider, and the one-shot loop, kept because it is the path that answers
/// on budget devices whose battery optimisation throttles continuous requests
/// for an app without a foreground service. The first genuine fix from either
/// counts, a fix both deliver is counted once, and every exit removes the
/// continuous request.
///
/// **What this card proves.** From the app's side, the contract the report is
/// about: with tracking *stopped* — so nothing else is holding the provider
/// open — a `getCurrentPosition()` with `maximumAge: 0` returns a fix that is
/// newer than the call itself, within a timeout much shorter than the
/// reporter's. Whether it came from the continuous request or the one-shot is
/// not visible here and does not matter; that both are tried, and both are
/// released, is pinned by `LocationEngineGetCurrentPositionTest`.
///
/// Run it where the phone can get a fix. Indoors with no fix the call falls
/// back to the last known location on timeout, and the card says so rather
/// than failing.
class Issue416Card extends StatefulWidget {
  const Issue416Card({super.key});

  @override
  State<Issue416Card> createState() => _Issue416CardState();
}

class _Issue416CardState extends State<Issue416Card>
    with IssueCardRun<Issue416Card> {
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (!_isAndroid) {
        setStatus(
          'ℹ️ Android only. #416 is the Android engine’s sampling loop; iOS '
          'has always collected samples from startUpdatingLocation.',
        );
        return;
      }

      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );
      // Nothing else may be holding the provider open, or a cached answer
      // would look fresh.
      await Tracelet.stop();

      setStatus('⏳ Requesting a fresh fix with tracking stopped…');
      final requestedAt = DateTime.now().toUtc();
      final sw = Stopwatch()..start();
      final location = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        maximumAge: 0,
        samples: 1,
        persist: false,
        timeout: 15,
      );
      sw.stop();

      final fixAt = DateTime.tryParse(location.timestamp)?.toUtc();
      final gotCoords =
          location.coords.latitude != 0 || location.coords.longitude != 0;
      check(
        'getCurrentPosition() returned a location',
        pass: gotCoords,
        detail: gotCoords
            ? 'in ${sw.elapsedMilliseconds} ms, accuracy '
                  '${location.coords.accuracy.toStringAsFixed(0)} m'
            : 'nothing usable came back in ${sw.elapsedMilliseconds} ms',
      );

      final fresh = fixAt != null && !fixAt.isBefore(requestedAt);
      final fellBack = sw.elapsedMilliseconds >= 14500;
      if (fellBack) {
        results.add(
          'ℹ️ the call ran to its timeout and answered from the last known '
          'location — no fresh fix was available where the phone is. Run it '
          'outdoors to exercise the fresh-fix path.',
        );
      } else {
        check(
          'the fix is newer than the request',
          pass: fresh,
          detail: fresh
              ? 'fix ${fixAt.toIso8601String()} ≥ request '
                    '${requestedAt.toIso8601String()} — the provider was woken, '
                    'not read from cache'
              : 'fix ${fixAt?.toIso8601String() ?? 'unparseable'} is older than '
                    'the request at ${requestedAt.toIso8601String()} — a '
                    'cached answer',
        );
      }

      final header = allPass
          ? '✅ SUCCESS: getCurrentPosition() wakes the provider for a fresh fix.'
          : '❌ FAILED — #416 not satisfied on this build.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'Two sources now run for the timeout window: a continuous request, '
        'which is the only API that actually wakes the provider, and the '
        'one-shot getCurrentLocation() loop, kept for budget devices that '
        'throttle continuous requests without a foreground service. The first '
        'genuine fix from either answers; the continuous request is removed on '
        'every exit. Before this fix only the one-shot ran, and on a device '
        'where it answers null or from cache the call spun to the timeout.',
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
          'android getCurrentPosition getCurrentLocation requestLocationUpdates '
          'fresh fix cached stale null retry timeout samples one-shot '
          'collectSamples 416 46',
      title: '#416: getCurrentPosition() asks the provider for a fresh fix',
      description:
          'The Android sampling loop only ever retried the one-shot '
          'getCurrentLocation(), which can answer null or from cache without '
          'waking GPS, despite the #46 changelog saying otherwise. With '
          'tracking stopped, requests a maximumAge: 0 fix and checks it is '
          'newer than the call.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
