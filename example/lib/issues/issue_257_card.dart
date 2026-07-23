import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

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

class _Issue257CardState extends State<Issue257Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _test() async {
    setState(() => _running = true);
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
          logger: LoggerConfig(debug: true, logLevel: LogLevel.verbose),
        ),
      );

      final started = await Tracelet.start();
      if (!started.enabled) {
        _set('❌ FAILED: tracking did not start (enabled=false).');
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));

      _set(
        'Applying a content-only setConfig() (new text)...\n'
        'The live $platformLabel should still show the OLD content until '
        'updateNotification() is called.',
      );
      await Tracelet.setConfig(
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
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 2));

      _set(
        'Calling Tracelet.updateNotification() to refresh the live '
        '$platformLabel...',
      );
      await Tracelet.updateNotification();
      await Future<void>.delayed(const Duration(seconds: 1));

      final state = await Tracelet.getState();
      if (!state.enabled) {
        _set(
          '❌ FAILED: tracking is no longer enabled after updateNotification() '
          '— the refresh must not restart or stop the pipeline.',
        );
        return;
      }

      final onDeviceNote = Platform.isIOS
          ? 'If a Live Activity Widget Extension is installed, confirm the '
                'activity body now reads "Refreshed via updateNotification()". '
                'Without the extension the call is a safe no-op.'
          : 'Confirm on-device that the notification now reads '
                '"Tracelet #257 — after".';

      _set(
        '✅ SUCCESS: updateNotification() completed and tracking stayed enabled '
        '(no pipeline restart). $onDeviceNote',
      );
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
      title: '#257: refresh the active foreground notification / Live Activity',
      description:
          'Starts tracking with an initial Android foreground-service '
          'notification (and iOS Live Activity), applies a content-only '
          'setConfig() with new text, then calls Tracelet.updateNotification() '
          'to refresh the live indicator without restarting tracking. Asserts '
          'the call completes and tracking stays enabled. Watch the '
          'notification shade (Android) or Dynamic Island / Lock Screen (iOS).',
      status: _status,
      running: _running,
      onRun: _test,
    );
  }
}
