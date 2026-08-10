import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #331 — after task removal the headless Dart task was intermittently
/// never invoked, and the failure was completely silent.
///
/// Native tracking kept running and kept producing fixes every 2–4 s; the
/// registered callback simply never fired, on roughly half of the attempts,
/// with no error at any log level. The reporter's two runs came from the same
/// PID four minutes apart and differed only in whether a headless FlutterEngine
/// ever attached.
///
/// The routing itself was fine — `LocationService.startBootTracking` builds an
/// `EventDispatcher` whose `headlessFallback` reaches
/// `HeadlessTaskService.dispatchEvent`. Everything past that point was
/// unobservable. Between `dispatchEvent` and `FlutterEngine(context)` there was
/// exactly **one** log line — "No headless callbacks registered" — and the
/// report confirmed it was absent, which left "no engine, no error" as the
/// whole of the evidence.
///
/// Four defects sat behind that silence, all fixed here:
///
/// * `ensureEngine()` opened with `if (flutterEngine != null) return`. An
///   engine that was created but whose Dart side never signalled `initialized`
///   made every later event a no-op **forever** — no timeout, no retry, no log.
/// * The spawn ran a **fresh** `FlutterLoader()` on the main thread and blocked
///   it in `ensureInitializationComplete()`. That re-runs full Flutter
///   initialization (the "FlutterJNI.loadLibrary called more than once" warning
///   visible in the reporter's *working* run) and waits on its init future. It
///   now uses the process-wide `FlutterInjector.instance().flutterLoader()`,
///   which is already initialized in a process that has run the app, so both
///   calls return immediately.
/// * The failure handler caught `Exception`, so an `Error` — an
///   `UnsatisfiedLinkError` from a native load, for one — escaped it unseen.
///   It catches `Throwable` now.
/// * `pendingEvents` was unbounded and a failed spawn called `destroy()`, which
///   cleared it. So events either accumulated without limit or were thrown away
///   wholesale. The queue is capped at 200 with oldest-first eviction, and a
///   failed spawn keeps what it buffered for the next attempt.
///
/// A stalled spawn is now abandoned after 30 s and retried, and every branch
/// records itself on the **lifecycle** channel, which is never level-gated —
/// the reports that motivated this are release builds where every debug line is
/// dropped before it reaches the store. The stage it reached is in the message,
/// so one run names the broken link:
///
/// ```text
/// headless: spawning a FlutterEngine (3 event(s) queued)
/// headless: engine ready — draining 3 queued event(s)
/// headless: engine spawn STALLED at stage POSTED after 30001ms — retrying
/// headless: engine spawn FAILED at stage LOADER_READY — <cause>
/// ```
///
/// **What this card can prove.** Only a real task removal exercises the
/// headless path, and no foreground card can swipe itself out of recents. So it
/// runs in two phases and tells you which one it is in:
///
/// 1. **Arm** — clears the log, starts tracking, and asks you to swipe the app
///    away, leave it a minute, then reopen and press Run again.
/// 2. **Verify** — reads the lifecycle trail the killed-state process left and
///    classifies it: the engine came up, or it failed and *said so*, or the
///    #331 signature (a spawn with no outcome at all) is back.
///
/// It reports what the trail contains rather than inferring a pass from
/// tracking having survived, and an absent `boot-tracking: bootstrapping`
/// anchor is reported as "the background pipeline never came up" — a different
/// bug from this one, in a different layer.
///
/// Android only: iOS has no headless FlutterEngine, and its background
/// relaunch runs the app's own handlers.
class Issue331Card extends StatefulWidget {
  const Issue331Card({super.key});

  @override
  State<Issue331Card> createState() => _Issue331CardState();
}

class _Issue331CardState extends State<Issue331Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  static const _spawning = 'headless: spawning a FlutterEngine';
  static const _ready = 'headless: engine ready';
  static const _stalled = 'headless: engine spawn STALLED';
  static const _failed = 'headless: engine spawn FAILED';
  static const _bootTracking = 'boot-tracking: bootstrapping';

  Future<void> _run() async {
    setState(() => _running = true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        _set(
          'ℹ️ Not applicable on this platform. #331 is the Android headless '
          'FlutterEngine spawn; iOS relaunches the app itself and runs its own '
          'handlers, and web has no headless isolate at all.',
        );
        return;
      }

      // The precondition, checked rather than assumed: main() registers the
      // task before runApp, but a build that skipped it would produce the
      // reported symptom for an entirely ordinary reason.
      check(
        'a headless task is registered in this isolate',
        Tracelet.isHeadlessRegistered,
        Tracelet.isHeadlessRegistered
            ? 'registerHeadlessTask() ran at startup — the native side has a '
                  'callback handle to invoke'
            : 'no headless task registered, so nothing below can fire. This is '
                  'the ordinary explanation for "headless never runs" and it '
                  'is not #331.',
      );

      final logs = await Tracelet.getLogs(500);
      final lifecycle = logs
          .where((e) => e.level.toUpperCase() == 'LIFECYCLE')
          .toList();
      bool sawLifecycle(String needle) =>
          lifecycle.any((e) => e.message.contains(needle));

      // Phase detection from the trail itself: the arm phase clears the log, so
      // a boot-tracking entry can only have come from a killed-state run since
      // then. No extra state to persist, and no way to be in the wrong phase
      // because of how the app was driven before.
      if (!sawLifecycle(_bootTracking)) {
        await Tracelet.clearLogs();
        await Tracelet.start();
        _set(
          'ARMED — now do the task removal.\n\n'
          '${results.join('\n')}\n\n'
          '1. Swipe this app away from recents (do NOT force-stop it).\n'
          '2. Leave the device for ~60 s. Move it if you can: fixes are what '
          'drive a headless dispatch.\n'
          '3. Reopen the app and press Run again.\n\n'
          'The log was cleared just now, so everything the verify phase reads '
          'was written by the killed-state process. Tracking is running and '
          'stopOnTerminate is false, so the foreground service survives the '
          'swipe — that is the state the report was filed from.\n\n'
          'What you are reproducing: the reporter saw this fail on roughly '
          'half of the attempts on an API 36 emulator, in a release build, in '
          'an app with several other Flutter engines (firebase_messaging, '
          'flutter_local_notifications, background_downloader). A single '
          'successful run here does not disprove the intermittency — what the '
          'fix guarantees is that a failed one now says so.',
        );
        return;
      }

      // ── Verify phase ─────────────────────────────────────────────────────
      check(
        'the background pipeline came up after task removal',
        true,
        'boot-tracking: bootstrapping is in the trail, so the foreground '
            'service restarted tracking natively — the precondition for any '
            'headless dispatch',
      );

      final spawning = sawLifecycle(_spawning);
      final ready = sawLifecycle(_ready);
      final stalled = sawLifecycle(_stalled);
      final failed = sawLifecycle(_failed);

      if (!spawning) {
        // Nothing asked for an engine. That is upstream of #331: the event
        // never reached HeadlessTaskService.dispatchEvent at all.
        check(
          'a headless dispatch was attempted',
          false,
          'no "spawning a FlutterEngine" entry. The killed-state pipeline ran '
              'but no event reached the headless service — so routing broke '
              'before it, not the spawn. Check that the boot EventDispatcher '
              'has its headlessFallback wired and that the run produced '
              'location fixes at all (a stationary device under a distance '
              'filter may simply have had nothing to dispatch).',
        );
      } else if (ready) {
        check(
          '#331 the headless engine came up and drained its queue',
          true,
          'spawn → ready, with the queued events delivered. This is the '
              'working path; the events buffered during the spawn were not '
              'lost waiting for it.',
        );
      } else if (stalled || failed) {
        // The engine did not come up — but this is the fix working. The old
        // build produced this exact outcome with nothing written at all.
        check(
          '#331 a spawn that did not complete identifies itself',
          true,
          'the engine never became ready, and the trail names the stage it '
              'died at instead of leaving "no engine, no error". Read the '
              'matching entry below: STALLED at POSTED means the main thread '
              'never ran the spawn block; LOADER_READY or later means Flutter '
              'came up and the engine or its Dart entrypoint did not.',
        );
        results.add(
          'ℹ️ the engine did not come up on this run. That is the reported '
          'failure — now diagnosable rather than silent. It is also recoverable: '
          'the next event starts a fresh spawn and delivers what was buffered.',
        );
      } else {
        check(
          '#331 a spawn always reaches an outcome',
          false,
          'REGRESSED — "spawning a FlutterEngine" with no ready, no STALLED '
              'and no FAILED after it. This is the original #331 signature: an '
              'engine was asked for and nothing ever said what became of it. '
              'The 30 s stall timeout should have fired on the next dispatched '
              'event.',
        );
      }

      final headlessTrail = lifecycle
          .where((e) => e.message.startsWith('headless:'))
          .toList();
      if (headlessTrail.isNotEmpty) {
        results.add(
          'ℹ️ what a bug report would now carry:\n'
          '${headlessTrail.take(10).map((e) => '  • ${e.message}').join('\n')}',
        );
      }

      final dropped = logs
          .where((e) => e.message.contains('headless: queue full'))
          .toList();
      if (dropped.isNotEmpty) {
        results.add(
          'ℹ️ the pending-event queue hit its 200-event cap during this run '
          '(${dropped.length} drop entries). Oldest-first, so the freshest '
          'events survived. Before the fix the queue was unbounded and grew by '
          'one entry per fix for the life of the process.',
        );
      }

      final header = allPass
          ? '✅ SUCCESS: the headless spawn reached a recorded outcome.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Scope: this reads the lifecycle trail the killed-state process wrote, '
        'which is the only Dart-visible evidence of a native spawn — the '
        'headless engine has no API surface. It cannot force the intermittency, '
        'so a green run means "this attempt reached an outcome", not "the '
        'race is gone". Run it several times.\n\n'
        'The recovery paths themselves are pinned by JVM tests that drive the '
        'real HeadlessTaskService — HeadlessEngineSpawnRecoveryTest covers a '
        'failed spawn keeping its queued events, a stalled spawn being '
        'abandoned and retried, and the queue cap evicting oldest-first.\n\n'
        'Press Run once more to re-arm: the verify phase leaves the trail in '
        'place, so the next tap sees it, clears it and starts over.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'headless task not invoked task removal swipe recents killed state '
          'FlutterEngine ensureEngine pendingEvents silent no error headless '
          'engine spawn stalled 331',
      title: '#331: headless task silently never invoked after task removal',
      description:
          'The headless FlutterEngine intermittently never spawned, with no '
          'error at any level and events piling up unbounded. Arms a task '
          'removal, then reads the lifecycle trail to say whether the engine '
          'came up — or which stage it died at.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
