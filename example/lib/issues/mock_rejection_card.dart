import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Mock-location rejection on one-shot APIs (found while auditing #243).
///
/// `rejectMockLocations: true` only guarded the continuous-tracking path on
/// Android — `getCurrentPosition()`, `watchPosition()`, and periodic fixes
/// happily returned spoofed locations (flagged `mock: true` but delivered).
/// All Android delivery paths now enforce the flag; iOS was already safe
/// because everything routes through didUpdateLocations.
///
/// Without a spoofer app the assertion is that a genuine fix still comes
/// through; with one active (Developer options → "Select mock location app"),
/// getCurrentPosition() must now time out / return no fix instead of the
/// spoofed coordinates.
class MockRejectionCard extends StatefulWidget {
  const MockRejectionCard({super.key});

  @override
  State<MockRejectionCard> createState() => _MockRejectionCardState();
}

class _MockRejectionCardState extends State<MockRejectionCard> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _test() async {
    if (_running) return;
    setState(() => _running = true);

    try {
      if (!Platform.isAndroid) {
        _set(
          'N/A: iOS one-shots already route through the rejecting tracking '
          'path. This repro targets the Android gap.',
        );
        return;
      }

      _set('Configuring rejectMockLocations: true ...');
      await Tracelet.stop();
      await Tracelet.ready(
        const Config(
          geo: GeoConfig(
            // mockDetectionLevel defaults to 1 (platform mock flag).
            filter: LocationFilter(rejectMockLocations: true),
          ),
        ),
      );

      final applied =
          Tracelet.activeConfig.geo.filter.rejectMockLocations &&
          Tracelet.activeConfig.geo.filter.mockDetectionLevel == 1;
      if (!applied) {
        _set('❌ FAILED: rejectMockLocations did not reach the active config.');
        return;
      }

      _set('Requesting one-shot fix (10s timeout)...');
      Location? fix;
      try {
        fix = await Tracelet.getCurrentPosition(
          timeout: 10,
          maximumAge: 0,
          persist: false,
        );
      } on TimeoutException {
        fix = null;
      } on PlatformException catch (e) {
        // LOCATION_FAILURE: every sample was rejected (or GPS unavailable).
        if (e.code == 'LOCATION_FAILURE' || e.code == 'LOCATION_UNAVAILABLE') {
          fix = null;
        } else {
          rethrow;
        }
      }

      if (fix == null) {
        _set(
          '✅ No fix delivered. If a mock-location app is active this is the '
          'FIX working: every spoofed sample was rejected. (If no spoofer is '
          'set, this is just GPS unavailability — try outdoors.)',
        );
      } else if (fix.isMock) {
        _set(
          '❌ FAILED: getCurrentPosition returned a MOCK fix '
          '(${fix.coords.latitude}, ${fix.coords.longitude}) despite '
          'rejectMockLocations: true — the bug is present.',
        );
      } else {
        _set(
          '✅ Genuine fix delivered (${fix.coords.latitude.toStringAsFixed(5)}, '
          '${fix.coords.longitude.toStringAsFixed(5)}), isMock=false.\n'
          'Now enable a spoofer (Developer options → "Select mock location '
          'app"), set a fake position, and rerun: the call must return no fix '
          'instead of the spoofed coordinates.',
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
      title: 'Mock rejection: one-shot & watch APIs (via #243 audit)',
      description:
          'rejectMockLocations only guarded continuous tracking on Android — '
          'getCurrentPosition(), watchPosition(), and periodic fixes still '
          'delivered spoofed locations. All delivery paths now enforce the '
          'flag. Run once for a baseline genuine fix, then again with a mock '
          'location app active to see the rejection.',
      status: _status,
      running: _running,
      onRun: _test,
    );
  }
}
