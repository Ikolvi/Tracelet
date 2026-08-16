import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issues #394 and #395 — the map froze while you were walking, then jumped.
///
/// `AdaptiveSamplingEngine` multiplies the distance gate by an activity factor
/// and a battery factor, and the product was unbounded. Walking on a phone below
/// 50 % battery gated at 75 m; while the activity classifier reported `Still` —
/// which it does often, a phone in a pocket being held fairly steady — it gated
/// at 750 m. The processor's anchor advances only on an *accepted* fix, so once
/// nothing was accepted, nothing could be: every later fix was measured against
/// the same frozen point. Four minutes of walking produced 59 rejections and
/// zero locations in the field report, with the odometer stuck and nothing in
/// the logs to say tracking was still running.
///
/// The jump was the same bug's second act. The implied-speed guard divides a
/// jump by the anchor's age, so a stale anchor makes any teleport look slow: a
/// 1.65 km cell-derived fix arriving 196 s later reads as 8.4 m/s and sails
/// through a ceiling meant for cars. It is now measured from the last fix the
/// processor *observed* rather than the last one it accepted — the same jump
/// against a 32 s observation gap is 51 m/s, which no transport mode permits.
///
/// **What this card proves.** That a walking session keeps accepting fixes.
/// It records how long the stream goes between accepted locations and fails if
/// any gap exceeds the escape's bound, which is the exact symptom.
///
/// **Walk continuously for the whole run, outdoors if you can.** A stationary
/// run cannot tell a working escape from a device that never moved, and the
/// card says so rather than passing.
class Issue394Card extends StatefulWidget {
  const Issue394Card({super.key});

  @override
  State<Issue394Card> createState() => _Issue394CardState();
}

class _Issue394CardState extends State<Issue394Card>
    with IssueCardRun<Issue394Card> {
  /// Long enough to cross the 60 s idle escape twice over.
  static const _walkWindow = Duration(seconds: 150);

  /// The bound the escape promises: no more than a minute without an accepted
  /// fix while the device is actually moving. Allowed a little slack for the
  /// sampling interval on top.
  static const _maxAcceptedGap = Duration(seconds: 75);

  /// Metres of travel below which this run proves nothing.
  static const _minimumTravel = 40.0;

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    StreamSubscription<Location>? sub;
    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            distanceFilter: 10,
            // The shipped default, and the setting that inflates the gate.
            enableAdaptiveMode: true,
          ),
          classifier: ClassifierConfig(
            enableFusedClassifier: true,
            autoTuneFromTransportMode: true,
          ),
          motion: MotionConfig(isMoving: true),
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      final acceptedAt = <DateTime>[];
      sub = Tracelet.onLocation((_) => acceptedAt.add(DateTime.now()));

      await Tracelet.setOdometer(0);
      await Tracelet.start();
      final startedAt = DateTime.now();

      _set('🚶 Walk continuously for ${_walkWindow.inSeconds}s — do not stop…');
      await Future<void>.delayed(_walkWindow);

      await Tracelet.stop();
      final travelled = await Tracelet.getOdometer();

      // Gaps: start → first fix, between fixes, last fix → stop.
      final marks = <DateTime>[startedAt, ...acceptedAt, DateTime.now()];
      var longestGap = Duration.zero;
      for (var i = 1; i < marks.length; i++) {
        final gap = marks[i].difference(marks[i - 1]);
        if (gap > longestGap) longestGap = gap;
      }

      check(
        'you moved far enough for this run to mean anything',
        pass: travelled >= _minimumTravel,
        detail: travelled >= _minimumTravel
            ? '${travelled.toStringAsFixed(1)} m recorded'
            : 'only ${travelled.toStringAsFixed(1)} m — a stationary run cannot '
                  'distinguish a working escape from a device that never moved. '
                  'Re-run and keep walking',
      );

      check(
        'the stream accepted locations at all',
        pass: acceptedAt.isNotEmpty,
        detail: acceptedAt.isEmpty
            ? 'zero locations in ${_walkWindow.inSeconds}s of walking — this is '
                  '#394 exactly'
            : '${acceptedAt.length} location(s)',
      );

      if (travelled >= _minimumTravel && acceptedAt.isNotEmpty) {
        check(
          'no gap longer than ${_maxAcceptedGap.inSeconds}s between accepted fixes',
          pass: longestGap <= _maxAcceptedGap,
          detail: longestGap <= _maxAcceptedGap
              ? 'longest gap ${longestGap.inSeconds}s — adaptive sampling '
                    'thinned the stream without ever freezing it'
              : 'longest gap ${longestGap.inSeconds}s. On a build without #394 '
                    'an inflated gate could hold a fix indefinitely, and the map '
                    'stayed on the last accepted point',
        );
      }

      // #395: a re-seed contributes no distance, so a teleport cannot inflate
      // the odometer. A walk of this length should stay in a plausible band.
      check(
        'the odometer holds a plausible distance for the walk',
        pass: travelled < 2000,
        detail: travelled < 2000
            ? '${travelled.toStringAsFixed(1)} m'
            : '${travelled.toStringAsFixed(1)} m in ${_walkWindow.inSeconds}s — '
                  'a spike was booked as travel, which is #395',
      );

      final header = allPass
          ? '✅ SUCCESS: the stream kept up with you.'
          : '❌ FAILED — #394/#395 not satisfied on this build.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Accepted ${acceptedAt.length} location(s); longest gap '
        '${longestGap.inSeconds}s; ${travelled.toStringAsFixed(1)} m recorded.\n\n'
        'Adaptive sampling may now only *delay* a fix. Past 60 s with nothing '
        'accepted, a fix that clears the un-inflated distanceFilter is admitted '
        'even though it sits inside the inflated gate — the un-inflated clause '
        'is what keeps a genuinely parked device silent, since its jitter never '
        'clears the configured filter. Check the Doctor report\'s "Location '
        'stream health" section: a stall now announces itself there with the '
        'rejection histogram and the gate that caused it.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await sub?.cancel();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'location stuck frozen map not updating walking adaptive sampling '
          'distance filter 750m DISTANCE_FILTER anchor stale spike jump '
          'teleport implied speed odometer 394 395',
      title: '#394/#395: the map froze while walking, then jumped',
      description:
          'Walks for 150 s and measures the longest gap between accepted '
          'locations. Adaptive sampling could inflate the distance gate to '
          '750 m with no time bound, freezing the stream for minutes; a fix is '
          'now admitted after 60 s regardless. Keep walking for the whole run — '
          'a stationary run reports that it proved nothing.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
