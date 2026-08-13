import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/foreign_fcm_engine.dart';
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #371 — when nothing in the fan-out can receive an event, it must go
/// to the headless task.
///
/// The regression #365 (for #364) left behind: with the foreign
/// firebase_messaging engine correctly held out of `MultiEventSender`, task
/// removal takes the primary's dispatcher out too — and the composite the SDK
/// still holds as its event sender is then **empty**. Every `send*` was
/// `dispatchers.forEach { … }`, a no-op on an empty list, and `headlessFallback`
/// was a property of `EventDispatcher`, i.e. of the members that had just left.
/// Native tracking kept producing fixes every few seconds; Dart received
/// nothing, and not one line was logged to say so.
///
/// **Why this card exists when #364's already passes.** #364's card measures
/// fan-out membership with a look-alike engine it constructs and destroys. That
/// is the right measurement for #364 and it still passes — but it cannot show
/// #371, for two reasons: the failure is in the *empty* fan-out, which only
/// happens after the primary detaches, and it is conditional on a foreign
/// engine still being attached at that moment. So this card uses
/// firebase_messaging itself, whose background service *owns* its engine for
/// the rest of the process, and then reproduces the detached state directly.
///
/// **What it proves.**
/// 1. The real `FlutterFirebaseMessagingBackgroundService` engine attaches, and
///    (the #364 guarantee, now with the actual plugin) does not join the fan-out.
/// 2. With the fan-out emptied — the exact post-swipe state — one location sent
///    through the SDK's own event sender reaches the registered headless task.
///    Before the fix that dispatch vanished; the card fails on such a build.
///
/// **What it cannot prove.** That this still holds when the app is genuinely
/// dead: that needs the process without a UI isolate, so no card can watch it.
/// Arming leaves the foreign engine in place across launches, which is what
/// makes the manual swipe-kill run repeatable — the steps are printed at the end.
///
/// **iOS.** Not applicable: `MultiEventSender` is Android-only, and
/// `TraceletIosPlugin.register(with:)` never wires a secondary registrar into
/// event delivery, so there is no fan-out to empty.
///
/// Run a **debug** build: the probe reads private fields reflectively.
class Issue371Card extends StatefulWidget {
  const Issue371Card({super.key});

  @override
  State<Issue371Card> createState() => _Issue371CardState();
}

class _Issue371CardState extends State<Issue371Card>
    with IssueCardRun<Issue371Card> {
  static const _debug = MethodChannel('com.tracelet/debug');

  /// Written by HeadlessTaskService when it starts an engine for queued events.
  static const _spawnMarker = 'headless: spawning a FlutterEngine';

  /// The always-on line the fix adds when the fan-out cannot receive (#371).
  static const _emptyFanOutMarker = 'routing to the headless task (#371)';

  void _set(String s) => setStatus(s);

  /// Manual only — Execute All must not arm this one.
  ///
  /// Running it leaves a second FlutterEngine attached for the rest of the
  /// process and re-creates it on the next launch, which is the point of the
  /// card but a poor thing to do to the app behind a sweep. It is also the
  /// half-a-repro case the harness reserves this for: the other half needs the
  /// app killed.
  @override
  IssueRunner? get cardRunner => null;

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

  Future<Map<String, dynamic>?> _state() =>
      _debug.invokeMapMethod<String, dynamic>('debugIssue371FanOutState');

  /// Waits for the foreign engine to finish attaching.
  ///
  /// The engine is built on the main thread from the plugin's own service, so
  /// it is not up the instant `onBackgroundMessage` returns.
  Future<Map<String, dynamic>?> _awaitForeignEngine(int baseline) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final s = await _state();
      if ((s?['engines'] as int? ?? 0) > baseline) return s;
    }
    return _state();
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
          'MultiEventSender is the Android fan-out; there is no iOS equivalent '
          'to leave empty. TraceletIosPlugin.register(with:) gives a secondary '
          'registrar the Pigeon HostApi only and never wires one into event '
          'delivery, so iOS has a single dispatcher whose headless fallback is '
          'reached whenever its engine is gone.',
        );
        return;
      }

      final before = await _state();
      if (before == null) {
        _set('❌ ERROR: debug channel returned null.');
        return;
      }
      final baselineEngines = before['engines'] as int? ?? -1;
      final baselineFanOut = before['fanOut'] as int? ?? -1;
      final beforeId = await _latestLogId();

      // ---- 1. the real foreign engine -----------------------------------
      _set('Arming firebase_messaging — its service builds the engine…');
      final armError = await ForeignFcmEngine.arm();
      if (armError != null) {
        _set('❌ ERROR: could not arm firebase_messaging — $armError');
        return;
      }

      final after = await _awaitForeignEngine(baselineEngines);
      final engines = after?['engines'] as int? ?? -1;
      final fanOut = after?['fanOut'] as int? ?? -1;

      check(
        'the real firebase_messaging engine attached',
        engines > baselineEngines,
        engines > baselineEngines
            ? 'engineCount $baselineEngines → $engines '
                  '(FlutterFirebaseMessagingBackgroundService built it)'
            : 'engineCount stayed at $engines — the plugin never created its '
                  'engine, so this run measured nothing. INCONCLUSIVE',
      );

      check(
        'it did NOT join the event fan-out (#364 still holds)',
        baselineFanOut >= 1 && fanOut == baselineFanOut,
        fanOut == baselineFanOut
            ? '$baselineFanOut → $fanOut dispatchers across the attach'
            : '$baselineFanOut → $fanOut — the foreign engine was added and '
                  'will swallow events once the UI engine dies',
      );

      // ---- 2. the #371 fix ------------------------------------------------
      final headlessRegistered = after?['headlessTaskRegistered'] == true;
      check(
        'a headless task is registered',
        headlessRegistered,
        headlessRegistered
            ? 'registerHeadlessTask() stored a callback, so a fallback has '
                  'somewhere to deliver'
            : 'no headless callback stored — call registerHeadlessTask() before '
                  'runApp(). Without it the probe below cannot tell "routed and '
                  'dropped" from "never routed". INCONCLUSIVE',
      );

      _set('Emptying the fan-out and sending one location through the SDK…');
      final probe = await _debug.invokeMapMethod<String, dynamic>(
        'debugIssue371EmptyFanOutProbe',
      );
      if (probe == null) {
        _set('❌ ERROR: the probe returned null.');
        return;
      }

      check(
        "the SDK's event sender is the fan-out",
        probe['senderIsTheFanOut'] == true,
        probe['senderIsTheFanOut'] == true
            ? 'setEventSender(globalEventSender) is still in force — which is '
                  'why emptying it strands every event'
            : 'the SDK holds a different sender; this probe does not describe '
                  'the reported state',
      );

      check(
        'the fan-out was restored',
        probe['restoredCount'] == probe['emptiedCount'],
        '${probe['emptiedCount']} dispatcher(s) removed, '
            '${probe['restoredCount']} put back — the app keeps receiving events',
      );

      check(
        'the fan-out itself carries a headless fallback',
        probe['fanOutFallbackWired'] == true,
        probe['fanOutFallbackWired'] == true
            ? 'MultiEventSender.headlessFallback is wired, so an empty '
                  'composite still has a route'
            : 'MultiEventSender.headlessFallback is null — with no members '
                  'left there is nothing to fall back from, and every event is '
                  'dropped in silence',
      );

      // The routing itself, observed by wrapping the fan-out's fallback around
      // this one send. Deliberately not the log lines below: both are written
      // once per process — the "#371" line on the *transition* into headless
      // routing, "headless: spawning" only while there is no engine yet — so
      // pressing Run a second time reported a false failure on a build that
      // routed the event perfectly well.
      final routedEvents = (probe['routedEvents'] as List<Object?>? ?? [])
          .map((e) => '$e')
          .toList();
      check(
        'the event was routed to the headless task',
        probe['routedToHeadless'] == true,
        probe['routedToHeadless'] == true
            ? "the fan-out handed '${routedEvents.join(', ')}' to the headless "
                  'route while it had no member that could receive'
            : 'the location sent into the empty fan-out reached nothing at '
                  'all, which is #371',
      );

      // Give HeadlessTaskService a moment to log its spawn.
      await Future<void>.delayed(const Duration(seconds: 2));
      final routedLines = await _logsSince(beforeId, _emptyFanOutMarker);
      final spawnLines = await _logsSince(beforeId, _spawnMarker);

      final summary = StringBuffer()
        ..writeln(allPass ? '✅ PASS' : '❌ FAIL')
        ..writeln()
        ..writeln(results.join('\n'))
        ..writeln()
        ..writeln('— Lifecycle log, first run of this process only —')
        ..writeln(
          routedLines.isNotEmpty || spawnLines.isNotEmpty
              ? [...routedLines, ...spawnLines].join('\n')
              : 'Nothing new. Expected from the second Run onwards: the '
                    '"$_emptyFanOutMarker" line is written when routing '
                    'switches to headless, not per event, and "$_spawnMarker" '
                    'only while no headless engine exists yet. Both already '
                    'happened on the first run. Restart the app to see them '
                    'again.',
        )
        ..writeln()
        ..writeln('— Armed —')
        ..writeln(
          'The firebase_messaging background engine is now attached and stays '
          'for the life of this process, and the example re-registers it on '
          'the next launch (Disarm below undoes that).',
        )
        ..writeln()
        ..writeln('— Not measured here: the killed-app run —')
        ..writeln(
          '1. Start tracking, with stopOnTerminate: false.\n'
          '2. Swipe the app from recents.\n'
          '3. adb logcat | grep -E '
          '"remainingEngines|SDK preserved|#371|headless: spawning"\n'
          'Expect: "secondary engines still active, SDK preserved", then '
          '"no attached engine can receive events … routing to the headless '
          'task (#371)" and "headless: spawning a FlutterEngine". Before the '
          'fix, the log stops after the heartbeat lines.',
        );
      _set(summary.toString());
    } on PlatformException catch (e) {
      _set('❌ ERROR: ${e.code} — ${e.message}');
    } on Object catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      setRunning(running: false);
    }
  }

  Future<void> _disarm() async {
    await ForeignFcmEngine.disarm();
    _set(
      'Disarmed. The persisted firebase_messaging callback handles are '
      'cleared, so the next launch of the example runs with a single engine. '
      'The engine created in *this* process stays until it is restarted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IssueCardShell(
          title: '#371 — Empty fan-out swallows every event',
          description:
              'Uses firebase_messaging to create the real foreign background '
              'engine, then empties the fan-out the way task removal does and '
              'checks the event still reaches the headless task.',
          status: status,
          running: running,
          keywords:
              'firebase_messaging foreign engine empty fan-out MultiEventSender '
              'headless task removal swipe kill dispatchers 364 regression',
          onRun: _run,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 24, bottom: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: running ? null : _disarm,
              child: const Text('Disarm firebase_messaging'),
            ),
          ),
        ),
      ],
    );
  }
}
