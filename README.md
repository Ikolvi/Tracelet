<p align="center">
  <img src="assets/logo_anim.webp" alt="Tracelet" width="600"/>
</p>

# Tracelet

<p align="center">
  <img src="assets/android_ios_rec.webp" alt="Tracelet Android & iOS" width="600"/>
</p>

<p align="center">
  <img src="assets/map_view.png" alt="Tracelet Live Map" width="300"/>
</p>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Pub Package](https://img.shields.io/pub/v/tracelet.svg)](https://pub.dev/packages/tracelet)
[![CI](https://github.com/Ikolvi/Tracelet/actions/workflows/ci.yml/badge.svg)](https://github.com/Ikolvi/Tracelet/actions)

> **Production-grade background geolocation for Flutter — fully open-source.**

📚 **Official Documentation:** [tracelet.ikolvi.com](https://tracelet.ikolvi.com)

<p align="center">
  <a href="https://tracelet.ikolvi.com/copy-prompt?utm_source=github&utm_medium=readme&utm_campaign=copy_prompt">
    <img src="https://img.shields.io/badge/%E2%9C%A8%20Copy%20AI%20Setup%20Prompt-%E2%96%B6%20click%20to%20copy-0F9D58?style=for-the-badge&labelColor=0B7A43" alt="Copy AI Setup Prompt" height="42"/>
  </a>
</p>

<p align="center">
  <sub><b>⚡ Set up with AI in minutes.</b> Clicking the badge opens Tracelet and copies a ready-made prompt — paste it into your AI coding assistant (Cursor, Claude Code, Kiro, Copilot Chat…) and it interviews you about your use case, then installs and configures Tracelet for your Flutter app.</sub>
</p>

Battery-conscious motion-detection intelligence, geofencing, SQLite persistence, HTTP sync, and headless Dart execution for iOS & Android.

### 🎬 Video Tutorial

<p align="center">
  <a href="https://www.youtube.com/watch?v=KCF7mfIOaFo">
    <img src="https://img.youtube.com/vi/KCF7mfIOaFo/maxresdefault.jpg" alt="Tracelet Tutorial — watch on YouTube" width="600"/>
  </a>
</p>

▶️ **[Watch the Tracelet tutorial on YouTube](https://www.youtube.com/watch?v=KCF7mfIOaFo)** — full setup and integration walkthrough.

---

## 🆕 New in 3.5.0 — Stable AI Crash Detection

On-device, opt-in, and battery-friendly — all detection runs in the shared Rust core (no cloud, no extra permissions for the location-based features):

- **🤖 AI crash model — now stable** — gate crashes on a trained probability instead of a fixed g-threshold. The shipped model is trained on a **CC0 / public-domain** crash dataset, so it's **cleared for commercial use** in production apps. Opt-in and downloaded on demand (never embedded), AES-256-GCM encrypted, with automatic **rule-engine fallback** and **auto-update** when you publish a new model version. `ImpactConfig(crashModelUnlockUrl, crashModelLicenseKey)`.
- **🚗 Driving telematics** — harsh braking / acceleration / cornering / speeding, each with a `0–1` severity score for trip scoring. `TelematicsConfig` + `Tracelet.onDrivingEvent`.
- **💥 Crash & fall detection** — corroborated impact detection (a big jolt alone is never enough) with a user "I'm OK" cancel-countdown before it escalates to your SOS flow. `ImpactConfig` + `Tracelet.onImpact` / `confirmImpact` / `cancelImpact`. → **[Crash & fall detection docs](https://tracelet.ikolvi.com/en/core/driving-safety#3-crash--fall-detection)**
- **🚶 Transport-mode classifier** — still / walking / running / cycling / vehicle, fusing accelerometer + GPS. `ClassifierConfig` + `Tracelet.onModeChange`.
- **🔋 Motion-gated wakelock (Android)** — drops the partial wakelock when stationary and re-asserts it on movement to cut idle battery drain. `AndroidConfig.releaseWakelockWhenStationary`.

Everything is **default-off** and side-channel — when disabled, your existing tracking behaves exactly as before. → **[Driving & Safety guide](https://tracelet.ikolvi.com/en/core/driving-safety)** · **[Diagnostics & Bug Reports](https://tracelet.ikolvi.com/en/core/diagnostics)**

---

> [!IMPORTANT]
> **Tracelet 3.2.0**: The SQLCipher dependency is no longer required for database encryption (Tracelet Core now natively uses AES-GCM in Rust, reducing APK size by ~16MB). Additionally, HTTP sync logic has been moved to the `tracelet_sync` module, which must now be included if you require network synchronization.

> [!IMPORTANT]
> **Tracelet 2.x.x**: Android-specific and iOS-specific settings (including foreground service notification) are now configured via `AndroidConfig` and `IosConfig` sub-objects, not `AppConfig`. See the [Migration Guide](help/MIGRATION_2.0.md) for the full config schema change.

---

### 💬 Community & Support

Join our official [Discord Channel](https://discord.gg/hb5zeACxhm)! It's the best place to:
- Request new features and customizations.
- Get help from the maintainers and the community.
- Discuss best practices for background geolocation in Flutter.

---

### 💖 Support Open-Source Development!

Tracelet is a labor of love, built to provide a robust, fully open-source, battery-conscious background tracking experience for the Flutter community. If this library has saved you hours of work or is powering your production applications, **please consider supporting its active maintenance and future development!**

Your support is deeply appreciated and directly helps keep this plugin up-to-date with evolving OS requirements. Every contribution, no matter the size, makes a massive difference and keeps me highly motivated to push new updates! Thank you so much for your generosity! 🙏

<p align="left">
  <a href="https://buymeacoffee.com/kiranbjm">
    <img src="assets/buy_me_a_coffee.png" alt="Buy Me a Coffee" width="220"/>
  </a>
</p>

---

## Features

- **Motion-detection intelligence** — Uses accelerometer, gyroscope & activity recognition to detect when the device is moving or stationary. Automatically toggles location services to conserve battery.
- **Background location tracking** — Continuous GPS recording with configurable `distanceFilter` and `desiredAccuracy`. Works after app is minimized, killed, or device rebooted.
- **Geofencing** — Add circular or polygon geofences with enter/exit/dwell detection. **Unlimited geofences** via proximity-based auto-load/unload — only the closest geofences within `geofenceProximityRadius` are registered with the OS (up to 100 on Android, 20 on iOS), enabling monitoring of thousands of geofences despite platform limits.
- **SQLite persistence** — All locations stored locally in SQLite. Query, count, delete, or sync to your server. Configurable retention (max days/records) and per-type persistence modes.
- **HTTP auto-sync** — Configurable batch upload with retry, exponential backoff, and offline queuing. Wi-Fi-only sync option via `disableAutoSyncOnCellular`. Configurable `maxRetries`, `retryBackoffBase`, and `retryBackoffCap` for fine-tuned retry strategy. Connectivity-aware deferred sync on both platforms. **401-aware retry** — on HTTP 401, fires a headless Dart callback to refresh JWT tokens via `registerHeadlessHeadersCallback()`, then retries with updated headers.
- **SSL certificate pinning** — Pin server certificates or SHA-256 fingerprints to prevent MITM attacks. Configure via `HttpConfig.sslPinningCertificates` (PEM) or `HttpConfig.sslPinningFingerprints` (hex SHA-256). Native validation on both platforms.
- **Dynamic HTTP headers** — Set headers at runtime via `setDynamicHeaders()`, or register a callback with `setHeadersCallback()` for on-demand header generation (e.g., rotating auth tokens). Headers merge with static `HttpConfig.headers`. Background-safe via `registerHeadlessHeadersCallback()`.
- **Route context** — Attach arbitrary metadata (`routeId`, `driverId`, `vehicleId`, etc.) to every synced location via `setRouteContext()`. Context is included in the HTTP sync body and cleared with `clearRouteContext()`.
- **Custom sync body builder** — Full control over the HTTP sync payload via `setSyncBodyBuilder()`. Receives locations and route context, returns a custom `Map` or `List`. Background-safe via `registerHeadlessSyncBodyBuilder()`.
- **Adaptive sampling** — Automatically adjusts `distanceFilter` based on detected activity (walking, driving, still), battery level, and speed. Reduces GPS polling when stationary or battery-low, increases resolution when driving. Enable with `enableAdaptiveMode: true`.
- **Health check API** — Single-call `getHealth()` returns a comprehensive diagnostic snapshot: tracking state, permissions, battery, OEM health, sensors, database stats, and auto-detected warnings. Build monitoring dashboards or pre-flight checks with zero boilerplate.
- **Headless execution** — Run Dart code in response to background events even when the Flutter UI is not running.
- **Start on boot** — Resume tracking automatically after device reboot.
- **Scheduling** — Define time-based schedules (e.g., "Mon–Fri 9AM–5PM"). Use `scheduleUseAlarmManager` on Android for exact-time execution.
- **Comprehensive logging** — SQLite-backed log system with email export.
- **Debug sounds** — Audible feedback during development for location, motion, geofence, and HTTP events.
- **Elasticity control** — Speed-based automatic distance filter scaling, with `disableElasticity` and `elasticityMultiplier` overrides.
- **Location filtering** — Reject GPS spikes and low-accuracy readings with `LocationFilter` (accuracy thresholds, max implied speed, odometer filtering).
- **Kalman filter GPS smoothing** — Optional Extended Kalman Filter smooths GPS coordinates in real-time, eliminating jitter and producing cleaner tracks. Enable with `useKalmanFilter: true` in `LocationFilter`.
- **Trip detection** — Automatic trip start/stop events based on motion state transitions. Each trip includes distance, duration, start/stop location, and all waypoints. Subscribe via `onTrip()`.
- **Polygon geofences** — Define geofences with arbitrary polygon vertices using ray-casting point-in-polygon containment checks. Set `vertices` on a `Geofence` instead of using a circular radius.
- **Auto-stop** — Automatically stop tracking after a configurable number of minutes via `stopAfterElapsedMinutes`.
- **Configurable motion sensitivity** — Tune accelerometer thresholds (`shakeThreshold`, `stillThreshold`, `stillSampleCount`) from Dart. Use built-in presets (Low / Medium / High) or set custom values. iOS auto-converts m/s² to g-force.
- **Activity recognition tuning** — Adjust confidence thresholds, stop-detection delays, and stationary behavior.
- **Timestamp metadata** — Optional extra timing fields on each location record via `enableTimestampMeta`.
- **Geofence high-accuracy mode** — Run the full continuous-GPS pipeline in geofence-only mode for reliable tight radii (e.g. 5 m) and EXIT events via the cross-platform `GeofenceConfig.geofenceModeHighAccuracy` (iOS + Android). On iOS this enables continuous GPS and the system location indicator. The legacy `AndroidConfig.geofenceModeHighAccuracy` is deprecated but still honored.
- **Prevent suspend (iOS)** — Silent audio keep-alive to prevent iOS from suspending the app in the background.
- **iOS background task protection** — All critical native operations (location persist, HTTP sync, headless engine boot, lifecycle transitions) wrapped in `beginBackgroundTask` for safe background execution.
- **iOS 17+ / 18+ session APIs** — `CLBackgroundActivitySession` (iOS 17+) and `CLServiceSession` (iOS 18+) for extended background runtime and authorization state.
- **Dart-controlled permissions** — No native dialogs. Full Dart-side customization of permission UI, translations, and behavior.
- **Foreground service toggle** — Run with or without a persistent notification (Android).
- **Shared Dart algorithms** — Location filtering (elasticity, accuracy, speed), geofence proximity evaluation, schedule parsing, and persistence logic all run in shared Dart code for cross-platform consistency. Write once — works on Android, iOS, web, and future desktop platforms.
- **Battery budget engine** — Automatic feedback control loop adjusts `distanceFilter`, `desiredAccuracy`, and periodic interval to stay within a configurable battery drain budget (`batteryBudgetPerHour`, typical 1.0–5.0 %/hr). Subscribe to real-time adjustment events via `onBudgetAdjustment()`.
- **Carbon footprint estimator** — Per-trip and cumulative CO₂ emission calculator using EU EEA 2024 mode-specific factors (gCO₂/km): car = 192, bus = 89, train = 41, walking/cycling = 0. Integrates with activity recognition to track distance per transport mode.
- **Delta encoding** — Batch location compression codec achieving 60–80% payload reduction for HTTP sync. First location transmitted in full; subsequent positions as deltas with shortened field names. Triple implementation (Dart + Kotlin + Swift) for native encoding.
- **R-tree spatial index** — O(log n) geofence proximity queries supporting 10,000+ geofences with sub-millisecond lookup. `queryCircle()` and `queryBBox()` APIs with Haversine-verified results.
- **GDPR/CCPA compliance reports** — `generateComplianceReport()` returns a structured data processing inventory covering: stored/synced counts, retention policy, privacy zones, encryption status, permissions, audit trail, and tracking config. Exports to JSON and Markdown.
- **Sparse updates** — App-level location deduplication at the persistence layer. Drops locations within `sparseDistanceThreshold` (default 50 m) of the last recorded position, with configurable idle heartbeat interval.
- **Dead reckoning** — Inertial navigation using accelerometer + gyroscope + compass when GPS is lost for longer than `deadReckoningActivationDelay` seconds. Auto-stops after configurable duration to prevent IMU drift. Query real-time state (`active`, `elapsed`, `estimatedAccuracy`) via `getDeadReckoningState()`.
- **Database encryption** — At-rest encryption for the local SQLite database. Android uses SQLCipher (AES-256) with keys stored in Android Keystore. iOS uses `NSFileProtectionComplete` backed by the Secure Enclave. Enable via `SecurityConfig(encryptDatabase: true)` or encrypt at runtime with `encryptDatabase()`.
- **Device attestation** — Verify device and app integrity using Google Play Integrity (Android) and App Attest (iOS). Generate cryptographic attestation tokens for server-side verification. Auto-refresh with configurable intervals.
- **Wi-Fi-only sync** — `disableAutoSyncOnCellular` skips HTTP auto-sync on cellular networks, syncing only when connected to Wi-Fi. Supported on Android, iOS, and Web.
- **Periodic mode** — Configurable one-shot location fixes at intervals from 60 seconds to 12 hours. Android supports sub-15-minute intervals via foreground service and exact alarms via `AlarmManager`.
- **Tracelet Doctor Overlay** — Advanced in-app diagnostic dashboard overlay (`tracelet_doctor`) to visualize tracking state, active sensors, SQLite database queue size, and OEM optimizations with live warnings and actionable fixes.
- **Driving telematics** — On-device harsh-braking / acceleration / cornering / speeding detection from the GPS stream, each with a `0–1` severity score. Opt-in via `TelematicsConfig`; subscribe with `onDrivingEvent()`. Also works on Web.
- **Crash & fall detection** — Corroborated impact detection (hard jolt **while moving**) with a user cancel-countdown before escalation. Opt-in via `ImpactConfig`; subscribe with `onImpact()` and resolve with `confirmImpact()` / `cancelImpact()`. You own the SOS UX. → **[docs](https://tracelet.ikolvi.com/en/core/driving-safety#3-crash--fall-detection)**
- **AI crash model (stable, licensed)** — Optional trained model that gates crashes on a learned probability; downloaded on demand, AES-256-GCM encrypted, with rule-engine fallback and auto-update. Trained on a CC0 / public-domain dataset (commercial-use OK). Opt-in via `ImpactConfig(crashModelUnlockUrl, crashModelLicenseKey)`.
- **Transport-mode classifier** — Fuses accelerometer + GPS to classify still / walking / running / cycling / vehicle with hysteresis. Opt-in via `ClassifierConfig`; subscribe with `onModeChange()`.
- **Motion-gated wakelock (Android)** — Drops the OEM partial wakelock when stationary and re-asserts it on movement, cutting idle battery drain. Opt-in via `AndroidConfig.releaseWakelockWhenStationary` (gated on the significant-motion wake sensor).
- **Telematics & Diagnostics APIs** — Retrieve raw telematics events (`getTelematicsEvents`), simulate mock events for testing (`simulateTelematicsEvent`), and access system logs (`getLogs`, `clearLogs`) directly from Dart, Kotlin, and Swift. The `tracelet_doctor` overlay bundles health + config + logs + telematics into a one-tap, paste-ready **bug report** (secrets redacted).
- **Live map view** — Built-in example with OpenStreetMap tiles, speed-colored route trail, geofence visualization, trip overlay, and real-time status overlay.

## Architecture

Tracelet uses a **federated plugin architecture** with 5 packages:

| Package | Description |
|---|---|
| [`tracelet`](packages/tracelet/) | App-facing Dart API — the only package you depend on |
| [`tracelet_doctor`](packages/tracelet_doctor/) | Advanced in-app diagnostic dashboard and health analysis overlay UI |
| [`tracelet_platform_interface`](packages/tracelet_platform_interface/) | Abstract platform interface + Pigeon definitions |
| [`tracelet_android`](packages/tracelet_android/) | Kotlin Android implementation |
| [`tracelet_ios`](packages/tracelet_ios/) | Swift iOS implementation |
| [`tracelet_web`](packages/tracelet_web/) | Web implementation (experimental) |

### Native SDKs (No Flutter Required)

Tracelet's core engines are also published as standalone native SDKs:

| Platform | Package | Install |
|---|---|---|
| Android | `com.ikolvi:tracelet-sdk` | [Maven Central](https://central.sonatype.com/artifact/com.ikolvi/tracelet-sdk) |
| iOS | `TraceletSDK` | [CocoaPods](https://cocoapods.org/pods/TraceletSDK) or [SPM](https://github.com/Ikolvi/Tracelet.git) |

See the [Native SDK Guide](help/NATIVE-SDK.md) and the new [Rust Core Architecture](help/RUST-CORE.md) for installation and internal details.

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

// 1. Listen to events
tl.Tracelet.onLocation((tl.Location location) {
  print('[location] $location');
});

tl.Tracelet.onMotionChange((tl.Location location) {
  print('[motionchange] isMoving: ${location.isMoving}');
});

// 2. Configure & ready
final state = await tl.Tracelet.ready(tl.Config.balanced().copyWith(
  geo: tl.GeoConfig(
    desiredAccuracy: tl.DesiredAccuracy.high,
    distanceFilter: 10.0,
  ),
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
  ),
  persistence: tl.PersistenceConfig(
    maxDaysToPersist: 7,
    maxRecordsToPersist: 5000,
  ),
  logger: tl.LoggerConfig(
    debug: true,
    logLevel: tl.LogLevel.verbose,
  ),
));

// 3. Start tracking
if (!state.enabled) {
  await tl.Tracelet.start();
}
```

## Permissions

Tracelet does **not** show any native permission dialogs — only the OS prompt
is triggered. All permission UI is controlled from Dart, giving you full
freedom to customize dialogs, translations, and behavior.

| Method | Description |
|---|---|
| `Tracelet.getPermissionStatus()` | Read-only check — no dialog |
| `Tracelet.requestPermission()` | Triggers OS dialog, returns result |
| `Tracelet.getNotificationPermissionStatus()` | Notification status (Android 13+) |
| `Tracelet.requestNotificationPermission()` | Request notification permission (Android 13+) |
| `Tracelet.openAppSettings()` | Opens the app's system settings |
| `Tracelet.openLocationSettings()` | Opens device location settings |
| `Tracelet.openBatterySettings()` | Opens battery optimization (Android) |

**Status codes:** `0` notDetermined · `1` denied · `2` whenInUse · `3` always · `4` deniedForever

### Recommended Flow

```dart
final status = await tl.Tracelet.getPermissionStatus();
if (status == 4) {
  // Permanently denied — show YOUR Dart dialog with "Open Settings" button
  await tl.Tracelet.openAppSettings();
  return;
}
if (status == 0 || status == 1) {
  final result = await tl.Tracelet.requestPermission(); // foreground
  if (result == 2) {
    // Show background rationale dialog, then:
    await tl.Tracelet.requestPermission(); // upgrade to Always
  }
} else if (status == 2) {
  // Already foreground — show rationale, then upgrade
  await tl.Tracelet.requestPermission();
}
```

> See the [Permissions Guide](help/PERMISSIONS.md) for
> complete dialog implementations (denied dialog, background rationale dialog,
> notification rationale dialog, full escalation flow) with copy-paste Flutter code.

## Background Tracking

### With Foreground Notification (Recommended)

> **Android 13+:** Request notification permission first, otherwise the
> notification is hidden. See
> [Notification Permission](packages/tracelet/README.md#notification-permission-android-13).

> **iOS:** Foreground service config is ignored — iOS uses its own
> background-mode mechanisms (BackgroundTasks, CoreLocation significant
> changes). No notification permission is needed for background location.

```dart
// Android 13+: ensure notification permission
if (Platform.isAndroid) {
  final ns = await tl.Tracelet.getNotificationPermissionStatus();
  if (ns != 3) await tl.Tracelet.requestNotificationPermission();
}

await tl.Tracelet.ready(tl.Config.balanced().copyWith(
  app: tl.AppConfig(
    stopOnTerminate: false,
    startOnBoot: true,
  ),
  android: tl.AndroidConfig(
    foregroundService: tl.ForegroundServiceConfig(
      notificationTitle: 'My App',
      notificationText: 'Tracking your location',
    ),
  ),
));
await tl.Tracelet.start();
```

### Without Foreground Notification

```dart
await tl.Tracelet.ready(tl.Config.balanced().copyWith(
  app: tl.AppConfig(
    stopOnTerminate: true,
  ),
  android: tl.AndroidConfig(
    foregroundService: tl.ForegroundServiceConfig(enabled: false),
  ),
));
await tl.Tracelet.start();
```

> See the [Background Tracking Guide](help/BACKGROUND-TRACKING.md) for
> runtime switching with `setConfig()`.

## OEM Compatibility (Chinese Manufacturers)

Devices from Huawei, Xiaomi, OnePlus, Samsung, Oppo, and Vivo ship with custom power management that aggressively kills background apps. Tracelet automatically applies mitigations (such as force-enabling foreground services on restricted OEMs and utilizing OEM-safe Wakelock tags).

You can also use the **Settings Health API** to prompt users to whitelist the app manually:

```dart
final health = await tl.Tracelet.getSettingsHealth();
if (health['isAggressiveOem'] == true) {
  // Automatically opens the manufacturer-specific settings screen 
  // (e.g. Xiaomi Autostart, Huawei App Launch, etc.)
  await tl.Tracelet.showPowerManager();
}
```

See the [OEM Compatibility Guide](help/OEM-COMPATIBILITY.md) for full details on manufacturer-specific behaviors.

## Documentation

The full documentation is available at [**tracelet.ikolvi.com**](https://tracelet.ikolvi.com).

| Guide | Description |
|---|---|
| [Motion & Notifications](packages/tracelet/docs/motion-and-notifications.md) | Advanced Config: Speed-based Motion Detection & Smart Notifications |
| [Android Setup](help/INSTALL-ANDROID.md) | Gradle, permissions, and manifest configuration |
| [iOS Setup](help/INSTALL-IOS.md) | Info.plist, capabilities, and entitlements |
| [Motion Detection Architecture](help/MOTION-DETECTION.md) | How `STATIONARY`/`MOVING` states and heartbeat actually work |
| [Permissions](help/PERMISSIONS.md) | Permission flow, status codes, Dart dialog examples |
| [Background Tracking](help/BACKGROUND-TRACKING.md) | Foreground service, silent mode, runtime switching |
| [API Reference](help/API.md) | All methods, events, and return types |
| [Configuration](help/CONFIGURATION.md) | All config groups with property tables |
| [Configuration Profiles](help/CONFIGURATION-PROFILES.md) | Easy-setup predefined profiles (Balanced, High Accuracy, Low Power) |
| [Kalman Filter](help/KALMAN-FILTER.md) | GPS smoothing — how it works, when to use it |
| [Trip Detection](help/TRIP-DETECTION.md) | Automatic trip events — setup, API, edge cases |
| [Polygon Geofences](help/POLYGON-GEOFENCES.md) | Polygon geofences — vertices, ray-casting, examples |
| [Web Support](help/WEB-SUPPORT.md) | Web platform capabilities, limitations, and browser APIs |
| [iOS Background Hardening](help/IOS-BACKGROUND-HARDENING.md) | Background task protection, session APIs, prevent suspend |
| [Adaptive Sampling](help/ADAPTIVE-SAMPLING.md) | Multi-factor distance filter — activity, battery, speed |
| [Health Check](help/HEALTH-CHECK.md) | Single-call diagnostics — warnings, permissions, sensors |
| [HTTP Sync](help/HTTP-SYNC.md) | Retry strategy, exponential backoff, connectivity handling |
| [Privacy Zones](help/PRIVACY-ZONES.md) | Location exclusion zones for sensitive areas |
| [Audit Trail](help/AUDIT-TRAIL.md) | Cryptographic hash-chain audit trail for compliance |
| [Mock Detection](help/MOCK-DETECTION.md) | Detect spoofed locations, mock provider flags, trust scoring |
| [OEM Compatibility](help/OEM-COMPATIBILITY.md) | OEM-specific battery kill issues, manufacturer workarounds |
| [Battery Budget](help/BATTERY-BUDGET.md) | Feedback loop — auto-tune tracking to stay within battery drain target |
| [Delta Encoding](help/DELTA-ENCODING.md) | 60–80% HTTP payload compression via differential location encoding |
| [Carbon Estimator](help/CARBON-ESTIMATOR.md) | Real-time CO₂ estimation by transport mode (EU EEA 2024 factors) |
| [Compliance Report](help/COMPLIANCE-REPORT.md) | Auto-generated GDPR Article 30 / CCPA compliance reports |
| [Dead Reckoning](help/DEAD-RECKONING.md) | IMU-based inertial navigation during GPS signal loss |
| [Database Encryption](help/DATABASE-ENCRYPTION.md) | At-rest SQLite encryption (SQLCipher / NSFileProtection) |
| [Device Attestation](help/DEVICE-ATTESTATION.md) | Platform attestation tokens (Play Integrity / App Attest) |
| [Sparse Updates](help/SPARSE-UPDATES.md) | App-level location deduplication — reduce DB writes and sync volume |
| [Periodic Mode](help/PERIODIC-MODE.md) | Timed one-shot GPS fixes — WorkManager, foreground service, exact alarms |

## Tracelet Doctor (Diagnostic UI Overlay)

Visualize and troubleshoot permissions, tracking state, active sensors, SQLite database queue size, and OEM battery optimizations with a single line of code using the `tracelet_doctor` package:

Add it under `dev_dependencies` (it's a debug tool — Flutter excludes dev-dependency packages from release builds):

```yaml
dependencies:
  tracelet: ^2.0.5

dev_dependencies:
  tracelet_doctor: ^1.0.0
```

Guard usage behind `kDebugMode` so it's tree-shaken out of release builds:

```dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:tracelet_doctor/tracelet_doctor.dart';

// Show the premium diagnostic dashboard overlay — debug builds only:
if (kDebugMode) {
  TraceletDoctor.show(context);
}
```

For more details, see the [Tracelet Doctor Package README](packages/tracelet_doctor/README.md).

## Requirements

| Platform | Minimum Version |
|---|---|
| Android | API 26 (Android 8.0 Oreo) |
| iOS | 14.0 |
| Web | Modern browsers (Chrome, Firefox, Safari, Edge) |
| Flutter | 3.22+ |
| Dart | 3.4+ |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

All native code is written from scratch. No proprietary SDK dependencies.
