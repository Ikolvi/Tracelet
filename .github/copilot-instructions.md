# Tracelet — Global Copilot Instructions

## Project Identity
- **Name**: Tracelet
- **Type**: Federated Flutter plugin (4 packages) for production-grade background geolocation
- **License**: Apache 2.0 — all code must be original, no proprietary SDK wrappers
- **Languages**: Dart, Kotlin (Android), Swift (iOS)

## Monorepo Structure
```
Tracelet/
├── packages/
│   ├── tracelet/                          # App-facing Dart API
│   ├── tracelet_platform_interface/       # Abstract platform interface + Pigeon defs
│   ├── tracelet_android/                  # Kotlin Android implementation
│   └── tracelet_ios/                      # Swift iOS implementation
├── melos.yaml
├── PLAN.md
└── .github/
```

## Golden Rules (ALL packages)
1. **Never copy code from transistorsoft** — all native code is written from scratch. Reference only public platform APIs (Android SDK, iOS SDK, Google Play Services).
2. **Type-safety first** — use Pigeon for Dart↔Native communication. No raw string-based MethodChannel dispatching except for EventChannel streams.
3. **Null-safety** — all Dart code is sound null-safe. Kotlin uses strict nullability. Swift uses optionals correctly.
4. **No `dynamic`** — avoid `dynamic` in Dart. Use typed maps (`Map<String, Object?>`) or proper model classes.
5. **Error handling** — every native call must handle errors. Never swallow exceptions. Propagate errors back to Dart as typed error codes.
6. **Thread safety** — SQLite writes use serial queues/single-thread executors. Platform channel calls happen on the main/UI thread. Heavy work happens on background threads.
7. **Battery consciousness** — this is the #1 product differentiator. Every design decision must consider battery impact. Never poll. Always use platform event-driven APIs.

## Naming Conventions
| Context | Convention | Example |
|---|---|---|
| Dart classes | PascalCase | `TraceletPlatform`, `GeoConfig` |
| Dart methods/properties | camelCase | `getCurrentPosition()`, `distanceFilter` |
| Dart files | snake_case | `background_geolocation.dart`, `geo_config.dart` |
| Kotlin classes | PascalCase | `LocationEngine`, `GeofenceManager` |
| Kotlin files | PascalCase | `LocationEngine.kt`, `TraceletPlugin.kt` |
| Swift classes | PascalCase | `LocationEngine`, `MotionDetector` |
| Swift files | PascalCase | `LocationEngine.swift` |
| EventChannel paths | dot.separated/slash | `com.tracelet/events/location` |
| MethodChannel path | dot.separated/slash | `com.tracelet/methods` |

## Commit Message Format
```
type(scope): message

feat(android): add FusedLocationProvider integration
fix(ios): fix CLLocationManager delegate crash on iOS 14
test(dart): add Config serialization round-trip tests
docs: update INSTALL-ANDROID.md with API 34 requirements
chore: bump pigeon to 22.x
```
Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`
Scopes: `dart`, `android`, `ios`, `interface`, `example`, `ci`, or omit for root-level

## Testing Requirements
- **Dart**: ≥90% code coverage. Every public method has at least one test.
- **Android**: Robolectric unit tests for all managers. Room tests with in-memory DB.
- **iOS**: XCTest for all managers. In-memory SQLite for DB tests.
- **Integration**: Real-device tests in `example/integration_test/`.

## Dependencies Policy
- **Dart**: Minimize dependencies. Only `collection`, `plugin_platform_interface`, `meta`.
- **Android**: Google Play Services Location, Room, OkHttp, WorkManager. No other third-party libs.
- **iOS**: Only Apple frameworks (CoreLocation, CoreMotion, UIKit, BackgroundTasks, SQLite3). No CocoaPods third-party deps.
- **Dev-only**: `pigeon`, `melos`, `build_runner`, `freezed` (if used), `mockito`, `test`.
