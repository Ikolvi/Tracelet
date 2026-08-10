import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #344 — in SMART motion mode, a `start()` whose committed pace was
/// stationary left the coordinator permanently deaf to motion.
///
/// `syncCurrentMode()` mapped the *session* mode onto the coordinator's
/// *posture*, and those are not the same thing:
///
/// * `stateManager.trackingMode` says **which start API was called**. `start()`
///   pins it to `.continuous` for the whole session — the stationary switch
///   deliberately leaves it alone and records the pace in `isMoving`.
/// * The core coordinator's `currentMode` says **what the engine is doing right
///   now**: continuous GPS, or parked in a stationary schedule.
///
/// ```swift
/// case .continuous:
///     mode = .continuous          // regardless of the committed pace
/// ```
///
/// `start()` sets `isMoving` from `motion.isMoving` (false by default) and then
/// syncs, so this wrote `Continuous` into a coordinator whose accelerometer and
/// speed inputs both said stationary. The core emits no action for that pair in
/// either direction:
///
/// ```rust
/// let should_be_moving = state.is_accel_moving || state.is_speed_moving;
/// if should_be_moving && state.current_mode != TrackingMode::Continuous { .. }
/// else if !should_be_moving && state.current_mode == TrackingMode::Continuous { .. }
/// else { CoordinatorAction::None }     // <- lands here, forever
/// ```
///
/// A shake set `should_be_moving`, but `currentMode` was *already* `Continuous`,
/// so the wake-up returned `None`, `switchToContinuousForce()` never ran, and
/// `isMoving` never became true. The field report that opened this issue shows
/// ~130 consecutive `onAccelStateChange -> isMoving=true, action=none` while the
/// user shook the phone: no fixes recorded, and therefore nothing to sync.
///
/// The usual escape hatches were both closed. `startSpeedMotionManager()` re-
/// asserts a restored-stationary speed machine, but the coordinator lives for
/// the whole process and the core dedupes an unchanged flag, so the previous
/// session had already left it false. And `reconcileTrackingMode()` (#319)
/// treats `isMoving` as the authority, so a false `isMoving` matched the parked
/// engine and looked perfectly consistent.
///
/// **What this card can prove.** Dart cannot inject accelerometer samples, but
/// it does not have to: `changePace(true)` enters the coordinator through the
/// same `onAccelStateChange` / `onSpeedStateChange` inputs the shake used, and
/// on the broken build it is swallowed identically. The card reproduces the
/// exact precondition — a session that settled stationary, stopped, and started
/// again **in the same process** — and then checks the wake-up actually lands.
///
/// **What it does not prove.** That a *physical* shake reaches the coordinator;
/// that is `MotionDetector`'s job and is unchanged here. The mapping itself is
/// pinned by `SmartMotionCoordinatorSyncModeTests` (iOS) and
/// `SmartMotionCoordinatorStationaryStartTest` (Android), both of which drive
/// the real core through the same sequence.
class Issue344Card extends StatefulWidget {
  const Issue344Card({super.key});

  @override
  State<Issue344Card> createState() => _Issue344CardState();
}

class _Issue344CardState extends State<Issue344Card> {
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

    StreamSubscription<Location>? sub;

    try {
      // SMART is the mode the coordinator arbitrates; isMoving:false is the
      // default and the value that triggered the bug.
      await Tracelet.setConfig(
        const Config(
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            isMoving: false,
          ),
        ),
      );

      final motionEvents = <bool>[];
      sub = Tracelet.onMotionChange((loc) => motionEvents.add(loc.isMoving));

      // --- Session 1: settle stationary, then stop. -----------------------
      // This is what the field report had: a session that ended with both
      // coordinator inputs reading stationary. The coordinator outlives stop(),
      // so session 2 inherits those flags — which is precisely why session 2's
      // own "re-assert stationary" call dedupes to a no-op and cannot repair
      // the posture.
      await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 2));
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(seconds: 2));
      await Tracelet.stop();
      await Future<void>.delayed(const Duration(seconds: 1));

      // --- Session 2: the start whose committed pace is stationary. -------
      final started = await Tracelet.start();
      await Future<void>.delayed(const Duration(seconds: 2));

      check(
        'the fresh session starts stationary',
        !started.isMoving,
        !started.isMoving
            ? 'isMoving=false after start(), as motion.isMoving:false asks for '
                  '— this is the state that used to wedge the coordinator'
            : 'isMoving=true after start(), so the precondition for #344 was '
                  'never set up. Nothing below is conclusive; check that '
                  'motion.isMoving:false actually reached the platform.',
      );

      motionEvents.clear();

      // --- The wake-up. ---------------------------------------------------
      // changePace(true) drives onAccelStateChange(true) + onSpeedStateChange(true)
      // — the same two coordinator inputs a real shake and a real GPS fix use.
      // Broken build: both return NONE because currentMode already said
      // Continuous, and isMoving stays false. Fixed build: the posture is
      // stationary, so the first input produces SWITCH_TO_CONTINUOUS.
      await Tracelet.changePace(true);
      await Future<void>.delayed(const Duration(seconds: 3));

      final afterWake = await Tracelet.getState();

      check(
        '#344 motion wakes a session that started stationary',
        afterWake.isMoving,
        afterWake.isMoving
            ? 'changePace(true) moved the session to isMoving=true — the '
                  'coordinator saw a stationary posture and emitted the switch '
                  'to continuous'
            : 'REGRESSED — isMoving is still false after changePace(true). The '
                  'coordinator swallowed the wake-up, exactly as it did for '
                  '~130 consecutive accelerometer events in the report that '
                  'opened #344. No fixes will be recorded and nothing will '
                  'sync for the rest of this process.',
      );

      final wakeEvents = motionEvents.where((m) => m).length;
      check(
        'the wake-up is reported to the app',
        wakeEvents >= 1,
        wakeEvents >= 1
            ? 'motionchange fired with isMoving=true, so a host app relying on '
                  'the event (not polling getState) also sees the transition'
            : 'no motionchange with isMoving=true arrived. If the row above '
                  'passed, the state changed without telling the app; if it '
                  'failed, this is the same swallowed switch.',
      );

      // Leave the device in a defined state rather than pinned to moving.
      await Tracelet.changePace(false);
      await Future<void>.delayed(const Duration(seconds: 1));
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: a stationary start no longer deafens the coordinator.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Scope: changePace() enters the coordinator through the same '
        'onAccelStateChange/onSpeedStateChange inputs a physical shake and a '
        'GPS fix use, and the broken build swallowed all of them the same way, '
        'so this reproduces the defect without needing to shake the device. '
        'What it does not cover is MotionDetector delivering the shake in the '
        'first place — that path was never broken; the report shows it firing '
        'correctly at 2.02 g and 4.29 g while the coordinator discarded every '
        'one.\n\n'
        'The precondition matters: session 1 exists only to leave both '
        'coordinator inputs stationary. Running the wake-up on a first-ever '
        'start can pass even on a broken build, because the speed machine may '
        'still flip its flag and repair the posture on the way through.\n\n'
        'Both platforms had the identical mapping and both are fixed. The core '
        'state machine is driven through this exact sequence by '
        'SmartMotionCoordinatorSyncModeTests (iOS, newly wired into '
        'Package.swift — the older SmartMotionCoordinatorTests.swift was never '
        'listed in its sources allowlist and had never run) and '
        'SmartMotionCoordinatorStationaryStartTest (Android).',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await sub?.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'smart motion coordinator stationary start syncCurrentMode posture '
          'session mode isMoving accelerometer shake action none stuck '
          'not moving no sync ios android 344',
      title: '#344: a stationary start must not deafen SMART motion detection',
      description:
          'Settles a session stationary, stops, starts again in the same '
          'process, and checks that motion still wakes it. syncCurrentMode() '
          'used to write CONTINUOUS into the coordinator while both its inputs '
          'said stationary, and every wake-up after that returned none.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
