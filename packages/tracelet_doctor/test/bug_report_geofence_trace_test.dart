import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';
import 'package:tracelet_doctor/tracelet_doctor.dart';

/// Platform stub that serves a canned log list and leaves every other call
/// unimplemented.
///
/// `TraceletBugReport.build` gathers each section defensively, so the health,
/// config and telematics sections degrade to an inline error while the log-backed
/// sections still render — which is exactly the surface under test here.
class _LogOnlyPlatform extends TraceletPlatform
    with MockPlatformInterfaceMixin {
  _LogOnlyPlatform(this.entries);

  final List<TlLogEntry> entries;

  /// Limits passed to [getLogs], in call order. Lets the test assert that the
  /// geofence section scans deeper than the general log window.
  final List<int> requestedLimits = <int>[];

  @override
  Future<List<TlLogEntry?>> getLogs(int limit) async {
    requestedLimits.add(limit);
    return entries.take(limit).toList();
  }
}

TlLogEntry _entry(int id, String level, String message) => TlLogEntry(
  id: id,
  level: level,
  message: message,
  timestamp: '2026-08-01T14:0$id:00.000Z',
);

void main() {
  group('TraceletBugReport geofence decision trace', () {
    /// A realistic mix: a genuine EXIT trace buried in routine lifecycle noise.
    List<TlLogEntry> sampleLogs() => <TlLogEntry>[
      _entry(1, 'INFO', 'ready() called'),
      _entry(
        2,
        'INFO',
        'Successfully synchronized ConfigManager state to Rust Core.',
      ),
      _entry(
        3,
        'INFO',
        '[geofence] ENTER ZONE_A dist=12.4 radius=50.0 buffer=20.0 thr=70.0 '
            'margin=-57.6 accRaw=8.0 accEff=8.0 exitAccuracyMax=-1',
      ),
      _entry(
        4,
        'INFO',
        'startGeofences() — geofence-only mode (highAccuracy=true)',
      ),
      _entry(
        5,
        'INFO',
        '[geofence] EXIT ZONE_A dist=264.3 radius=50.0 buffer=20.0 thr=70.0 '
            'margin=166.3 accRaw=28.0 accEff=28.0 exitAccuracyMax=-1',
      ),
      _entry(
        6,
        'DEBUG',
        '[geofence] proximity scope update (not ENTER/EXIT): 3 active',
      ),
    ];

    test('lifts geofence lines into a dedicated section', () async {
      TraceletPlatform.instance = _LogOnlyPlatform(sampleLogs());

      final report = await TraceletBugReport.build(includeConfig: false);

      expect(report, contains('## Geofence transitions (decision trace)'));
      // Both crossings must be present with their full decision inputs.
      expect(report, contains('[geofence] ENTER ZONE_A'));
      expect(report, contains('[geofence] EXIT ZONE_A'));
      expect(report, contains('accRaw=28.0'));
      expect(report, contains('thr=70.0'));
    });

    test('excludes non-geofence chatter from the section', () async {
      TraceletPlatform.instance = _LogOnlyPlatform(sampleLogs());

      final report = await TraceletBugReport.build(includeConfig: false);

      final start = report.indexOf('## Geofence transitions');
      final end = report.indexOf('## Logs');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final section = report.substring(start, end);

      // The point of the section is that rare crossings are not buried.
      expect(section, contains('[geofence] EXIT ZONE_A'));
      expect(section, isNot(contains('ready() called')));
      expect(
        section,
        isNot(contains('Successfully synchronized ConfigManager')),
      );
    });

    test('scans deeper than the general log window', () async {
      // Crossings are rare and lifecycle chatter is not, so the trace has to
      // look further back than the ## Logs section or it defeats its purpose.
      final platform = _LogOnlyPlatform(sampleLogs());
      TraceletPlatform.instance = platform;

      await TraceletBugReport.build(
        includeConfig: false,
        logLimit: 100,
        geofenceTraceLimit: 400,
      );

      expect(platform.requestedLimits, contains(400));
      expect(platform.requestedLimits, contains(100));
      expect(platform.requestedLimits.reduce((a, b) => a > b ? a : b), 400);
    });

    test(
      'reports absence explicitly rather than rendering an empty block',
      () async {
        TraceletPlatform.instance = _LogOnlyPlatform(<TlLogEntry>[
          _entry(1, 'INFO', 'ready() called'),
        ]);

        final report = await TraceletBugReport.build(includeConfig: false);

        expect(report, contains('No geofence activity in the last'));
      },
    );

    test('survives a log source that throws', () async {
      // Defensive-gathering contract: one broken section must not take the
      // whole report down, since a report is often the only artifact available.
      TraceletPlatform.instance = _ThrowingLogPlatform();

      final report = await TraceletBugReport.build(includeConfig: false);

      expect(report, contains('## Geofence transitions (decision trace)'));
      expect(report, contains('Could not read the geofence trace'));
    });
  });
}

class _ThrowingLogPlatform extends TraceletPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<List<TlLogEntry?>> getLogs(int limit) async {
    throw StateError('database unavailable');
  }
}
