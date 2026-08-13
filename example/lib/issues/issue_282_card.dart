import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #282 — iOS periodic fixes now use the shared best-of-N sampling window.
///
/// Previously `LocationEngine.performPeriodicFix()` took a single
/// `requestLocation()` one-shot, which on iOS frequently returns a stale cached
/// or first-coarse fix before the GPS converges. When periodic desired accuracy
/// is `DesiredAccuracy.high`, the fix now routes through the same
/// `collectSamples` best-of-N window `getCurrentPosition` uses and persists the
/// most accurate sample.
///
/// This is a manual, on-device iOS repro: it starts a periodic-configured
/// session at high accuracy with a short interval and lists each incoming fix's
/// accuracy and `locationSource`. On a real device the periodic fixes should be
/// GPS-quality (small accuracy, `locationSource == "gps"`) rather than
/// Wi-Fi/cell-level. Requires movement/real GPS; not a deterministic assertion.
class Issue282Card extends StatefulWidget {
  const Issue282Card({super.key});

  @override
  State<Issue282Card> createState() => _Issue282CardState();
}

class _Issue282CardState extends State<Issue282Card>
    with IssueCardRun<Issue282Card> {
  bool _tracking = false;
  int _fixCount = 0;
  StreamSubscription<Location>? _sub;

  void _set(String s) => setStatus(s);

  // Start/stop tracking by hand: a sweep would leave the SDK tracking.
  @override
  IssueRunner? get cardRunner => null;

  Future<void> _start() async {
    if (!Platform.isIOS) {
      _set('ℹ️ iOS-only repro (#282 changes the iOS periodic fix path).');
      return;
    }
    setRunning(running: true);
    setState(() => _fixCount = 0);
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          motion: MotionConfig(
            motionDetectionMode: MotionDetectionMode.smart,
            // Short timeouts so the device drops into stationary periodic mode
            // quickly for the repro.
            stopTimeout: 1,
            speedStationaryDelay: 15,
            stationaryPeriodicInterval: 20,
          ),
          geo: GeoConfig(
            // High accuracy → native getPeriodicDesiredAccuracy() == 0, which
            // now takes the best-of-N sampling window instead of a single
            // requestLocation() one-shot.
            periodicDesiredAccuracy: DesiredAccuracy.high,
            periodicLocationInterval: 20,
          ),
        ),
      );

      _sub = Tracelet.onLocation((loc) {
        setState(() => _fixCount++);
        _set(
          '✅ Fix #$_fixCount — accuracy=${loc.coords.accuracy.toStringAsFixed(1)}m, '
          'source="${loc.locationSource}".\n'
          'Stay still so the SDK enters periodic mode; periodic fixes should be '
          'GPS-quality (small accuracy / source "gps") thanks to the best-of-N '
          'window, not a single coarse one-shot.',
        );
      });

      await Tracelet.start();
      setState(() => _tracking = true);
      _set(
        'Tracking started (high-accuracy periodic, 20s). Keep the device still '
        'and wait for periodic fixes to arrive...',
      );
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      setRunning(running: false);
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await Tracelet.stop();
    } catch (_) {}
    if (mounted) {
      setState(() => _tracking = false);
      _set('Stopped after $_fixCount fix(es).');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'ios periodic fix best of n sampling collectSamples requestLocation '
          'high accuracy stale coarse locationSource getcurrentposition 282',
      title: '#282: iOS periodic fix uses best-of-N sampling window',
      description:
          'Starts a high-accuracy periodic session (20s) and lists each fix '
          'accuracy / locationSource. On iOS, periodic fixes now route through '
          'the shared best-of-N window instead of a single requestLocation() '
          'one-shot, so they should be GPS-quality. Manual on-device iOS repro.',
      status: status,
      running: running,
      runLabel: _tracking ? 'Stop' : 'Start tracking',
      onRun: _tracking ? _stop : _start,
    );
  }
}
