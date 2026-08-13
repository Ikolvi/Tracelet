import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #257 — expose a public API to refresh the active foreground-service
/// notification (and its iOS Live Activity analogue).
///
/// Tracelet lets the Android foreground-service notification be configured
/// through [ForegroundServiceConfig] (title, text, icon, color, actions,
/// priority, ongoing state), and the iOS on-screen tracking indicator through
/// [LiveActivityConfig] (title, body). Before #257 there was no public API to
/// apply those changes to an already-running service/activity: a
/// notification-only `setConfig()` did not repost the live notification or
/// refresh the running Live Activity, so new content only appeared after an
/// unrelated restart or foreground transition.
///
/// [Tracelet.updateNotification] fills that gap on both platforms:
/// - Android: reposts the active foreground-service notification from the
///   latest [ForegroundServiceConfig] without restarting tracking. Safe no-op
///   when the service is not running.
/// - iOS: if the developer opted into a Live Activity via [LiveActivityConfig]
///   (and added the Widget Extension), refreshes the running activity's body
///   from the latest config. The title is immutable on a running activity.
///   Safe no-op when no Live Activity is configured or running.
/// - Web: no-op.
///
/// This test starts tracking with an initial notification / Live Activity,
/// applies a content-only `setConfig()` with new text, then calls
/// [Tracelet.updateNotification]. On Android, watch the notification shade; on
/// iOS with a Live Activity, watch the Dynamic Island / Lock Screen. The card
/// asserts the call completes without throwing and that tracking stays enabled
/// throughout (the refresh must never restart the pipeline).
class Issue257Card extends StatefulWidget {
  const Issue257Card({super.key});

  @override
  State<Issue257Card> createState() => _Issue257CardState();
}

class _Issue257CardState extends State<Issue257Card>
    with IssueCardRun<Issue257Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  /// Keeps tracking alive for [seconds] while updating the status once per
  /// second via [message] (given the remaining seconds), so the live
  /// notification / Live Activity stays on screen long enough to observe. The
  /// Live Activity in particular takes a moment to appear and refresh, so the
  /// test must not tear it down immediately.
  Future<void> _observe(
    int seconds,
    String Function(int remaining) message,
  ) async {
    for (var remaining = seconds; remaining > 0; remaining--) {
      _set(message(remaining));
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _test() async {
    setRunning(running: true);
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        _set(
          'ℹ️ updateNotification() is a no-op on this platform (no '
          'foreground-service notification). Verifying it completes safely...',
        );
        await Tracelet.updateNotification();
        _set(
          '✅ SUCCESS: updateNotification() completed without error (no-op).',
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

      final platformLabel = Platform.isIOS
          ? 'Live Activity'
          : 'foreground-service notification';

      _set('Starting tracking with initial $platformLabel...');
      await Tracelet.ready(
        const Config(
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              notificationTitle: 'Tracelet #257 — before',
              notificationText: 'Original notification content',
            ),
          ),
          ios: IosConfig(
            liveActivityConfig: LiveActivityConfig(
              title: 'Tracelet #257',
              body: 'Original activity content',
            ),
          ),
          // Force and hold the MOVING state for the duration of the test.
          //
          // On iOS the Live Activity is bound to the moving sub-state
          // (LocationEngine.start()/stop()): when the SDK auto-detects
          // "stationary" it calls stop(), which ENDS the Live Activity. Without
          // this, a stationary test device tears the activity down mid-test.
          // `isMoving: true` starts it moving (so the activity appears
          // immediately) and `disableStopDetection: true` keeps it up.
          //
          // The SAME motion config is passed to setConfig() below — motion keys
          // are restart-sensitive, so a mismatch would restart the pipeline
          // (stop() → end activity) instead of refreshing it in place.
          motion: MotionConfig(isMoving: true, disableStopDetection: true),
          logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      final started = await Tracelet.start();
      if (!started.enabled) {
        _set('❌ FAILED: tracking did not start (enabled=false).');
        return;
      }

      // Belt-and-suspenders: force moving so the Live Activity is present before
      // we try to refresh it (no-op on Android / when already moving).
      await Tracelet.changePace(true);

      // Give the OS time to actually present the notification / Live Activity
      // (ActivityKit registration is async and can take a second or two), and
      // hold on the ORIGINAL content long enough that the upcoming refresh is
      // visibly a change rather than the initial appearance.
      await _observe(
        6,
        (r) =>
            'Tracking started. The $platformLabel should now show the ORIGINAL '
            'content ("Original ${Platform.isIOS ? 'activity' : 'notification'} '
            'content").\nRefreshing it in ${r}s — watch it change...',
      );

      _set('Applying a content-only setConfig() (new text)...');
      await Tracelet.setConfig(
        // Only the notification / Live Activity content changes here. The motion
        // config MUST match ready() exactly — motion keys are restart-sensitive,
        // and any diff would restart the pipeline (which on iOS ends and
        // recreates the Live Activity) instead of leaving it running for
        // updateNotification() to refresh in place.
        const Config(
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              notificationTitle: 'Tracelet #257 — after',
              notificationText: 'Refreshed via updateNotification()',
            ),
          ),
          ios: IosConfig(
            liveActivityConfig: LiveActivityConfig(
              title: 'Tracelet #257',
              body: 'Refreshed via updateNotification()',
            ),
          ),
          motion: MotionConfig(isMoving: true, disableStopDetection: true),
        ),
      );

      // Let the setConfig() write settle before refreshing so updateNotification
      // reads the new config and (on iOS) re-presents the Live Activity with the
      // latest content if it isn't currently on screen.
      await Future<void>.delayed(const Duration(seconds: 1));

      _set(
        'Calling Tracelet.updateNotification() to refresh the live '
        '$platformLabel...',
      );
      await Tracelet.updateNotification();

      final state = await Tracelet.getState();
      if (!state.enabled) {
        _set(
          '❌ FAILED: tracking is no longer enabled after updateNotification() '
          '— the refresh must not restart or stop the pipeline.',
        );
        return;
      }

      final onDeviceNote = Platform.isIOS
          ? 'the Live Activity body should now read "Refreshed via '
                'updateNotification()" (Lock Screen / Dynamic Island). If it is '
                'unchanged, ensure a Live Activity Widget Extension is installed '
                '— without it the call is a safe no-op.'
          : 'the notification should now read "Tracelet #257 — after / '
                'Refreshed via updateNotification()".';

      // Keep tracking alive so the refreshed indicator stays on screen long
      // enough to visually confirm before we stop (which would tear it down).
      await _observe(
        10,
        (r) =>
            '✅ Refreshed — verify on-device: $onDeviceNote\n\n'
            'Tracking stays enabled (no pipeline restart). Stopping in ${r}s...',
      );

      _set(
        '✅ SUCCESS: updateNotification() refreshed the live $platformLabel and '
        'tracking stayed enabled throughout (no pipeline restart). '
        'On-device, $onDeviceNote',
      );
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      try {
        await Tracelet.stop();
      } catch (_) {}
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords: 'notification live activity refresh updatenotification',
      title: '#257: refresh the active foreground notification / Live Activity',
      description:
          'Starts tracking with an initial Android foreground-service '
          'notification (and iOS Live Activity), applies a content-only '
          'setConfig() with new text, then calls Tracelet.updateNotification() '
          'to refresh the live indicator without restarting tracking. Asserts '
          'the call completes and tracking stays enabled. Watch the '
          'notification shade (Android) or Dynamic Island / Lock Screen (iOS).',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
