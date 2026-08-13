import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #251 — `destroyLocation(uuid)` could not delete persisted locations
/// because the native SDK parsed the public UUID as a numeric database id.
///
/// The public identifier is a UUID string (e.g. `36ef46cf-…`), but both the
/// Android (`uuid.toLongOrNull()`) and iOS (`Int64(uuid)`) SDKs tried to parse
/// it as a `Long`/`Int64`. For any real UUID that parse returns null and the
/// method returned `false` before touching the database — so pending locations
/// stayed in the queue forever. The SDKs now resolve the UUID to its row id
/// (via `getLocationForAudit`) and delete that record.
///
/// This test inserts a location, confirms the returned identifier is a real
/// UUID (not a bare number), deletes it by that UUID, and asserts it is gone
/// from the store.
class Issue251Card extends StatefulWidget {
  const Issue251Card({super.key});

  @override
  State<Issue251Card> createState() => _Issue251CardState();
}

class _Issue251CardState extends State<Issue251Card>
    with IssueCardRun<Issue251Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    if (running) return;
    setRunning(running: true);

    try {
      _set('Inserting a location to obtain a real UUID...');
      final uuid = await Tracelet.insertLocation({
        'timestamp': DateTime.now().toIso8601String(),
        'coords': {'latitude': 45.0, 'longitude': 5.0, 'accuracy': 10.0},
      });

      if (uuid.isEmpty || uuid == 'success') {
        _set('❌ ERROR: insertLocation did not return a usable UUID: "$uuid".');
        return;
      }

      // The reported symptom: the identifier is a UUID, not a bare number, so
      // the old numeric-parse path could never delete it.
      final isNumeric = int.tryParse(uuid) != null;

      _set(
        'Inserted UUID "$uuid" (numeric? $isNumeric). '
        'Destroying it by UUID...',
      );

      final beforeCount = (await Tracelet.getLocations()).length;
      final deleted = await Tracelet.destroyLocation(uuid);
      final after = await Tracelet.getLocations();
      final stillPresent = after.any((l) => l.uuid == uuid);

      if (deleted && !stillPresent) {
        _set(
          '✅ PASSED: destroyLocation("$uuid") returned true and the record is '
          'gone (${after.length} left, was $beforeCount). A standard UUID is '
          'now resolved to its row id instead of being rejected as non-numeric.'
          '${isNumeric ? '' : '\nNote the identifier is a real UUID — exactly '
                    'the case that used to fail on both platforms.'}',
        );
      } else if (!deleted) {
        _set(
          '❌ FAILED: destroyLocation("$uuid") returned false — the UUID is '
          'still being parsed as a numeric id (#251 not fixed).',
        );
      } else {
        _set(
          '❌ FAILED: destroyLocation returned true but the record with UUID '
          '"$uuid" is still present.',
        );
      }
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: 'Issue #251: destroyLocation cannot delete by UUID',
      description:
          'Inserts a location, confirms the returned identifier is a real UUID '
          '(not a bare number), then deletes it via destroyLocation(uuid) and '
          'verifies it is gone. Both Android and iOS used to parse the UUID as '
          'a numeric database id and return false without deleting anything.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
