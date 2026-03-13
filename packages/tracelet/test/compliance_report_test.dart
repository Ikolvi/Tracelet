import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet/tracelet.dart';

void main() {
  group('ComplianceReport', () {
    late ComplianceReport report;

    setUp(() {
      report = ComplianceReport(
        generatedAt: DateTime.utc(2024, 1, 15, 14, 30),
        totalLocationsStored: 1247,
        totalLocationsSynced: 1100,
        oldestRecord: '2024-01-10T08:15:00.000Z',
        newestRecord: '2024-01-15T14:28:00.000Z',
        maxDaysToPersist: 30,
        maxRecordsToPersist: 10000,
        databaseEncrypted: true,
        activePrivacyZones: 2,
        privacyZoneIdentifiers: const ['home', 'office'],
        httpSyncUrl: 'https://api.example.com/locations',
        autoSyncEnabled: true,
        auditTrailEnabled: true,
        auditTrailValid: true,
        locationPermissionStatus: 3,
        motionPermissionStatus: 2,
        sparseUpdatesEnabled: true,
        kalmanFilterEnabled: true,
        deltaCompressionEnabled: false,
        trackingEnabled: true,
        trackingMode: 'location',
      );
    });

    test('constructor stores all required fields', () {
      expect(report.generatedAt, DateTime.utc(2024, 1, 15, 14, 30));
      expect(report.totalLocationsStored, 1247);
      expect(report.totalLocationsSynced, 1100);
      expect(report.maxDaysToPersist, 30);
      expect(report.maxRecordsToPersist, 10000);
      expect(report.databaseEncrypted, isTrue);
      expect(report.activePrivacyZones, 2);
      expect(report.privacyZoneIdentifiers, ['home', 'office']);
      expect(report.autoSyncEnabled, isTrue);
      expect(report.auditTrailEnabled, isTrue);
      expect(report.locationPermissionStatus, 3);
      expect(report.motionPermissionStatus, 2);
      expect(report.sparseUpdatesEnabled, isTrue);
      expect(report.kalmanFilterEnabled, isTrue);
      expect(report.deltaCompressionEnabled, isFalse);
      expect(report.trackingEnabled, isTrue);
      expect(report.trackingMode, 'location');
    });

    test('optional fields can be set', () {
      expect(report.oldestRecord, '2024-01-10T08:15:00.000Z');
      expect(report.newestRecord, '2024-01-15T14:28:00.000Z');
      expect(report.httpSyncUrl, 'https://api.example.com/locations');
      expect(report.auditTrailValid, isTrue);
    });

    test('optional fields default to null', () {
      final minimal = ComplianceReport(
        generatedAt: DateTime.utc(2024),
        totalLocationsStored: 0,
        totalLocationsSynced: 0,
        maxDaysToPersist: -1,
        maxRecordsToPersist: -1,
        databaseEncrypted: false,
        activePrivacyZones: 0,
        privacyZoneIdentifiers: const [],
        autoSyncEnabled: false,
        auditTrailEnabled: false,
        locationPermissionStatus: 0,
        motionPermissionStatus: 0,
        sparseUpdatesEnabled: false,
        kalmanFilterEnabled: false,
        deltaCompressionEnabled: false,
        trackingEnabled: false,
        trackingMode: 'location',
      );

      expect(minimal.oldestRecord, isNull);
      expect(minimal.newestRecord, isNull);
      expect(minimal.httpSyncUrl, isNull);
      expect(minimal.auditTrailValid, isNull);
    });
  });

  group('ComplianceReport — toJson', () {
    late ComplianceReport report;

    setUp(() {
      report = ComplianceReport(
        generatedAt: DateTime.utc(2024, 1, 15, 14, 30),
        totalLocationsStored: 500,
        totalLocationsSynced: 450,
        oldestRecord: '2024-01-01T00:00:00.000Z',
        newestRecord: '2024-01-15T14:00:00.000Z',
        maxDaysToPersist: 90,
        maxRecordsToPersist: 50000,
        databaseEncrypted: true,
        activePrivacyZones: 1,
        privacyZoneIdentifiers: const ['home'],
        httpSyncUrl: 'https://api.example.com/sync',
        autoSyncEnabled: true,
        auditTrailEnabled: true,
        auditTrailValid: true,
        locationPermissionStatus: 3,
        motionPermissionStatus: 2,
        sparseUpdatesEnabled: false,
        kalmanFilterEnabled: true,
        deltaCompressionEnabled: true,
        trackingEnabled: true,
        trackingMode: 'location',
      );
    });

    test('contains all top-level sections', () {
      final json = report.toJson();

      expect(json.containsKey('generatedAt'), isTrue);
      expect(json.containsKey('dataInventory'), isTrue);
      expect(json.containsKey('retentionPolicy'), isTrue);
      expect(json.containsKey('privacyMeasures'), isTrue);
      expect(json.containsKey('dataDestinations'), isTrue);
      expect(json.containsKey('auditTrail'), isTrue);
      expect(json.containsKey('consent'), isTrue);
      expect(json.containsKey('trackingState'), isTrue);
    });

    test('generatedAt is ISO8601 string', () {
      final json = report.toJson();
      expect(json['generatedAt'], '2024-01-15T14:30:00.000Z');
    });

    test('dataInventory has correct values', () {
      final json = report.toJson();
      final inv = json['dataInventory'] as Map<String, Object?>;

      expect(inv['totalLocationsStored'], 500);
      expect(inv['totalLocationsSynced'], 450);
      expect(inv['oldestRecord'], '2024-01-01T00:00:00.000Z');
      expect(inv['newestRecord'], '2024-01-15T14:00:00.000Z');
    });

    test('retentionPolicy has correct values', () {
      final json = report.toJson();
      final ret = json['retentionPolicy'] as Map<String, Object?>;

      expect(ret['maxDaysToPersist'], 90);
      expect(ret['maxRecordsToPersist'], 50000);
    });

    test('privacyMeasures has correct values', () {
      final json = report.toJson();
      final priv = json['privacyMeasures'] as Map<String, Object?>;

      expect(priv['databaseEncrypted'], isTrue);
      expect(priv['activePrivacyZones'], 1);
      expect(priv['privacyZoneIdentifiers'], ['home']);
      expect(priv['sparseUpdatesEnabled'], isFalse);
      expect(priv['kalmanFilterEnabled'], isTrue);
      expect(priv['deltaCompressionEnabled'], isTrue);
    });

    test('dataDestinations has correct values', () {
      final json = report.toJson();
      final dest = json['dataDestinations'] as Map<String, Object?>;

      expect(dest['httpSyncUrl'], 'https://api.example.com/sync');
      expect(dest['autoSyncEnabled'], isTrue);
    });

    test('auditTrail has correct values', () {
      final json = report.toJson();
      final audit = json['auditTrail'] as Map<String, Object?>;

      expect(audit['enabled'], isTrue);
      expect(audit['valid'], isTrue);
    });

    test('consent has correct values', () {
      final json = report.toJson();
      final consent = json['consent'] as Map<String, Object?>;

      expect(consent['locationPermissionStatus'], 3);
      expect(consent['motionPermissionStatus'], 2);
    });

    test('trackingState has correct values', () {
      final json = report.toJson();
      final state = json['trackingState'] as Map<String, Object?>;

      expect(state['enabled'], isTrue);
      expect(state['mode'], 'location');
    });

    test('null optional fields appear as null in JSON', () {
      final minimal = ComplianceReport(
        generatedAt: DateTime.utc(2024),
        totalLocationsStored: 0,
        totalLocationsSynced: 0,
        maxDaysToPersist: -1,
        maxRecordsToPersist: -1,
        databaseEncrypted: false,
        activePrivacyZones: 0,
        privacyZoneIdentifiers: const [],
        autoSyncEnabled: false,
        auditTrailEnabled: false,
        locationPermissionStatus: 0,
        motionPermissionStatus: 0,
        sparseUpdatesEnabled: false,
        kalmanFilterEnabled: false,
        deltaCompressionEnabled: false,
        trackingEnabled: false,
        trackingMode: 'location',
      );

      final json = minimal.toJson();
      final inv = json['dataInventory'] as Map<String, Object?>;
      expect(inv['oldestRecord'], isNull);
      expect(inv['newestRecord'], isNull);

      final dest = json['dataDestinations'] as Map<String, Object?>;
      expect(dest['httpSyncUrl'], isNull);

      final audit = json['auditTrail'] as Map<String, Object?>;
      expect(audit['valid'], isNull);
    });
  });

  group('ComplianceReport — toMarkdown', () {
    late ComplianceReport report;

    setUp(() {
      report = ComplianceReport(
        generatedAt: DateTime.utc(2024, 1, 15, 14, 30),
        totalLocationsStored: 500,
        totalLocationsSynced: 450,
        maxDaysToPersist: 30,
        maxRecordsToPersist: 10000,
        databaseEncrypted: true,
        activePrivacyZones: 2,
        privacyZoneIdentifiers: const ['home', 'office'],
        autoSyncEnabled: true,
        auditTrailEnabled: true,
        auditTrailValid: true,
        locationPermissionStatus: 3,
        motionPermissionStatus: 2,
        sparseUpdatesEnabled: true,
        kalmanFilterEnabled: true,
        deltaCompressionEnabled: false,
        trackingEnabled: true,
        trackingMode: 'location',
      );
    });

    test('produces non-empty string', () {
      expect(report.toMarkdown(), isNotEmpty);
    });

    test('contains report title', () {
      expect(report.toMarkdown(), contains('Compliance Report'));
    });

    test('contains section headers', () {
      final md = report.toMarkdown();
      expect(md, contains('Data Inventory'));
      expect(md, contains('Retention Policy'));
      expect(md, contains('Privacy Measures'));
      expect(md, contains('Data Destinations'));
      expect(md, contains('Audit Trail'));
      expect(md, contains('Consent Status'));
      expect(md, contains('Tracking State'));
    });

    test('contains location counts', () {
      final md = report.toMarkdown();
      expect(md, contains('500'));
      expect(md, contains('450'));
    });

    test('shows unlimited for -1 retention', () {
      final unlimited = ComplianceReport(
        generatedAt: DateTime.utc(2024),
        totalLocationsStored: 0,
        totalLocationsSynced: 0,
        maxDaysToPersist: -1,
        maxRecordsToPersist: -1,
        databaseEncrypted: false,
        activePrivacyZones: 0,
        privacyZoneIdentifiers: const [],
        autoSyncEnabled: false,
        auditTrailEnabled: false,
        locationPermissionStatus: 0,
        motionPermissionStatus: 0,
        sparseUpdatesEnabled: false,
        kalmanFilterEnabled: false,
        deltaCompressionEnabled: false,
        trackingEnabled: false,
        trackingMode: 'location',
      );

      final md = unlimited.toMarkdown();
      expect(md, contains('Unlimited'));
    });

    test('shows Enabled/Disabled for boolean fields', () {
      final md = report.toMarkdown();
      expect(md, contains('Enabled'));
    });

    test('shows Not verified when auditTrailValid is null', () {
      final noAudit = ComplianceReport(
        generatedAt: DateTime.utc(2024),
        totalLocationsStored: 0,
        totalLocationsSynced: 0,
        maxDaysToPersist: -1,
        maxRecordsToPersist: -1,
        databaseEncrypted: false,
        activePrivacyZones: 0,
        privacyZoneIdentifiers: const [],
        autoSyncEnabled: false,
        auditTrailEnabled: false,
        locationPermissionStatus: 0,
        motionPermissionStatus: 0,
        sparseUpdatesEnabled: false,
        kalmanFilterEnabled: false,
        deltaCompressionEnabled: false,
        trackingEnabled: false,
        trackingMode: 'location',
      );

      expect(noAudit.toMarkdown(), contains('Not verified'));
    });
  });

  group('ComplianceReport — toString', () {
    test('produces readable summary', () {
      final report = ComplianceReport(
        generatedAt: DateTime.utc(2024, 1, 15, 14, 30),
        totalLocationsStored: 500,
        totalLocationsSynced: 450,
        maxDaysToPersist: 30,
        maxRecordsToPersist: 10000,
        databaseEncrypted: true,
        activePrivacyZones: 2,
        privacyZoneIdentifiers: const ['home', 'office'],
        autoSyncEnabled: true,
        auditTrailEnabled: true,
        locationPermissionStatus: 3,
        motionPermissionStatus: 2,
        sparseUpdatesEnabled: false,
        kalmanFilterEnabled: false,
        deltaCompressionEnabled: false,
        trackingEnabled: true,
        trackingMode: 'location',
      );

      final s = report.toString();
      expect(s, contains('ComplianceReport'));
      expect(s, contains('500'));
      expect(s, contains('privacyZones: 2'));
    });
  });
}
