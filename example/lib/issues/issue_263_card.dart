import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';

/// Issue #263 — `IncompatibleClassChangeError` when Play Services Location
/// resolved below 21.2.0.
///
/// Tracelet's Android bytecode targets the **interface**-based
/// `FusedLocationProviderClient` and `ActivityRecognitionClient`, which only
/// became interfaces in `play-services-location:21.2.0`. The SDK keeps that
/// dependency `compileOnly` so it can degrade gracefully to the AOSP
/// `LocationManager` when GMS is absent — but that also meant it published no
/// version constraint, so Gradle was free to resolve an older copy (19.0.0 was
/// seen in the field) from an unrelated transitive dependency. Against that
/// version the same types are concrete classes, and the first call into either
/// client threw `java.lang.IncompatibleClassChangeError` at runtime.
///
/// The fix is a published Gradle dependency **constraint** raising the resolved
/// version to `>= 21.2.0` whenever the dependency is present, without adding it
/// to the graph.
///
/// This card is a runtime smoke test for that class of failure. The bug is not
/// observable as a Dart value — it manifests as a native linkage error the
/// moment the SDK touches either client. So the card deliberately *exercises*
/// both paths: a fused location request and an activity/motion query. If the
/// wrong Play Services version were resolved, these would throw rather than
/// return.
class Issue263Card extends StatefulWidget {
  const Issue263Card({super.key});

  @override
  State<Issue263Card> createState() => _Issue263CardState();
}

class _Issue263CardState extends State<Issue263Card>
    with IssueCardRun<Issue263Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _run;

  Future<void> _run() async {
    setRunning(running: true);
    final results = <String>[];
    var allPass = true;

    void check(String name, bool pass, String detail) {
      results.add('${pass ? '✅' : '❌'} $name — $detail');
      if (!pass) allPass = false;
    }

    try {
      if (kIsWeb || !Platform.isAndroid) {
        _set(
          'ℹ️ Android-only. #263 is a Gradle dependency-resolution bug in the '
          'Android SDK: Tracelet targets the interface-based '
          'FusedLocationProviderClient / ActivityRecognitionClient introduced '
          'in play-services-location 21.2.0, and an older transitively '
          'resolved copy made those types concrete classes, throwing '
          'IncompatibleClassChangeError at the first call. There is no iOS or '
          'web equivalent.',
        );
        return;
      }

      await Tracelet.requestLocationAuthorization();
      await Tracelet.ready(const Config());

      // 1. Provider state reads the location stack. On a bad resolution this is
      //    one of the first places the linkage error surfaces.
      final provider = await Tracelet.getProviderState();
      check(
        'Location provider state resolves without a linkage error',
        true,
        'gps=${provider.gps} network=${provider.network} '
            'enabled=${provider.enabled} status=${provider.status}',
      );

      // 2. The actual FusedLocationProviderClient call path. This is the one
      //    that threw IncompatibleClassChangeError against 19.0.0.
      try {
        final loc = await Tracelet.getCurrentPosition(
          samples: 1,
          timeout: 20,
          persist: false,
        );
        check(
          'FusedLocationProviderClient returns a fix',
          true,
          'got ${loc.coords.latitude.toStringAsFixed(4)}, '
              '${loc.coords.longitude.toStringAsFixed(4)} '
              '(±${loc.coords.accuracy.toStringAsFixed(0)}m)',
        );
      } catch (e) {
        // A timeout indoors is not the bug; a linkage error is.
        final linkage =
            e.toString().contains('IncompatibleClassChangeError') ||
            e.toString().contains('NoSuchMethodError') ||
            e.toString().contains('NoClassDefFoundError');
        check(
          'FusedLocationProviderClient is linked correctly',
          !linkage,
          linkage
              ? 'LINKAGE ERROR — an incompatible play-services-location is '
                    'resolved: $e'
              : 'no fix available (indoors / no signal), but the client '
                    'linked and answered: $e',
        );
      }

      // 3. The ActivityRecognitionClient path — the second interface-based
      //    client affected by the same version floor.
      final motion = await Tracelet.getMotionAuthorization();
      check(
        'ActivityRecognitionClient is linked correctly',
        true,
        'motion authorization resolved to $motion without a linkage error',
      );

      // 4. Sensor probe: reports which native providers actually resolved,
      //    which is what distinguishes "GMS present and correct" from the
      //    AOSP fallback the SDK is designed to degrade to.
      final sensors = await Tracelet.getSensors();
      check(
        'Sensor/provider probe answers',
        sensors.platform.isNotEmpty,
        'platform=${sensors.platform} accelerometer=${sensors.accelerometer} '
            'significantMotion=${sensors.significantMotion} — the SDK '
            'resolved a usable native stack',
      );

      await Tracelet.stop();

      final header = allPass
          ? '✅ SUCCESS: both interface-based Play Services clients link and '
                'respond — the >= 21.2.0 floor is holding.'
          : '❌ FAILED — #263 not satisfied on this build. See the failing rows.';

      _set(
        '$header\n\n${results.join('\n')}\n\n'
        'This is a linkage bug, not a value bug: it cannot be asserted by '
        'comparing a config field, only by actually calling into '
        'FusedLocationProviderClient and ActivityRecognitionClient and seeing '
        'them answer. play-services-location stays compileOnly so the SDK '
        'still falls back to the AOSP LocationManager when GMS is absent; the '
        'published Gradle constraint only raises the version when the '
        'dependency is present at all.',
      );
    } catch (e) {
      final linkage =
          e.toString().contains('IncompatibleClassChangeError') ||
          e.toString().contains('NoSuchMethodError') ||
          e.toString().contains('NoClassDefFoundError');
      _set(
        '${linkage ? "❌ FAILED — #263 REGRESSED: incompatible "
                  "play-services-location resolved" : "❌ FAILED"}: $e\n\n'
        '${results.join('\n')}',
      );
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      keywords:
          'IncompatibleClassChangeError play-services-location 21.2.0 '
          'FusedLocationProviderClient ActivityRecognitionClient gradle '
          'dependency constraint compileOnly GMS AOSP LocationManager crash '
          'linkage android version floor',
      title: '#263: Play Services Location version floor (>= 21.2.0)',
      description:
          'Android-only runtime smoke test for the IncompatibleClassChangeError '
          'crash that occurred when Gradle resolved play-services-location '
          'below 21.2.0, where FusedLocationProviderClient and '
          'ActivityRecognitionClient are concrete classes rather than the '
          'interfaces Tracelet compiles against. Exercises both client paths; '
          'a timeout indoors is tolerated, a linkage error is not.',
      status: status,
      running: running,
      onRun: _run,
    );
  }
}
