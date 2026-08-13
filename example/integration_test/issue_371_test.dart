import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';
import 'package:tracelet_example/foreign_fcm_engine.dart';

/// Issue #371 — on-device regression coverage for the event fan-out that has
/// no member able to receive.
///
/// The Robolectric tests
/// (`MultiEventSenderFallbackTest`, `PluginSecondaryEngineGuardTest`) pin the
/// routing decision and the wiring with mock bindings. What they cannot show is
/// the situation that produces it, which needs a second **real** FlutterEngine
/// in the process, built by another plugin: this drives
/// firebase_messaging's own background service and then reproduces the
/// post-task-removal state — fan-out emptied, SDK still holding it as its event
/// sender — and checks that a location dispatched into it reaches the headless
/// task instead of disappearing.
///
/// ```
/// flutter test integration_test/issue_371_test.dart -d <android-device>
/// ```
///
/// Android only, and a debug build: the probes read private fields
/// reflectively.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const debug = MethodChannel('com.tracelet/debug');

  Future<Map<String, dynamic>> state() async {
    final s = await debug.invokeMapMethod<String, dynamic>(
      'debugIssue371FanOutState',
    );
    return s ?? <String, dynamic>{};
  }

  Future<int> latestLogId() async {
    final logs = await Tracelet.getLogs(500);
    return logs.fold<int>(0, (max, e) => e.id > max ? e.id : max);
  }

  Future<List<String>> logsSince(int sinceId, String marker) async {
    final logs = await Tracelet.getLogs(500);
    return logs
        .where((e) => e.id > sinceId && e.message.contains(marker))
        .map((e) => e.message)
        .toList();
  }

  setUpAll(() async {
    await Tracelet.registerHeadlessTask(issue371HeadlessTask);
    await Tracelet.ready(const Config());
  });

  testWidgets('the real firebase_messaging engine stays out of the fan-out', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;

    final before = await state();
    final baselineEngines = before['engines'] as int;
    final baselineFanOut = before['fanOut'] as int;
    expect(
      baselineFanOut,
      greaterThanOrEqualTo(1),
      reason:
          'the fan-out must be readable and hold this app engine — run a '
          'debug build, release minification renames these fields',
    );

    expect(await ForeignFcmEngine.arm(), isNull);

    // FlutterFirebaseMessagingBackgroundService builds the engine on the main
    // thread; it is not up the instant onBackgroundMessage returns.
    var after = await state();
    for (
      var i = 0;
      i < 40 && (after['engines'] as int) <= baselineEngines;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      after = await state();
    }

    expect(
      after['engines'] as int,
      greaterThan(baselineEngines),
      reason:
          'firebase_messaging never created its background engine, so nothing '
          'was measured — check that onBackgroundMessage stored its handle',
    );
    expect(
      after['fanOut'] as int,
      baselineFanOut,
      reason:
          'the foreign engine joined the event fan-out — it will swallow every '
          'event once the UI engine dies (#364)',
    );
  });

  testWidgets('an emptied fan-out still reaches the headless task', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;

    expect(
      (await state())['headlessTaskRegistered'],
      isTrue,
      reason:
          'without a registered headless task, "routed and dropped" and "never '
          'routed" look the same from here',
    );

    final sinceId = await latestLogId();
    final probe = await debug.invokeMapMethod<String, dynamic>(
      'debugIssue371EmptyFanOutProbe',
    );

    expect(probe, isNotNull);
    expect(
      probe!['senderIsTheFanOut'],
      isTrue,
      reason:
          'the SDK must still hold MultiEventSender as its event sender — that '
          'is what makes an empty fan-out fatal rather than irrelevant',
    );
    expect(
      probe['restoredCount'],
      probe['emptiedCount'],
      reason: "the probe must put the app's own dispatcher back",
    );

    // The symptom first, the mechanism second: on a build without the fix this
    // is the assertion that should fail, and it fails saying what the reporter
    // saw rather than naming a field.
    await Future<void>.delayed(const Duration(seconds: 2));
    final routed = await logsSince(sinceId, 'routing to the headless task');
    final spawned = await logsSince(
      sinceId,
      'headless: spawning a FlutterEngine',
    );
    expect(
      routed.isNotEmpty || spawned.isNotEmpty,
      isTrue,
      reason:
          'the location sent into the empty fan-out reached nothing at all — '
          'this is #371',
    );

    expect(
      probe['fanOutFallbackWired'],
      isTrue,
      reason:
          'MultiEventSender.headlessFallback is null: with the members gone '
          'there is nothing left to fall back from (#371)',
    );
  });

  tearDownAll(() async {
    if (Platform.isAndroid) await ForeignFcmEngine.disarm();
  });
}

/// Registered so the headless route has somewhere to deliver. The probe's
/// synthetic fix is tagged `issue-371-probe`.
@pragma('vm:entry-point')
void issue371HeadlessTask(HeadlessEvent event) {}
