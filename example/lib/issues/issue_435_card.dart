import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #435 — on iOS 16.4+, an Always-authorized app with
/// `showsBackgroundLocationIndicator: false` and no background session was
/// suspended in the background while moving, and continuous tracking delivered
/// nothing until a significant-location-change wake.
///
/// Apple's rule (developer forums thread 727015): an app running both
/// `startUpdatingLocation()` and significant-change monitoring can be suspended
/// in the background if it sets a distance filter or asks for accuracy coarser
/// than 100 m — unless the location indicator is showing. `start()` always runs
/// both, and passed the configured `distanceFilter` (default 10 m) straight to
/// CoreLocation. Before 3.8.8 every moving transition opened a
/// `CLBackgroundActivitySession`, which shows the indicator and so hid the
/// rule; #423 correctly made that session opt-in, and exposed it.
///
/// With the indicator off and no session under Always, CoreLocation now runs
/// with `kCLDistanceFilterNone` and accuracy of 100 m or better. The configured
/// distance filter stays in the Rust processor, so stored and synced volume do
/// not change.
///
/// **What this card proves**, with the app on screen: under Always with the
/// indicator off the SDK logs that it dropped CoreLocation's filter, and with
/// the indicator on it does not. Background suspension itself only happens off
/// screen. To see it, background the app and walk for ten minutes: points
/// should keep arriving rather than only at Wi-Fi handoffs.
class Issue435Card extends StatefulWidget {
  const Issue435Card({super.key});

  @override
  State<Issue435Card> createState() => _Issue435CardState();
}

class _Issue435CardState extends State<Issue435Card>
    with IssueCardRun<Issue435Card> {
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  IssueRunner? get cardRunner => _run;

  static const _guardLine = 'CoreLocation distanceFilter set to none';

  Future<List<LogEntry>> _startAndCollect({required bool indicator}) async {
    await Tracelet.ready(
      Config(
        // The default filter, which is what tripped the rule.
        geo: const GeoConfig(distanceFilter: 10),
        motion: const MotionConfig(isMoving: true),
        http: const HttpConfig(autoSync: false),
        // The customer's configuration, stated in full.
        ios: IosConfig(
          showsBackgroundLocationIndicator: indicator,
          useBackgroundActivitySession: false,
        ),
      ),
    );
    await Tracelet.destroyLog();
    await Tracelet.start();
    await Future<void>.delayed(const Duration(seconds: 3));
    final logs = await Tracelet.getLogs(300);
    await Tracelet.stop();
    return logs;
  }

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (!_isIOS) {
        setStatus(
          "ℹ️ iOS only. The suspension rule is CoreLocation's; Android keeps "
          'delivering through its foreground service.',
        );
        return;
      }

      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always) {
        setStatus(
          'ℹ️ Not verified — authorization is ${auth.name}. The rule only '
          'bites under Always: under When-In-Use the OS shows the indicator in '
          'the background regardless, so the SDK leaves the filter alone. Grant '
          '"Always" and run again.',
        );
        return;
      }

      setStatus('⏳ Indicator off, no background session…');
      final off = await _startAndCollect(indicator: false);
      final guardLines = off
          .where((l) => l.message.contains(_guardLine))
          .map((l) => l.message)
          .toList();
      check(
        'indicator off: CoreLocation runs unfiltered',
        pass: guardLines.isNotEmpty,
        detail: guardLines.isNotEmpty
            ? guardLines.first
            : 'no guard line — the 10 m filter went to CoreLocation, which '
                  'iOS 16.4+ suspends in the background (the bug)',
      );

      setStatus('⏳ Indicator on…');
      final on = await _startAndCollect(indicator: true);
      final guardWithIndicator = on.any((l) => l.message.contains(_guardLine));
      check(
        'indicator on: the configured filter is kept',
        pass: !guardWithIndicator,
        detail: !guardWithIndicator
            ? "the indicator is Apple's other way out, so nothing changes"
            : 'the guard engaged although the indicator is on',
      );

      final header = allPass
          ? '✅ SUCCESS: the stream avoids iOS 16.4+ background suspension.'
          : '❌ FAILED — #435 not satisfied on this build.';
      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        'What the app records is unchanged: the 10 m filter still gates '
        'stored and synced locations in the Rust processor. Suspension itself '
        'only happens off screen — background the app and walk for ten '
        'minutes; points should keep arriving rather than only at Wi-Fi '
        'handoffs.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'ios background suspended suspension 16.4 distanceFilter significant '
          'location change showsBackgroundLocationIndicator '
          'useBackgroundActivitySession blue bar always 435 423',
      title: '#435: iOS keeps streaming in the background with the bar off',
      description:
          'With the indicator off and no background session, the configured '
          'distanceFilter plus significant-change monitoring got the app '
          'suspended in the background on iOS 16.4+. Starts with the indicator '
          'off, then on, and checks CoreLocation is unfiltered only when needed.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
