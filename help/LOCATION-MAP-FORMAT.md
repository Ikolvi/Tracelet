# Location Map Format Contract

This document defines the canonical `Map<String, Any?>` format for location data exchanged between native SDKs and the Flutter platform layer.

All map builders (SDK `buildLocationMap()`, `enrichLocation()`, DB `locationRowToMap()` / `cursorToLocation()`) **must** produce maps conforming to this contract. The Flutter `EventDispatcher.mapToTlLocation()` on both platforms consumes this format.

## Canonical Structure

```json
{
  "uuid": "string",
  "timestamp": "ISO-8601 string or epoch millis (long). See [TIMESTAMP-FORMAT.md](TIMESTAMP-FORMAT.md) for details.",
  "is_moving": true,
  "odometer": 1234.5,
  "event": "motionchange | location | heartbeat | geofence | ...",
  "mock": false,

  "coords": {
    "latitude": 37.4219983,
    "longitude": -122.084,
    "accuracy": 5.0,
    "speed": 2.5,
    "heading": 180.0,
    "altitude": 100.0,
    "altitudeAccuracy": 3.0,
    "speedAccuracy": 1.5,
    "headingAccuracy": 10.0,
    "floor": 2
  },

  "battery": {
    "level": 0.75,
    "is_charging": true
  },

  "activity": {
    "type": "still | walking | running | onFoot | inVehicle | onBicycle | unknown",
    "confidence": 85
  },

  "address": {
    "street": "1600 Amphitheatre Pkwy",
    "city": "Mountain View",
    "state": "CA",
    "country": "United States",
    "postalCode": "94043",
    "isoCountryCode": "US"
  },

  "extras": { "key": "value" }
}
```

## Key Rules

| Key | Convention | Notes |
|-----|-----------|-------|
| `coords` | **Nested map** | Never flat. All coordinate fields live inside `coords`. |
| `coords.altitudeAccuracy` | **camelCase** | Not `altitude_accuracy`. `-1` when unknown, never `0`. |
| `coords.speedAccuracy` | **camelCase** | Not `speed_accuracy`. `-1` when unknown, never `0`. |
| `coords.headingAccuracy` | **camelCase** | Not `heading_accuracy`. `-1` when unknown, never `0`. |
| `battery.is_charging` | **snake_case** | Not `isCharging`. |
| `is_moving` | **snake_case** | EventDispatcher also accepts `isMoving` as fallback. |
| `mock` | **No prefix** | Not `isMock` or `is_mock`. |
| `activity.type` | **String** | Matches Dart `ActivityType` enum `.name` values. |
| `activity.confidence` | **Int (0–100)** | Raw percentage from platform API. |
| `address` | **Nested map** | Never flat. Only populated when `resolveAddress` is true. |

## Producers (must output this format)

| Component | Platform | File |
|-----------|----------|------|
| `LocationEngine.enrichLocation()` | Android | `sdk/android/.../location/LocationEngine.kt` |
| `PeriodicLocationWorker.buildLocationMap()` | Android | `sdk/android/.../location/PeriodicLocationWorker.kt` |
| `BatteryUtils.getBatteryInfo()` | Android | `sdk/android/.../util/BatteryUtils.kt` |
| `TraceletDatabase.cursorToLocation()` | Android | `sdk/android/.../db/TraceletDatabase.kt` |
| `LocationEngine.buildLocationMap()` | iOS | `sdk/ios/.../location/LocationEngine.swift` |
| `LocationEngine.onDrLocationEstimated()` | iOS | `sdk/ios/.../location/LocationEngine.swift` |
| `TraceletDatabase.locationRowToMap()` | iOS | `sdk/ios/.../db/TraceletDatabase.swift` |
| `TraceletLocation.toMap()` | Android | `sdk/android/.../model/Models.kt` |
| `TraceletLocation.toMap()` | iOS | `sdk/ios/.../model/Models.swift` |

## Consumers

| Component | Platform | File |
|-----------|----------|------|
| `EventDispatcher.mapToTlLocation()` | Android | `packages/tracelet_android/.../EventDispatcher.kt` |
| `EventDispatcher.mapToTlLocation()` | iOS | `packages/tracelet_ios/.../EventDispatcher.swift` |
| `TraceletDatabase.insertLocation()` | Android | `sdk/android/.../db/TraceletDatabase.kt` |
| `TraceletDatabase.insertLocation()` | iOS | `sdk/ios/.../db/TraceletDatabase.swift` |
| `Location.fromMap()` | Dart | `packages/tracelet/lib/src/models/location.dart` |
| `Location.fromTl()` | Dart | `packages/tracelet/lib/src/models/location.dart` |

## Dart-side Resilience

The Dart `fromMap()` factories accept both conventions for backward compatibility:

- `map['speed_accuracy'] ?? map['speedAccuracy']`
- `map['is_charging'] ?? map['isCharging']`
- `map['is_moving'] ?? map['isMoving']`
- `map['is_mock'] ?? map['isMock'] ?? map['mock']`

This resilience is intentional — it prevents crashes when reading data written by older SDK versions. However, **new code must always produce the canonical format**.

## DB Persistence

The database flattens the nested structure into columns. When reading back:

- The DB output layer (`cursorToLocation` / `locationRowToMap`) reconstructs the nested map format.
- DB consumers (`insertLocation`) read from nested maps first, with flat-key fallbacks.
- The iOS DB `insertLocation` accepts both `speedAccuracy` and `speed_accuracy` in coords (camelCase preferred).
- `altitudeAccuracy`, `speedAccuracy` and `headingAccuracy` are stored and come back on every stored read and in the default sync payload; a row stored before they were persisted reads `-1` ([#445](https://github.com/Ikolvi/Tracelet/issues/445)).

## Test Coverage

Format compliance is enforced by dedicated test suites:

- **Android**: `sdk/android/.../test/.../model/LocationMapFormatTest.kt` (28 tests)
- **iOS**: `sdk/ios/Tests/TraceletSDKTests/LocationMapFormatTests.swift` (28 tests)
- **Dart**: `packages/tracelet/test/location_map_format_test.dart` (25 tests)
