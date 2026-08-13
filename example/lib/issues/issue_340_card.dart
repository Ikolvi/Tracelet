import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #340 — the same app posted its own sync body on Android and the SDK
/// default on iOS.
///
/// The reported iOS request carried the Rust default shape (`location` +
/// `params`, one location per request) while Android posted the app's batched
/// `buildTraceletSyncBody()` envelope against the same server. The original
/// report also claimed `setRouteContext` was dropped on iOS; that part was a
/// misread of a stale stored row — route context is applied at record time and
/// is not retroactive, so rows persisted before the call legitimately lack it —
/// and it was withdrawn. The wrong *body* was real.
///
/// **The cause.** `hasCustomSyncBodyBuilder` only ever reflects the
/// **foreground** isolate: Dart sets it from `setSyncBodyBuilder`. Both
/// platforms opened `requestSyncBody` with
///
/// ```swift
/// if !hasCustomSyncBodyBuilder { return traceletNoSyncBodyBuilderSentinel }
/// ```
///
/// and only *below* that consulted the headless builder. So a process whose
/// Dart never ran the app code that calls `setSyncBodyBuilder` — iOS's
/// background relaunch, launched by a location event with nobody driving the
/// UI, which is exactly the `resume=true` session the report came from — read
/// `false` there and posted the default payload, with
/// `registerHeadlessSyncBodyBuilder`'s callback sitting registered and usable
/// the whole time.
///
/// This example registers the headless builder in `main()` and the foreground
/// one in `_initialize()`, behind the Initialize button. A relaunched process
/// runs the first and not the second, which is why the same build posted two
/// different bodies.
///
/// Android was less exposed but had the same ordering: its engine-less
/// processes are covered by `HeadlessSyncInterceptor`, installed from a
/// ContentProvider at process start, which routes straight to the headless
/// builder. That seam does not exist on iOS, and it does not help an *attached*
/// engine whose Dart has not registered a foreground builder — the gap fixed
/// here on both platforms.
///
/// **What this card can prove.** `setSyncBodyBuilder(null)` puts the SDK into
/// the exact state the relaunched process is in: no foreground builder, a
/// headless builder registered. A sync from there must still send the app's
/// body. The evidence is the always-on `sync-body:` lifecycle line added in
/// #341, which names which body each sync posted:
///
/// ```text
/// sync-body: posting the app's custom sync body
/// sync-body: posting the DEFAULT payload — no custom sync body builder reached native
/// ```
///
/// It is written on *transition*, so the card establishes a known source first
/// and then asserts that clearing the foreground builder does not flip it to
/// the default payload. Whether a sync ran at all is taken from `onHttp`, which
/// fires per attempt regardless of the outcome — the transition line cannot
/// answer that, and reading it as if it could made an ordinary "source did not
/// change" run look like a failure.
///
/// Building this card surfaced a second gap: on Android only `triggerSync` —
/// the debounced auto-sync — reported the source. `syncBatchBlocking`, which is
/// what a manual `sync()` and the killed-state paths call, reported nothing at
/// all, so those syncs left no trail on Android while iOS (which reports from
/// inside its own `syncBatchBlocking`) did. Both entry points report now.
///
/// **What it does not prove.** That a real iOS background relaunch behaves this
/// way — no foreground card can relaunch itself. It reproduces the *state* that
/// relaunch produces, which is what the fix turns on. The HTTP POST itself may
/// well fail (the demo URL points at a test server that is probably not
/// running); that is irrelevant here, because the body is chosen and reported
/// before the request goes out.
class Issue340Card extends StatefulWidget {
  const Issue340Card({super.key});

  @override
  State<Issue340Card> createState() => _Issue340CardState();
}

class _Issue340CardState extends State<Issue340Card>
    with IssueCardRun<Issue340Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  /// Mirrors `buildTraceletSyncBody` in `main.dart` — the same envelope the
  /// app's foreground and headless builders both produce. Kept local rather
  /// than imported: `main.dart` imports this file's tab, and a card should not
  /// depend on the app shell to run.
  Map<String, Object?> _body(List<Map<String, Object?>> locations) =>
      <String, Object?>{
        'device': 'tracelet-example',
        'sentAt': DateTime.now().toUtc().toIso8601String(),
        'locationCount': locations.length,
        'locations': locations,
      };

  static const _defaultPayloadMarker = 'posting the DEFAULT payload';

  var _httpEvents = 0;

  /// Persists one location and syncs, so a body is actually built.
  Future<void> _syncOnce() async {
    await Tracelet.insertLocation(<String, Object?>{
      'coords': <String, Object?>{'latitude': 10.86077, 'longitude': 76.65026},
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    try {
      await Tracelet.sync();
    } catch (_) {
      // The demo URL points at a local test server that may not be running.
      // The body is chosen and reported before the POST, which is all this
      // card reads.
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }

  Future<List<String>> _syncBodyLines() async {
    final logs = await Tracelet.getLogs(300);
    return logs
        .where((e) => e.level.toUpperCase() == 'LIFECYCLE')
        .map((e) => e.message)
        .where((m) => m.startsWith('sync-body:'))
        .toList();
  }

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    StreamSubscription<HttpEvent>? httpSub;

    try {
      if (kIsWeb) {
        _set(
          'ℹ️ Not applicable on web — there is no native sync pipeline and no '
          'headless isolate to fall back to.',
        );
        return;
      }

      await Tracelet.clearLogs();

      // A sync attempt emits an http event whether the POST succeeds or not,
      // which is how this card knows a sync actually ran. The `sync-body:` line
      // cannot serve as that precondition: it is written only when the source
      // *changes*, so a process already posting the custom body says nothing —
      // "no entry" would then mean both "nothing synced" and "nothing changed".
      _httpEvents = 0;
      httpSub = Tracelet.onHttp((_) => _httpEvents++);

      // 1. Establish a known source: a foreground builder, registered here so
      //    the card does not depend on the Initialize button having been
      //    pressed.
      await Tracelet.setSyncBodyBuilder(
        (SyncBodyContext context) async => _body(context.locations),
      );
      await _syncOnce();

      final syncsRan = _httpEvents;
      check(
        'a sync actually ran',
        syncsRan > 0,
        syncsRan > 0
            ? '$syncsRan sync attempt(s) reported over onHttp — a body was '
                  'built, so the rows below are about which one'
            : 'no sync attempt at all, so nothing below is conclusive. Check '
                  'that http.url is configured and that the inserted location '
                  'landed in the database.',
      );

      final afterForeground = await _syncBodyLines();
      results.add(
        afterForeground.isEmpty
            ? 'ℹ️ no sync-body transition recorded while the foreground builder '
                  'was registered — expected when the process was already '
                  'posting the custom body, since the line marks a change of '
                  'source rather than each sync.'
            : 'ℹ️ source with the foreground builder registered: '
                  '"${afterForeground.last}"',
      );

      // 2. Reproduce the relaunched-process state: no foreground builder, the
      //    headless one still registered from main().
      await Tracelet.setSyncBodyBuilder(null);
      final before = (await _syncBodyLines()).length;
      await _syncOnce();
      final after = await _syncBodyLines();
      final newLines = after.skip(before).toList();

      final fellBackToDefault = newLines.any(
        (m) => m.contains(_defaultPayloadMarker),
      );
      check(
        '#340 clearing the foreground builder does not fall back to the '
        'default payload',
        !fellBackToDefault,
        fellBackToDefault
            ? 'REGRESSED — "${newLines.firstWhere((m) => m.contains(_defaultPayloadMarker))}". '
                  'A headless builder is registered and reachable; this is the '
                  'reported bug, and on iOS it is what a background relaunch '
                  'produced on every sync.'
            : newLines.isEmpty
            ? 'the posted body did not change source when the foreground '
                  'builder went away — the headless builder took over silently, '
                  'which is the fix working'
            : 'source after clearing: "${newLines.last}"',
      );

      // Restore the foreground builder so the rest of the app behaves as the
      // home page expects.
      await Tracelet.setSyncBodyBuilder(
        (SyncBodyContext context) async => _body(context.locations),
      );

      final header = allPass
          ? '✅ SUCCESS: a registered headless builder serves the body when the '
                'foreground one is absent.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Trail from this run:\n'
        '${after.isEmpty ? '  (none)' : after.map((m) => '  • $m').join('\n')}\n\n'
        'Scope: this reproduces the *state* an iOS background relaunch leaves '
        'the SDK in — headless builder registered, foreground builder never '
        'registered — and checks the body chosen from there. It cannot force a '
        'real relaunch. The HTTP POST may fail (the demo URL is a local test '
        'server); the body is chosen and reported before the request, so that '
        'does not affect the result.\n\n'
        'On the withdrawn half of the report: route context was never missing '
        'on iOS. The 250-location batch is ordered oldest-first and the '
        'boundary was visible inside it — rows before setRouteContext ran '
        'lacked extras.route_context, rows after it carried it. Route context '
        'is applied at record time and is not retroactive.\n\n'
        'The routing decision itself is pinned by SyncBodyHeadlessFallbackTest '
        '(Android JVM): a registered headless builder is consulted when the '
        'foreground one is absent, and with nothing registered anywhere the '
        '#125 immediate sentinel still comes back so the sync posts the '
        'default payload instead of aborting.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await httpSub?.cancel();
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'sync body builder custom body default payload headless relaunch '
          'setSyncBodyBuilder registerHeadlessSyncBodyBuilder route context '
          'ios android parity 340',
      title:
          '#340: iOS posted the default payload while a builder was registered',
      description:
          'hasCustomSyncBodyBuilder only reflects the foreground isolate, so a '
          'relaunched process fell back to the SDK default with a headless '
          'builder registered. Clears the foreground builder and checks which '
          'body the next sync posts.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
