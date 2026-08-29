import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #1182 — one-shot acquisition must converge on quality rather than
/// treating the first network or cached sample as equivalent to a GNSS fix.
class Issue1182Card extends StatefulWidget {
  const Issue1182Card({super.key});

  @override
  State<Issue1182Card> createState() => _Issue1182CardState();
}

class _Issue1182CardState extends State<Issue1182Card>
    with IssueCardRun<Issue1182Card> {
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
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          app: AppConfig(stopOnTerminate: true, startOnBoot: false),
          persistence: PersistenceConfig(persistMode: PersistMode.none),
        ),
      );

      setStatus('⏳ Waiting for a ≤100 m fix…');
      final qualityStarted = DateTime.now();
      final quality = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        accuracyTarget: 100,
        requestId: 'issue-1182-quality',
        timeout: 30,
        maximumAge: 0,
        persist: false,
      );
      final qualityElapsed = DateTime.now().difference(qualityStarted);
      check(
        'targeted request converged',
        pass: quality.coords.accuracy <= 100,
        detail:
            'accuracy=${quality.coords.accuracy.toStringAsFixed(1)} m, '
            'elapsed=${qualityElapsed.inMilliseconds} ms',
      );

      setStatus('⏳ Exercising best-candidate timeout…');
      final timeoutStarted = DateTime.now();
      final fallback = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        accuracyTarget: 0.1,
        requestId: 'issue-1182-timeout',
        timeout: 5,
        maximumAge: 0,
        persist: false,
      );
      final timeoutElapsed = DateTime.now().difference(timeoutStarted);
      check(
        'deadline returned the best observed candidate',
        pass: timeoutElapsed >= const Duration(seconds: 4),
        detail:
            'accuracy=${fallback.coords.accuracy.toStringAsFixed(1)} m, '
            'elapsed=${timeoutElapsed.inMilliseconds} ms',
      );

      setStatus('⏳ Exercising cancellation…');
      final cancellationFuture = Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        accuracyTarget: 0.1,
        requestId: 'issue-1182-cancel',
        timeout: 30,
        maximumAge: 0,
        persist: false,
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      final cancelled = await Tracelet.cancelCurrentPosition(
        'issue-1182-cancel',
      );
      var completedWithLocation = false;
      try {
        await cancellationFuture;
        completedWithLocation = true;
      } catch (_) {
        // Native cancellation completes the pending Future as unavailable.
      }
      check(
        'cancellation stopped the in-flight request',
        pass: cancelled && !completedWithLocation,
        detail: 'cancelled=$cancelled, lateLocation=$completedWithLocation',
      );

      setStatus(
        '${allPass ? '✅ SUCCESS' : '❌ FAILED'} — #1182 quality convergence\n\n'
        '${results.join('\n')}',
      );
    } catch (error) {
      setStatus('❌ FAILED: $error\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          '1182 one-shot current position quality accuracy target deadline '
          'best candidate cancellation GPS cached network coarse GNSS',
      title: '#1182: one-shot acquisition converges on quality',
      description:
          'Runs real target, timeout, and cancellation requests. Reports only '
          'accuracy and elapsed time; it never displays or stores coordinates.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
