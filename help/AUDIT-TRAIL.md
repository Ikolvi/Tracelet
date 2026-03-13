# Tamper-Proof Audit Trail

**Enterprise Feature** — Cryptographic chain of custody for location records.

The Audit Trail creates a SHA-256 hash chain over every persisted location
record. Each record's hash is computed from a canonical representation of
the location data **and** the previous record's hash, forming a
blockchain-like chain. Tampering with any record (insert, modify, or delete)
breaks the chain and is immediately detectable via `verifyAuditTrail()`.

## Use Cases

| Scenario | Benefit |
| --- | --- |
| Fleet management | Prove drivers followed required routes |
| Insurance telematics | Tamper-proof trip data for claims |
| Regulatory compliance | Immutable location audit log |
| Legal evidence | Chain-of-custody proof for court submissions |
| Asset tracking | Detect unauthorized location data manipulation |

## Quick Start

```dart
import 'package:tracelet/tracelet.dart';

// Enable audit trail in config
final state = await Tracelet.ready(Config(
  audit: AuditConfig(
    enabled: true,
  ),
));

await Tracelet.start();

// Later: verify the chain is intact
final verification = await Tracelet.verifyAuditTrail();
print('Chain valid: ${verification.isValid}');
print('Records verified: ${verification.verifiedRecords}');

// Get proof for a specific location
final proof = await Tracelet.getAuditProof('location-uuid');
if (proof != null) {
  print('Hash: ${proof.hash}');
  print('Chain index: ${proof.chainIndex}');
}
```

## Configuration

Add `AuditConfig` to your `Config`:

```dart
Config(
  audit: AuditConfig(
    // Enable the audit trail (default: false)
    enabled: true,

    // Hash algorithm (default: HashAlgorithm.sha256)
    // Currently only SHA-256 is supported.
    hashAlgorithm: HashAlgorithm.sha256,

    // Include location extras in the hash (default: false)
    // When true, the extras map is included in the canonical hash input.
    // WARNING: Enabling this means any change to extras will break the chain.
    includeExtrasInHash: false,
  ),
)
```

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `bool` | `false` | Enable tamper-proof audit trail |
| `hashAlgorithm` | `HashAlgorithm` | `sha256` | Hash algorithm for chain computation |
| `includeExtrasInHash` | `bool` | `false` | Include extras map in hash input |

## API Reference

### `Tracelet.verifyAuditTrail()`

Verifies the entire audit chain from genesis to the latest record.

```dart
Future<AuditVerification> verifyAuditTrail()
```

**Returns** an `AuditVerification` with:

| Field | Type | Description |
| --- | --- | --- |
| `isValid` | `bool` | `true` if the entire chain is intact |
| `totalRecords` | `int` | Total number of audit records |
| `verifiedRecords` | `int` | Number of records successfully verified |
| `brokenAtIndex` | `int?` | Chain index where the break was detected |
| `brokenAtUuid` | `String?` | UUID of the location where the break occurred |
| `error` | `String?` | Human-readable error description |

### `Tracelet.getAuditProof(uuid)`

Returns the audit proof for a specific location record.

```dart
Future<AuditProof?> getAuditProof(String uuid)
```

**Returns** an `AuditProof` with:

| Field | Type | Description |
| --- | --- | --- |
| `uuid` | `String` | The location UUID |
| `hash` | `String` | SHA-256 hash of this record |
| `previousHash` | `String` | Hash of the previous record in the chain |
| `chainIndex` | `int` | Position in the chain (0-based) |
| `timestamp` | `String` | ISO 8601 timestamp of the location |

Returns `null` if no audit record exists for the given UUID.

## How It Works

### Hash Chain Structure

```
┌──────────────────────────────────────────────────┐
│  Genesis Hash                                     │
│  SHA256("tracelet:genesis:" + deviceId)           │
└──────────────┬───────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────┐
│  Record 0                                         │
│  hash = SHA256(genesisHash + canonical(loc[0]))  │
│  previous_hash = genesisHash                      │
└──────────────┬───────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────┐
│  Record 1                                         │
│  hash = SHA256(hash[0] + canonical(loc[1]))      │
│  previous_hash = hash[0]                          │
└──────────────┬───────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────┐
│  Record N                                         │
│  hash = SHA256(hash[N-1] + canonical(loc[N]))    │
│  previous_hash = hash[N-1]                        │
└──────────────────────────────────────────────────┘
```

### Canonical String Format

Each location is serialized into a deterministic string for hashing:

```
previousHash|TRACELET_AUDIT|chainIndex|uuid|lat|lng|timestamp|accuracy|speed|heading|altitude|odometer|isMoving
```

**Fixed decimal precision** ensures cross-platform consistency:

| Field | Precision | Example |
| --- | --- | --- |
| `latitude` | 6 decimal places (~11cm) | `37.774900` |
| `longitude` | 6 decimal places | `-122.419400` |
| `accuracy` | 2 decimal places | `5.00` |
| `speed` | 2 decimal places | `1.50` |
| `heading` | 2 decimal places | `180.00` |
| `altitude` | 2 decimal places | `35.00` |
| `odometer` | 2 decimal places | `1500.00` |
| `isMoving` | boolean → `"1"` / `"0"` | `1` |

**Example canonical string:**
```
a1b2c3...|TRACELET_AUDIT|0|550e8400-e29b-41d4-...|37.774900|-122.419400|2024-06-15T10:30:00.000Z|5.00|1.50|180.00|35.00|1500.00|1
```

### Genesis Hash

The chain starts with a **genesis hash** derived from a stable device identifier:
- **Android**: `SHA256("tracelet:genesis:" + Build.FINGERPRINT)`
- **iOS**: `SHA256("tracelet:genesis:" + identifierForVendor)`

This makes the chain device-specific. The genesis hash is recomputed (not stored),
so it's always available for verification even after app reinstall.

### Database Schema

Audit records are stored in a separate `audit_trail` table:

```sql
CREATE TABLE audit_trail (
    uuid TEXT PRIMARY KEY,
    hash TEXT NOT NULL,
    previous_hash TEXT NOT NULL,
    chain_index INTEGER NOT NULL UNIQUE,
    created_at TEXT DEFAULT (datetime('now'))
)
```

Location queries (`getLocations`, `getUnsyncedLocations`) automatically LEFT JOIN
the audit_trail table, so audit fields (`audit_hash`, `audit_previous_hash`,
`audit_chain_index`) appear on `Location` objects when available.

## Location Object

When audit trail is enabled, `Location` objects include three additional fields:

```dart
final location = await Tracelet.getCurrentPosition();

// These are non-null when audit trail is enabled
print(location.auditHash);           // SHA-256 hash
print(location.auditPreviousHash);   // Previous record's hash
print(location.auditChainIndex);     // Chain position (0-based)
```

These fields are also included in HTTP sync payloads, so your server receives
the full audit data alongside location data.

## Verification Examples

### Periodic Verification

```dart
// Verify every hour
Timer.periodic(Duration(hours: 1), (_) async {
  final result = await Tracelet.verifyAuditTrail();
  if (!result.isValid) {
    print('ALERT: Audit chain broken at index ${result.brokenAtIndex}');
    print('UUID: ${result.brokenAtUuid}');
    print('Error: ${result.error}');
    // Send alert to server
  }
});
```

### Server-Side Verification

Since the canonical format and SHA-256 algorithm are documented, you can
independently verify the chain on your server:

```python
import hashlib

def verify_chain(locations, device_id):
    genesis = hashlib.sha256(f"tracelet:genesis:{device_id}".encode()).hexdigest()
    expected_prev = genesis

    for loc in sorted(locations, key=lambda l: l['audit_chain_index']):
        canonical = (
            f"{expected_prev}|TRACELET_AUDIT|{loc['audit_chain_index']}|"
            f"{loc['uuid']}|"
            f"{loc['coords']['latitude']:.6f}|{loc['coords']['longitude']:.6f}|"
            f"{loc['timestamp']}|"
            f"{loc['coords']['accuracy']:.2f}|{loc['coords']['speed']:.2f}|"
            f"{loc['coords']['heading']:.2f}|{loc['coords']['altitude']:.2f}|"
            f"{loc['odometer']:.2f}|"
            f"{'1' if loc['is_moving'] else '0'}"
        )
        computed = hashlib.sha256(canonical.encode()).hexdigest()
        if computed != loc['audit_hash']:
            return False, loc['audit_chain_index']
        expected_prev = computed

    return True, len(locations)
```

## Platform Support

| Platform | Status | Notes |
| --- | --- | --- |
| Android | Full support | SHA-256 via `java.security.MessageDigest` |
| iOS | Full support | SHA-256 via CommonCrypto (`CC_SHA256`) |
| Web | Stub only | Returns empty/valid — no background tracking |

## Performance Impact

- **CPU**: Negligible. SHA-256 of a ~200-char string takes <1ms.
- **Storage**: ~100 bytes per audit record (UUID + two 64-char hashes + index).
- **Battery**: Zero additional battery impact — piggybacked on existing location events.
- **Verification**: O(n) scan. 10,000 records verify in <500ms on typical hardware.

## Important Notes

1. **Chain resets on reinstall**: The genesis hash depends on the device identifier.
   On iOS, `identifierForVendor` changes on reinstall, starting a new chain.
   On Android, `Build.FINGERPRINT` persists across reinstalls.

2. **Call `Tracelet.reset()` carefully**: Resetting the plugin clears the audit
   chain state. This is expected behavior — the chain restarts from genesis.

3. **HTTP sync includes audit fields**: When `autoSync` is enabled, the
   `audit_hash`, `audit_previous_hash`, and `audit_chain_index` fields are
   automatically included in the HTTP payload.

4. **Disabled by default**: The audit trail has zero overhead when disabled.
   No hashes are computed, no audit records are stored.

5. **Cross-platform consistency**: The canonical string format uses fixed
   decimal places to ensure Android, iOS, and server-side verification
   produce identical hashes for the same location data.
