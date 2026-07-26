import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #252 — the iOS heartbeat writer persisted the same GPS fix twice, so
/// `getLocations()` returned byte-identical duplicate location rows (roughly
/// half the points of a moving trip were duplicated on-device).
///
/// Two writers persisted locations with independent, non-cross-checking dedup
/// state. The normal dispatch calls `insertLocation` with `event="location"`
/// and the dedup guard only skipped a repeat when `event == "location"`. The
/// heartbeat timer re-tagged the same cached fix with `event="heartbeat"` and
/// called `insertLocation` too — so the guard was skipped and the fix already
/// stored by the normal path was inserted a second time (identical timestamp).
/// The guard now shares one last-inserted-timestamp key across both the
/// `location` and `heartbeat` writers, so the second insert is deduped.
///
/// This test drives that guard directly from Dart: it inserts one fix as a
/// normal `location`, then re-inserts the *same timestamp* tagged as a
/// `heartbeat`, and asserts only a single row lands in the store (the buggy
/// build stored two). The Android guard is kept in parity, so this runs on
/// both platforms.
class Issue252Card extends StatefulWidget {
  const Issue252Card({super.key});

  @override
  State<Issue252Card> createState() => _Issue252CardState();
}

class _Issue252CardState extends State<Issue252Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _test() async {
    if (_running) return;
    setState(() => _running = true);

    try {
      _set('Clearing the store...');
      await Tracelet.ready(const Config());
      await Tracelet.destroyLocations();

      // A single shared timestamp — the crux of the bug is that the heartbeat
      // re-persists a fix the normal dispatch already stored, at the identical
      // timestamp.
      final ts = DateTime.now().toUtc().toIso8601String();

      _set('Inserting the fix once as a normal "location" event...');
      await Tracelet.insertLocation({
        'timestamp': ts,
        'coords': {'latitude': 45.0, 'longitude': 5.0, 'accuracy': 10.0},
        'event': 'location',
      });

      _set('Re-inserting the SAME fix tagged as a "heartbeat" event...');
      await Tracelet.insertLocation({
        'timestamp': ts,
        'coords': {'latitude': 45.0, 'longitude': 5.0, 'accuracy': 10.0},
        'event': 'heartbeat',
      });

      // The store was cleared and no tracking is running, so every row present
      // came from the two inserts above. The native side normalizes the stored
      // timestamp string (so a raw `l.timestamp == ts` match is unreliable) —
      // the total row count is the honest signal: 1 = the heartbeat write was
      // deduped, 2 = the byte-identical duplicate is back.
      final total = (await Tracelet.getLocations()).length;

      if (total == 1) {
        _set(
          '✅ PASSED: only one row stored for the two inserts. The heartbeat '
          "writer now shares the location writer's dedup key, so it no longer "
          're-inserts a fix the normal dispatch already persisted.',
        );
      } else if (total >= 2) {
        _set(
          '❌ FAILED: $total rows stored — the heartbeat writer re-inserted a '
          'byte-identical duplicate (#252 not fixed). getLocations() would '
          'return the fix twice.',
        );
      } else {
        _set(
          '❌ FAILED: no rows stored ($total total) — the initial "location" '
          'insert did not persist, so the dedup path was never exercised.',
        );
      }
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: 'Issue #252: heartbeat writer duplicates location rows',
      description:
          'Inserts one GPS fix as a normal "location" event, then re-inserts '
          'the same timestamp tagged as a "heartbeat" event, and verifies only '
          'a single row is stored. On iOS the heartbeat used to bypass the '
          'location-only dedup guard and persist a byte-identical duplicate, so '
          'getLocations() returned roughly half a moving trip twice.',
      status: _status,
      running: _running,
      onRun: _test,
    );
  }
}
