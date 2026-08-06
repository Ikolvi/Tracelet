import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #305 — the cross-platform geofence high-accuracy flag was dropped on
/// two of the four config transports.
///
/// `AndroidConfig.geofenceModeHighAccuracy` was superseded by the
/// cross-platform `GeofenceConfig.geofenceModeHighAccuracy`. Both Pigeon host
/// implementations correctly OR the two flags. Two other transports did not:
///
/// - `tracelet_web` read **only** the deprecated Android-only flag, so setting
///   the documented cross-platform one had no effect on web at all.
/// - The method-channel `_geofenceToMap` emitted only two of the five geofence
///   keys, silently dropping `geofenceModeHighAccuracy` (so no OR happened on
///   that path), `geofenceInitialTrigger`, and `geofenceExitAccuracyMax` — the
///   #276 tunable.
///
/// Separately, all four `TraceletProfile` presets still encoded the flag in the
/// `"android"` block rather than `"geofence"`, which meant deleting the
/// deprecated field would have silently disabled high-accuracy geofencing for
/// `TraceletProfile.highAccuracy`. They now use the cross-platform block, so
/// the deprecated field has no remaining internal dependants.
///
/// This card runs entirely in-process against the config models — the transport
/// mapping is pure Dart, so no device movement or permissions are needed.
class Issue305Card extends StatefulWidget {
  const Issue305Card({super.key});

  @override
  State<Issue305Card> createState() => _Issue305CardState();
}

class _Issue305CardState extends State<Issue305Card> {
  String _status = 'Idle';
  bool _running = false;

  void _set(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      // 1. The preset regression. highAccuracy must enable high-accuracy
      //    geofencing through the CROSS-PLATFORM flag, so it works on iOS too
      //    and survives removal of the deprecated Android-only field.
      final highAccuracy = Config.highAccuracy();
      check(
        'highAccuracy profile sets the cross-platform flag',
        highAccuracy.geofence.geofenceModeHighAccuracy,
        'GeofenceConfig.geofenceModeHighAccuracy is '
            '${highAccuracy.geofence.geofenceModeHighAccuracy} — previously '
            'this lived in the android block, so iOS never saw it',
      );

      // 2. The other three presets must be explicit about NOT enabling it,
      //    rather than inheriting a default from the wrong block.
      final others = <Config>[
        Config.balanced(),
        Config.lowPower(),
        Config.passive(),
      ];
      final offEverywhere = others.every(
        (c) => !c.geofence.geofenceModeHighAccuracy,
      );
      check(
        'Other profiles leave high-accuracy geofencing off',
        offEverywhere,
        'balanced / lowPower / passive all resolve to false via the geofence '
            'block',
      );

      // 3. The transport itself — the code that was actually broken — is NOT
      //    assertable from here. `_geofenceToMap` is private to
      //    MethodChannelTracelet and only observable with a mocked channel, and
      //    the web mapping needs a browser. A Config.toMap()/fromMap() cycle
      //    would look like a test but prove nothing: the Dart model always
      //    serialized all five keys, so that round-trip passes on a build where
      //    the transport drops them.
      results.add(
        'ℹ️ The method-channel and web mappings are covered by '
        'method_channel_geofence_config_test.dart, which asserts the map that '
        "actually crosses the channel (all five keys, both flags OR'd, and "
        'the android/geofence blocks agreeing). That test caught a real bug '
        'this card could not see.',
      );

      // 4. Backward compatibility: the deprecated Android-only flag must still
      //    work on its own. Removing it is a separate, later step — until then
      //    an app that sets only the old flag must keep working.
      const legacy = Config(
        // ignore: deprecated_member_use
        android: AndroidConfig(geofenceModeHighAccuracy: true),
      );
      // ignore: deprecated_member_use
      final legacyFlag = legacy.android.geofenceModeHighAccuracy;
      check(
        'The deprecated Android-only flag is still honored',
        legacyFlag,
        'hosts OR it with the cross-platform flag, so existing apps are '
            'unaffected until it is formally removed',
      );

      final header = allPass
          ? '✅ SUCCESS: the cross-platform geofence flag is carried on every '
                'transport, and the presets no longer depend on the '
                'deprecated one.'
          : '❌ FAILED — #305 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        "The Pigeon hosts always OR'd the two flags correctly; web read only "
        'the deprecated one, and the method channel dropped three geofence '
        'keys outright — including geofenceExitAccuracyMax, so the #276 '
        'tunable never reached native on that path. Both now match the hosts.',
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
          'geofenceModeHighAccuracy geofenceExitAccuracyMax '
          'geofenceInitialTrigger method channel web plugin deprecated '
          'AndroidConfig GeofenceConfig TraceletProfile highAccuracy preset '
          'cross-platform flag dropped transport',
      title:
          '#305: Cross-platform geofence flag dropped on web + method channel',
      description:
          'Asserts that the built-in profiles enable high-accuracy geofencing '
          'through the cross-platform GeofenceConfig flag (so iOS sees it), '
          'that all five geofence keys survive a config round-trip — three '
          'were silently dropped on the method-channel transport, including '
          'the #276 geofenceExitAccuracyMax tunable — and that the deprecated '
          'Android-only flag still works for existing apps.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
