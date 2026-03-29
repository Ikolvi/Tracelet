# Database Encryption

**Enterprise Feature** — At-rest encryption for the local SQLite database.

Tracelet can encrypt the local location database to protect sensitive
geolocation data at rest. Encryption is transparent to the application —
all reads, writes, and queries work identically whether the database is
encrypted or not.

## Use Cases

| Scenario | Benefit |
| --- | --- |
| Healthcare / HIPAA | Encrypt PHI-linked location data at rest |
| Financial services | Protect client movement patterns |
| Government / defense | Classified location data protection |
| GDPR Article 32 | Technical measure for data protection |
| Insurance telematics | Tamper-resistant claims data |
| Enterprise fleet | Protect driver location history on lost devices |

## Quick Start

### Android Setup (required)

Database encryption on Android uses SQLCipher, which is an **optional**
dependency to keep APK size small for apps that don't need it.

Add the following to your **app-level** `build.gradle` (not the plugin):

```kotlin
// android/app/build.gradle.kts  (or build.gradle)
dependencies {
    implementation("net.zetetic:sqlcipher-android:4.6.1@aar")
}
```

> **Size impact:** SQLCipher adds ~7.5 MB per ABI (~30 MB in a universal APK).
> Use App Bundles (`flutter build appbundle`) to serve only the matching ABI
> to each device (~7.5 MB per device).
>
> If you don't add this dependency, calling `encryptDatabase` will throw an
> `IllegalStateException` with setup instructions. iOS encryption uses
> built-in `NSFileProtection` and requires no extra dependencies.

### Dart API

```dart
import 'package:tracelet/tracelet.dart' as tl;

// Option 1: Enable encryption in config (auto-encrypts on first start)
final state = await tl.Tracelet.ready(tl.Config(
  security: tl.SecurityConfig(
    encryptDatabase: true,
  ),
));

// Option 2: Encrypt an existing database at runtime
final encrypted = await tl.Tracelet.encryptDatabase();
print('Encrypted: $encrypted'); // true

// Check encryption status
final isEncrypted = await tl.Tracelet.isDatabaseEncrypted();
print('Database encrypted: $isEncrypted'); // true
```

## Configuration

Add `SecurityConfig` to your `Config`:

```dart
Config(
  security: SecurityConfig(
    // Enable at-rest database encryption (default: false)
    encryptDatabase: true,

    // Custom encryption key (default: null — auto-generated)
    // If null, a secure 256-bit random key is generated and stored
    // in platform-secure storage (Android Keystore / iOS Keychain).
    // If provided, this key is used directly.
    encryptionKey: null,
  ),
)
```

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `encryptDatabase` | `bool` | `false` | Enable at-rest database encryption |
| `encryptionKey` | `String?` | `null` | Custom encryption key (null = auto-generated) |

---

## API Reference

### `Tracelet.isDatabaseEncrypted()`

Check whether the local database is currently encrypted.

```dart
final isEncrypted = await Tracelet.isDatabaseEncrypted();
```

| Returns | Description |
| --- | --- |
| `Future<bool>` | `true` if the database is encrypted at rest |

### `Tracelet.encryptDatabase()`

Encrypt an existing unencrypted database. This migrates all existing data
to an encrypted database file. Safe to call if already encrypted (returns
`true` immediately).

```dart
final success = await Tracelet.encryptDatabase();
if (success) {
  print('Database is now encrypted');
}
```

| Returns | Description |
| --- | --- |
| `Future<bool>` | `true` if encryption succeeded or already encrypted |

> **Note:** Encryption is a one-way operation. Once encrypted, the database
> cannot be decrypted back to plaintext via the API.

---

## Platform Implementation

### Android — SQLCipher (AES-256)

| Component | Detail |
| --- | --- |
| Encryption library | SQLCipher (`net.zetetic:sqlcipher-android:4.6.1`) |
| Algorithm | AES-256-CBC with HMAC-SHA512 |
| Key storage | Android Keystore via `EncryptedSharedPreferences` |
| Master key | `MasterKey` with AES256_GCM scheme |
| Key encryption | AES256_SIV |
| Value encryption | AES256_GCM |

**Migration flow (existing unencrypted → encrypted):**

1. Open existing database with SQLCipher (no key)
2. `ATTACH` new encrypted database with key
3. `SELECT sqlcipher_export('encrypted')` — copies all data
4. `DETACH` encrypted database
5. Replace original file with encrypted version
6. Mark as encrypted in `EncryptedSharedPreferences`
7. Reinitialize database instance

**Key management:**

```
┌─────────────────────┐
│  encryptionKey set?  │
└──────────┬──────────┘
           │
     ┌─────┴─────┐
     │ Yes       │ No
     ▼           ▼
  Use custom   Check Keystore
  key (UTF-8)  for existing key
                    │
              ┌─────┴─────┐
              │ Found     │ Not found
              ▼           ▼
           Use it     Generate 256-bit
                      random key & store
```

### iOS — NSFileProtection (Secure Enclave)

| Component | Detail |
| --- | --- |
| Protection class | `NSFileProtectionComplete` |
| Hardware backing | Secure Enclave (A7+ chips) |
| Scope | Database file + WAL + SHM + directory |
| Key management | iOS Keychain (hardware-backed) |

**How it works:**

iOS Data Protection encrypts files at the filesystem level using a
class key derived from the device passcode and hardware UID. With
`NSFileProtectionComplete`, the database file is:

- **Encrypted** when the device is locked
- **Decrypted** only when the device is unlocked
- **Unreadable** if the device is extracted without the passcode

**Files protected:**

| File | Purpose |
| --- | --- |
| `tracelet.db` | Main SQLite database |
| `tracelet.db-wal` | Write-ahead log (if exists) |
| `tracelet.db-shm` | Shared memory file (if exists) |
| Database directory | Parent directory protection |

> **No third-party dependencies.** iOS encryption uses only Apple frameworks
> — no CocoaPods dependencies are added.

---

## Compliance Mapping

| Regulation | Requirement | Tracelet Coverage |
| --- | --- | --- |
| GDPR Art. 32 | Encryption of personal data | AES-256 (Android) / NSFileProtection (iOS) |
| HIPAA §164.312(a)(2)(iv) | Encryption at rest | Full database encryption |
| SOC 2 CC6.1 | Logical access / encryption controls | Platform-native key management |
| PCI DSS 3.4 | Render PAN unreadable | Encrypted storage |
| CCPA §1798.150 | Reasonable security measures | Industry-standard encryption |

The `ComplianceReport` includes encryption status automatically:

```dart
final report = await Tracelet.generateComplianceReport();
print('Encrypted: ${report.databaseEncrypted}'); // true
```

---

## Best Practices

1. **Use auto-generated keys** — Let the platform manage encryption keys
   via Android Keystore / iOS Keychain. Custom keys require your own
   secure key management.

2. **Encrypt early** — Enable `encryptDatabase: true` in your initial
   config to encrypt from the start. Migrating a large existing database
   takes longer.

3. **Combine with audit trail** — Use encryption + audit trail together
   for defense-in-depth: encryption protects data at rest, the hash
   chain detects tampering.

4. **Test on real devices** — SQLCipher requires native libraries. Test
   on physical Android devices and iOS simulators/devices.

---

## Related Guides

- [Audit Trail](AUDIT-TRAIL.md) — Tamper-proof hash chain for location records
- [Privacy Zones](PRIVACY-ZONES.md) — Location exclusion zones
- [Compliance Report](COMPLIANCE-REPORT.md) — Auto-generated GDPR/CCPA reports
- [Configuration](CONFIGURATION.md) — All config groups with property tables
- [API Reference](API.md) — All methods and return types
