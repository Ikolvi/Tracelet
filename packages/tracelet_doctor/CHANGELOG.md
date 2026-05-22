## 1.0.4

 - Update a dependency to the latest release.

## 1.0.3

 - Update a dependency to the latest release.

## 1.0.2

 - Update a dependency to the latest release.

# Changelog

## 1.0.1

- **CHORE**: Update `tracelet` dependency to `^2.0.6`.
- **DOCS**: Added `example/example.dart` for pub.dev documentation scoring.
- **DOCS**: Added documentation cross-references back to `tracelet` in README.md.

## 1.0.0

- **Initial release** of Tracelet Doctor.
- Drop-in diagnostic bottom sheet via `TraceletDoctor.show(context)`.
- Permission status card (location, motion activity, accuracy authorization).
- Tracking state card (enabled/disabled, mode, motion, odometer, scheduler).
- Battery & OEM card with aggression rating meter (Huawei, Xiaomi, Samsung detection).
- Configuration review card with 5 smart issue detectors:
  - Missing headless task registration detection.
  - Tracking active without "Always" permission warning.
  - Mock locations detected during active tracking.
  - Power Save mode active during tracking.
  - Aggressive OEM without battery optimization exemption.
- Sensor availability grid (accelerometer, gyroscope, magnetometer, significant-motion).
- Database & device card with pending queue count and **clear pending locations** button with confirmation dialog.
- Warning list with 12 `HealthWarning` types and human-readable descriptions.
- Friendly "Tracelet Not Available" screen when plugin is not initialized.
- Copy-to-clipboard for full JSON diagnostic report.
- Re-run diagnostics without dismissing the sheet.
- Animated loading state and graceful error handling with retry.
- Dark glassmorphic theme with semantic status colors.
