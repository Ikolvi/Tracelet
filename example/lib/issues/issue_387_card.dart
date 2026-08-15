import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #387 — `setOdometer()` moved the total but not the reference it is
/// measured from.
///
/// Distance is accumulated in the Rust `LocationProcessor`, which keeps its own
/// odometer anchor — deliberately separate from the tracking anchor, so a fix
/// too coarse to trust defers its distance instead of losing it. `setOdometer`
/// wrote the counter and nothing else, and nothing on any platform ever cleared
/// that anchor (`LocationProcessor.reset()` existed and had no callers outside
/// the core). The next accepted fix therefore added the whole span since the
/// previous one, so the value the caller had just set survived exactly one fix.
///
/// The everyday form is "reset to zero, then start tracking": the phantom leg
/// is however far the device was carried while it was not being tracked, booked
/// against the new trip. `setOdometer` now clears the odometer anchor on all
/// three platforms — and only that one, since dropping the tracking anchor
/// would waive the distance filter for the next fix and silently change which
/// locations get recorded.
///
/// **What this card proves.** It drives the odometer with real fixes rather
/// than asserting on a number it set itself: it records a leg, resets to zero,
/// and checks the next fix does not re-book the distance already travelled.
///
/// **Walk about 30 m between the prompts.** The card needs genuine movement —
/// a stationary run cannot tell a working reset from a device that simply never
/// moved, and says so rather than passing.
class Issue387Card extends StatefulWidget {
  const Issue387Card({super.key});

  @override
  State<Issue387Card> createState() => _Issue387CardState();
}

class _Issue387CardState extends State<Issue387Card>
    with IssueCardRun<Issue387Card> {
  /// How long each walking phase gives you to cover ground.
  static const _walkWindow = Duration(seconds: 25);

  /// Distance that counts as "you actually moved", in metres. Comfortably above
  /// GPS jitter, so a stationary phone cannot satisfy it by drifting.
  static const _minimumLeg = 15.0;

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
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          // Moving pace: this card is about distance, so it needs the
          // continuous stream rather than a stationary session's single anchor.
          motion: MotionConfig(isMoving: true),
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );
      await Tracelet.start();

      // ---------------------------------------------------------------------
      // 1. Record a real leg, so there is an anchor to be stale
      // ---------------------------------------------------------------------
      await Tracelet.setOdometer(0);
      _set(
        '📍 Phase 1 of 2 — walk about 30 m now (${_walkWindow.inSeconds}s)…',
      );
      await Future<void>.delayed(_walkWindow);

      final firstLeg = await Tracelet.getOdometer();
      check(
        'the odometer counts a leg you actually walked',
        firstLeg >= _minimumLeg,
        firstLeg >= _minimumLeg
            ? '${firstLeg.toStringAsFixed(1)} m recorded'
            : 'only ${firstLeg.toStringAsFixed(1)} m — this run cannot test a '
                  'reset, because there is no distance for a stale anchor to '
                  're-book. Re-run and walk further, outdoors if you can',
      );

      // ---------------------------------------------------------------------
      // 2. Reset, then stand still. Nothing may reappear.
      // ---------------------------------------------------------------------
      await Tracelet.setOdometer(0);
      final justAfterReset = await Tracelet.getOdometer();
      check(
        'setOdometer(0) reads back as zero',
        justAfterReset == 0,
        'getOdometer() returned ${justAfterReset.toStringAsFixed(1)} m — this '
            'much always passed, including on the broken build: the counter was '
            'never the problem',
      );

      _set('🧍 Phase 2 of 2 — stand still now (${_walkWindow.inSeconds}s)…');
      await Future<void>.delayed(_walkWindow);

      final afterStanding = await Tracelet.getOdometer();
      check(
        'the leg already walked is not re-booked after the reset',
        afterStanding < _minimumLeg,
        afterStanding < _minimumLeg
            ? '${afterStanding.toStringAsFixed(1)} m after standing still — the '
                  'reset held. On a build without #387 the next fix alone '
                  'restored roughly the ${firstLeg.toStringAsFixed(1)} m you had '
                  'just cleared'
            : '${afterStanding.toStringAsFixed(1)} m appeared without you '
                  'moving — the anchor survived the reset, which is #387',
      );

      // ---------------------------------------------------------------------
      // 3. The control: resetting must not stop the odometer working
      // ---------------------------------------------------------------------
      _set(
        '📍 Control — walk about 30 m once more (${_walkWindow.inSeconds}s)…',
      );
      await Future<void>.delayed(_walkWindow);

      final afterWalkingAgain = await Tracelet.getOdometer();
      check(
        'distance travelled after the reset is still counted',
        afterWalkingAgain > afterStanding + _minimumLeg,
        afterWalkingAgain > afterStanding + _minimumLeg
            ? '${afterWalkingAgain.toStringAsFixed(1)} m — the anchor was '
                  're-established rather than switched off, which is what makes '
                  'the zero above meaningful'
            : 'only ${afterWalkingAgain.toStringAsFixed(1)} m. If you did walk, '
                  'the reset may have disabled accumulation instead of '
                  're-anchoring it — the opposite failure, and just as wrong',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a reset odometer stays reset, and keeps counting from '
                'where you reset it.'
          : '❌ FAILED — #387 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        "setOdometer() now clears the processor's odometer anchor through a new "
        'LocationProcessor.resetOdometerAnchor(), so the next accepted fix has '
        'nothing to measure from — exactly like the first fix of a session. Only '
        'that anchor is cleared: the tracking anchor decides whether the next fix '
        'clears the distance filter, so a full reset() would have changed which '
        'locations are recorded as a side effect of setting a counter. Android, '
        'iOS and web all had the defect independently and are all fixed.',
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
          'setOdometer odometer reset anchor distance phantom leg getOdometer '
          'trip distance wrong jumps untracked travel between sessions 387',
      title: '#387: a reset odometer re-booked the distance you just cleared',
      description:
          'Walks a leg, resets the odometer to zero, then stands still — the '
          'cleared distance must not come back on the next fix. Ends with a '
          'control leg proving the reset re-anchored rather than switched '
          'counting off. Walk about 30 m when prompted; a stationary run '
          'reports that it proved nothing.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
