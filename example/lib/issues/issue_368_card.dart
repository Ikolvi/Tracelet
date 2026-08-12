import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/test_server_endpoint.dart';

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
/// **Run it against the test server.** Start `dart run example/test_server.dart`
/// and scan its QR code first. The card then points `url` at the scanned
/// `/locations` and `telematicsUrl` at `/telematics` on the same server, syncs a
/// driving event with an empty location queue, and asserts the POST came back
/// successful — which can only have happened on the telematics endpoint, since
/// there were no locations to send. The server console shows the body landing on
/// `/telematics` with its `speed`/`value` intact, which is the half no in-app
/// assertion can make.
///
/// Without a scanned server it still runs, using refused ports: it checks the
/// config plumbing and that a failed telematics POST keeps the events queued
/// rather than settling them. That half proves the fix is safe; the live half
/// proves it is routed.
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
      // Paired with the test server? Then the live half can run. Unpaired is a
      // configuration state, not a failure — the offline half still proves the
      // fix is safe.
      final scanned = scannedSyncUrl();
      final liveTelematicsUrl = scanned == null
          ? null
          : siblingEndpoint(scanned, 'telematics');
      final live = scanned != null && liveTelematicsUrl != null;

      final locationUrl = live ? scanned : _locationUrl;
      final telematicsUrl = live ? liveTelematicsUrl : _telematicsUrl;

      await Tracelet.ready(
        Config(
          http: HttpConfig(
            url: locationUrl,
            telematicsUrl: telematicsUrl,
            autoSync: false,
            syncTelematics: true,
            maxRetries: 0,
          ),
          logger: const LoggerConfig(logLevel: LogLevel.debug),
        ),
      );

      final state = await Tracelet.getState();
      check(
        'telematicsUrl reaches the running config',
        state.config?.http.telematicsUrl == telematicsUrl,
        'State.config reports ${state.config?.http.telematicsUrl} — this much '
            'always passed, including on the broken build, which is exactly '
            'why the gap was invisible',
      );

      var httpAttempts = 0;
      var httpSuccesses = 0;
      httpSub = Tracelet.onHttp((HttpEvent e) {
        httpAttempts++;
        if (e.success) httpSuccesses++;
      });

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
      await Future<void>.delayed(const Duration(milliseconds: 800));

      check(
        'A telematics-only sync issues its own request',
        httpAttempts > 0,
        '$httpAttempts HTTP attempt(s) reported with an empty location queue — '
            'the telematics now travel on a request of their own instead of '
            'waiting for a location payload to hitch onto',
      );

      final after = await Tracelet.getTelematicsEvents(50);

      if (live) {
        // A 200 with nothing but telematics to send is the routing proof: the
        // location queue was empty, so the request that succeeded was theirs.
        check(
          'The telematics endpoint accepted the request',
          httpSuccesses > 0,
          '$httpSuccesses successful POST(s) against $telematicsUrl — check '
              'the server console: the body arrived on /telematics, not on '
              '/locations, carrying speed and value (#367)',
        );
        check(
          'A delivered event is marked synced, not deleted',
          after.length == 1 && after.first.synced,
          '${after.length} event(s) still readable and '
              '${after.first.synced ? 'marked synced' : 'still unsynced'} — '
              'uploading must settle the row without removing it from local '
              'history (#313, #366)',
        );
      } else {
        check(
          'A failed telematics POST keeps the events',
          after.length == 1 && !after.first.synced,
          '${after.length} event(s) still stored and unsynced after the '
              'refused POST — the dedicated endpoint is accounted for '
              'separately, so its failure queues rather than discards (#366)',
        );
      }

      await Tracelet.destroyTelematicsEvents();
      await Tracelet.stop();

      final header = allPass
          ? (live
                ? '✅ SUCCESS: telematics were routed to telematicsUrl and '
                      'accepted.'
                : '✅ SUCCESS (offline half): telematicsUrl is honored and '
                      'fails safely.')
          : '❌ FAILED — #368 not satisfied on this build. See the failing rows.';

      final mode = live
          ? 'Ran against the scanned test server: $telematicsUrl. The console '
                'there is the other half of this proof — the body lands on '
                '/telematics rather than /locations, which is the thing no '
                'in-app assertion can see.'
          : 'Ran offline against refused ports, which is why there is no '
                'routing row: proving a body reached a particular host needs a '
                'host that answers. Start `dart run example/test_server.dart`, '
                'scan its QR, and run this card again for the live half.';

      _set(
        '$header\n\n${results.join('\n')}\n\n$mode\n\n'
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
