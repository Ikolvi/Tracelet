# Compliance Report

Tracelet can generate a comprehensive **GDPR Article 30** / **CCPA** compliance
report documenting all location data processing activities. The report is
auto-populated from current configuration, database state, and permission status.

---

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

final report = await tl.Tracelet.generateComplianceReport();

// Export as structured JSON (for automated compliance systems)
final json = report.toJson();

// Export as human-readable Markdown (for auditors / DPOs)
final markdown = report.toMarkdown();

print('Locations stored: ${report.totalLocationsStored}');
print('Privacy zones active: ${report.activePrivacyZones}');
print('Audit trail valid: ${report.auditTrailValid}');
```

---

## What's Included

The report covers seven compliance domains:

### 1. Data Inventory

| Field | Type | Description |
|-------|------|-------------|
| `generatedAt` | `DateTime` | Report generation timestamp |
| `totalLocationsStored` | `int` | Current locations in local database |
| `totalLocationsSynced` | `int` | Approximate locations synced to server |
| `oldestRecord` | `String?` | Timestamp of oldest stored record |
| `newestRecord` | `String?` | Timestamp of newest stored record |

Supports **Data Subject Access Requests (DSAR)** — the inventory shows exactly
what data exists and its time range.

### 2. Retention Policy

| Field | Type | Description |
|-------|------|-------------|
| `maxDaysToPersist` | `int` | Days to retain data (`-1` = unlimited) |
| `maxRecordsToPersist` | `int` | Max records to retain (`-1` = unlimited) |

Maps directly to GDPR **storage limitation principle** (Article 5(1)(e)).

### 3. Privacy Measures

| Field | Type | Description |
|-------|------|-------------|
| `databaseEncrypted` | `bool` | Database encrypted at rest |
| `activePrivacyZones` | `int` | Number of active privacy zones |
| `privacyZoneIdentifiers` | `List<String>` | Identifiers of all active zones |
| `sparseUpdatesEnabled` | `bool` | App-level deduplication active |
| `kalmanFilterEnabled` | `bool` | GPS smoothing via Kalman filter |
| `deltaCompressionEnabled` | `bool` | Delta encoding for HTTP payloads |

Documents **data minimization** (Article 5(1)(c)) and **integrity measures**
(Article 5(1)(f)).

### 4. Data Destinations

| Field | Type | Description |
|-------|------|-------------|
| `httpSyncUrl` | `String?` | Server URL receiving data (`null` if disabled) |
| `autoSyncEnabled` | `bool` | Automatic sync on new location |

Identifies **data recipients** as required by Article 30(1)(d).

### 5. Audit Trail

| Field | Type | Description |
|-------|------|-------------|
| `auditTrailEnabled` | `bool` | Tamper-proof hash chain enabled |
| `auditTrailValid` | `bool?` | Chain integrity validation status |

Demonstrates **accountability** (Article 5(2)) through cryptographic
tamper detection.

### 6. Consent & Permissions

| Field | Type | Description |
|-------|------|-------------|
| `locationPermissionStatus` | `int` | Current location permission code |
| `motionPermissionStatus` | `int` | Current motion/activity permission code |

Documents **lawful basis** for processing (Article 6) and consent status.

### 7. Tracking State

| Field | Type | Description |
|-------|------|-------------|
| `trackingEnabled` | `bool` | Whether tracking is currently active |
| `trackingMode` | `String` | Current mode: `location`, `geofences`, or `periodic` |

---

## Export Formats

### JSON (`toJson()`)

Structured hierarchical output suitable for automated compliance platforms:

```json
{
  "generatedAt": "2024-01-15T14:30:00.000Z",
  "dataInventory": {
    "totalLocationsStored": 1247,
    "totalLocationsSynced": 1100,
    "oldestRecord": "2024-01-10T08:15:00.000Z",
    "newestRecord": "2024-01-15T14:28:00.000Z"
  },
  "retentionPolicy": {
    "maxDaysToPersist": 30,
    "maxRecordsToPersist": 10000
  },
  "privacyMeasures": {
    "databaseEncrypted": true,
    "activePrivacyZones": 2,
    "privacyZoneIdentifiers": ["home", "office"],
    "sparseUpdatesEnabled": true,
    "kalmanFilterEnabled": true,
    "deltaCompressionEnabled": true
  },
  "dataDestinations": {
    "httpSyncUrl": "https://api.example.com/locations",
    "autoSyncEnabled": true
  },
  "auditTrail": {
    "enabled": true,
    "valid": true
  },
  "consent": {
    "locationPermissionStatus": 3,
    "motionPermissionStatus": 2
  },
  "trackingState": {
    "enabled": true,
    "mode": "location"
  }
}
```

### Markdown (`toMarkdown()`)

Human-readable report with formatted tables and sections, suitable for
printing or sharing with Data Protection Officers:

```markdown
# Tracelet Compliance Report

Generated: 2024-01-15 14:30:00

## Data Inventory

| Metric | Value |
|--------|-------|
| Locations stored | 1,247 |
| Locations synced | ~1,100 |
| Oldest record | 2024-01-10 08:15 |
| Newest record | 2024-01-15 14:28 |

## Retention Policy

| Setting | Value |
|---------|-------|
| Max days | 30 |
| Max records | 10,000 |

...
```

---

## GDPR Article 30 Mapping

| Article 30 Requirement | Compliance Report Field |
|------------------------|------------------------|
| Name of controller | App-level (not in report) |
| Purposes of processing | App-level (not in report) |
| Categories of data subjects | Implied (device user) |
| Categories of personal data | `dataInventory` (location, battery, motion) |
| Recipients | `dataDestinations.httpSyncUrl` |
| Transfers to third countries | Derived from `httpSyncUrl` domain |
| Retention time limits | `retentionPolicy` |
| Technical/org measures | `privacyMeasures`, `auditTrail` |

Fields marked "App-level" should be added by your application when composing
the final compliance documentation.

---

## Usage Patterns

### Scheduled Compliance Check

```dart
// Generate weekly compliance report
final report = await tl.Tracelet.generateComplianceReport();

// Validate audit trail integrity
if (report.auditTrailEnabled && report.auditTrailValid == false) {
  notifyDPO('Audit trail integrity check failed!');
}

// Check retention compliance
if (report.totalLocationsStored > 50000) {
  notifyDPO('Location storage exceeds 50k records');
}

// Archive report
await archiveComplianceReport(report.toJson());
```

### In-App Privacy Dashboard

```dart
final report = await tl.Tracelet.generateComplianceReport();

showPrivacyDialog(
  dataStored: '${report.totalLocationsStored} locations',
  timeRange: '${report.oldestRecord} to ${report.newestRecord}',
  privacyZones: '${report.activePrivacyZones} zones active',
  encryption: report.databaseEncrypted ? 'Enabled' : 'Disabled',
  auditTrail: report.auditTrailValid == true ? 'Valid' : 'Check needed',
);
```

---

## Related Guides

- [Privacy Zones](PRIVACY-ZONES.md) — Geographic exclusion zones
- [Audit Trail](AUDIT-TRAIL.md) — Tamper-proof hash chain
- [Configuration](CONFIGURATION.md) — All config groups with property tables
- [HTTP Sync](HTTP-SYNC.md) — Server sync configuration
