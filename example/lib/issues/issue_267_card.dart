import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #267 — expose [Tracelet.requestTermination] on the headless
/// `com.tracelet/methods` MethodChannel so a killed-app background isolate can
/// shut the GPS foreground service down.
///
/// When an FCM silent push triggers a background task (e.g. an auto-punchout)
/// while the app is terminated, the background handler cannot call
/// [Tracelet.stop] because `stop()` is routed through Pigeon, and Pigeon is not
/// wired up in a headless Dart isolate. The GPS foreground service therefore
/// keeps polling and draining the battery until the user manually re-opens the
/// app.
///
/// [Tracelet.requestTermination] fixes this: it invokes `requestTermination` on
/// the `com.tracelet/methods` MethodChannel directly (the same channel used by
/// `setDynamicHeaders` / `setSyncBodyResponse`), which IS available in headless
/// isolates. On Android the native handler in `HeadlessTaskService` calls
/// `TraceletSdk.getInstance(context).stop()`, tearing down the foreground
/// service. It returns whether the native service acknowledged the request; no
/// [State] is returned because Pigeon is unavailable in that isolate.
///
/// IMPORTANT — where it works:
/// - From a HEADLESS isolate (FCM background handler while the app is killed),
///   the `com.tracelet/methods` handler is registered on the headless
///   FlutterEngine, so `requestTermination()` returns `true` and the GPS
///   service stops.
/// - From the FOREGROUND app (this card runs in the foreground), that handler
///   is NOT registered on the main engine, so the call throws
///   `MissingPluginException` internally and gracefully returns `false`. This
///   is the same graceful path iOS takes (its headless architecture differs and
///   is out of scope). The value here is confirming the fallback never crashes.
/// - Android only.
///
/// This card verifies the graceful fallback: it calls `requestTermination()`
/// and asserts it completes without throwing and returns a bool. To exercise
/// the real termination path, tap "Arm headless repro" to start a GPS
/// foreground service, then (from your own FCM silent-push background handler,
/// with the app killed) call `Tracelet.requestTermination()` and confirm the
/// service stops.
class Issue267Card extends StatefulWidget {
  const Issue267Card({super.key});

  @override
  State<Issue267Card> createState() => _Issue267CardState();
}

class _Issue267CardState extends State<Issue267Card>
    with IssueCardRun<Issue267Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    setRunning(running: true);
    try {
      if (!Platform.isAndroid) {
        _set(
          'ℹ️ #267 is Android-only. requestTermination() targets the Android '
          'headless MethodChannel path. On this platform it gracefully returns '
          'false. Verifying it completes without throwing...',
        );
        final result = await Tracelet.requestTermination();
        _set(
          result == false
              ? '✅ SUCCESS: requestTermination() returned false without '
                    'throwing (graceful non-Android fallback).'
              : '❌ FAILED: expected false on this platform but got $result.',
        );
        return;
      }

      _set('Requesting location permission...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _set('❌ FAILED: location permission denied ($auth).');
        return;
      }

      _set('Starting tracking so a GPS foreground service is running...');
      await Tracelet.ready(
        const Config(
          motion: MotionConfig(isMoving: true, disableStopDetection: true),
        ),
      );
      final started = await Tracelet.start();
      if (!started.enabled) {
        _set('❌ FAILED: tracking did not start (enabled=false).');
        return;
      }

      _set(
        'Calling Tracelet.requestTermination() from the FOREGROUND isolate...',
      );
      final ack = await Tracelet.requestTermination();

      // From the foreground, the com.tracelet/methods requestTermination
      // handler is not registered on the main engine, so this returns false
      // via the internal MissingPluginException catch. That IS the expected
      // graceful behaviour — the point of the assertion is "no crash".
      _set(
        '✅ SUCCESS: requestTermination() completed without throwing and '
        'returned $ack.\n\n'
        'From the FOREGROUND, false is expected: the requestTermination '
        'handler lives on the HEADLESS FlutterEngine, so the main engine has '
        'no handler and the call falls back gracefully (no crash).\n\n'
        'To see it return TRUE and actually stop the GPS service:\n'
        '1. Keep a tracking session running (this card started one).\n'
        '2. Kill the app from recents.\n'
        '3. Trigger an FCM silent push that runs your background handler.\n'
        '4. In that headless handler call Tracelet.requestTermination() — the '
        'native service acknowledges and TraceletSdk.stop() tears down the '
        'foreground service, so GPS stops draining the battery.',
      );
    } catch (e) {
      _set(
        '❌ FAILED: requestTermination() threw instead of returning gracefully: '
        '$e',
      );
    } finally {
      // The foreground call is a no-op on the running service (handler is
      // headless-only), so stop tracking explicitly for cleanup.
      try {
        await Tracelet.stop();
      } catch (_) {}
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'android headless requesttermination termination fcm silent push '
          'background isolate methodchannel com.tracelet/methods stop '
          'foreground service gps battery pigeon auto punchout killed app',
      title:
          '#267: expose requestTermination() on the headless MethodChannel '
          '(Android)',
      description:
          'Adds Tracelet.requestTermination() so a killed-app background '
          'isolate (e.g. an FCM silent-push handler) can stop the GPS '
          'foreground service — Tracelet.stop() cannot, because it uses Pigeon '
          'which is unavailable in headless isolates. This card starts a '
          'tracking session, then calls requestTermination() from the '
          'foreground and asserts it returns a bool without crashing (false is '
          'expected in the foreground; the handler is registered only on the '
          'headless engine). Trigger it from a real FCM background handler '
          'while the app is killed to see the GPS service stop. Android-only.',
      runLabel: 'Arm headless repro',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
