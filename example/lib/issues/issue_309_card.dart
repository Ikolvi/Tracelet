import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issues #309–#314 — crash-ML and telematics wiring fixes.
///
/// Six defects found while auditing how driving events and crash detection feed
/// the opt-in AI crash model:
///
/// - **#309 (critical)** — a model declaring feature names the SDK cannot supply
///   loaded "successfully", scored an all-zero feature vector, and — because a
///   probability of `0.0` still satisfies `crashProba >= 0` — held the detector
///   in ML *Replace* mode, silently bypassing the g-threshold rule. Crash
///   detection was dead while the SDK reported the model ready.
/// - **#310** — `peak_g`/`mean_g`/`gyro_peak_dps` came from a 1 s window while
///   the model was trained on 16 s windows (`speed_max`/`dv` already used 16 s),
///   so the feature vector straddled two time bases.
/// - **#311** — iOS wrote `crashModel` from a background queue and read it on the
///   main run loop with no lock (Android used `@Volatile`).
/// - **#312** — the crash speed gate used the latest fix, which after an impact
///   is often already the post-crash speed, failing the gate and losing the
///   crash.
/// - **#313** — `getTelematicsEvents()` returned the *oldest* events and only the
///   *unsynced* ones, so it contradicted its own docs and emptied out once
///   `syncTelematics` was on.
/// - **#314** — the model cache was keyed by a fixed filename rather than by URL,
///   and the iOS cache directory was never created.
///
/// What this card can actually prove at runtime differs per fix. #309 and #313
/// are observable from Dart and are asserted here. #310, #311, #312 and #314 are
/// internal to the native pipeline — they are covered by the Rust unit tests and
/// reported below as context rather than pretended to be verified.
class Issue309Card extends StatefulWidget {
  const Issue309Card({super.key});

  @override
  State<Issue309Card> createState() => _Issue309CardState();
}

class _Issue309CardState extends State<Issue309Card> {
  String _status = 'Idle';
  bool _running = false;

  static const _debug = MethodChannel('com.tracelet/debug');

  /// Deterministic key shared with the #183 crash-model integration tests.
  static const _keyB64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';

  /// A valid 2-tree forest over `peak_g` (a supported name). peak_g=3.0 →
  /// tree A(>2)=0.9, tree B(<=5)=0.4 → average 0.65.
  static const _validBlobB64 =
      'AQABAgMEBQYHCAkKCzwgsH6kkbdp6DK1serLCAjivdhT0iZzXlsLhPZuDHOQO0ue0J6c'
      'ProA1hqI+6USY5V7Bug7otaoWrUQQijP2NzcEfQn//NSCW4x2QaA42rKAtH7TEZPflrT'
      'zbLhSt6J0OfaOo7NLaxo+3Jh3i0TVV2APFOHzvQJt3yie+/hjgdi3yBlqOulojRglWqb'
      'Zuhg7wfYzgRoPbE87TOdEtjosrWip7Ik2aLgJZ5P7Kfz27eXpJOXX6fQUdoAvrSyA6CV'
      'yUh8ptc/8fv7anrxktIzvPeJEZQSHzrhxF+htupzZr/WbhH6n7sMIUY6LtRsx3QSDsT2'
      '3wG/CtKUO0ZWX6atH602spr58b46WxmAAG7QRU4o4O/44a26rYJAckFzfJXWPmQh5BPh'
      '8+ImpmEWATy5lI60kWtyeKSSSuVsYNUEf7FJgWSGEDvh3DI7nec=';

  /// The same forest shape declaring the feature names an older training
  /// notebook exported. Decrypts and parses cleanly — only the names are wrong.
  static const _mismatchedBlobB64 =
      'AQECAwQFBgcICQoLDH7IPLCN4IX0KdFBfUsxi0shJo2h8E9858Ymi0vB0ga2psi5rB7Q'
      'ifvvx9eN54bUf/2aLpOn/EVTDCY84V5cGC4DD25GzNNnuzAw1h+aTHbVuBIKc9IF0/JW'
      'u6RWDNxUS+WjHxXQKGpHz42jC5vaNf62tAv141ehM18Pkq7V/UlGZQldyY+/ABLQ83PQ'
      '2O+cbPWmELO9rmIO90MI8zEKM3CaHhezSAcJb6XkoqviSp1RQ75r2qbqDIXoPuAe/w2U'
      'wVgv6sOuYBf2oiR+tPX45AxdGqMH6r1ph0wV89XcBQ==';

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
      await Tracelet.ready(const Config());

      // ── #309: the model loader must reject an unusable feature contract ──
      // The debug method channel is wired in the example's Android MainActivity
      // only, so this half of the card is Android-only.
      final canProbeModel = !kIsWeb && Platform.isAndroid;
      if (canProbeModel) {
        // A good model must still load — validation that rejects everything
        // would "fix" #309 by breaking the feature.
        try {
          final ok = await _debug.invokeMapMethod<String, Object?>(
            'debugCrashModelPredict',
            {
              'blob': _validBlobB64,
              'key': _keyB64,
              'features': <double>[3],
            },
          );
          final proba = (ok?['proba'] as num?)?.toDouble() ?? -1;
          check(
            '#309 a model with supported feature names still loads and scores',
            ok?['treeCount'] == 2 && (proba - 0.65).abs() < 1e-6,
            'treeCount=${ok?['treeCount']} proba=${proba.toStringAsFixed(4)} '
                '(expected 2 trees, 0.65)',
          );
        } catch (e) {
          check(
            '#309 a model with supported feature names still loads and scores',
            false,
            'a valid model was rejected: $e',
          );
        }

        // The regression itself: mismatched names must fail the load.
        try {
          await _debug.invokeMapMethod<String, Object?>(
            'debugCrashModelPredict',
            {
              'blob': _mismatchedBlobB64,
              'key': _keyB64,
              'features': <double>[3],
            },
          );
          check(
            '#309 a model with unsupported feature names is rejected',
            false,
            'REGRESSED — the model loaded. It would score an all-zero vector '
                'on every window and, because proba 0.0 still satisfies '
                'crashProba >= 0, hold the detector in ML Replace mode with the '
                'g-threshold rule bypassed: crash detection silently dead.',
          );
        } on PlatformException catch (e) {
          final named = (e.message ?? '').contains('accel_g');
          check(
            '#309 a model with unsupported feature names is rejected',
            named,
            named
                ? 'rejected at load, naming the offending feature: ${e.message}'
                : 'rejected, but the error does not name the bad feature: '
                      '${e.message}',
          );
        }
      } else {
        results.add(
          'ℹ️ #309 model-load probe skipped — the debug method channel is '
          "wired in the example's Android MainActivity only. The validation "
          'itself lives in the shared Rust core, so it is identical on iOS.',
        );
      }

      // ── #313: history is newest-first and survives the sync flag ──
      await Tracelet.destroyTelematicsEvents();
      const inserted = <String>[
        'harsh_braking',
        'harsh_cornering',
        'speeding',
        'crash',
      ];
      for (final kind in inserted) {
        await Tracelet.simulateTelematicsEvent(
          eventType: kind,
          severity: 0.5,
          latitude: 10.78,
          longitude: 76.68,
        );
      }

      final history = await Tracelet.getTelematicsEvents(50);
      check(
        '#313 history returns every stored event',
        history.length == inserted.length,
        'got ${history.length}, expected ${inserted.length} '
            '(${history.map((e) => e.eventType).join(', ')})',
      );

      // The documented contract is "most recent first". The old query was
      // ORDER BY id ASC, so `crash` — inserted last — came back last.
      final newestFirst =
          history.isNotEmpty && history.first.eventType == inserted.last;
      check(
        '#313 history is ordered most-recent-first',
        newestFirst,
        newestFirst
            ? 'newest is "${history.first.eventType}", the last event inserted'
            : 'REGRESSED — newest is "${history.firstOrNull?.eventType}", '
                  'expected "${inserted.last}". The history API is still '
                  "sharing the sync batcher's ORDER BY id ASC query.",
      );

      // A limit must trim the OLDEST, not the newest.
      final limited = await Tracelet.getTelematicsEvents(2);
      final trimmedOldest =
          limited.length == 2 &&
          limited.map((e) => e.eventType).toSet().containsAll({
            'crash',
            'speeding',
          });
      check(
        '#313 a limit keeps the most recent events',
        trimmedOldest,
        'limit 2 → ${limited.map((e) => e.eventType).join(', ')} '
            '(expected crash, speeding)',
      );

      await Tracelet.destroyTelematicsEvents();

      final header = allPass
          ? '✅ SUCCESS: the crash-model feature contract is enforced and the '
                'telematics history API returns what it documents.'
          : '❌ FAILED — see the failing rows below.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'Not observable from Dart, covered by the Rust/native tests:\n'
        "• #310 — the model's peak_g/mean_g/gyro_peak_dps are now aggregated "
        'over the same ~16 s window it was trained on, instead of the 1 s '
        'window being scored while speed_max/dv already used 16 s.\n'
        '• #311 — iOS now takes a lock around crashModel; it was written from '
        "the loader's background queue and read on the main run loop with no "
        'synchronisation (Android already used @Volatile).\n'
        '• #312 — the crash speed gate now uses the pre-impact speed (max over '
        'the last 3 s) rather than the latest fix, which after an impact is '
        'often already the post-crash speed.\n'
        '• #314 — the encrypted-model cache is keyed by model URL, so changing '
        'crashModelUrl invalidates it even without a sha256; the iOS cache '
        'directory is created rather than silently failing every write.',
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
          'crash model ML feature names accel_g peak_g mean_g gyro_peak_dps '
          'speed_max dv replace mode telematics history getTelematicsEvents '
          'synced newest first pre-impact speed gate data race crashModel '
          'volatile NSLock cache url sha256 application support 309 310 311 '
          '312 313 314',
      title: '#309–#314: crash-ML feature contract & telematics history',
      description:
          'Verifies that a crash model declaring feature names the SDK cannot '
          'supply is rejected at load — the failure that used to leave the '
          'detector in ML Replace mode with the g-threshold rule bypassed, '
          'silently disabling crash detection — while a valid model still '
          'loads and scores. Also checks that getTelematicsEvents() returns '
          'the most recent events rather than the oldest unsynced ones.',
      status: _status,
      running: _running,
      onRun: _run,
    );
  }
}
