import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #367 — stored telematics dropped `speed` and `value`.
///
/// `DrivingEvent` carries seven fields and `onDrivingEvent` delivered all of
/// them, but the very next statement persisted four:
///
/// ```kotlin
/// rustDatabase?.insertTelematicsEvent(e.kind, e.severity, e.latitude, e.longitude)
/// ```
///
/// `speed` and `value` had nowhere to go — the `tracelet_telematics` table had
/// no columns for them. So a live listener saw a complete event while anything
/// reading it back, or receiving it through sync, got a normalized 0–1
/// `severity` flag with no physical quantity behind it: no idea how hard the
/// braking was or how fast the vehicle was going. `severity` is not a
/// substitute, it only says how far past the threshold the event landed.
///
/// The table now carries both, added by `ALTER TABLE` alongside the existing
/// migrations so upgrades are seamless. Impacts get the same treatment, mapped
/// to their natural analogues: entry speed and peak g.
///
/// **What this card can and cannot prove.** It verifies the full path is wired
/// — schema, FFI, Pigeon, and the Dart model — by round-tripping an event and
/// reading the magnitudes back as real numbers rather than absent fields. It
/// cannot synthesize a *genuine* harsh-braking event: those come from
/// `processFix` reacting to real speed and heading changes, which needs actual
/// motion. `simulateTelematicsEvent` is the only injection point available from
/// Dart and it has no magnitudes to pass, so the values it round-trips are
/// zero. Zero here means "wired and reporting", not "captured from the road" —
/// the on-road capture is exercised by the driving-event path in the telematics
/// tab, not here.
class Issue367Card extends StatefulWidget {
  const Issue367Card({super.key});

  @override
  State<Issue367Card> createState() => _Issue367CardState();
}

class _Issue367CardState extends State<Issue367Card>
    with IssueCardRun<Issue367Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      await Tracelet.ready(
        const Config(
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      await Tracelet.destroyTelematicsEvents();
      await Tracelet.simulateTelematicsEvent(
        eventType: 'harsh_braking',
        severity: 0.82,
        latitude: 24.8607,
        longitude: 67.0011,
      );

      final events = await Tracelet.getTelematicsEvents(10);
      check(
        'The event round-trips',
        events.length == 1,
        'read back ${events.length} event(s) — if this fails the rest of the '
            'card proves nothing',
      );

      if (events.isEmpty) {
        throw StateError('no telematics event was stored');
      }
      final e = events.first;

      // The load-bearing assertion: on a build without the columns these fields
      // do not exist at all, so a decoded record leaves them null.
      check(
        'speed survives storage',
        e.speed != null,
        e.speed == null
            ? 'speed decoded as null — the column or its plumbing is missing'
            : 'speed read back as ${e.speed} (0 is expected for a simulated '
                  'event; the point is that the field exists and is populated)',
      );
      check(
        'value survives storage',
        e.value != null,
        e.value == null
            ? 'value decoded as null — the column or its plumbing is missing'
            : 'value read back as ${e.value}, alongside severity '
                  '${e.severity} — two distinct numbers, which is the whole '
                  'point: severity is the normalized flag, value is the '
                  'measurement',
      );

      // The pre-existing fields must be unharmed: this migration is additive,
      // and a schema change that quietly broke severity would be a worse bug
      // than the one it fixes.
      check(
        'The existing fields are untouched',
        e.eventType == 'harsh_braking' && e.severity == 0.82,
        'event_type "${e.eventType}" and severity ${e.severity} came back '
            'unchanged — new columns were added, nothing was renamed',
      );

      await Tracelet.destroyTelematicsEvents();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: the magnitudes are persisted and readable end to end.'
          : '❌ FAILED — #367 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Read the zero values honestly: a simulated event has no measurement '
        'behind it, so 0 is the correct answer and this card is proving the '
        'wiring, not the capture. A real harsh-braking event carries its own '
        'speed and g. Rows written before the migration also read back as 0 — '
        'the columns are NOT NULL DEFAULT 0.0, so an upgraded install cannot '
        'distinguish an old row from a genuine zero, and nothing pretends '
        'otherwise. Both values are additive on the wire too: they join the '
        'objects in extras.__telematics without renaming or removing anything '
        'an existing backend already parses.',
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
          'telematics DrivingEvent speed value severity magnitude harsh '
          'braking acceleration cornering speeding peakG speedBefore impact '
          'getTelematicsEvents tracelet_telematics migration columns',
      title: '#367: stored telematics dropped speed and value',
      description:
          'Round-trips a telematics event and asserts speed and value come '
          'back as real fields rather than absent ones, with severity and '
          'event_type unchanged. The magnitudes reached onDrivingEvent but were '
          'dropped at the insert, so stored history and every synced payload '
          'kept only a normalized flag. A simulated event has no measurement, '
          'so the values are zero — this proves the wiring, not the capture.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
