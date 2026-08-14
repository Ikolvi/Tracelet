import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #385 — a session that *starts* stationary never acquired a first
/// location.
///
/// `motion.isMoving` defaults to false, so `start()` takes its stationary
/// branch. That branch runs no continuous stream on purpose (#319, "nothing
/// needs the continuous stream while the device is still"), and on this path
/// nothing else acquired either: in SMART mode the coordinator is synced to
/// STATIONARY_PERIODIC and *then* told both of its inputs are stationary, so it
/// reports no mode change and never arms the periodic worker. The one-shot that
/// did exist was fired from `changePace(true)` — a stationary → moving
/// *transition* that a session beginning stationary never takes.
///
/// The result was an app that called `start()` and got nothing at all until the
/// user physically walked away. `start()` acquired unconditionally until 3.2.0
/// replaced `locationEngine.start()` with the pace branch: the stream had been
/// doing double duty as the ongoing feed *and* the initial fix, and only the
/// first job was replaced.
///
/// The fix acquires one fix at `start()` and leaves the pace alone — the other
/// option, starting in the moving pace, buys the same first location with a
/// full-rate GPS stream nobody asked for.
///
/// **What this card proves.** Phase 1 starts a session at the default stationary
/// pace and waits, without moving, for a location. Phase 2 is the regression
/// half: the pace must still be stationary afterwards (the fix must not be a
/// disguised `isMoving: true`), and `changePace` must still take the device in
/// and out of moving.
///
/// **Keep the device still while this runs.** Real movement would produce a
/// location the honest way and make phase 1 pass on a broken build.
class Issue385Card extends StatefulWidget {
  const Issue385Card({super.key});

  @override
  State<Issue385Card> createState() => _Issue385CardState();
}

class _Issue385CardState extends State<Issue385Card>
    with IssueCardRun<Issue385Card> {
  /// How long a stationary session is given to produce its first location.
  /// Generous: a cold GPS start indoors is slow, and a false ❌ here would read
  /// as "the fix does not work" when it only means "no satellites yet".
  static const _firstFixWindow = Duration(seconds: 60);

  /// How long the moving pace is given to produce a further location in phase 2.
  static const _pacedFixWindow = Duration(seconds: 30);

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

    StreamSubscription<Location>? sub;
    final seen = <Location>[];
    final startedAt = DateTime.now();

    /// Waits until [count] locations have arrived, or [window] elapses.
    Future<void> waitForLocations(int count, Duration window) async {
      final deadline = DateTime.now().add(window);
      while (seen.length < count && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    try {
      await Tracelet.requestLocationAuthorization();

      // isMoving: false is the default, and passing it explicitly is the point
      // — ready() merges into the persisted config, so a card that ran earlier
      // and left isMoving: true behind would otherwise hand this run the moving
      // path and prove nothing. autoSync: false keeps the DB read below from
      // racing an upload that prunes the row.
      await Tracelet.ready(
        const Config(
          motion: MotionConfig(isMoving: false),
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );
      await Tracelet.destroyLocations();

      sub = Tracelet.onLocation(seen.add);

      // ---------------------------------------------------------------------
      // 1. The bug: a stationary start must still produce a location
      // ---------------------------------------------------------------------
      await Tracelet.start();

      final preState = await Tracelet.getState();
      check(
        'the session really did start stationary',
        preState.enabled && !preState.isMoving,
        'enabled=${preState.enabled} isMoving=${preState.isMoving} — if this '
            'says isMoving=true the run is meaningless: a moving start was '
            'never the broken case',
      );

      await waitForLocations(1, _firstFixWindow);
      final elapsed = DateTime.now().difference(startedAt).inSeconds;

      check(
        'a location arrives without moving the device',
        seen.isNotEmpty,
        seen.isNotEmpty
            ? 'first fix after ${elapsed}s at '
                  '${seen.first.coords.latitude.toStringAsFixed(5)}, '
                  '${seen.first.coords.longitude.toStringAsFixed(5)} '
                  '(event: ${seen.first.event}) — on a build without #385 this '
                  'window ends empty and stays empty'
            : 'nothing in ${_firstFixWindow.inSeconds}s. Either #385 is not in '
                  'this build, or the device has no fix to give — check that '
                  'location is enabled and try again near a window',
      );

      final rows = await Tracelet.getLocations();
      check(
        'the initial fix is an ordinary location record',
        rows.isNotEmpty,
        rows.isNotEmpty
            ? '${rows.length} row(s) in the DB — it went through the normal '
                  'pipeline (filters, odometer, persistMode, dispatch) rather '
                  'than being handed to the listener as a special case'
            : 'no rows persisted. Under the default persistMode the anchor '
                  'should be stored like any other fix',
      );

      // ---------------------------------------------------------------------
      // 2. The regression half: the pace itself must be untouched
      // ---------------------------------------------------------------------
      final afterFix = await Tracelet.getState();
      check(
        'the session is still stationary after the fix',
        !afterFix.isMoving,
        !afterFix.isMoving
            ? 'isMoving=false — the location was acquired without promoting the '
                  'session to the moving pace, which is the whole difference '
                  'between this fix and the isMoving:true workaround'
            : 'isMoving=true. The SDK started a full-rate stream instead of '
                  'taking one fix — that is the battery cost #385 set out to '
                  'avoid',
      );

      seen.clear();
      await Tracelet.changePace(true);
      final moving = await Tracelet.getState();
      check(
        'changePace(true) still moves the session to the moving pace',
        moving.isMoving,
        moving.isMoving
            ? 'isMoving=true — the transition path is unchanged'
            : 'changePace(true) did not take effect',
      );

      await waitForLocations(1, _pacedFixWindow);
      check(
        'the moving pace still delivers locations',
        seen.isNotEmpty,
        seen.isNotEmpty
            ? '${seen.length} location(s) after the transition — the immediate '
                  'fix (#54) and the continuous stream both still run'
            : 'no location in ${_pacedFixWindow.inSeconds}s while moving. This '
                  'is not #385 — the transition path is a separate mechanism, '
                  'and a stationary device indoors can legitimately be slow',
      );

      await Tracelet.changePace(false);
      final backToStationary = await Tracelet.getState();
      check(
        'changePace(false) still parks the session',
        !backToStationary.isMoving,
        !backToStationary.isMoving
            ? 'isMoving=false — pace control round-trips'
            : 'the session stayed moving after changePace(false)',
      );

      await Tracelet.stop();
      await Tracelet.destroyLocations();

      final header = allPass
          ? '✅ SUCCESS: a stationary start acquires its position, and the pace '
                'is left exactly where the app put it.'
          : '❌ FAILED — #385 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        "The fix fires one provider request from start()'s stationary branch "
        '(LocationEngine.requestStartupFix on both platforms) and routes it '
        'through the ordinary location pipeline, so it is filtered, '
        'odometer-counted, persisted under the configured persistMode and '
        'dispatched like any other fix. It is skipped when a stream is already '
        'running — a moving start, or the in-app-evaluated geofence branch '
        '(#357) — and skipped on resume, so the killed-state relaunch path is '
        'byte-for-byte what it was. On Android a passive desiredAccuracy is '
        'floored to balanced for this one request, since PRIORITY_PASSIVE only '
        'yields a fix while another app is actively requesting one and would '
        'reproduce the very silence being fixed.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await sub?.cancel();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'start stationary isMoving first location no location not capturing '
          'onLocation silent initial fix motion.isMoving default pace '
          'changePace stationary start dark session anchor 385',
      title: '#385: a stationary start never captured a first location',
      description:
          'Starts a session at the default stationary pace and waits, without '
          'moving, for a location — the fix must hand you the position you '
          'started at. Then checks the pace was left stationary and that '
          'changePace still round-trips, so the fix is not a disguised '
          'isMoving:true. Keep the device still while this runs.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
