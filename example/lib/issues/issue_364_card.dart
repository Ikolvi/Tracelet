import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #364 — a FlutterEngine created by *another plugin* must not be
/// treated as an event receiver.
///
/// When firebase_messaging (or flutter_local_notifications,
/// background_downloader, flutter_overlay_window…) creates its own
/// FlutterEngine, Flutter's plugin auto-registration attaches Tracelet to it
/// too. `isSpawningHeadlessEngine` — the #358 discriminator — only recognises
/// engines *Tracelet* spawned, so a foreign engine took the UI branch and its
/// dispatcher joined the global event fan-out with a live Pigeon `eventApi`.
/// `EventDispatcher` reads a non-null `eventApi` as "a Flutter engine can
/// receive this", so `fallback()` stopped routing to `HeadlessTaskService`:
/// after the app was swiped away the real UI engine died, the foreign engine
/// survived holding the fan-out, and every event was posted into an isolate
/// that never called `Tracelet.onLocation`. Native tracking kept running
/// perfectly; Dart saw nothing for the rest of the process.
///
/// **What this card proves.** It creates a real foreign engine on-device —
/// `FlutterEngine(applicationContext)`, the same constructor
/// `FlutterFirebaseMessagingBackgroundService` uses, whose isolate never
/// touches Tracelet — and measures the fan-out around it. Fan-out membership is
/// the mechanism itself: it is the list every event is broadcast to, and the
/// only reason the reporter's events went missing. On a build without the fix
/// the count goes up by one when the engine attaches; with the fix it does not,
/// because the engine now joins only once its own Dart side subscribes.
///
/// **What it cannot prove.** The user-visible half — that the headless task
/// fires after the app is swiped away — needs the app to be dead, so no card
/// can observe it. Those steps are printed at the end to run by hand.
///
/// It also cannot see what happens *after* the primary detaches, which is where
/// this fix left a second hole: with the foreign engine correctly held out, the
/// fan-out was empty rather than hostile, and an empty fan-out dropped events
/// just as quietly (#371). `issue_371_card.dart` covers that — with the real
/// firebase_messaging engine rather than the look-alike one built here, because
/// that failure needs the foreign engine to still be attached at swipe time.
///
/// **iOS.** The foreign-engine path does not exist there: `register(with:)`
/// gives secondary registrars the Pigeon HostApi only and never wires them into
/// event delivery. The iOS half of this fix is the detach path — the primary's
/// dispatcher used to keep a live `eventApi` bound to a dead messenger — which
/// is likewise unobservable from a live isolate and is covered by
/// `PluginSecondaryEngineGuardTests`. The card reports that rather than
/// claiming a pass it did not measure.
///
/// Run a **debug** build: the probe reads private fields reflectively and
/// release minification will not resolve them.
class Issue364Card extends StatefulWidget {
  const Issue364Card({super.key});

  @override
  State<Issue364Card> createState() => _Issue364CardState();
}

class _Issue364CardState extends State<Issue364Card>
    with IssueCardRun<Issue364Card> {
  static const _debug = MethodChannel('com.tracelet/debug');

  /// The always-on line the plugin writes when a secondary engine attaches.
  static const _attachMarker = 'engines: secondary attach';

  /// The line written only when a secondary engine's Dart side subscribes and
  /// it is let into the fan-out.
  static const _joinMarker = 'joining the event fan-out';

  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<int> _latestLogId() async {
    final logs = await Tracelet.getLogs(500);
    return logs.fold<int>(0, (max, e) => e.id > max ? e.id : max);
  }

  Future<List<String>> _logsSince(int sinceId, String marker) async {
    final logs = await Tracelet.getLogs(500);
    return logs
        .where((e) => e.id > sinceId && e.message.contains(marker))
        .map((e) => e.message)
        .toList();
  }

  Future<void> _run() async {
    if (running) return;
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (!Platform.isAndroid) {
        _set(
          'ℹ️ iOS — not applicable, and deliberately not reported as a pass.\n\n'
          'TraceletIosPlugin.register(with:) already gives a secondary '
          'registrar the Pigeon HostApi only; it never wires one into event '
          'delivery, so a foreign engine cannot capture events on iOS the way '
          'it did on Android.\n\n'
          'The iOS half of #364 is the detach path: the primary dispatcher '
          'kept a live eventApi bound to a dead messenger, so after the engine '
          'went away events were posted into it instead of falling through to '
          'the HeadlessRunner. That needs the engine to be gone, so it is not '
          'observable from this isolate — PluginSecondaryEngineGuardTests '
          'covers it in RunnerTests.',
        );
        return;
      }

      // Tracking need not be running: the fan-out is populated at engine
      // attach, which already happened when this app started.
      _set('Creating a foreign FlutterEngine (the firebase_messaging shape)…');
      final beforeId = await _latestLogId();

      final res = await _debug.invokeMapMethod<String, dynamic>(
        'debugIssue364ForeignEngine',
      );
      if (res == null) {
        _set('❌ ERROR: debug channel returned null.');
        return;
      }

      final before = res['fanOutBefore'] as int? ?? -1;
      final afterAttach = res['fanOutAfterAttach'] as int? ?? -1;
      final afterDestroy = res['fanOutAfterDestroy'] as int? ?? -1;

      final attachLines = await _logsSince(beforeId, _attachMarker);
      final joinLines = await _logsSince(beforeId, _joinMarker);

      check(
        'the fan-out was readable',
        before >= 1,
        before >= 1
            ? '$before dispatcher(s) before the foreign engine — this app '
                  'engine is in there'
            : 'read $before — reflection failed. Run a debug build; release '
                  'minification renames the fields this probe reads',
      );

      check(
        'the plugin saw the foreign engine attach',
        attachLines.isNotEmpty,
        attachLines.isNotEmpty
            ? attachLines.last
            : 'no "$_attachMarker" line — the engine never attached, so this '
                  'run measured nothing. INCONCLUSIVE',
      );

      check(
        'the foreign engine did NOT join the event fan-out',
        before >= 1 && afterAttach == before,
        afterAttach == before
            ? '$before → $afterAttach dispatchers across the attach'
            : '$before → $afterAttach dispatchers — the foreign engine was '
                  'added, and will swallow every event once the UI engine dies',
      );

      check(
        'no engine claimed a subscription it never made',
        joinLines.isEmpty,
        joinLines.isEmpty
            ? 'no "$_joinMarker" line, which is correct: this engine runs no '
                  'Dart that subscribes to Tracelet'
            : joinLines.last,
      );

      check(
        "the app's own delivery was left intact",
        afterDestroy == before,
        '$afterDestroy dispatcher(s) after the foreign engine was destroyed '
            '(started at $before)',
      );

      final summary = StringBuffer()
        ..writeln(allPass ? '✅ PASS' : '❌ FAIL')
        ..writeln()
        ..writeln(results.join('\n'))
        ..writeln()
        ..writeln('— Not measured here —')
        ..writeln(
          'That events reach the headless task after task removal needs the '
          'app to be dead. To check it by hand: registerHeadlessTask(), '
          'start() with stopOnTerminate: false, swipe the app from recents, '
          'then watch for "headless: spawning a FlutterEngine" and '
          '"headless event: location" in logcat.',
        );
      _set(summary.toString());
    } on PlatformException catch (e) {
      _set('❌ ERROR: ${e.code} — ${e.message}');
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: '#364 — Foreign engine event capture',
      description:
          'Creates a FlutterEngine the way another plugin would and checks it '
          'does not join the event fan-out, so events still reach the headless '
          'task after task removal.',
      status: status,
      running: running,
      keywords:
          'foreign engine firebase_messaging headless fan-out secondary '
          'engine task removal eventApi',
      onRun: _run,
    );
  }
}
