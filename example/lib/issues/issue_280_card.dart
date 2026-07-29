import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #280 — `locationSource` / `reducedAccuracy` dropped from persisted &
/// synced locations.
///
/// Both fields are emitted on the live `onLocation` event at the top level of
/// the location map, but the persist path only serialized `audit_*`, `battery`
/// and `extras` into the `route_context` column — so the classification was
/// lost at write time and every DB-sourced read (`getLocations`,
/// `getPendingLocations`, the DB-sourced sync payload) reported
/// `locationSource: "unknown"` / `reducedAccuracy: false`.
///
/// The fix persists both as first-class `route_context` keys (like `audit_*`)
/// and `LocationMapper` promotes them back to the top level on read, so the
/// live event and DB-sourced reads agree.
///
/// This card is an on-device E2E: it inserts a location tagged
/// `locationSource: "gps"`, `reducedAccuracy: true`, persists it, reads it back
/// via `getLocations()`, and asserts the tags survived the round-trip.
class Issue280Card extends StatefulWidget {
  const Issue280Card({super.key});

  @override
  State<Issue280Card> createState() => _Issue280CardState();
}

class _Issue280CardState extends State<Issue280Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      _set('Testing #280 (persist locationSource / reducedAccuracy)...');
      await Tracelet.ready(const Config());
      await Tracelet.destroyLocations();

      const uuid = 'issue-280-gps';
      await Tracelet.insertLocation({
        'uuid': uuid,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'coords': {
          'latitude': 37.7749,
          'longitude': -122.4194,
          'accuracy': 8.0,
        },
        // The classification the live onLocation event carries — must survive
        // persistence and come back on the DB-sourced read.
        'locationSource': 'gps',
        'reducedAccuracy': true,
      });

      final locations = await Tracelet.getLocations();
      if (locations.isEmpty) {
        _set('❌ FAILED: no locations returned from getLocations().');
        return;
      }
      final loc = locations.firstWhere(
        (l) => l.uuid == uuid,
        orElse: () => locations.first,
      );

      final sourceOk = loc.locationSource == 'gps';
      final reducedOk = loc.reducedAccuracy == true;

      if (sourceOk && reducedOk) {
        _set(
          '✅ SUCCESS: persisted classification survived the round-trip — '
          'locationSource="${loc.locationSource}", '
          'reducedAccuracy=${loc.reducedAccuracy}. '
          'Before the fix both came back as "unknown" / false.',
        );
      } else {
        _set(
          '❌ FAILED: classification lost on persist — '
          'locationSource="${loc.locationSource}" (want "gps"), '
          'reducedAccuracy=${loc.reducedAccuracy} (want true).',
        );
      }
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
          'locationSource location source reducedAccuracy reduced accuracy '
          'persist getlocations sync route_context gps wifi cell unknown 280',
      title: '#280: locationSource / reducedAccuracy dropped when persisted',
      description:
          'Inserts a location tagged locationSource="gps" / reducedAccuracy=true, '
          'persists it, then reads it back with getLocations() and asserts both '
          'tags survived. Before the fix the persist path never serialized them '
          'into route_context, so DB-sourced reads and the sync payload always '
          'reported "unknown" / false. Requires a running device (on-device E2E).',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
