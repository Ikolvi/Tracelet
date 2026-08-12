import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #368 — `telematicsUrl` was accepted everywhere and read nowhere.
///
/// The field was public, documented, and fully plumbed: Dart → Pigeon → both
/// native config managers → the Rust config struct, where it sat as
///
/// ```rust
/// /// URL to sync telematics data to.
/// pub telematics_url: Option<String>,
/// ```
///
/// and was never read again. `telematics_url` appeared exactly once in the
/// whole Rust codebase — that declaration. It never reached the sync provider
/// either: `SyncHttpConfig` had no telematics field, so the code that performs
/// the POST could not have consulted it. Telematics went to `HttpConfig.url`
/// inside `extras.__telematics` regardless, with no warning. A backend team
/// routing telematics to a separate service saw an endpoint that received zero
/// traffic and no explanation. Same shape as #361, where the persistence caps
/// were accepted and never enforced.
///
/// It now does what it always claimed. When set, telematics are POSTed to that
/// endpoint on their own request as `{"telematics": [...]}`, routed through the
/// sync provider so headers, timeouts, retry/backoff, 401 token refresh and SSL
/// pinning behave exactly as they do for locations. When unset — the default —
/// nothing changes: they stay in `extras.__telematics` on the location request,
/// so existing integrations are untouched.
///
/// Failure is accounted for separately from the location batch (#366): a failed
/// telematics POST leaves those rows unsynced for the next attempt and does not
/// take the locations down with it.
///
/// **What this card can and cannot prove.** Without a live endpoint it cannot
/// observe *which* host received a body — that needs the test server. What it
/// does prove is that the value survives into the running config, that a
/// telematics-only sync now issues an HTTP attempt of its own, and that when
/// that attempt fails the events are kept rather than silently settled.
class Issue368Card extends StatefulWidget {
  const Issue368Card({super.key});

  @override
  State<Issue368Card> createState() => _Issue368CardState();
}

class _Issue368CardState extends State<Issue368Card> {
  String _status = 'Idle';
  bool _running = false;

  /// Two distinct closed ports on loopback: connections are refused at once
  /// rather than hanging, and the two endpoints stay clearly separate.
  static const _locationUrl = 'http://127.0.0.1:9/locations';
  static const _telematicsUrl = 'http://127.0.0.1:9/telematics';

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final results = <String>[];
    var allPass = true;
    StreamSubscription<HttpEvent>? httpSub;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      await Tracelet.ready(
        const Config(
          http: HttpConfig(
            url: _locationUrl,
            telematicsUrl: _telematicsUrl,
            autoSync: false,
            syncTelematics: true,
            maxRetries: 0,
          ),
          logger: LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      final state = await Tracelet.getState();
      check(
        'telematicsUrl reaches the running config',
        state.config?.http.telematicsUrl == _telematicsUrl,
        'State.config reports ${state.config?.http.telematicsUrl} — this much '
            'always passed, including on the broken build, which is exactly '
            'why the gap was invisible',
      );

      var httpAttempts = 0;
      httpSub = Tracelet.onHttp((HttpEvent _) => httpAttempts++);

      await Tracelet.destroyTelematicsEvents();
      await Tracelet.destroyLocations();
      await Tracelet.simulateTelematicsEvent(
        eventType: 'harsh_cornering',
        severity: 0.6,
        latitude: 24.8607,
        longitude: 67.0011,
      );

      // Deliberately no locations: with an empty location queue the only thing
      // worth sending is the telematics, so any HTTP attempt at all had to have
      // been made on their behalf.
      await Tracelet.sync();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      check(
        'A telematics-only sync issues its own request',
        httpAttempts > 0,
        '$httpAttempts HTTP attempt(s) reported with an empty location queue — '
            'the telematics now travel on a request of their own instead of '
            'waiting for a location payload to hitch onto',
      );

      final after = await Tracelet.getTelematicsEvents(50);
      check(
        'A failed telematics POST keeps the events',
        after.length == 1 && !after.first.synced,
        '${after.length} event(s) still stored and unsynced after the refused '
            'POST — the dedicated endpoint is accounted for separately, so its '
            'failure queues rather than discards (#366)',
      );

      await Tracelet.destroyTelematicsEvents();
      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: telematicsUrl is honored and fails safely.'
          : '❌ FAILED — #368 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Confirming the body actually lands on the telematics host, and not '
        'the location host, needs a reachable endpoint — run the example test '
        'server and point the two URLs at different paths to watch them '
        'arrive separately. This card stops where honest local assertions stop. '
        'Note the default is unchanged: leave telematicsUrl unset and '
        'telematics keep riding the location request in extras.__telematics, '
        'so no existing backend has to move.',
      );
    } catch (e) {
      _set('❌ FAILED: $e\n\n${results.join('\n')}');
    } finally {
      await httpSub?.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'telematicsUrl HttpConfig separate endpoint telematics sync route '
          'accepted never used ignored syncTelematics __telematics extras '
          'dedicated URL backend routing',
      title: '#368: telematicsUrl was accepted but never used',
      description:
          'Asserts telematicsUrl survives into the running config, that a sync '
          'with an empty location queue now issues an HTTP attempt of its own '
          'for the telematics, and that a refused POST leaves them queued. The '
          'field was plumbed all the way to the Rust config struct and then '
          'read by nothing, so a separate telematics endpoint silently '
          'received no traffic at all.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
