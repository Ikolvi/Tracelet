import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #383 — `persistMode` was not honoured for geofence ENTER/EXIT
/// transitions.
///
/// `PersistenceConfig.persistMode` decides which record types reach the local
/// database. It was applied to ordinary GPS fixes by
/// `LocationEngine.persistLocationIfAllowed` — the only place either platform
/// ever read `getPersistMode()` — and geofence transitions never went through
/// it. `GeofenceManager.onGeofenceEvent` was wired straight to the SDK's
/// unconditional `insertLocation`, so `location` ("persist only location
/// records") and `none` ("do not persist any records") both wrote every
/// crossing to the DB and handed it to the sync provider for the next HTTP
/// batch.
///
/// It is a privacy bug rather than a bookkeeping one: `persistMode: none` is a
/// reasonable choice for an app that wants geofence *callbacks* — a check-in
/// screen built on `onGeofence` — without the SDK keeping a location history.
/// That app was silently accumulating a record of every fence the device
/// crossed, and uploading it if `http` was configured.
///
/// The fix routes the geofence path through
/// `ConfigManager.shouldPersistGeofenceRecords()`, mirroring what the location
/// path already did. Only the DB write is gated — the listener event is
/// dispatched separately, so `none` keeps its documented "events are still
/// fired" behaviour, which is the half of the contract that was always correct.
///
/// **What this card proves.** Each phase registers a *fresh* fence around your
/// current position and lets the initial-entry trigger fire ENTER, then reads
/// the DB back. Fence identifiers are distinct per phase on purpose: the #292
/// dedup suppresses a repeat ENTER for a stationary device, so reusing one id
/// would make later phases silently observe nothing.
///
/// The `all` phase at the end is the control, and is what makes the two zeroes
/// above it mean anything — without it, "no geofence rows" is equally
/// consistent with "the gate works" and "no transition ever fired on this
/// device". Both must hold for the card to pass.
class Issue383Card extends StatefulWidget {
  const Issue383Card({super.key});

  @override
  State<Issue383Card> createState() => _Issue383CardState();
}

class _Issue383CardState extends State<Issue383Card>
    with IssueCardRun<Issue383Card> {
  /// Comfortably larger than a typical fix error, so registering while standing
  /// inside reliably trips the initial ENTER. Also above the ~100 m floor, so
  /// the OS path is exercised rather than only the in-app evaluator.
  static const _radiusMeters = 200.0;

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

    StreamSubscription<GeofenceEvent>? sub;
    final seenEvents = <String>[];

    try {
      await Tracelet.requestLocationAuthorization();
      await Tracelet.removeGeofences();

      // autoSync: false so nothing drains the queue underneath the reads — a
      // sync that uploaded and pruned a geofence row would make an unenforced
      // mode look enforced, which is the one way this card could pass falsely.
      await Tracelet.ready(
        const Config(
          http: HttpConfig(autoSync: false),
          persistence: PersistenceConfig(persistMode: PersistMode.none),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );
      await Tracelet.start();

      sub = Tracelet.onGeofence(
        (e) => seenEvents.add('${e.action} ${e.identifier}'),
      );

      final here = await Tracelet.getCurrentPosition(
        desiredAccuracy: DesiredAccuracy.high,
        timeout: 30,
      );
      final lat = here.coords.latitude;
      final lng = here.coords.longitude;

      final state = await Tracelet.getState();
      check(
        'persistMode: none is accepted and read back',
        state.config?.persistence.persistMode == PersistMode.none,
        'State.config reports ${state.config?.persistence.persistMode} — this '
            'much always passed, including on the broken build',
      );

      /// Registers a fence around the current position and waits for the
      /// initial-entry trigger, returning the geofence rows written meanwhile.
      Future<List<Location>> runPhase(String fenceId) async {
        await Tracelet.destroyLocations();
        seenEvents.clear();
        await Tracelet.addGeofence(
          Geofence(
            identifier: fenceId,
            latitude: lat,
            longitude: lng,
            radius: _radiusMeters,
          ),
        );
        // The initial ENTER is dispatched off the registration callback; a few
        // seconds covers the OS round-trip on both platforms.
        await Future<void>.delayed(const Duration(seconds: 5));
        final rows = await Tracelet.getLocations();
        return rows.where((Location l) => l.event == 'geofence').toList();
      }

      // ---------------------------------------------------------------------
      // 1. persistMode.none — the privacy-relevant case
      // ---------------------------------------------------------------------
      final noneRows = await runPhase('issue-383-none');
      final noneFired = seenEvents.isNotEmpty;
      check(
        'under none, the geofence event still fires',
        noneFired,
        noneFired
            ? 'onGeofence delivered ${seenEvents.join(", ")} — "events are '
                  'still fired" is the half of the doc that was always true'
            : 'no ENTER arrived, so this run cannot say anything about '
                  'persistence — are you inside the fence, with location '
                  'permission granted?',
      );
      check(
        'under none, nothing is written to the database',
        noneRows.isEmpty,
        noneRows.isEmpty
            ? '0 geofence rows after the crossing'
            : '${noneRows.length} geofence row(s) persisted despite '
                  'persistMode.none — this is #383',
      );

      // ---------------------------------------------------------------------
      // 2. persistMode.location — excludes geofence records by name
      // ---------------------------------------------------------------------
      await Tracelet.setConfig(
        const Config(
          persistence: PersistenceConfig(persistMode: PersistMode.location),
        ),
      );
      final locationRows = await runPhase('issue-383-location');
      check(
        'under location, no geofence row is written',
        locationRows.isEmpty,
        locationRows.isEmpty
            ? '0 geofence rows — "persist only location records" now excludes '
                  'the records it names'
            : '${locationRows.length} geofence row(s) persisted under '
                  'persistMode.location',
      );

      // ---------------------------------------------------------------------
      // 3. persistMode.all — the control
      // ---------------------------------------------------------------------
      await Tracelet.setConfig(
        const Config(
          persistence: PersistenceConfig(persistMode: PersistMode.all),
        ),
      );
      final allRows = await runPhase('issue-383-all');
      check(
        'under all, the geofence row IS written',
        allRows.isNotEmpty,
        allRows.isNotEmpty
            ? '${allRows.length} geofence row(s) persisted — so the two zeroes '
                  'above are the gate working, not a transition that never '
                  'fired'
            : 'no geofence row under persistMode.all. The control failed, so '
                  'the phases above prove nothing on this run — the fix may '
                  'still be fine; re-run while standing inside the fence',
      );

      await Tracelet.removeGeofences();
      await Tracelet.destroyLocations();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: persistMode gates geofence rows, and the event fires '
                'either way.'
          : '❌ FAILED — #383 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'The gate lives in ConfigManager.shouldPersistGeofenceRecords() on both '
        'platforms, read live at each transition rather than latched at setup, '
        'so a setConfig mid-session takes effect on the next crossing — which '
        'is what phases 2 and 3 rely on. It sits on the single callback both '
        'transition sources funnel through (OS-delivered handleGeofenceEvent '
        'and software-evaluated proximity), so the sub-100 m in-app evaluator '
        'is covered by the same check. An unrecognised mode falls back to '
        'persisting: a gate is not worth silent data loss.',
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
          'persistMode PersistMode none location geofence PersistenceConfig '
          'persist geofence transitions ENTER EXIT database rows synced http '
          'privacy location history getLocations onGeofence not honoured',
      title: '#383: persistMode ignored for geofence transitions',
      description:
          'Registers a fresh fence at your position under persistMode.none, '
          'then .location, then .all, and reads the DB back after each initial '
          'ENTER. The first two must write no geofence row while still firing '
          'the event; the third must write one — that control is what makes '
          'the two zeroes meaningful rather than a crossing that never fired.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
