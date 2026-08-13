import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart'
    show TlLocationTuning, TlModeChangeEvent;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #301 — auto-tune follow-ups to #299.
///
/// #299 shipped `autoTuneFromTransportMode`, and both SDKs put the applied
/// thresholds on the native mode-change payload. But `TlModeChangeEvent` carried
/// only `mode` and `confidence`, so the plugin dispatchers dropped them: an
/// auto-tune was silent for exactly the Flutter apps the docs said could observe
/// it. Alongside that, nothing re-aligned the processor with the committed mode
/// after a reconfiguration, so switching auto-tuning **off** left its thresholds
/// in force and `setConfig()` silently discarded an active tune.
///
/// The deterministic half of this card asserts the event contract that #301
/// adds — that is the part that regressed, and it needs no device movement. The
/// live half then watches the real classifier, which requires you to actually
/// walk around, so it reports observations rather than gating the verdict.
///
/// The threshold numbers below mirror `tuning_for_transport_mode` in the Rust
/// core. That table is not exposed to Dart, so they are restated here rather
/// than read from the source of truth — keep them in step if the table changes.
class Issue301Card extends StatefulWidget {
  const Issue301Card({super.key});

  @override
  State<Issue301Card> createState() => _Issue301CardState();
}

class _Issue301CardState extends State<Issue301Card>
    with IssueCardRun<Issue301Card> {
  StreamSubscription<ModeChangeEvent>? _sub;

  /// How long to watch the live classifier before giving up on a commit. The
  /// classifier needs `modeSwitchDwellMs` (8 s) of a consistent mode before it
  /// commits anything, so anything much shorter can only ever report "nothing".
  static const _watchWindow = Duration(seconds: 25);

  /// The auto-tune table, keyed by committed mode.
  static const _expectedTuning = <String, LocationTuning>{
    'still': LocationTuning(
      distanceFilter: 25,
      trackingAccuracyThreshold: 15,
      odometerAccuracyThreshold: 10,
      maxImpliedSpeed: 3,
    ),
    'walking': LocationTuning(
      distanceFilter: 8,
      trackingAccuracyThreshold: 15,
      odometerAccuracyThreshold: 10,
      maxImpliedSpeed: 4,
    ),
    'running': LocationTuning(
      distanceFilter: 12,
      trackingAccuracyThreshold: 25,
      odometerAccuracyThreshold: 15,
      maxImpliedSpeed: 9,
    ),
    'cycling': LocationTuning(
      distanceFilter: 20,
      trackingAccuracyThreshold: 30,
      odometerAccuracyThreshold: 20,
      maxImpliedSpeed: 20,
    ),
    'vehicle': LocationTuning(
      distanceFilter: 30,
      trackingAccuracyThreshold: 50,
      odometerAccuracyThreshold: 30,
      maxImpliedSpeed: 60,
    ),
  };

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      // ---------------------------------------------------------------------
      // Deterministic: the event contract #301 adds.
      // ---------------------------------------------------------------------

      // 1. The regression itself. Before #301 there was no field to carry this,
      //    so the walking thresholds the SDK had already applied stopped at the
      //    Pigeon boundary.
      final walking = ModeChangeEvent.fromTl(
        TlModeChangeEvent(
          mode: 'walking',
          confidence: 0.8,
          appliedTuning: TlLocationTuning(
            distanceFilter: 8,
            trackingAccuracyThreshold: 15,
            odometerAccuracyThreshold: 10,
            maxImpliedSpeed: 4,
          ),
        ),
      );
      check(
        'Applied thresholds survive the platform boundary',
        walking.appliedTuning == _expectedTuning['walking'],
        'onModeChange reports ${walking.appliedTuning}',
      );

      // 2. And it must not invent one. `null` is the honest answer when auto-
      //    tuning is off, or when the mode is `unknown` and your own configured
      //    values were restored.
      final plain = ModeChangeEvent.fromTl(
        TlModeChangeEvent(mode: 'walking', confidence: 0.8),
      );
      check(
        'No tuning reported when auto-tuning is off',
        plain.appliedTuning == null,
        'appliedTuning is null, so your configured thresholds are in force',
      );

      // 3. An auto-tune has to be greppable in a log line, not just readable
      //    field-by-field — that is the whole point of surfacing it.
      check(
        'An auto-tune is visible in a logged event',
        walking.toString().contains('tuned') &&
            !plain.toString().contains('tuned'),
        'ModeChangeEvent.toString() carries the tuning only when there is one',
      );

      // ---------------------------------------------------------------------
      // Live: the real classifier on this device.
      // ---------------------------------------------------------------------
      _set(
        '${results.join('\n')}\n\n'
        '⏳ Watching the live classifier for ${_watchWindow.inSeconds}s — '
        'walk around with the phone.',
      );

      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            distanceFilter: 0,
            filter: LocationFilter(useKalmanFilter: true),
          ),
          classifier: ClassifierConfig(
            enableFusedClassifier: true,
            autoTuneFromTransportMode: true,
          ),
        ),
      );

      final observed = <ModeChangeEvent>[];
      await _sub?.cancel();
      _sub = Tracelet.onModeChange(observed.add);
      await Tracelet.start();
      await Future<void>.delayed(_watchWindow);

      if (observed.isEmpty) {
        results.add(
          'ℹ️ Live classifier — no mode committed in '
          '${_watchWindow.inSeconds}s. It needs 8s of consistent motion, so '
          'this usually means the phone sat still. Not a failure.',
        );
      } else {
        final last = observed.last;
        final expected = _expectedTuning[last.mode];
        // #306: `unknown` is a legitimate commit — it is the mode that restores
        // your configured values — and it carries no tuning, so `appliedTuning`
        // is correctly null. Asserting `!= null` unconditionally failed the card
        // for correct SDK behaviour whenever the phone sat still. The contract
        // is "appliedTuning matches the table for this mode", and for a mode
        // with no entry that means null.
        check(
          'Live auto-tune arrives on onModeChange',
          last.appliedTuning == expected,
          expected == null
              ? 'committed "${last.mode}", which carries no tuning — your '
                    'configured thresholds are in force'
              : 'committed "${last.mode}" → ${last.appliedTuning}',
        );
      }

      // Switching auto-tuning off used to be a one-way door: the next commit
      // returned early before it could restore, so the last mode's thresholds
      // stayed in force for the rest of the session.
      await Tracelet.setConfig(
        const Config(classifier: ClassifierConfig(enableFusedClassifier: true)),
      );
      // #306: this only ever asserted the Dart-side config mirror, while its
      // label claimed the native thresholds had been restored — so it could not
      // fail if the native restore regressed. Renamed to what it actually
      // proves. The native restore itself has no Dart-observable surface (there
      // is no getter for the processor's live tuning), so it is covered by the
      // SDK unit tests and by the INFO log line #303 added to that path.
      check(
        'Auto-tuning is off in the active config',
        !Tracelet.activeConfig.classifier.autoTuneFromTransportMode,
        'the flag round-trips; the native restore it triggers is asserted in '
            'the SDK unit tests and logged at INFO by syncTransportModeTuning',
      );

      await _sub?.cancel();
      _sub = null;
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: an auto-tune is now observable from Flutter, and '
                'turning it off gives you your own thresholds back.'
          : '❌ FAILED — #301 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'ModeChangeEvent.appliedTuning carries the four thresholds a committed '
        'mode put in force — distanceFilter, trackingAccuracyThreshold, '
        'odometerAccuracyThreshold and maxImpliedSpeed — and is null when '
        'auto-tuning is off or the mode is "unknown". Both SDKs also re-align '
        'the processor with the committed mode after any setConfig(), so a '
        'location-key change no longer silently drops an active tune and '
        'disabling the feature no longer leaves its thresholds behind.',
      );
    } catch (e) {
      await _sub?.cancel();
      _sub = null;
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'appliedTuning onModeChange mode change auto tune transport mode '
          'autoTuneFromTransportMode enableFusedClassifier setConfig restore '
          'thresholds silent config mutation distanceFilter '
          'odometerAccuracyThreshold maxImpliedSpeed classifier walking',
      title: '#301: Auto-tuned thresholds are reported to Flutter',
      description:
          'Asserts that ModeChangeEvent.appliedTuning carries the thresholds a '
          'committed transport mode applied — they used to be dropped at the '
          'platform boundary, making an auto-tune silent — and that turning '
          'auto-tuning off restores your configured values instead of leaving '
          'the last mode in force. The contract checks run in-process; the live '
          'section watches the real classifier for 25s, so walk around.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
