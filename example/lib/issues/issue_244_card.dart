import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// PR #244 — iOS `buildLocationMap` hardcoded `activity.type: "unknown"` /
/// `confidence: -1` on every persisted/dispatched location, so the fused
/// transport mode never reached the per-point `activity` even with
/// `fusedClassifierAuthoritative: true`. Follow-ups: the fused confidence is
/// now persisted alongside the mode (both platforms), fused modes are mapped
/// to the Activity Recognition vocabulary (`vehicle` → `in_vehicle`,
/// `cycling` → `on_bicycle`), and the Dart model parses the snake_case
/// activity strings (they used to collapse to `ActivityType.unknown`).
///
/// The test enables the authoritative fused classifier, then samples
/// locations for ~30 s while listening to `onModeChange`. Sitting still is
/// enough: once the classifier commits `still` (≈8 s dwell), per-point
/// `activity.type` must report it instead of `unknown`. Walk or drive to see
/// the other modes.
class Issue244Card extends StatefulWidget {
  const Issue244Card({super.key});

  @override
  State<Issue244Card> createState() => _Issue244CardState();
}

class _Issue244CardState extends State<Issue244Card>
    with IssueCardRun<Issue244Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    if (running) return;
    setRunning(running: true);

    StreamSubscription<ModeChangeEvent>? modeSub;
    StreamSubscription<Location>? locSub;
    try {
      _set('Configuring authoritative fused classifier...');
      await Tracelet.stop();
      await Tracelet.ready(
        Config.balanced().copyWith(
          classifier: const ClassifierConfig(
            enableFusedClassifier: true,
            fusedClassifierAuthoritative: true,
          ),
          logger: const LoggerConfig(debug: true, logLevel: LogLevel.debug),
        ),
      );

      var lastMode = '(none yet)';
      final seen = <String, int>{};
      modeSub = Tracelet.onModeChange((e) {
        lastMode = '${e.mode} @ ${(e.confidence * 100).round()}%';
      });
      locSub = Tracelet.onLocation((loc) {
        final key = '${loc.activity.type.name}/${loc.activity.confidence.name}';
        seen[key] = (seen[key] ?? 0) + 1;
      });

      await Tracelet.start();

      // Sample one-shot fixes for ~30 s — each goes through the same
      // buildLocationMap that used to hardcode "unknown"/-1, so this works
      // even while the device sits still on a desk.
      const rounds = 6;
      for (var i = 1; i <= rounds; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final loc = await Tracelet.getCurrentPosition(timeout: 10);
        final key = '${loc.activity.type.name}/${loc.activity.confidence.name}';
        seen[key] = (seen[key] ?? 0) + 1;
        _set(
          'Sampling $i/$rounds...\n'
          'point activity: $key\n'
          'last onModeChange: $lastMode\n'
          'seen so far: $seen',
        );
      }

      final classified = Map.of(seen)
        ..removeWhere((k, _) => k.startsWith('unknown/'));
      if (classified.isNotEmpty) {
        _set(
          '✅ Per-point activity carries the classified mode: $seen\n'
          '(last onModeChange: $lastMode)\n'
          'Before #244 every iOS point was unknown/-1. Walk or drive and run '
          'again to see walking / in_vehicle with the fused confidence.',
        );
      } else {
        _set(
          '❌ All ${seen.values.fold(0, (a, b) => a + b)} sampled points came '
          'back unknown while onModeChange said "$lastMode" — the classified '
          'mode is not reaching the per-point activity (#244).\n'
          'Note: needs a real device (the classifier reads the accelerometer) '
          'and ~10 s for the first mode to commit.',
        );
      }
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      await modeSub?.cancel();
      await locSub?.cancel();
      await Tracelet.stop();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: 'PR #244: fused mode in per-point activity',
      description:
          'Enables fusedClassifierAuthoritative and samples locations for '
          "~30 s. Each point's activity.type must carry the classified mode "
          '(e.g. still, in_vehicle) with a real confidence — on iOS it was '
          'hardcoded unknown/-1, and vehicle/cycling now map to the AR '
          'vocabulary on both platforms. Run on a real device.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
