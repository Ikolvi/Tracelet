import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tracelet/tracelet.dart' show traceletVersion;
import 'package:tracelet_doctor/tracelet_doctor.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

/// Platform stub that serves a canned log list and leaves every other call
/// unimplemented.
///
/// `TraceletBugReport.build` gathers each section defensively, so the health,
/// config and telematics sections degrade to an inline error while the
/// log-backed sections still render — which is exactly the surface under test.
class _LogOnlyPlatform extends TraceletPlatform
    with MockPlatformInterfaceMixin {
  _LogOnlyPlatform(this.entries);

  final List<TlLogEntry> entries;

  @override
  Future<List<TlLogEntry?>> getLogs(int limit) async =>
      entries.take(limit).toList();
}

TlLogEntry _entry(int id, String level, String message) => TlLogEntry(
  id: id,
  level: level,
  message: message,
  timestamp: '2026-08-16T12:0$id:00.000Z',
);

/// Serves only the foreground-service snapshot. The health section degrades to
/// an inline error without a health call, which is fine: the verdict under test
/// is the one that has to fire even when `HealthCheck.warnings` is empty.
class _FgsHealthPlatform extends TraceletPlatform
    with MockPlatformInterfaceMixin {
  _FgsHealthPlatform(this.health);

  final Map<String, Object?> health;

  @override
  Future<List<TlLogEntry?>> getLogs(int limit) async => <TlLogEntry?>[];

  @override
  Future<Map<String, Object?>> getForegroundServiceHealth() async => health;
}

void main() {
  group('TraceletBugReport version header', () {
    test('names the Tracelet version that produced the report', () async {
      TraceletPlatform.instance = _LogOnlyPlatform(<TlLogEntry>[]);

      final report = await TraceletBugReport.build(includeConfig: false);

      // Without this, triage opens by asking which version — and a report
      // pasted into an issue weeks later cannot answer (#398).
      expect(report, contains('**Tracelet:** $traceletVersion'));
    });

    test('keeps the host app line beside it when one is supplied', () async {
      TraceletPlatform.instance = _LogOnlyPlatform(<TlLogEntry>[]);

      final report = await TraceletBugReport.build(
        includeConfig: false,
        appName: 'Acme Driver',
        appVersion: '2.1.0',
      );

      expect(report, contains('**Tracelet:** $traceletVersion'));
      expect(report, contains('**App:** Acme Driver 2.1.0'));
    });
  });

  group('TraceletBugReport location stream health', () {
    /// The field failure's shape: a stall, its recovery, and the throttle that
    /// caused it, buried in routine chatter.
    List<TlLogEntry> sampleLogs() => <TlLogEntry>[
      _entry(1, 'INFO', 'ready() called'),
      _entry(
        2,
        'LIFECYCLE',
        'battery budget: throttle level 1 — drain 30.0%/hr vs budget 3.0%/hr '
            '(measured over 1800s, ±10.0%/hr); overlay df=10.0m acc=0 '
            'floor=0m cadence=×1.50',
      ),
      _entry(3, 'DEBUG', 'Heartbeat: lat=10.78, lon=76.69, accuracy=4.0m'),
      _entry(
        4,
        'LIFECYCLE',
        'location stream stalled — nothing accepted for 196s, 59 fix(es) '
            'rejected [ACCURACY_FILTER=22 DISTANCE_FILTER=37]; last gate=750.0m '
            '(configured 10.0m), last fix acc=65.6m, in force: '
            'distanceFilter=8.0m trackingAccuracy=15m',
      ),
      _entry(
        5,
        'LIFECYCLE',
        'location stream recovered after 201s — 59 fix(es) rejected meanwhile '
            '[ACCURACY_FILTER=22 DISTANCE_FILTER=37], admitted by the idle '
            'escape (#394)',
      ),
      _entry(6, 'LIFECYCLE', 'session: stop — was mode=continuous'),
    ];

    test(
      'lifts stalls and throttle movements into a dedicated section',
      () async {
        TraceletPlatform.instance = _LogOnlyPlatform(sampleLogs());

        final report = await TraceletBugReport.build(includeConfig: false);

        expect(report, contains('## Location stream health'));
        expect(report, contains('location stream stalled'));
        expect(report, contains('location stream recovered'));
        expect(report, contains('battery budget: throttle level 1'));
        // The numbers that make a stall diagnosable rather than merely reported.
        expect(report, contains('ACCURACY_FILTER=22 DISTANCE_FILTER=37'));
        expect(report, contains('last gate=750.0m'));
        expect(report, contains('±10.0%/hr'));
      },
    );

    test('excludes unrelated chatter from the section', () async {
      TraceletPlatform.instance = _LogOnlyPlatform(sampleLogs());

      final report = await TraceletBugReport.build(includeConfig: false);

      final start = report.indexOf('## Location stream health');
      final end = report.indexOf('## Session lifecycle');
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final section = report.substring(start, end);

      expect(section, contains('location stream stalled'));
      expect(section, isNot(contains('Heartbeat')));
      expect(section, isNot(contains('session: stop')));
    });

    test('reports an absence of entries as an absence, not as health', () async {
      TraceletPlatform.instance = _LogOnlyPlatform(<TlLogEntry>[
        _entry(1, 'INFO', 'ready() called'),
        _entry(2, 'LIFECYCLE', 'session: start — mode=continuous'),
      ]);

      final report = await TraceletBugReport.build(includeConfig: false);

      final start = report.indexOf('## Location stream health');
      final end = report.indexOf('## Session lifecycle');
      final section = report.substring(start, end);

      // The section must still explain itself rather than render an empty block.
      expect(section, contains('none were recorded'));

      // But it must not claim health from that absence. This assertion used to
      // run the other way — it required the report to say "the stream has been
      // accepting fixes" — and the wording it pinned is the one that appeared
      // over a 52-second window in which the stream accepted nothing at all.
      // The stall watchdog only ran when a fix arrived, so total silence
      // produced no marker, and no marker rendered as good news (#405, #407).
      expect(section, isNot(contains('the stream has been accepting fixes')));
    });
  });

  group('TraceletBugReport health-check blockers', () {
    /// #406: `HealthCheck.warnings` is computed from the health map alone, and
    /// the background restrictions live in the foreground-service snapshot — a
    /// different native call. So the top section reported "all systems
    /// healthy" on a device where the OS had switched background tracking off,
    /// with the contradiction sitting one section below in the same report.
    ///
    /// The field report that made this concrete read `Warnings: none — all
    /// systems healthy ✅` above `Background restricted | true`, on a phone
    /// whose service was demoted with no location capability.
    test('a Restricted device is never called healthy', () async {
      TraceletPlatform.instance = _FgsHealthPlatform(<String, Object?>{
        'platform': 'android',
        'backgroundRestricted': true,
      });

      final report = await TraceletBugReport.build(includeConfig: false);

      expect(
        report,
        isNot(contains('all systems healthy')),
        reason:
            'the OS has blocked background tracking outright — the verdict '
            'at the top of the report must not contradict the section below it',
      );
      // The bullet the health verdict emits, not the foreground-service
      // verdict further down — that one already said this and was ignored
      // precisely because the summary above it said healthy.
      expect(report, contains('- 🔴 App is in the "Restricted" battery state'));
    });

    test('a promotion the OS refused is named as a blocker', () async {
      TraceletPlatform.instance = _FgsHealthPlatform(<String, Object?>{
        'platform': 'android',
        'lastForegroundPromotionResult': 'refused',
      });

      final report = await TraceletBugReport.build(includeConfig: false);

      expect(report, isNot(contains('all systems healthy')));
      expect(report, contains('refused the last foreground-service promotion'));
    });

    test('an unrestricted device still reads healthy', () async {
      TraceletPlatform.instance = _FgsHealthPlatform(<String, Object?>{
        'platform': 'android',
        'backgroundRestricted': false,
        'lastForegroundPromotionResult': 'success',
        'locationCapabilityLikelyDenied': false,
      });

      final report = await TraceletBugReport.build(includeConfig: false);

      // The other half: a blocker that fires on a healthy device is noise, and
      // noise is what gets ignored on the day it matters.
      expect(report, contains('all systems healthy'));
    });
  });
}
