import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #416 — Android current-position sampling regressed to cached one-shots.
///
/// The native regression test proves `requestLocationUpdates()` supplies the
/// result and is removed exactly once. This card proves the public API returns a
/// recently captured fix on real hardware without another location client first
/// waking GPS. Location permission must already be granted so this card remains
/// independent of the permission-lifecycle fix in #415.
class Issue416Card extends StatefulWidget {
  const Issue416Card({super.key});

  @override
  State<Issue416Card> createState() => _Issue416CardState();
}

class _Issue416CardState extends State<Issue416Card>
    with IssueCardRun<Issue416Card> {
  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    setStatus('⏳ Waiting for a fresh Android provider update…');
    final stopwatch = Stopwatch()..start();

    try {
      // Permission is a precondition so this card does not depend on #415.
      final authorization = await Tracelet.getLocationAuthorization();
      if (authorization != AuthorizationStatus.whenInUse &&
          authorization != AuthorizationStatus.always) {
        setStatus(
          '⚠️ PRECONDITION: grant foreground location permission from the '
          'example app, then run #416 again. This card deliberately does not '
          'request permission so it remains independent of #415.',
        );
        return;
      }

      await Tracelet.ready(
        const Config(
          app: AppConfig(stopOnTerminate: true, startOnBoot: false),
          motion: MotionConfig(disableMotionActivityUpdates: true),
          http: HttpConfig(autoSync: false),
        ),
      );
      final location = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        maximumAge: 0,
        samples: 1,
        persist: false,
        timeout: 15,
      );
      stopwatch.stop();

      final capturedAt = DateTime.parse(location.timestamp).toUtc();
      final age = DateTime.now().toUtc().difference(capturedAt);
      // The bound allows delivery latency while rejecting a cached position.
      final fresh = !age.isNegative && age <= const Duration(seconds: 10);
      setStatus(
        fresh
            ? '✅ PASS: getCurrentPosition returned a fresh provider update.\n\n'
                  'Fix age: ${age.inMilliseconds} ms\n'
                  'Elapsed: ${stopwatch.elapsedMilliseconds} ms\n'
                  'Source: ${location.locationSource}'
            : '❌ FAILED: getCurrentPosition returned a stale fix.\n\n'
                  'Captured at: ${capturedAt.toIso8601String()}\n'
                  'Fix age: ${age.inSeconds} s\n'
                  'Elapsed: ${stopwatch.elapsedMilliseconds} ms',
      );
    } catch (error) {
      stopwatch.stop();
      setStatus(
        '❌ FAILED: getCurrentPosition did not produce a fresh fix.\n\n'
        'Elapsed: ${stopwatch.elapsedMilliseconds} ms\n$error',
      );
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: '#416: getCurrentPosition did not wake the provider',
      description:
          'Requests one high-accuracy sample with maximumAge zero and verifies '
          'the returned capture time is fresh. Grant location first; this card '
          'does not invoke the #415 permission path.',
      keywords:
          '416 android getCurrentPosition collectSamples fresh cached stale '
          'requestLocationUpdates getCurrentLocation GPS provider',
      status: status,
      running: running,
      onRun: _run,
      prepare: false,
    );
  }
}
