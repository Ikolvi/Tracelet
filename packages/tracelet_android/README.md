# tracelet_android

Android implementation of the [Tracelet](https://pub.dev/packages/tracelet) background geolocation plugin.

This package uses Kotlin and native Android APIs (FusedLocationProvider, Room, WorkManager, Geofencing API) to provide production-grade background location tracking.

## Native Features

- **Kalman Filter GPS Smoothing** — Extended Kalman Filter implementation (`KalmanLocationFilter.kt`) smooths raw GPS coordinates using device-reported accuracy as measurement noise. Produces cleaner tracks and eliminates jitter. [Learn more →](https://github.com/Ikolvi/Tracelet/blob/main/help/KALMAN-FILTER.md)
- **Trip Detection** — `TripManager.kt` tracks motion state transitions to detect trip start/stop. Each trip includes distance, duration, waypoints, and start/stop locations. [Learn more →](https://github.com/Ikolvi/Tracelet/blob/main/help/TRIP-DETECTION.md)
- **Polygon Geofences** — Ray-casting point-in-polygon algorithm in `GeofenceManager.kt` for arbitrary polygon containment checks alongside circular geofences. [Learn more →](https://github.com/Ikolvi/Tracelet/blob/main/help/POLYGON-GEOFENCES.md)
- **Mock Location Detection** — Multi-layered spoof detection using `Location.isMock()` (API 31+) / `isFromMockProvider()` (API 18+), satellite count analysis, and `SystemClock.elapsedRealtimeNanos` drift detection. Configurable via `MockDetectionLevel`. [Learn more →](https://github.com/Ikolvi/Tracelet/blob/main/help/MOCK-DETECTION.md)
- **Unlimited Geofences** — Proximity-based auto-load/unload in `GeofenceManager.kt`. Only the closest geofences within `geofenceProximityRadius` are registered with the OS (up to 100), enabling monitoring of thousands of geofences. Geofences are dynamically swapped on each location update with `geofencesChange` events.
- **OEM Compatibility** — Automatic mitigations for aggressive OEM power management: Huawei PowerGenie wakelock tag hack, Xiaomi autostart detection, Samsung/OnePlus/Oppo/Vivo settings deep-links, boot receiver wakelock, and ProGuard consumer rules. Settings Health API exposes device health for user-facing onboarding. [Learn more →](https://github.com/Ikolvi/Tracelet/blob/main/help/OEM-COMPATIBILITY.md)
- **HTTP Sync Retry Engine** — Configurable retry with exponential backoff in `HttpSyncManager.kt` for transient 5xx, 429, and timeout failures. Respects `Retry-After` headers and defers sync on connectivity loss. [Learn more →](https://github.com/Ikolvi/Tracelet/blob/main/help/HTTP-SYNC.md)
- **Configurable Motion Sensitivity** — `MotionDetector.kt` reads `shakeThreshold`, `stillThreshold`, and `stillSampleCount` from config at runtime, allowing per-app tuning of accelerometer sensitivity without code changes.
- **Delta Encoding** — Native `DeltaEncoder.kt` compresses HTTP sync payloads by encoding only field deltas between consecutive locations, achieving 60–80% bandwidth reduction. Mirrors the Dart implementation for platform consistency.
- **Wi-Fi-Only Sync** — `HttpSyncManager.kt` supports `disableAutoSyncOnCellular` to skip auto-sync on cellular networks.
- **Periodic Mode** — `PeriodicLocationWorker` supports configurable intervals (60 sec–12 hrs), foreground service for sub-15-minute intervals, and exact alarms via `AlarmManager.setExactAndAllowWhileIdle()`.

## Usage

**You should not depend on this package directly.** Instead, depend on [`tracelet`](https://pub.dev/packages/tracelet) which automatically includes this package on Android builds.

```yaml
dependencies:
  tracelet: ^1.1.0
```

For Android-specific setup (permissions, Gradle configuration), see the [Android Setup Guide](https://github.com/Ikolvi/Tracelet/blob/main/help/INSTALL-ANDROID.md).

## Related Packages

| Package | Description |
|---|---|
| [`tracelet`](https://pub.dev/packages/tracelet) | App-facing Dart API — the only package you depend on |
| [`tracelet_platform_interface`](https://pub.dev/packages/tracelet_platform_interface) | Abstract platform interface |
| [`tracelet_ios`](https://pub.dev/packages/tracelet_ios) | iOS implementation |
| [`tracelet_web`](https://pub.dev/packages/tracelet_web) | Web implementation |

## More Information

- [GitHub Repository](https://github.com/Ikolvi/Tracelet)
- [Documentation](https://github.com/Ikolvi/Tracelet/tree/main/help)
- [Issue Tracker](https://github.com/Ikolvi/Tracelet/issues)

