import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/geofence_notifier.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #356 — a geofence smaller than the OS can resolve must still fire
/// ENTER/EXIT, including while the app is terminated.
///
/// Play Services and CoreLocation both need a radius of roughly 100 m: below
/// that the fence is smaller than the error of the fixes it is compared
/// against, so neither ever becomes confident enough to report a crossing
/// (#355). The failure is deceptive rather than obvious — registering while
/// inside fires an immediate ENTER from the initial trigger, so the fence looks
/// live, and then nothing is ever reported again.
///
/// Such a fence is now owned by the in-app evaluator: decided at its *true*
/// radius, with the OS region registered at 100 m purely as a wake-up and the
/// OS's own transitions for it discarded, since at the inflated radius they
/// describe the wrong boundary. The exit-hysteresis band tracks the measured
/// fix accuracy (clamped 3–20 m) instead of a flat 20 m, so a 10 m fence on a
/// 4 m-accurate handset needs ~8 m of travel to EXIT rather than ~28 m.
///
/// **This card sets up a manual test rather than asserting one.** The behaviour
/// under test only exists once the app's process is gone, and no in-process
/// Dart assertion can observe that: if the app is alive to run the check, the
/// terminated path was never taken (the same limitation #316 and #353 hit). So
/// this card creates the fence, verifies the preconditions that must hold
/// *before* you walk, and then hands over to you.
///
/// The observable signal is a **local notification** posted from the headless
/// isolate. A crossing that fires while the app is killed has no UI to land in,
/// so reading the log store afterwards proves the event was recorded but not
/// *when* — a notification timestamped as you cross is the only real-time
/// evidence the SDK woke and reported with nothing of the app running.
class Issue356Card extends StatefulWidget {
  const Issue356Card({super.key});

  @override
  State<Issue356Card> createState() => _Issue356CardState();
}

class _Issue356CardState extends State<Issue356Card> {
  String _status = 'Idle';
  bool _running = false;

  static const _fenceId = 'issue-356-tiny';
  static const _radiusMeters = 10.0;

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

    try {
      await Tracelet.requestLocationAuthorization();
      // The crossing arrives as a notification while the app is dead, so the
      // permission has to be granted now, not discovered missing afterwards.
      await GeofenceNotifier.ensureInitialized();
      final notificationsWork = await GeofenceNotifier.probe();
      await Tracelet.removeGeofences();

      // stopOnTerminate: false and startOnBoot: true are the session shape the
      // terminated-state test needs — without them the SDK is *meant* to stop
      // when the task is removed and a missing crossing would prove nothing.
      await Tracelet.ready(
        const Config(
          app: AppConfig(stopOnTerminate: false, startOnBoot: true),
          // A sub-100 m fence is evaluated in-app, which needs the location
          // stream running. Continuous tracking (the default mode) provides it.
          logger: LoggerConfig(logLevel: LogLevel.verbose, debug: true),
        ),
      );
      await Tracelet.start();

      final here = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        timeout: 30,
      );
      final lat = here.coords.latitude;
      final lng = here.coords.longitude;
      final accuracy = here.coords.accuracy;

      await Tracelet.addGeofence(
        Geofence(
          identifier: _fenceId,
          latitude: lat,
          longitude: lng,
          radius: _radiusMeters,
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));

      final fences = await Tracelet.getGeofences();
      final created = fences.where((g) => g.identifier == _fenceId).toList();
      check(
        'a 10 m geofence is created at your current position',
        created.isNotEmpty && created.first.radius == _radiusMeters,
        created.isEmpty
            ? 'not found in getGeofences()'
            : 'r=${created.first.radius.toStringAsFixed(0)}m at '
                  '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      );

      // Checked before you walk, on purpose: once the app is killed the
      // headless isolate has no UI and no log-write API, so a notification
      // that fails there is indistinguishable from a crossing that never
      // fired. Prove the channel now and that ambiguity is gone.
      check(
        'notifications reach you (a "📍 SETUP" one just posted)',
        notificationsWork,
        notificationsWork
            ? 'if you did not see it, grant notification permission — '
                  'otherwise the killed-app test cannot report anything'
            : 'posting failed — the terminated-state test will look like a '
                  'geofence failure when it is a notification failure',
      );

      final state = await Tracelet.getState();
      check(
        'tracking is running so the evaluator gets fixes',
        state.enabled,
        'enabled=${state.enabled} trackingMode=${state.trackingMode} — a fence '
            'the OS cannot resolve is evaluated in-app, which needs the '
            'location stream',
      );

      // The fix that makes this fence decidable is the accuracy-scaled band,
      // so the accuracy you actually have decides how far you must walk.
      final band = accuracy <= 0 ? 20.0 : accuracy.clamp(3.0, 20.0);
      final exitDistance =
          _radiusMeters +
          (_radiusMeters * 0.1 > band ? _radiusMeters * 0.1 : band);
      check(
        'your fix accuracy makes the fence decidable',
        accuracy > 0 && accuracy <= 20,
        accuracy <= 0
            ? 'the platform reported no accuracy — the band falls back to '
                  '20 m, so EXIT needs ~30 m of travel'
            : '±${accuracy.toStringAsFixed(1)}m → hysteresis band '
                  '${band.toStringAsFixed(1)}m → EXIT at roughly '
                  '${exitDistance.toStringAsFixed(0)}m from the centre',
      );

      final header = allPass
          ? '✅ READY: 10 m fence created at your position. Now run the manual '
                'terminated-state test below.'
          : '❌ SETUP FAILED — fix the failing rows before testing.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Why this cannot be asserted here: the behaviour only exists once the '
        "app's process is gone. If the app is alive to run a check, the "
        'terminated path was never taken.\n\n'
        'Manual test:\n'
        '1. Stay where you are. You should already have had an ENTER — that '
        'one is the initial trigger, not a detection, so it does not count.\n'
        '2. Swipe the app away from recents (Android) / kill it from the app '
        'switcher (iOS). Do NOT stop tracking first.\n'
        '3. Walk ~${exitDistance.toStringAsFixed(0)}m away and then STAND '
        'STILL THERE FOR 30 SECONDS. EXIT needs two consecutive fixes beyond '
        'the band (the anti-flap rule from #355), and fixes arrive 8-13s '
        'apart — walking out and straight back gives only one, so no EXIT '
        'fires and the run looks like a failure when it is working correctly. '
        'A notification "⬅️ EXIT — $_fenceId" should arrive with the app still '
        'dead.\n'
        '4. Walk back to where you started and again wait ~30s. '
        '"➡️ ENTER — $_fenceId" should arrive.\n'
        '5. Reopen the app and confirm the same crossings are in the log store '
        '(Logs tab, or the Doctor bug report) — they are written on the '
        'always-on lifecycle channel, so they survive a release build and any '
        'logLevel, and are kept for 2000 rows rather than cleared.\n\n'
        'If EXIT never arrives, check the "[geofence]" lines via getLogs(): '
        'they name which component owns the fence and carry dist, radius, '
        'buffer and thr for the decision, so a held EXIT can be told from one '
        'that was never evaluated.\n\n'
        'Cleanup: press Run again to recreate the fence at your new position, '
        'or use "Remove Geofences" on the main tab.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'geofence small radius 10m sub-100m terminated killed state headless '
          'notification ENTER EXIT hysteresis accuracy in-app evaluator '
          'wake-up radius polygon Play Services CoreLocation region monitoring '
          '356',
      title: '#356: a 10 m geofence fires ENTER/EXIT, even when killed',
      description:
          'Creates a 10 m geofence at your current position and sets up the '
          'terminated-state test. Fences under ~100 m are smaller than the OS '
          'can resolve, so Tracelet now evaluates them in-app at the true '
          'radius with a hysteresis band scaled to your measured fix accuracy. '
          'Crossings post a local notification from the headless isolate, '
          'which is the only real-time evidence when the app is dead.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
