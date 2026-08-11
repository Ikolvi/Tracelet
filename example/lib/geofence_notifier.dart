import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Posts a local notification for a geofence crossing.
///
/// This exists for one reason: a crossing that fires while the app is killed
/// has no UI to land in, so the notification *is* the observation. Verifying
/// terminated-state geofencing by reading the log store afterwards proves the
/// event was recorded, but not when — a notification timestamped at the moment
/// you crossed the boundary is the only evidence that the SDK woke and reported
/// while nothing of the app was running.
///
/// Deliberately usable from the headless isolate. That isolate is a fresh Dart
/// VM with none of `main()`'s state, so it must initialize the plugin itself —
/// [ensureInitialized] is idempotent and cheap for exactly that reason.
class GeofenceNotifier {
  GeofenceNotifier._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Android channel id. Distinct from the SDK's own foreground-service channel
  /// so silencing the ongoing "tracking active" notification does not also
  /// silence crossings.
  static const _channelId = 'tracelet_geofence_events';
  static const _channelName = 'Geofence crossings';

  /// Initializes the plugin if this isolate has not already done so.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await _plugin.initialize(
      const InitializationSettings(
        // @mipmap/ic_launcher is guaranteed to exist in any Flutter app
        // template, so the example needs no extra drawable to work.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestBadgePermission: false),
      ),
    );
  }

  /// Posts a crossing notification.
  ///
  /// [id] must differ per notification or the platform replaces the previous
  /// one — for this test that would hide an EXIT behind the ENTER that preceded
  /// it, which is precisely the pair being verified. The low 31 bits of the
  /// clock give a distinct id without tracking a counter across isolates.
  /// Returns whether the notification was actually posted. Callers in the
  /// headless isolate ignore it; the setup probe does not.
  static Future<bool> showCrossing({
    required String action,
    required String identifier,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await ensureInitialized();

      final icon = switch (action) {
        'ENTER' => '➡️',
        'EXIT' => '⬅️',
        'DWELL' => '⏱️',
        _ => '📍',
      };
      final where = (latitude != null && longitude != null)
          ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
          : 'location unavailable';

      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
        '$icon $action — $identifier',
        '${TimeOfDayText.now()} · $where',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Fires on geofence ENTER/EXIT, including while the app is '
                'terminated.',
            importance: Importance.high,
            priority: Priority.high,
            // Left at the defaults (ongoing: false, autoCancel: true): each
            // crossing is a discrete event the tester dismisses, unlike the
            // SDK's persistent tracking notification.
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (e) {
      // Never let a notification failure take down the headless isolate —
      // the crossing itself is still recorded in the SDK's log store.
      debugPrint('[GeofenceNotifier] failed to post $action: $e');
      return false;
    }
  }

  /// Posts a throwaway notification to prove the channel works.
  ///
  /// Without this, a terminated-state test has two indistinguishable failure
  /// modes: the crossing never fired, or notifications were never permitted on
  /// this device. The headless isolate cannot report the difference — it has no
  /// UI and no public log-write API to leave a trace in — so the check has to
  /// happen in the foreground, before the app is killed.
  static Future<bool> probe() => showCrossing(
    action: 'SETUP',
    identifier: 'notifications are working — dismiss me',
  );
}

/// Wall-clock stamp for the notification body.
///
/// The delivery time is not the crossing time — a killed app can be woken
/// seconds later — so the body carries when the event was handled, which is
/// what you compare against your walk.
extension TimeOfDayText on DateTime {
  static String now() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }
}
