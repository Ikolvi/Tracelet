import 'package:flutter/material.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #294 — a single over-confident GPS fix causes false EXIT/ENTER
/// flapping for a stationary device (high-accuracy geofence mode).
///
/// Consumer GNSS routinely emits a lone fix that lands far outside the fence
/// while reporting a *tight* accuracy the accuracy-aware EXIT gate (#274)
/// cannot see through — field logs from a vivo V2431 and a Samsung SM-G781B
/// show a stationary office device jumping to 198–301 m out at 1.7–9 m reported
/// accuracy, then straight back. Hysteresis (#268) is spatial and accuracy
/// gating (#274) trusts the (lying) accuracy, so neither catches it.
///
/// The fix is temporal: a geofence EXIT must be confirmed across two
/// consecutive out-of-fence fixes, because a boundary crossing is a *sustained*
/// state change while a glitch is a single out-and-back sample. This card drives
/// the REAL shipped [GeofenceEvaluator] (the pure-Dart mirror of the Rust core)
/// through every edge case and reports each — including the case the concern is
/// really about: a genuine departure must still EXIT.
class Issue294Card extends StatefulWidget {
  const Issue294Card({super.key});

  @override
  State<Issue294Card> createState() => _Issue294CardState();
}

class _Issue294CardState extends State<Issue294Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  static const _lat = 10.787929;
  static const _lng = 76.684183;
  static const _radius =
      50.0; // exit threshold = radius + max(radius*0.1, 20) = 70 m

  final _geofences = <Map<String, Object?>>[
    {
      'identifier': 'OFFICE',
      'latitude': _lat,
      'longitude': _lng,
      'radius': _radius,
    },
  ];

  /// ~[meters] north of the office centre (1° lat ≈ 111_320 m).
  double _north(double meters) => _lat + meters / 111320.0;

  /// Feeds one fix [meters] north of centre with [accuracy] and returns the
  /// (enter, exit) counts it produced.
  (int, int) _fix(GeofenceEvaluator ev, double meters, double accuracy) {
    final ts = ev.evaluateProximity(
      latitude: _north(meters),
      longitude: _lng,
      accuracy: accuracy,
      geofences: _geofences,
    );
    return (
      ts.where((t) => t.action == 'ENTER').length,
      ts.where((t) => t.action == 'EXIT').length,
    );
  }

  /// A fresh evaluator already inside the office (initial ENTER consumed).
  GeofenceEvaluator _entered() {
    final ev = GeofenceEvaluator();
    _fix(ev, 8, 5);
    return ev;
  }

  /// Runs [fixes] (meters, accuracy) through a fresh already-inside evaluator
  /// and returns the total (enter, exit) counts observed after arrival.
  (int, int) _after(List<(double, double)> fixes) {
    final ev = _entered();
    var enters = 0, exits = 0;
    for (final (meters, acc) in fixes) {
      final (e, x) = _fix(ev, meters, acc);
      enters += e;
      exits += x;
    }
    return (enters, exits);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final results = <String>[];
      var allPass = true;

      void check(String name, bool pass, String detail) {
        results.add('${pass ? '✅' : '❌'} $name — $detail');
        if (!pass) allPass = false;
      }

      // 1. Sustained inside all day → no EXIT, no re-ENTER.
      {
        final (e, x) = _after(const [
          (10, 6),
          (12, 6),
          (9, 6),
          (11, 6),
          (10, 6),
        ]);
        check(
          'Stationary inside',
          e == 0 && x == 0,
          '$e ENTER / $x EXIT after arrival (want 0/0)',
        );
      }

      // 2. Single over-confident glitch (200 m out @1.7 m), then back → absorbed.
      {
        final (e, x) = _after(const [(200, 1.7), (9, 5)]);
        check(
          'Single over-confident glitch',
          e == 0 && x == 0,
          '$e ENTER / $x EXIT (want 0/0 — absorbed)',
        );
      }

      // 3. Alternating out/in glitches → never confirms an EXIT.
      {
        final (_, x) = _after(const [
          (200, 1.7),
          (10, 5),
          (220, 1.7),
          (12, 5),
          (210, 1.7),
        ]);
        check('Alternating glitches', x == 0, '$x EXIT (want 0)');
      }

      // 4. Genuine SUSTAINED departure → exactly one EXIT (the concern!).
      {
        final (_, x) = _after(const [(120, 10), (120, 10)]);
        check(
          'Genuine sustained departure',
          x == 1,
          '$x EXIT (want exactly 1 — a real exit still counts)',
        );
      }

      // 5. Depart then return → one EXIT then one fresh ENTER.
      {
        final (e, x) = _after(const [(120, 10), (120, 10), (130, 10), (10, 6)]);
        check(
          'Depart then return',
          e == 1 && x == 1,
          '$e ENTER / $x EXIT after arrival (want 1/1)',
        );
      }

      // 6. Brief real step-out shorter than confirmation → absorbed. Documented
      //    trade-off: for a 50 m attendance fence a sub-2-fix excursion is noise,
      //    not a departure. This is expected behaviour, not a failure.
      {
        final (_, x) = _after(const [(120, 10), (10, 6)]);
        check(
          'Brief <2-fix step-out (absorbed by design)',
          x == 0,
          '$x EXIT (want 0 — sub-confirmation excursion)',
        );
      }

      final header = allPass
          ? '✅ SUCCESS: confirmed-exit gate holds on every edge case — glitches '
                'are absorbed and a genuine departure still fires exactly one EXIT.'
          : '❌ FAILED — #294 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'A geofence EXIT is confirmed across two consecutive out-of-fence fixes '
        '(the temporal complement to the #268 spatial hysteresis). A real exit is '
        'never missed — only delayed by one fix interval. Runs in-process against '
        'the real GeofenceEvaluator; no permissions or device movement required.',
      );
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'geofence exit confirmation debounce over-confident drift flapping '
          'false exit stationary attendance vivo samsung gnss glitch high accuracy '
          'geofenceevaluator hysteresis sustained departure',
      title:
          '#294: Single over-confident GPS fix causes false EXIT/ENTER flapping',
      description:
          'Drives the real GeofenceEvaluator through every edge case of the '
          'confirmed-exit gate: a lone over-confident fix (200 m out at 1.7 m '
          'accuracy) and alternating glitches are absorbed, while a genuine '
          'sustained departure still fires exactly one EXIT (delayed one fix). '
          'Confirms a normal exit is never missed. Runs in-process; no '
          'permissions or device movement required.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
