import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #253 — a failed foreground promotion still marked the Android service
/// as a running foreground service.
///
/// In `LocationService.startForegroundWithNotification()`, exceptions from
/// `startForeground()` were caught internally: the method logged, called
/// `stopForeground()` + `stopSelf()`, and set `isRunning = false`. Because the
/// exception was swallowed, execution returned normally to the caller — and
/// every caller (`onStartCommand()` and `updateNotificationVisibility()`) then
/// ran `isForegroundService = true` unconditionally. The service was therefore
/// stopping (or already stopped) while its internal state claimed it was a live
/// foreground service.
///
/// The fix makes `startForegroundWithNotification()` RETURN whether the
/// promotion succeeded, and every caller now assigns
/// `isForegroundService = startForegroundWithNotification()` — so a failed
/// promotion leaves the flag `false`, consistent with the torn-down service.
///
/// This bug is Android-only: iOS has no foreground-service promotion that can
/// fail after the fact. Its `BackgroundTaskHelper.begin()` already returns
/// `nil` when iOS denies the task and callers store that nil, so there is no
/// equivalent "marked active after a failed start" path.
///
/// The internal `isForegroundService` flag is not observable through the public
/// Dart API, so — like the #120 Rust-parity card — this test reaches through
/// the `com.tracelet/debug` channel and inspects the shipped native code:
/// `startForegroundWithNotification()` must compile to a `Boolean`-returning
/// method (the buggy build returned `Unit`/void, forcing the unconditional
/// `= true`). On iOS the handler reports the invariant as satisfied.
class Issue253Card extends StatefulWidget {
  const Issue253Card({super.key});

  @override
  State<Issue253Card> createState() => _Issue253CardState();
}

class _Issue253CardState extends State<Issue253Card>
    with IssueCardRun<Issue253Card> {
  static const _debug = MethodChannel('com.tracelet/debug');

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    if (running) return;
    setRunning(running: true);

    try {
      _set('Inspecting the native foreground-promotion guard...');
      final res = await _debug.invokeMapMethod<String, dynamic>(
        'debugForegroundPromotionGuard',
      );

      if (res == null) {
        _set('❌ ERROR: debug channel returned null.');
        return;
      }

      final gated = res['gated'] == true;
      final returnType = res['returnType'];

      if (Platform.isIOS) {
        _set(
          gated
              ? '✅ PASSED (iOS): not affected. iOS has no foreground-service '
                    'promotion that can fail after the fact — '
                    'BackgroundTaskHelper.begin() returns nil when denied and '
                    'callers store that nil, so no flag is ever left true on a '
                    'failed start.'
              : '❌ FAILED: iOS handler did not confirm the invariant.',
        );
        return;
      }

      if (gated) {
        _set(
          '✅ PASSED: startForegroundWithNotification() compiles to a '
          'Boolean-returning method (returnType="$returnType"). Callers gate '
          'isForegroundService on the result, so a failed promotion leaves it '
          'false instead of the old unconditional = true.',
        );
      } else {
        _set(
          '❌ FAILED: startForegroundWithNotification() returns '
          '"$returnType" (not Boolean) — the caller still sets '
          'isForegroundService = true unconditionally (#253 not fixed).',
        );
      }
    } on PlatformException catch (e) {
      _set('❌ ERROR: ${e.code} — ${e.message}');
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title:
          'Issue #253: failed foreground promotion still marks service active',
      description:
          'On Android a caught startForeground() failure tore the service down '
          'but the caller still set isForegroundService = true. The promotion '
          'now returns its success and callers gate the flag on it. This test '
          'inspects the shipped native code to confirm the guard is in place '
          '(Android); iOS is structurally unaffected.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
