# Mock Location Detection & Prevention

Tracelet includes a multi-layered mock location detection system that identifies
and optionally rejects GPS spoofing attempts. It works across Android, iOS, and
web — using platform-specific signals where available and pure-Dart heuristics
as a cross-platform fallback.

---

## Quick Start

```dart
Config(
  geo: GeoConfig(
    filter: LocationFilter(
      rejectMockLocations: true,
      mockDetectionLevel: MockDetectionLevel.heuristic,
    ),
  ),
)
```

This enables full mock detection with automatic rejection. Spoofed locations
are silently dropped and never delivered to your `onLocation` callback.

---

## Detection Levels

Detection is controlled by the `mockDetectionLevel` option on `LocationFilter`.
Higher levels apply more checks but may increase false positives (e.g. flagging
legitimate external GPS receivers).

| Level | Enum Value | Checks Applied |
|-------|------------|----------------|
| 0 | `MockDetectionLevel.disabled` | None. All locations accepted unconditionally. |
| 1 | `MockDetectionLevel.basic` | Platform API flag only (see below). |
| 2 | `MockDetectionLevel.heuristic` | Basic + native heuristics + Dart timestamp check. |

### Level 0 — Disabled

No mock detection. The `isMock` field on `Location` is always `false`.
Use this when you don't care about spoofing (e.g. development/testing).

### Level 1 — Basic (Default)

Uses the platform's built-in mock location flag:

| Platform | API Used | Min Version |
|----------|----------|-------------|
| Android | `Location.isMock()` | API 31 (Android 12) |
| Android | `Location.isFromMockProvider()` | API 18 (Android 4.3) |
| iOS | `CLLocation.sourceInformation?.isSimulatedBySoftware` | iOS 15.0 |
| iOS < 15 | — | Always `false` |
| Web | — | Always `false` |

This catches casual spoofing via Developer Options or "Fake GPS" apps.
**Limitation:** On rooted/jailbroken devices, Xposed/Magisk modules can strip
the mock flag before it reaches your app.

### Level 2 — Heuristic

Everything from Level 1, plus additional native-side and Dart-side checks that
are harder to bypass:

#### Android Heuristics

| Check | Signal | Threshold |
|-------|--------|-----------|
| **Satellite count** | `location.extras.getInt("satellites")` | Flag if exactly 0 satellites with accuracy < 50m |
| **Elapsed realtime drift** | `location.elapsedRealtimeNanos` vs `SystemClock.elapsedRealtimeNanos()` | Flag if drift > 10 seconds or negative (future) |

**Satellite count:** Real GPS fixes outdoors report 4–30 visible satellites.
Mock locations from spoofing apps typically report 0 because they don't
interact with the GPS hardware. A satellite count of 0 combined with high
apparent accuracy (< 50m) is a strong spoofing indicator.

**Elapsed realtime drift:** Android's `Location.elapsedRealtimeNanos` is set by
the GPS hardware using the kernel monotonic clock — it cannot be manipulated
from userspace without root. The check compares this against the current
`SystemClock.elapsedRealtimeNanos()`. A large drift means the location's
hardware timestamp doesn't match when it was actually received, indicating
injection or replay.

#### iOS Heuristics

| Check | Signal | Threshold |
|-------|--------|-----------|
| **Timestamp drift** | `Date()` vs `location.timestamp` | Flag if drift > 10 seconds |

iOS doesn't expose satellite count or a monotonic elapsed-realtime clock on
`CLLocation`, so the heuristic checks are more limited. The timestamp drift
check catches replayed locations with stale timestamps.

#### Dart Heuristics (All Platforms)

| Check | Signal | Threshold |
|-------|--------|-----------|
| **Timestamp monotonicity** | Current `timestampMs` vs previous `timestampMs` | Flag if current < previous |

Location timestamps from real GPS hardware are monotonically increasing.
A backward jump indicates that locations are being replayed from a recorded
track or injected with manipulated timestamps.

---

## Rejection Behavior

When `rejectMockLocations: true` is set, locations flagged as mock are
automatically rejected. The rejection behavior depends on your `filterPolicy`:

| Policy | Behavior |
|--------|----------|
| `LocationFilterPolicy.adjust` (default) | Silent drop — location is not delivered. |
| `LocationFilterPolicy.ignore` | Silent drop — location is not delivered. |
| `LocationFilterPolicy.discard` | Drop + error event dispatched to `onError`. |

### Filter Reasons

Rejected locations produce one of two filter reasons:

| Reason | Meaning |
|--------|---------|
| `MOCK_LOCATION` | Flagged by platform API or native heuristic. |
| `MOCK_LOCATION_TIMESTAMP` | Failed timestamp monotonicity check (heuristic level only). |

---

## Heuristic Metadata

When `mockDetectionLevel` is set to `heuristic`, each `Location` object
includes a `mockHeuristics` field with detailed diagnostic data from the
native detection engine:

```dart
Tracelet.onLocation((Location loc) {
  if (loc.mockHeuristics != null) {
    print('Satellites: ${loc.mockHeuristics!.satellites}');
    print('Realtime drift: ${loc.mockHeuristics!.elapsedRealtimeDriftMs}ms');
    print('Timestamp drift: ${loc.mockHeuristics!.timestampDriftMs}ms');
    print('Platform flag: ${loc.mockHeuristics!.platformFlagMock}');
  }
});
```

### `MockHeuristics` Fields

| Field | Type | Platform | Description |
|-------|------|----------|-------------|
| `satellites` | `int?` | Android | GPS satellite count. `0` = suspicious, `-1` = unavailable. |
| `elapsedRealtimeDriftMs` | `double?` | Android | Monotonic clock drift in milliseconds. |
| `timestampDriftMs` | `double?` | iOS | Wall-clock timestamp drift in milliseconds. |
| `platformFlagMock` | `bool?` | Both | Raw platform API mock flag for logging. |

This data is useful for:
- **Server-side validation** — send heuristics to your backend for additional
  anti-spoofing analysis.
- **Analytics** — track the prevalence and type of spoofing attempts.
- **Custom logic** — implement your own scoring/threshold system beyond
  Tracelet's built-in checks.

> **Note:** `mockHeuristics` is `null` when detection level is `disabled` or
> `basic`. It is populated regardless of whether `rejectMockLocations` is
> enabled — you can inspect heuristics without automatic rejection.

---

## Provider Change Events

When a mock location is detected for the first time during a tracking session,
a `ProviderChangeEvent` is fired with `mockLocationsDetected: true`:

```dart
Tracelet.onProviderChange((ProviderChangeEvent event) {
  if (event.mockLocationsDetected) {
    // Alert the user or log to server
    print('⚠️ Mock location provider detected!');
  }
});
```

This event fires only once per session (not on every mock location) to avoid
spamming your event handler.

---

## Configuration Reference

```dart
LocationFilter(
  // Enable/disable automatic rejection of mock locations.
  // Default: false
  rejectMockLocations: true,

  // Detection depth. Higher = more checks, more false positive risk.
  // Default: MockDetectionLevel.disabled
  mockDetectionLevel: MockDetectionLevel.heuristic,

  // Controls rejection behavior (also affects accuracy/speed filters).
  // Default: LocationFilterPolicy.adjust (silent drop)
  policy: LocationFilterPolicy.discard,
)
```

---

## Platform Limitations

### Android
- **Rooted devices:** Xposed Framework, Magisk modules, and custom ROMs can
  strip the `isMock` / `isFromMockProvider` flag before it reaches your app.
  Heuristic mode partially compensates for this by checking satellite count
  and elapsed realtime drift.
- **External GPS receivers:** Bluetooth GPS pucks may report 0 satellites in
  the `Location` extras while still being legitimate. Consider using `basic`
  level if your users commonly use external receivers.

### iOS
- **iOS < 15:** No mock detection API exists. `isMock` is always `false` at
  `basic` level. Heuristic timestamp drift check still works.
- **Jailbroken devices:** Location simulation hooks can bypass
  `sourceInformation` entirely.
- **Simulators:** Xcode's simulated locations are correctly flagged as mock
  on iOS 15+.

### Web
- **No detection:** The browser Geolocation API provides no mock/spoof
  signals. `isMock` is always `false`. Browser extensions that override
  `navigator.geolocation` are undetectable.

---

## Recommendations

| Use Case | Recommended Level |
|----------|-------------------|
| Development / testing | `disabled` |
| General consumer app | `basic` |
| Fleet management / logistics | `heuristic` |
| High-security (banking, compliance) | `heuristic` + server-side validation |

For high-security applications, combine `heuristic` detection with server-side
analysis of the `mockHeuristics` data. No client-side check is 100% reliable
on rooted/jailbroken devices.

---

## Example: Full Setup

```dart
import 'package:tracelet/tracelet.dart';

Future<void> initTracking() async {
  // Listen for mock detection alerts
  Tracelet.onProviderChange((event) {
    if (event.mockLocationsDetected) {
      // Warn user, log to server, or stop tracking
      print('Mock location detected!');
    }
  });

  // Listen for locations with heuristic metadata
  Tracelet.onLocation((Location loc) {
    print('${loc.coords.latitude}, ${loc.coords.longitude}');
    print('Mock: ${loc.isMock}');

    if (loc.mockHeuristics != null) {
      // Log heuristics to your analytics service
      analytics.log('location_heuristics', loc.mockHeuristics!.toMap());
    }
  });

  // Configure with full mock detection
  await Tracelet.ready(Config(
    geo: GeoConfig(
      distanceFilter: 10.0,
      filter: LocationFilter(
        rejectMockLocations: true,
        mockDetectionLevel: MockDetectionLevel.heuristic,
        policy: LocationFilterPolicy.discard, // Fire error events on rejection
      ),
    ),
  ));

  await Tracelet.start();
}
```
