import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #326 — `Config.toMap()` emitted sixteen empty sections for a config
/// that set nothing, because every per-section guard was dead code.
///
/// #321 made the whole model unset-aware, and a follow-up found that
/// `if (filter != null)` and `if (foregroundService != null)` could never be
/// false — those getters resolve to a non-null object even when unset — so every
/// payload still carried `geo: {'filter': {}}` and
/// `android: {'foregroundService': {}}`.
///
/// `Config.toMap()` had the identical construct for all sixteen **sections**,
/// dead for the identical reason: the fields are non-nullable with
/// `const GeoConfig()`-style defaults. So `const Config().toMap()` returned
/// `{geo: {}, app: {}, android: {}, …}` — sixteen empty maps. The analyzer had
/// been reporting every one of them, which is what made `melos analyze` fail.
///
/// Nothing downstream read them, which is what made the fix safe: the wire
/// format is the Pigeon `toTlConfig()`, not this; `Config.fromMap` falls back
/// through an absent section; and `Tracelet.activeConfig` is a *resolved* config
/// after `ready()`, so every section still carries fields and the Doctor's
/// config dump is unchanged. But a partial update that changes nothing should
/// not look like it touched every section — least of all in a pasted bug report,
/// which is where this payload is actually read by a human.
///
/// `AttestationToken.toMap()` lost the same dead guards. A token is a *result*,
/// not a partial configuration, so #321's omit-unset rule never applied to it,
/// and `token`/`timestamp`/`provider` are non-nullable — guarding them implied a
/// token could arrive without one.
///
/// Every check here is pure serialization, so this card runs on web too and
/// needs no permissions and no tracking session.
class Issue326Card extends StatefulWidget {
  const Issue326Card({super.key});

  @override
  State<Issue326Card> createState() => _Issue326CardState();
}

class _Issue326CardState extends State<Issue326Card> {
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
      // ---------------------------------------------------------------------
      // The payload itself, asserted at the top level.
      // ---------------------------------------------------------------------
      final empty = const Config().toMap();
      check(
        '#326 const Config() emits no sections at all',
        empty.isEmpty,
        empty.isEmpty
            ? 'the payload is {} — a setConfig() that configures nothing sends '
                  'nothing, at every depth'
            : 'REGRESSED — still emits ${empty.length} section(s): '
                  '${empty.keys.join(', ')}',
      );

      // The counterpart, and the reason the row above is not vacuous: an empty
      // payload must mean "nothing was supplied", not "toMap() stopped
      // emitting". Without this a serializer returning {} unconditionally would
      // satisfy every other row on this card.
      final oneField = const Config(
        app: AppConfig(heartbeatInterval: 30),
      ).toMap();
      final exactlyOne =
          oneField.length == 1 &&
          (oneField['app'] as Map<String, Object?>?)?['heartbeatInterval'] ==
              30;
      check(
        'a section appears as soon as it carries a field',
        exactlyOne,
        exactlyOne
            ? 'setting one field emits exactly one section carrying exactly '
                  'that field — the empty payload above is real, not a broken '
                  'serializer'
            : 'REGRESSED — emits ${oneField.keys.join(', ')}; if this fails the '
                  'row above proves nothing',
      );

      // ---------------------------------------------------------------------
      // The nested rule #321 already fixed, re-asserted where it is now
      // observable: a section that IS present must still omit an unset sub-map.
      // ---------------------------------------------------------------------
      final androidSection =
          const Config(
                android: AndroidConfig(locationUpdateInterval: 5000),
              ).toMap()['android']!
              as Map<String, Object?>;
      final geoSection =
          const Config(geo: GeoConfig(distanceFilter: 25)).toMap()['geo']!
              as Map<String, Object?>;
      final subMapsOmitted =
          !androidSection.containsKey('foregroundService') &&
          !geoSection.containsKey('filter');
      check(
        'a present section still omits its unset sub-maps',
        subMapsOmitted,
        subMapsOmitted
            ? 'android carries locationUpdateInterval with no '
                  'foregroundService, and geo carries distanceFilter with no '
                  'filter'
            : 'REGRESSED — android=${androidSection.keys.join(', ')}; '
                  'geo=${geoSection.keys.join(', ')}',
      );

      // ---------------------------------------------------------------------
      // ready() must still pin everything. Dropping empty sections is only safe
      // because the baseline is established explicitly — otherwise a fresh
      // install would depend on each platform's own defaults matching Dart's.
      // ---------------------------------------------------------------------
      final resolved = const Config().resolved().toMap();
      check(
        'ready() still sends a complete baseline',
        resolved.length >= 10 &&
            resolved.values.every((v) => v is Map && v.isNotEmpty),
        resolved.length >= 10 &&
                resolved.values.every((v) => v is Map && v.isNotEmpty)
            ? '${resolved.length} sections, every one populated — omission is '
                  'safe because resolved() states every value explicitly'
            : 'REGRESSED — resolved() emits ${resolved.length} section(s), so '
                  'omitting unset fields would leave the platform guessing',
      );

      // A round trip must not turn "unset" into "explicitly the default", and it
      // must survive sections being absent — Config.fromMap(toMap()) is a real
      // path (the battery-budget engine and remote config both use it), and an
      // absent section now takes fromMap's flat-format fallback.
      const partial = Config(
        geo: GeoConfig(distanceFilter: 25),
        ios: IosConfig(preventSuspend: true),
      );
      final roundTripped = Config.fromMap(partial.toMap()).toMap();
      final roundTripsClean =
          roundTripped.toString() == partial.toMap().toString();
      check(
        'a sparse payload round-trips unchanged',
        roundTripsClean,
        roundTripsClean
            ? 'fromMap(toMap()) is identity on a two-section config, so the '
                  'absent sections did not inflate into explicit defaults'
            : 'REGRESSED — round-tripped to $roundTripped instead of '
                  '${partial.toMap()}',
      );

      // ---------------------------------------------------------------------
      // AttestationToken: a result, not a partial config.
      // ---------------------------------------------------------------------
      final token = AttestationToken(
        token: 'abc',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        provider: 'play_integrity',
      );
      final tokenMap = token.toMap();
      final tokenComplete =
          tokenMap['token'] == 'abc' &&
          tokenMap['timestamp'] == 1700000000000 &&
          tokenMap['provider'] == 'play_integrity' &&
          !tokenMap.containsKey('verified');
      check(
        '#326 an attestation token serializes every field it always has',
        tokenComplete,
        tokenComplete
            ? 'token, timestamp and provider are always present; verified is '
                  'absent until a server sets it — the omit-unset rule applies '
                  'to config, not to results'
            : 'REGRESSED — emits $tokenMap',
      );

      final verified = AttestationToken(
        token: 'abc',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        provider: 'app_attest',
        verified: true,
      ).toMap();
      check(
        'a verified token carries the verdict',
        verified['verified'] == true,
        verified['verified'] == true
            ? 'verified=true is transmitted once it exists'
            : 'REGRESSED — the verdict is being dropped: $verified',
      );

      final header = allPass
          ? '✅ SUCCESS: an unset Config serializes to nothing at any depth, '
                'and a supplied field still reaches the platform.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Why this is only a payload change: the wire format is the Pigeon '
        'toTlConfig(), not toMap(). toMap() has three Dart-local callers, all '
        'of which already tolerated an absent section — the remote-config deep '
        'merge, the state backfill (Config.fromMap falls back through one), and '
        'the battery-budget adjustment (already written as '
        "map['geo'] as Map? ?? {}). And activeConfig is resolved() after "
        'ready(), so the Doctor config dump and the copied setup JSON are '
        'unchanged in practice.\n\n'
        'Where it is visible: a partial setConfig() payload, and therefore the '
        'bug reports and issue cards that inspect one. Sixteen empty sections '
        'made an update that changed nothing look like it had touched '
        'everything.\n\n'
        'This card runs on web: it is pure serialization, so it needs no '
        'permissions and no tracking session.',
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
          'config toMap setConfig partial section empty payload minimal '
          'serialize unset dead guard analyzer unnecessary_null_comparison '
          'attestation token resolved baseline round trip 326 321 320',
      title: '#326: an unset Config emits no sections, not sixteen empty ones',
      description:
          'Verifies that Config.toMap() drops a section that carries nothing — '
          'not just an unset nested sub-map — while a supplied field still '
          'appears, ready() still sends a complete baseline, and a sparse '
          'payload round-trips without inflating unset fields into defaults.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
