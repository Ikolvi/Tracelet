import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #257 — expose a public API to refresh the active foreground-service
/// notification.
///
/// Tracelet lets the foreground-service notification be configured through
/// [ForegroundServiceConfig] (title, text, icon, color, actions, priority,
/// ongoing state). Before #257 there was no public API to apply those changes
/// to an already-running Android foreground service: a notification-only
/// `setConfig()` did not repost the live notification, so the new content only
/// appeared after an unrelated service restart or foreground transition.
///
/// [Tracelet.updateNotification] fills that gap. It reposts the active
/// foreground-service notification from the latest configuration without
/// restarting the tracking pipeline. It is a safe no-op when the service is
/// not running, and a no-op on platforms without a foreground-service
/// notification (iOS, web).
///
/// This test starts persistent foreground-service tracking with an initial
/// notification, applies a notification-only `setConfig()` with a new title and
/// text, then calls [Tracelet.updateNotification]. On Android, watch the
/// notification shade: the notification content should change to the new title
/// and text without tracking restarting. The card asserts the call completes
/// without throwing and that tracking stays enabled throughout.
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
      if (!Platform.isAndroid) {
        _set(
          'ℹ️ updateNotification() is a no-op on this platform — iOS/web have '
          'no foreground-service notification. Verifying it completes safely...',
        );
        await Tracelet.updateNotification();
        _set(
          '✅ SUCCESS: updateNotification() completed without error (no-op on '
          'non-Android platforms).',
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

      _set('Starting tracking with initial foreground notification...');
      await Tracelet.ready(
        const Config(
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              notificationTitle: 'Tracelet #257 — before',
              notificationText: 'Original notification content',
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
        'Applying a notification-only setConfig() (new title + text)...\n'
        'Watch the notification shade — it should still show the OLD content '
        'until updateNotification() is called.',
      );
      await Tracelet.setConfig(
        const Config(
          android: AndroidConfig(
            foregroundService: ForegroundServiceConfig(
              notificationTitle: 'Tracelet #257 — after',
              notificationText: 'Refreshed via updateNotification()',
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 2));

      _set(
        'Calling Tracelet.updateNotification() to refresh the live '
        'notification...',
      );
      await Tracelet.updateNotification();
      await Future<void>.delayed(const Duration(seconds: 1));

      final state = await Tracelet.getState();
      if (!state.enabled) {
        _set(
          '❌ FAILED: tracking is no longer enabled after updateNotification() '
          '— the notification refresh must not restart or stop the pipeline.',
        );
        return;
      }

      _set(
        '✅ SUCCESS: updateNotification() reposted the foreground-service '
        'notification with the new configuration and tracking stayed enabled '
        '(no pipeline restart). Confirm on-device that the notification now '
        'reads "Tracelet #257 — after".',
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
      title: '#257: refresh the active foreground-service notification',
      description:
          'Starts persistent foreground-service tracking, applies a '
          'notification-only setConfig() (new title + text), then calls '
          'Tracelet.updateNotification() to repost the live notification '
          'without restarting tracking. Asserts the call completes and tracking '
          'stays enabled. On Android, watch the notification content change.',
      status: _status,
      running: _running,
      onRun: _test,
    );
  }
}
