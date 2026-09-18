import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #415 — the Android permission Future was orphaned when the Activity
/// detached while the dialog was up.
///
/// `TraceletSdk.requestPermission()` parks the Pigeon reply in
/// `pendingPermissionCallback` and completes it from
/// `onRequestPermissionsResult`, which reaches the plugin through the listener
/// registered on the `ActivityPluginBinding`. `onDetachedFromActivity()`
/// removes that listener — and, since the 2.0.0 lifecycle rewrite, did nothing
/// about the reply. If the detach landed while the OS dialog was showing, the
/// only completion path was gone and `requestLocationAuthorization()` never
/// resolved. The *next* call short-circuited on the stale pending callback and
/// returned the current status synchronously, which is why "it works the
/// second time" was part of the report.
///
/// The SDK has had `clearPendingPermissionCallback()` for exactly this since
/// March; the plugin now calls it again on a full detach, before the activity
/// is dropped so the status it completes with can still tell DENIED from
/// NOT_DETERMINED. Not on the config-change detach — there the listener is
/// re-added on reattach and the dialog's result still arrives.
///
/// **What this card proves.** The detach itself cannot be triggered from Dart
/// — it is the host Activity being torn down under a live dialog — so the
/// lifecycle order is pinned by `PluginPermissionCallbackDetachTest`. This
/// card checks the contract the report was about from the app's side: on a
/// fresh install, the first `requestLocationAuthorization()` resolves within
/// the timeout the reporter used, and a second call resolves too, with the
/// same answer. On an install that has already answered the dialog both calls
/// resolve immediately, and the card says so rather than claiming more.
class Issue415Card extends StatefulWidget {
  const Issue415Card({super.key});

  @override
  State<Issue415Card> createState() => _Issue415CardState();
}

class _Issue415CardState extends State<Issue415Card>
    with IssueCardRun<Issue415Card> {
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, {required bool pass, required String detail}) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (!_isAndroid) {
        setStatus(
          'ℹ️ Android only. #415 is the Flutter plugin’s Activity lifecycle on '
          'Android; iOS completes its authorization request from the '
          'CLLocationManager delegate and has no equivalent detach.',
        );
        return;
      }

      await Tracelet.ready(
        const Config(
          http: HttpConfig(autoSync: false),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      final before = await Tracelet.getLocationAuthorization();
      final fresh = before == AuthorizationStatus.notDetermined;

      setStatus(
        fresh
            ? '⏳ Answer the location dialog — the Future must resolve within '
                  '10 s of your answer…'
            : '⏳ Requesting (already answered on this install)…',
      );

      // ---------------------------------------------------------------------
      // 1. The first request resolves.
      // ---------------------------------------------------------------------
      final sw = Stopwatch()..start();
      AuthorizationStatus? first;
      var timedOut = false;
      try {
        // The reporter's timeout, but measured from the dialog's dismissal is
        // impossible from here — so the budget is generous enough to answer.
        first = await Tracelet.requestLocationAuthorization().timeout(
          const Duration(seconds: 60),
        );
      } on TimeoutException {
        timedOut = true;
      }
      sw.stop();
      check(
        'the first requestLocationAuthorization() resolves',
        pass: !timedOut,
        detail: timedOut
            ? 'still pending after 60 s — the reply was orphaned'
            : 'resolved ${first!.name} in ${sw.elapsedMilliseconds} ms',
      );

      // ---------------------------------------------------------------------
      // 2. A second request is not blocked by stale pending state, and agrees.
      // ---------------------------------------------------------------------
      AuthorizationStatus? second;
      var secondTimedOut = false;
      try {
        second = await Tracelet.requestLocationAuthorization().timeout(
          const Duration(seconds: 10),
        );
      } on TimeoutException {
        secondTimedOut = true;
      }
      check(
        'a second request resolves and agrees with the first',
        pass: !secondTimedOut && second == first,
        detail: secondTimedOut
            ? 'still pending after 10 s'
            : second == first
            ? 'both ${second!.name}'
            : 'first ${first?.name}, second ${second!.name} — the second '
                  'answer came from a stale pending callback',
      );

      final header = allPass
          ? '✅ SUCCESS: the permission Future resolves, once per request.'
          : '❌ FAILED — #415 not satisfied on this build.';

      setStatus(
        '$header\n\n${results.join('\n')}\n\n'
        '${fresh ? 'This was a fresh install, so the dialog was shown and the Future resolved from its result.' : 'This install had already answered the dialog, so both calls resolved from the stored status without showing it. Uninstall and reinstall to exercise the dialog path.'}\n\n'
        'The detach the report describes — the host Activity torn down while '
        'the OS dialog is up — cannot be triggered from Dart. The plugin now '
        'completes the pending reply in onDetachedFromActivity(), before the '
        'activity is dropped, and leaves it alone on the config-change detach '
        'where the result still arrives after reattach; that order is pinned '
        'by PluginPermissionCallbackDetachTest.',
      );
    } catch (e) {
      setStatus('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'android permission requestLocationAuthorization future never '
          'resolves pending orphaned onDetachedFromActivity activity detach '
          'dialog clearPendingPermissionCallback 415',
      title: '#415: the permission Future survives an Activity detach',
      description:
          'onDetachedFromActivity() removed the only listener that completed a '
          'pending permission reply, so a dialog answered after a detach left '
          'requestLocationAuthorization() hanging forever and the next call '
          'answering from stale state. Requests twice and checks both resolve '
          'and agree; the detach order itself is pinned in the plugin’s tests.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
