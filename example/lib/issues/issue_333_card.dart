import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #333 — `SmartMotionCoordinator` read the raw platform speed to decide
/// whether to overrule a *moving* accelerometer, and an unavailable reading
/// passed the "near zero" test.
///
/// The coordinator is a logical OR: continuous tracking is kept while either
/// the accelerometer or the GPS-speed machine reports motion. When the speed
/// machine says stationary but the accelerometer disagrees, one narrow override
/// applies — a device physically still with the accelerometer picking up hand
/// tremor, where GPS speed is genuinely ~0. It was gated on:
///
/// ```swift
/// let lastSpeed = sdk?.locationEngine.getLastLocation()?.speed ?? 0
/// if lastSpeed <= 0.15 { /* override the accelerometer to false */ }
/// ```
///
/// `CLLocation.speed` is **-1** on a fix carrying no speed, and -1 sails
/// through `<= 0.15`; Android's `Location.speed` reports 0.0 in the same
/// situation. So "we don't know how fast this is" was read as "definitely
/// parked", and the coordinator overruled the one input that was reporting
/// motion — on missing data. The declaration of `lastEffectiveSpeed` names this
/// hazard outright: "the cached CLLocation.speed may be stale, 0, or -1".
///
/// The fix reads `lastEffectiveSpeed` (the resolved value, which falls back to
/// a distance/time derivation exactly when the platform reading is absent) and
/// treats "no resolved speed at all" as unknown — unknown never overrules a
/// positive motion signal.
///
/// **What this card can prove.** The override needs the accelerometer and the
/// speed machine to actively disagree, which cannot be staged from Dart. What
/// is checkable here is the decision trail: every branch now records which one
/// it took, so the run reports whichever the device actually exercised and
/// fails only on the branch that is unambiguously wrong.
class Issue333Card extends StatefulWidget {
  const Issue333Card({super.key});

  @override
  State<Issue333Card> createState() => _Issue333CardState();
}

class _Issue333CardState extends State<Issue333Card> {
  static const _observeWindow = Duration(seconds: 20);

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
      await Tracelet.start();
      _set('Observing the coordinator for ${_observeWindow.inSeconds}s…');
      await Future<void>.delayed(_observeWindow);

      final logs = await Tracelet.getLogs(400);
      final messages = logs.map((e) => e.message).toList();

      // The three branches the override can take. Only the first is a bug.
      final overrode = messages
          .where((m) => m.contains('overriding accel to false'))
          .toList();
      final trustedOnUnknown = messages
          .where((m) => m.contains('no GPS speed resolved yet'))
          .toList();
      final trustedOnSpeed = messages
          .where((m) => m.contains('above the'))
          .where((m) => m.contains('tremor threshold'))
          .toList();

      // Row 1: the branch that must never appear again. The old build printed
      // "GPS speed near zero (-1.00 m/s)" — a negative reading is the sentinel
      // for "absent", never a measurement.
      final overrodeOnSentinel = overrode
          .where((m) => m.contains('(-'))
          .toList();
      check(
        '#333 an absent speed never counts as standing still',
        overrodeOnSentinel.isEmpty,
        overrodeOnSentinel.isEmpty
            ? 'no override was justified by a negative speed reading'
            : 'REGRESSED — overrode a moving accelerometer on a sentinel '
                  'value: ${overrodeOnSentinel.first}',
      );

      // Row 2: the misleading log text. 11.26 m/s is 40 km/h; describing it as
      // walking made the field report actively mislead whoever read it.
      final calledDrivingWalking = messages
          .where((m) => m.contains('suggests walking'))
          .toList();
      check(
        'the decision log states what it actually concluded',
        calledDrivingWalking.isEmpty,
        calledDrivingWalking.isEmpty
            ? 'the "suggests walking" text is gone; the branch now names the '
                  'threshold it compared against'
            : 'REGRESSED — still describing any speed above the threshold as '
                  'walking: ${calledDrivingWalking.first}',
      );

      // Row 3: context, not a verdict. Which branch ran depends entirely on
      // what the device was doing, so it is reported rather than asserted.
      final branchSummary = <String>[
        if (trustedOnSpeed.isNotEmpty)
          'trusted the accelerometer on a real speed (${trustedOnSpeed.length}×)',
        if (trustedOnUnknown.isNotEmpty)
          'trusted the accelerometer with no resolved speed, the #333 fix (${trustedOnUnknown.length}×)',
        if (overrode.isNotEmpty)
          'overrode the accelerometer as hand tremor (${overrode.length}×)',
      ];
      results.add(
        branchSummary.isEmpty
            ? 'ℹ️ the override was never reached in this run — it needs the '
                  'speed machine to go stationary while the accelerometer '
                  'still reports motion, which a short foreground run rarely '
                  'produces. Rows above still hold: they assert the absence of '
                  'the two wrong outcomes.'
            : 'ℹ️ branches exercised: ${branchSummary.join('; ')}',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: no override was taken on missing data, and the '
                'decision log describes what it decided.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Note on the log level: these branch messages are `info`, so this card '
        'needs logLevel at info or below to see them. The lifecycle entries '
        'that survive a release build with default settings are the '
        '`smart-motion:` mode switches — see the #334 card.\n\n'
        'Why it mattered: the override collapses the coordinator OR to the '
        'speed machine alone at exactly the moment the two inputs disagree — '
        'the moment the OR exists to arbitrate. Together with #332 this was a '
        'second path to "tracking went stationary while I was moving".',
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
          'smart motion coordinator accel accelerometer override hand tremor '
          'gps speed invalid -1 unavailable walking threshold effective speed '
          '333',
      title:
          '#333: an unknown GPS speed no longer overrules a moving '
          'accelerometer',
      description:
          'Checks the coordinator decision trail for the two outcomes that are '
          'unambiguously wrong: an override justified by a sentinel (absent) '
          'speed reading, and a log line calling 40 km/h "walking". Which '
          'branch actually runs depends on the device, so that is reported as '
          'context.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
