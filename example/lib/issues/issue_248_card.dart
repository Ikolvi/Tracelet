import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #248 — `insertLocation failed: UNIQUE constraint failed:
/// location_events.uuid` recurring on a fixed ~2-minute interval while
/// tracking sits idle in stationary periodic mode (including after a
/// boot-triggered auto-resume with the host app never launched).
///
/// Root cause: the stationary periodic timer in the native LocationService
/// requested each tick's fix via `getCurrentPosition()` without disabling
/// engine-side persistence. The engine persisted the enriched location map
/// first, then handed the *same map* (same uuid) to the timer's callback,
/// which inserted it again — so every tick's second insert failed with the
/// UNIQUE constraint error. The ~2-minute cadence is simply the default
/// `stationaryPeriodicInterval` (120 s). Side effects: the stored record
/// carried event `getCurrentPosition` instead of `periodic` and a stale
/// odometer. The timer now requests fixes with `persist: false` and remains
/// the single writer of the enriched `periodic` record.
///
/// This test forces stationary periodic mode with a short interval, waits
/// two ticks, and asserts the ticks landed in the DB as `periodic` events
/// (not `getCurrentPosition`). Watch `adb logcat` during the run: no
/// `insertLocation failed: ... UNIQUE constraint failed` lines may appear.
class Issue248Card extends StatefulWidget {
  const Issue248Card({super.key});

  @override
  State<Issue248Card> createState() => _Issue248CardState();
}

class _Issue248CardState extends State<Issue248Card> {
  String _status = 'Idle';
  bool _running = false;

  static const int _intervalSeconds = 30;
  static const int _waitSeconds = 75; // two ticks + margin

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _test() async {
    if (_running) return;
    setState(() => _running = true);

    try {
      if (!Platform.isAndroid) {
        _set('N/A: this is an Android stationary-periodic-timer issue.');
        return;
      }

      _set('Stopping any existing tracking...');
      await Tracelet.stop();
      final testStart = DateTime.now().toUtc();

      _set(
        'Configuring speed mode with a ${_intervalSeconds}s stationary '
        'periodic interval...',
      );
      await Tracelet.ready(
        Config.balanced().copyWith(
          motion: const MotionConfig(
            motionDetectionMode: MotionDetectionMode.speed,
            stationaryPeriodicInterval: _intervalSeconds,
          ),
        ),
      );

      await Tracelet.start();

      // Force the stationary periodic timer — the reporter's idle-with-
      // tracking-armed state — instead of waiting for speed detection.
      _set('Forcing stationary periodic mode via changePace(false)...');
      await Tracelet.changePace(false);

      for (var remaining = _waitSeconds; remaining > 0; remaining -= 5) {
        _set(
          'Stationary periodic timer armed — waiting ${remaining}s for '
          'two ticks (watch logcat for "insertLocation failed")...',
        );
        await Future<void>.delayed(const Duration(seconds: 5));
      }

      _set('Reading captured records from the database...');
      final locations = await Tracelet.getLocations();
      final captured = locations.where((l) {
        final ts = DateTime.tryParse(l.timestamp);
        return ts != null && !ts.isBefore(testStart);
      }).toList();
      final periodicCount = captured.where((l) => l.event == 'periodic').length;
      final onePositionCount = captured
          .where((l) => l.event == 'getCurrentPosition')
          .length;

      await Tracelet.stop();

      if (periodicCount >= 2 && onePositionCount == 0) {
        _set(
          '✅ $periodicCount stationary ticks persisted as "periodic" events '
          'and none as "getCurrentPosition" (the buggy engine-side insert '
          'that used to win the uuid). Confirm logcat shows no '
          '"insertLocation failed: ... UNIQUE constraint failed: '
          'location_events.uuid" lines during the wait window.',
        );
      } else if (periodicCount < 2) {
        _set(
          '❌ FAILED: only $periodicCount "periodic" record(s) were stored '
          'in ${_waitSeconds}s (expected 2). Either the timer did not run '
          'or its inserts are still failing — check logcat for '
          '"insertLocation failed: ... UNIQUE constraint failed".',
        );
      } else {
        _set(
          '❌ FAILED: $onePositionCount record(s) stored with event '
          '"getCurrentPosition" — the engine-side duplicate insert is back, '
          'which also means every tick logs the UNIQUE constraint error.',
        );
      }
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: 'Issue #248: UNIQUE constraint failed every stationary tick',
      description:
          'Arms the stationary periodic timer (the state a tracking session '
          'idles in — also entered by the boot auto-resume with the app never '
          'opened) with a ${_intervalSeconds}s interval and waits two ticks. '
          'Each tick used to insert its location twice with the same uuid: '
          'once inside getCurrentPosition(), once from the timer — so the '
          'second insert failed with "UNIQUE constraint failed: '
          'location_events.uuid" every ~120s (the default interval). Verifies '
          'ticks now persist exactly once, as "periodic" events.',
      status: _status,
      running: _running,
      onRun: _test,
    );
  }
}
