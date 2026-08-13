import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';
import 'package:tracelet_example/issues/issue_card_state.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart'
    show TlIosActivityType;

/// Issue #250 — `IosConfig.activityType` never reached `CLLocationManager` as
/// configured. Two independent bugs compounded so every value resolved to
/// `.otherNavigation`:
///
///  * Bug 1 (Dart bridge): `IosConfig.toTlConfig()` mapped between two
///    differently-ordered enums by raw `.index`, so e.g. `otherNavigation`
///    (index 2) was sent as `TlIosActivityType.fitness`.
///  * Bug 2 (iOS native): `TraceletHostApiImpl` stored `activityType` as an Int
///    while `ConfigManager.getActivityType()` read it back as a String, so the
///    lookup always failed and fell through to `.otherNavigation`.
///
/// This card verifies Bug 1 directly in-app: it maps every
/// [LocationActivityType] through the real bridge (`IosConfig.toTlConfig()`)
/// and asserts each lands on the matching [TlIosActivityType] by name (not by
/// index). Bug 2 lives in the native SDK — after the fix the configured type
/// now actually reaches `CLLocationManager.activityType`; verify at runtime by
/// configuring a non-default type and inspecting the CoreLocation manager.
class Issue250Card extends StatefulWidget {
  const Issue250Card({super.key});

  @override
  State<Issue250Card> createState() => _Issue250CardState();
}

class _Issue250CardState extends State<Issue250Card>
    with IssueCardRun<Issue250Card> {
  void _set(String s) => setStatus(s);

  @override
  IssueRunner? get cardRunner => _test;

  Future<void> _test() async {
    if (running) return;
    setRunning(running: true);

    try {
      // The exact mapping the SDK must produce — by name, never by index.
      const expected = <LocationActivityType, TlIosActivityType>{
        LocationActivityType.other: TlIosActivityType.other,
        LocationActivityType.automotiveNavigation: TlIosActivityType.automotive,
        LocationActivityType.otherNavigation: TlIosActivityType.otherNavigation,
        LocationActivityType.fitness: TlIosActivityType.fitness,
        LocationActivityType.airborne: TlIosActivityType.airborne,
      };

      final failures = <String>[];
      expected.forEach((input, want) {
        final got = IosConfig(activityType: input).toTlConfig().activityType;
        if (got != want) {
          failures.add('$input → $got (expected $want)');
        }
      });

      if (failures.isNotEmpty) {
        _set(
          '❌ FAILED: the Dart bridge still corrupts the activity type '
          '(the #250 index-mapping bug):\n${failures.join('\n')}',
        );
        return;
      }

      final buffer = StringBuffer(
        '✅ Dart bridge maps all 5 activity types by name:\n',
      );
      expected.forEach((input, want) {
        final short = input.name;
        buffer.writeln('  • $short → ${want.name}');
      });

      if (Platform.isIOS) {
        // Push a non-default type through a real ready() so the native side
        // applies it to CLLocationManager.activityType (the Bug 2 path).
        buffer.writeln(
          '\nApplying activityType=automotiveNavigation via ready() so the '
          'native SDK sets CLLocationManager.activityType (Bug 2 path). '
          'Inspect the CoreLocation manager to confirm it is '
          '.automotiveNavigation (2), not .otherNavigation (5).',
        );
        await Tracelet.stop();
        await Tracelet.ready(
          Config.balanced().copyWith(
            ios: const IosConfig(
              activityType: LocationActivityType.automotiveNavigation,
            ),
          ),
        );
      } else {
        buffer.writeln(
          '\n(activityType is an iOS/CLLocationManager concept — the native '
          'Bug 2 fix only applies on iOS.)',
        );
      }

      _set(buffer.toString());
    } catch (e) {
      _set('❌ ERROR: $e');
    } finally {
      setRunning(running: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: 'Issue #250: iOS activityType never applied as configured',
      description:
          'Maps every LocationActivityType through the real IosConfig bridge '
          'and asserts each reaches the matching TlIosActivityType by name '
          '(not by index — otherNavigation used to arrive as fitness). On iOS '
          'it also pushes activityType=automotiveNavigation through ready() so '
          'you can confirm CLLocationManager.activityType now honors the '
          'configured value instead of always falling back to otherNavigation.',
      status: status,
      running: running,
      onRun: _test,
    );
  }
}
