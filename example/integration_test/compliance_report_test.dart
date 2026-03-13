import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tracelet/tracelet.dart';

/// Integration tests for the Compliance Report feature.
///
/// These tests exercise the real native plugin through MethodChannels,
/// verifying that [ComplianceReport] generation, JSON/Markdown export, and
/// field population work correctly through the platform layer.
///
/// **Note:** These tests do NOT require location permissions or active tracking.
/// The report queries current plugin state and configuration.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Compliance Report — Generation', () {
    testWidgets('generateComplianceReport returns a ComplianceReport', (
      tester,
    ) async {
      final report = await Tracelet.generateComplianceReport();
      expect(report, isA<ComplianceReport>());
    });

    testWidgets('report has valid generatedAt timestamp', (tester) async {
      final before = DateTime.now();
      final report = await Tracelet.generateComplianceReport();
      final after = DateTime.now();

      expect(report.generatedAt, isA<DateTime>());
      // generatedAt should be roughly now (within 5 seconds)
      expect(
        report.generatedAt.isAfter(before.subtract(const Duration(seconds: 5))),
        isTrue,
      );
      expect(
        report.generatedAt.isBefore(after.add(const Duration(seconds: 5))),
        isTrue,
      );
    });

    testWidgets('report contains non-negative location counts', (tester) async {
      final report = await Tracelet.generateComplianceReport();

      expect(report.totalLocationsStored, greaterThanOrEqualTo(0));
      expect(report.totalLocationsSynced, greaterThanOrEqualTo(0));
    });

    testWidgets('report contains retention policy fields', (tester) async {
      final report = await Tracelet.generateComplianceReport();

      // Retention values are either -1 (unlimited) or positive
      expect(report.maxDaysToPersist, isA<int>());
      expect(report.maxRecordsToPersist, isA<int>());
    });

    testWidgets('report contains privacy measures', (tester) async {
      final report = await Tracelet.generateComplianceReport();

      expect(report.databaseEncrypted, isA<bool>());
      expect(report.activePrivacyZones, isA<int>());
      expect(report.activePrivacyZones, greaterThanOrEqualTo(0));
      expect(report.privacyZoneIdentifiers, isA<List<String>>());
      expect(report.sparseUpdatesEnabled, isA<bool>());
      expect(report.kalmanFilterEnabled, isA<bool>());
      expect(report.deltaCompressionEnabled, isA<bool>());
    });

    testWidgets('report contains tracking state', (tester) async {
      final report = await Tracelet.generateComplianceReport();

      expect(report.trackingEnabled, isA<bool>());
      expect(report.trackingMode, isA<String>());
    });

    testWidgets('report contains audit trail status', (tester) async {
      final report = await Tracelet.generateComplianceReport();

      expect(report.auditTrailEnabled, isA<bool>());
      // auditTrailValid may be null if audit trail is disabled
    });

    testWidgets('report contains permission statuses', (tester) async {
      final report = await Tracelet.generateComplianceReport();

      expect(report.locationPermissionStatus, isA<int>());
      expect(report.motionPermissionStatus, isA<int>());
    });
  });

  group('Compliance Report — JSON Export', () {
    testWidgets('toJson produces structured map', (tester) async {
      final report = await Tracelet.generateComplianceReport();
      final json = report.toJson();

      expect(json, isA<Map<String, Object?>>());
      expect(json.containsKey('generatedAt'), isTrue);
      expect(json.containsKey('dataInventory'), isTrue);
      expect(json.containsKey('retentionPolicy'), isTrue);
      expect(json.containsKey('privacyMeasures'), isTrue);
      expect(json.containsKey('dataDestinations'), isTrue);
      expect(json.containsKey('auditTrail'), isTrue);
      expect(json.containsKey('consent'), isTrue);
      expect(json.containsKey('trackingState'), isTrue);
    });

    testWidgets('toJson dataInventory has correct structure', (tester) async {
      final report = await Tracelet.generateComplianceReport();
      final json = report.toJson();
      final dataInventory = json['dataInventory'] as Map<String, Object?>;

      expect(dataInventory.containsKey('totalLocationsStored'), isTrue);
      expect(dataInventory.containsKey('totalLocationsSynced'), isTrue);
    });

    testWidgets('toJson privacyMeasures has correct structure', (tester) async {
      final report = await Tracelet.generateComplianceReport();
      final json = report.toJson();
      final privacy = json['privacyMeasures'] as Map<String, Object?>;

      expect(privacy.containsKey('databaseEncrypted'), isTrue);
      expect(privacy.containsKey('activePrivacyZones'), isTrue);
      expect(privacy.containsKey('privacyZoneIdentifiers'), isTrue);
    });
  });

  group('Compliance Report — Markdown Export', () {
    testWidgets('toMarkdown produces non-empty string', (tester) async {
      final report = await Tracelet.generateComplianceReport();
      final markdown = report.toMarkdown();

      expect(markdown, isA<String>());
      expect(markdown.isNotEmpty, isTrue);
    });

    testWidgets('toMarkdown contains section headers', (tester) async {
      final report = await Tracelet.generateComplianceReport();
      final markdown = report.toMarkdown();

      expect(markdown, contains('Compliance Report'));
      expect(markdown, contains('Data Inventory'));
      expect(markdown, contains('Retention'));
      expect(markdown, contains('Privacy'));
    });
  });

  group('Compliance Report — Model Construction', () {
    testWidgets('ComplianceReport constructor populates all fields', (
      tester,
    ) async {
      final report = ComplianceReport(
        generatedAt: DateTime.utc(2024, 1, 15, 14, 30),
        totalLocationsStored: 1247,
        totalLocationsSynced: 1100,
        oldestRecord: '2024-01-10T08:15:00.000Z',
        newestRecord: '2024-01-15T14:28:00.000Z',
        maxDaysToPersist: 30,
        maxRecordsToPersist: 10000,
        databaseEncrypted: true,
        activePrivacyZones: 2,
        privacyZoneIdentifiers: ['home', 'office'],
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

      expect(report.totalLocationsStored, 1247);
      expect(report.activePrivacyZones, 2);
      expect(report.privacyZoneIdentifiers, ['home', 'office']);
      expect(report.auditTrailValid, isTrue);
      expect(report.trackingMode, 'location');
    });

    testWidgets('ComplianceReport handles null optional fields', (
      tester,
    ) async {
      final report = ComplianceReport(
        generatedAt: DateTime.utc(2024, 1, 15, 14, 30),
        totalLocationsStored: 0,
        totalLocationsSynced: 0,
        maxDaysToPersist: -1,
        maxRecordsToPersist: -1,
        databaseEncrypted: false,
        activePrivacyZones: 0,
        privacyZoneIdentifiers: <String>[],
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

      expect(report.oldestRecord, isNull);
      expect(report.httpSyncUrl, isNull);
      expect(report.auditTrailValid, isNull);
      expect(report.maxDaysToPersist, -1);
    });
  });
}
