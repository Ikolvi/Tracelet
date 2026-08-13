import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #265 — Android `addGeofence()` returns `false` after a *successful*
/// persistence.
///
/// `Tracelet.addGeofence()` can return `false` even though the geofence was
/// persisted and shows up in `Tracelet.getGeofences()` immediately afterward,
/// so apps display a bogus "registration failed" error for a geofence that
/// actually exists.
///
/// Root cause (native): the Flutter host invokes `addGeofence` on Android's
/// main thread. When there is no known device location yet, `addGeofence()`
/// persists the record to the Rust DB and then calls `registerGeofence()`,
/// which schedules the Play Services registration asynchronously:
///
/// ```
/// var success = false
/// geofencingClient.addGeofences(
///   onSuccess = { success = true; latch.countDown() },
///   onFailure = { latch.countDown() },
/// )
/// if (Looper.myLooper() != Looper.getMainLooper()) {
///   latch.await(REGISTRATION_TIMEOUT_MS, MILLISECONDS)   // skipped on main thread
/// }
/// return success   // still false on the main thread — callback hasn't run yet
/// ```
///
/// The SDK correctly avoids blocking the main thread (the callback also needs
/// the main looper), but then returns the unchanged `false`. Since the DB
/// insert already happened, `getGeofences()` shows the geofence — hence the
/// "returned false but it's persisted" mismatch.
///
/// This test reproduces it automatically: it requests location permission,
/// calls `ready()` WITHOUT starting tracking (so no device location is known
/// and the direct `registerGeofence()` path is taken), clears geofences, then
/// adds one and reloads the list. It asserts the FIXED behaviour — a
/// successfully-scheduled registration on the main thread returns `true` and
/// the geofence is present. Pre-fix, it fails with "returned false but it IS
/// persisted (#265)".
///
/// NOTE: the bug only manifests via the direct-registration path, which is
/// taken when NO device location is known yet. For the most reliable repro,
/// run this test right after launching the app, before starting tracking or
/// requesting a position (a prior fix routes `addGeofence` through the
/// proximity path, which already returns `true`).
class Issue265Card extends StatefulWidget {
  const Issue265Card({super.key});

  @override
  State<Issue265Card> createState() => _Issue265CardState();
}

class _Issue265CardState extends State<Issue265Card>
    with IssueCardRun<Issue265Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    setRunning(running: true);
    try {
      if (!Platform.isAndroid) {
        _set(
          'ℹ️ #265 is Android-specific (Play Services geofence registration on '
          'the main thread). Not applicable on this platform.',
        );
        return;
      }

      _set('Requesting location permission...');
      final auth = await Tracelet.requestLocationAuthorization();
      if (auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        _set(
          '❌ Cannot test: location permission denied ($auth). Geofence '
          'registration requires location permission (registerGeofence() '
          'returns false without it, for an unrelated reason).',
        );
        return;
      }

      // ready() without start()/getCurrentPosition() so the SDK has no known
      // device location — this is what routes addGeofence() through the direct
      // registerGeofence() path that exhibits #265.
      _set('Initializing (no tracking, so no known location)...');
      await Tracelet.ready(const Config());

      // Clean slate so a leftover geofence from a previous run can't mask the
      // result.
      await Tracelet.removeGeofences();

      const identifier = 'issue-265-office';
      const geofence = Geofence(
        identifier: identifier,
        latitude: 6.5244,
        longitude: 3.3792,
        radius: 100,
      );

      _set('Calling addGeofence()...');
      final added = await Tracelet.addGeofence(geofence);

      final persisted = await Tracelet.getGeofences();
      final isPersisted = persisted.any((g) => g.identifier == identifier);

      // Clean up.
      await Tracelet.removeGeofences();

      if (added && isPersisted) {
        _set(
          '✅ SUCCESS: addGeofence() returned true AND the geofence is present '
          'in getGeofences(). The main-thread registration path now reports '
          'success after scheduling instead of returning a stale false (#265).',
        );
      } else if (!added && isPersisted) {
        _set(
          '❌ FAILED (bug #265 reproduced): addGeofence() returned FALSE, but '
          'the geofence IS persisted and shows up in getGeofences(). On the '
          'main thread registerGeofence() returns the initial false before the '
          'async Play Services callback flips it to true. Apps see a bogus '
          '"registration failed" for a geofence that was actually created.',
        );
      } else if (added && !isPersisted) {
        _set(
          '⚠️ INCONCLUSIVE: addGeofence() returned true but the geofence is NOT '
          'in getGeofences(). Unexpected — not the #265 signature.',
        );
      } else {
        _set(
          '⚠️ INCONCLUSIVE: addGeofence() returned false and the geofence is '
          'NOT persisted. This looks like a genuine failure (permission, or a '
          'device location was already known so the proximity path ran), not '
          'the #265 stale-false mismatch. Try again right after a fresh app '
          'launch, before any tracking/position.',
        );
      }
    } catch (e) {
      _set('❌ FAILED: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'android addgeofence returns false persisted getgeofences '
          'registergeofence main thread play services latch async race '
          'geofencingclient registration',
      title: '#265: addGeofence() returns false after successful persistence',
      description:
          'Requests location permission, calls ready() WITHOUT starting '
          'tracking (so no device location is known and the direct '
          'registerGeofence() path runs), then adds a geofence and reloads the '
          'list. Asserts addGeofence() returns true when the geofence is '
          'actually persisted. Pre-fix it returns false on the main thread '
          '(the async Play Services callback has not flipped success yet) while '
          'getGeofences() shows the geofence. Android-only; run right after a '
          'fresh launch for the most reliable repro.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
