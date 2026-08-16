import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issues #393 and #396 — the battery budget rewrote the app's configuration
/// and could not be talked out of it.
///
/// Two defects, one code path. The engine measured drain from a single pair of
/// battery-level readings five minutes apart, and iOS reports that level in 5 %
/// steps — so one reporting step read as 60 %/hr against a 3 %/hr budget, on a
/// device that was draining normally. Having "detected" a twentyfold overrun it
/// then throttled by writing its output straight into `ConfigManager`:
///
/// ```
/// state.distance_filter = (state.distance_filter * 1.5).clamp(10.0, 5000.0);
/// ```
///
/// A configured `distanceFilter: 0` — this app's own setting, the documented
/// "record every fix" opt-out — multiplied to 0 and clamped *up* to 10. The
/// processor goes out of its way to preserve a configured zero across a
/// transport-mode retune, but that check reads the base tuning the write had
/// just replaced, so from the next mode commit the Walking gate applied where
/// the app had asked for no gate at all. Nothing could restore it: the engine
/// only ever multiplied, and its recovery factor clamped at 10 too.
///
/// The throttle is now a bounded ladder applied as an **overlay**. Your
/// configuration is never written to, so `Tracelet.activeConfig` keeps saying
/// what you set, and lifting the throttle restores your values exactly.
///
/// **What this card proves.** That the budget engine, running, leaves the
/// configuration alone — including the `distanceFilter: 0` opt-out that the old
/// engine destroyed first.
///
/// **What it cannot prove here.** That a genuine over-budget drain eventually
/// throttles: the ladder now needs two conclusive 15-minute measurement windows
/// before it moves, which is the entire point and far longer than a card can
/// sit. The Rust suite covers the movement itself, including the exact 0.25 →
/// 0.20 reading from the field report.
class Issue393Card extends StatefulWidget {
  const Issue393Card({super.key});

  @override
  State<Issue393Card> createState() => _Issue393CardState();
}

class _Issue393CardState extends State<Issue393Card>
    with IssueCardRun<Issue393Card> {
  /// Long enough to cover several battery samples on both platforms.
  static const _observationWindow = Duration(seconds: 20);

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

    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            // The opt-out the old engine clamped away first.
            distanceFilter: 0,
            // An unmeetably tight budget: if anything could still throttle on
            // noise, this is the configuration that would show it.
            batteryBudgetPerHour: 0.1,
          ),
          motion: MotionConfig(isMoving: true),
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );
      await Tracelet.start();

      check(
        'the configured distanceFilter: 0 survives ready()',
        pass: Tracelet.activeConfig.geo.distanceFilter == 0,
        detail:
            'activeConfig reports '
            '${Tracelet.activeConfig.geo.distanceFilter}m',
      );

      _set(
        '⏳ Letting the budget engine sample (${_observationWindow.inSeconds}s)…',
      );
      await Future<void>.delayed(_observationWindow);

      final config = Tracelet.activeConfig.geo;
      check(
        'the budget engine has not written to distanceFilter',
        pass: config.distanceFilter == 0,
        detail: config.distanceFilter == 0
            ? 'still 0 — the throttle is an overlay, not a config write'
            : 'became ${config.distanceFilter}m. On a build without #393 this '
                  'is exactly what happened, and it was permanent',
      );
      check(
        'the budget engine has not written to desiredAccuracy',
        pass: config.desiredAccuracy == DesiredAccuracy.high,
        detail: 'activeConfig reports ${config.desiredAccuracy.name}',
      );
      check(
        'the budget target you set is the one still in force',
        pass: config.batteryBudgetPerHour == 0.1,
        detail: '${config.batteryBudgetPerHour}%/hr',
      );

      // The tuning actually in force is read back from the native processor,
      // so this catches a throttle that reached the filter without going
      // through config.
      final tuning = await Tracelet.getCurrentLocationTuning();
      if (tuning == null) {
        check(
          'the location filter reports its thresholds',
          pass: false,
          detail:
              'no processor — start() did not bring one up, so this run '
              'proved nothing about the filter',
        );
      } else {
        check(
          'the filter in force did not acquire a distance gate from nowhere',
          pass: tuning.distanceFilter == 0,
          detail: tuning.distanceFilter == 0
              ? 'the processor is gating at 0 m, as configured'
              : 'the processor is gating at ${tuning.distanceFilter}m — a '
                    'transport-mode auto-tune would do this legitimately, but '
                    'with distanceFilter: 0 configured it must not',
        );
      }

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: the battery budget left your configuration alone.'
          : '❌ FAILED — #393/#396 not satisfied on this build.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'The engine now measures drain over at least 15 minutes and discounts '
        'one battery-level reporting step (5 % on iOS, 1 % on Android) from '
        'every figure, so a drain only counts when it beats the budget by more '
        'than the measurement can resolve — the 60 %/hr that started the field '
        'failure was one 5 % step over five minutes and nothing else. Two '
        'consecutive conclusive windows move the ladder one rung, and each rung '
        'throttles sampling cadence before it touches accuracy. Nothing is '
        'written to your config at any point.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'battery budget throttle distanceFilter 0 overwritten config '
          'quantization drain 60%/hr desiredAccuracy clamp ladder overlay '
          'batteryBudgetPerHour 393 396',
      title: '#393/#396: the battery budget overwrote your configuration',
      description:
          'Runs with distanceFilter: 0 and an unmeetably tight battery budget, '
          'then checks the engine has not rewritten either value. The old '
          'engine clamped a configured 0 up to 10 m, wrote it into the live '
          'config, and could never put it back. No walking required.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
