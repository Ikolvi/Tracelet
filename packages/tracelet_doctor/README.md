# Tracelet Doctor

📚 **Official Documentation:** [tracelet.ikolvi.com](https://tracelet.ikolvi.com)

<p align="left">
  <a href="https://tracelet.ikolvi.com/copy-prompt?utm_source=pubdev&utm_medium=readme&utm_campaign=copy_prompt&utm_content=tracelet_doctor">
    <img src="https://img.shields.io/badge/%E2%9C%A8%20Copy%20AI%20Setup%20Prompt-0F9D58?style=for-the-badge&logoColor=white" alt="Copy AI Setup Prompt"/>
  </a>
</p>

> ⚡ **Set up Tracelet with AI.** Click the badge to copy a ready-made prompt, then paste it into your AI coding assistant (Cursor, Claude Code, Kiro, Copilot Chat…) — it interviews you, then installs and configures Tracelet (and wires up this diagnostic overlay as a debug-only dev dependency) in your Flutter app.


[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Pub Package](https://img.shields.io/pub/v/tracelet_doctor.svg)](https://pub.dev/packages/tracelet_doctor)
[![tracelet Pub](https://img.shields.io/pub/v/tracelet.svg)](https://pub.dev/packages/tracelet)

> **Drop-in diagnostic overlay for [Tracelet](https://pub.dev/packages/tracelet)** — visualize permissions, OEM health, battery state, sensors, and tracking status in a single tap.

## Screenshot

The Doctor shows a premium dark-themed bottom sheet with:

- ⚠️ **Warnings** — actionable issues (permission denied, power save, aggressive OEM, mock GPS, etc.)
- 🛡️ **Permissions** — location, motion activity, accuracy authorization
- 📍 **Tracking State** — enabled/disabled, mode, motion, odometer, scheduler
- 🔋 **Battery & OEM** — power save, battery optimization, manufacturer, aggression rating meter
- 📡 **Sensors** — accelerometer, gyroscope, magnetometer, significant-motion
- 💾 **Database & Device** — pending location count, mock detection, platform, OS version

## Quick Start

Tracelet Doctor is a **debugging tool**, so add it under `dev_dependencies` — Flutter
excludes dev-dependency packages from release builds, keeping it out of what you ship:

```yaml
dependencies:
  tracelet: ^2.0.6

dev_dependencies:
  tracelet_doctor: ^1.0.1
```

Because it lives in `dev_dependencies`, guard every reference to it behind
`kDebugMode` so the import is tree-shaken out of release builds and your app still
compiles in release mode:

```dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:tracelet_doctor/tracelet_doctor.dart';

// Show the diagnostic sheet — debug builds only.
if (kDebugMode) {
  TraceletDoctor.show(context);
}
```

A common pattern is a debug-only trigger, so it never appears in production:

```dart
Scaffold(
  // ...
  floatingActionButton: kDebugMode
      ? FloatingActionButton(
          onPressed: () => TraceletDoctor.show(context),
          child: const Icon(Icons.medical_services),
        )
      : null,
);
```

That's it — one line to show it, and it's automatically stripped from release builds.

> **Why `dev_dependencies`?** In release mode Flutter drops dev-dependency packages,
> and the `kDebugMode` guards let the Dart tree-shaker remove the Doctor code and its
> import entirely — so it adds nothing to your production app size and can't be opened
> by end users. If you instead need the diagnostics available in a production support
> build, move `tracelet_doctor` to regular `dependencies` and drop the `kDebugMode`
> guards.

## Features

- **Zero native code** — pure Dart/Flutter widget
- **One-line integration** — `TraceletDoctor.show(context)`
- **Dark glassmorphic theme** — premium aesthetic with semantic status colors
- **12 warning types** — automatically computed from device state
- **Copy to clipboard** — export the full diagnostic JSON for sharing
- **Re-run** — refresh diagnostics without dismissing the sheet
- **Loading state** — animated pulse indicator while gathering data
- **Error handling** — graceful retry on platform call failures

## How It Works

The Doctor calls `Tracelet.getHealth()` internally, which fires 10 parallel platform calls:

1. `getState()` — tracking enabled, mode, motion, odometer
2. `getProviderState()` — location services, GPS, network, accuracy
3. `getSettingsHealth()` — OEM manufacturer, aggression rating
4. `getSensors()` — accelerometer, gyroscope, magnetometer, sig-motion
5. `getDeviceInfo()` — platform, OS version
6. `isPowerSaveMode()` — battery saver active
7. `isIgnoringBatteryOptimizations()` — app exemption status
8. `getPermissionStatus()` — location authorization
9. `getMotionPermissionStatus()` — motion/activity recognition
10. `getCount()` — pending locations in the database

All results are aggregated into a typed `HealthCheck` object with automatically computed `warnings`.

## Architecture

This is a **separate, optional package** in the Tracelet monorepo:

| Package | Description |
|---|---|
| `tracelet` | Core SDK — the only package apps depend on ([pub.dev](https://pub.dev/packages/tracelet)) |
| **`tracelet_doctor`** (this package) | Diagnostic overlay widget |
| `tracelet_platform_interface` | Abstract platform interface |
| `tracelet_android` | Kotlin Android implementation |
| `tracelet_ios` | Swift iOS implementation |
| `tracelet_web` | Web implementation |

## License

Apache 2.0 — see [LICENSE](../../LICENSE) for details.
