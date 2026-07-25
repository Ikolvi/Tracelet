import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #261 — `IosConfig.useSignificantChangesOnly` must not open a
/// `CLBackgroundActivitySession`.
///
/// On iOS 17+, significant-change monitoring is Apple's standard low-power
/// background-location API and should NOT keep a persistent location indicator
/// (Dynamic Island / status-bar pill) on screen while idle. `LocationEngine`
/// already honors [IosConfig.useSignificantChangesOnly] by skipping
/// `startUpdatingLocation()`. But `TraceletSdk.start()` still called
/// `backgroundActivitySessionManager.start()` whenever the engine was in the
/// moving state — and `CLBackgroundActivitySession` intentionally holds a
/// background location activity session alive and auto-shows the system
/// location indicator, even without continuous GPS. That defeated
/// significant-changes-only mode for the "no ongoing location UI" use case.
///
/// The fix mirrors the treatment already given to periodic mode and
/// low-accuracy geofence-only mode (see #210): when `useSignificantChangesOnly`
/// is enabled, `start()` (and the resume / `changePace(true)` path) must NOT
/// open a `CLBackgroundActivitySession`.
///
/// This test starts tracking with `useSignificantChangesOnly: true` while
/// forcing (and holding) the moving state — the exact condition under which
/// `start()` used to open the session. It clears the native log, calls
/// `start()`, then inspects the log: the SDK must NOT have logged
/// "CLBackgroundActivitySession started". On-device, background the app and
/// confirm the persistent location indicator does not stay on while idle.
class Issue261Card extends StatefulWidget {
  const Issue261Card({super.key});

  @override
  State<Issue261Card> createState() => _Issue261CardState();
}

class _Issue261CardState extends State<Issue261Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _test() async {
    setState(() => _running = true);
    try {
      if (!Platform.isIOS) {
        _set(
          'ℹ️ This check targets iOS 17+ (CLBackgroundActivitySession / the '
          'persistent location indicator). It is not applicable on this '
          'platform.',
        );
        return;
      }

      _set('Requesting permissions...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _set('❌ FAILED: location permission denied ($auth).');
        return;
      }

      _set('Starting tracking with useSignificantChangesOnly: true...');
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            distanceFilter: 250,
            desiredAccuracy: DesiredAccuracy.low,
          ),
          // Force and HOLD the moving state. start() only reaches the
          // backgroundActivitySessionManager.start() call when the engine is
          // moving; disableStopDetection keeps it there so the assertion is
          // deterministic (auto-detected "stationary" would take a different
          // path and mask the bug).
          motion: MotionConfig(isMoving: true, disableStopDetection: true),
          ios: IosConfig(
            useSignificantChangesOnly: true,
            disableLocationAuthorizationAlert: true,
          ),
          logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      // Clear the log so the assertion only sees this start() invocation.
      await Tracelet.destroyLog();

      final started = await Tracelet.start();
      if (!started.enabled) {
        _set('❌ FAILED: tracking did not start (enabled=false).');
        return;
      }

      // Belt-and-suspenders: ensure we are in the moving state so start()'s
      // moving branch (the one that used to open the session) is exercised.
      await Tracelet.changePace(true);

      // Let the native start() path run and flush its debug logs.
      await Future<void>.delayed(const Duration(seconds: 2));

      final logs = (await Tracelet.getLog()).toLowerCase();
      final state = await Tracelet.getState();

      await Tracelet.stop();

      // The manager logs "[Tracelet] CLBackgroundActivitySession started
      // (iOS 17+)" from BackgroundActivitySessionManager.start(). Its presence
      // means the persistent indicator would be held open — the #261 bug.
      final openedSession = logs.contains(
        'clbackgroundactivitysession started',
      );

      if (!state.enabled) {
        _set(
          '❌ FAILED: tracking was not enabled after start() — cannot verify '
          'the significant-changes path.',
        );
        return;
      }

      if (!openedSession) {
        _set(
          '✅ SUCCESS: with useSignificantChangesOnly: true and the device '
          'moving, start() did NOT open a CLBackgroundActivitySession, so iOS '
          'will not hold the persistent location indicator open. '
          'On-device: background the app and confirm the Dynamic Island / '
          'status-bar location pill does not stay on while idle (it may blink '
          'briefly when a significant-change event is delivered — that is '
          'normal).',
        );
      } else {
        _set(
          '❌ FAILED: start() opened a CLBackgroundActivitySession while '
          'useSignificantChangesOnly: true (found '
          '"CLBackgroundActivitySession started" in the native log). That '
          'keeps the persistent location indicator on and defeats '
          'significant-change monitoring — the #261 bug. It should be skipped '
          'for significant-changes-only mode, like periodic and low-accuracy '
          'geofence modes.',
        );
      }
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      try {
        await Tracelet.stop();
      } catch (_) {}
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'ios significant changes usesignificantchangesonly '
          'clbackgroundactivitysession location indicator dynamic island '
          'persistent background activity session',
      title:
          '#261: useSignificantChangesOnly must not open a background activity '
          'session',
      description:
          'Starts tracking with IosConfig.useSignificantChangesOnly: true while '
          'holding the moving state, clears the native log, then calls start() '
          'and inspects the log. Asserts the SDK did NOT open a '
          'CLBackgroundActivitySession (which would keep the persistent iOS '
          'location indicator on and defeat significant-change monitoring). '
          'iOS 17+ only; background the app to confirm no ongoing location pill.',
      status: _status,
      running: _running,
      onRun: _test,
    );
  }
}
