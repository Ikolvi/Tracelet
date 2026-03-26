# Tracelet — Native SDK Extraction Plan

> **Goal**: Extract platform-agnostic native SDKs from the Flutter plugin, publish as standalone libraries, and enable multi-framework support (Flutter, React Native, Capacitor, pure native apps).
> **Status**: In Progress — Phase 1 & 2 substantially complete
> **Created**: March 2025
> **Last Updated**: March 2025

---

## Table of Contents

1. [Rationale](#rationale)
2. [Target Architecture](#target-architecture)
3. [Current State Analysis](#current-state-analysis)
4. [Phase 1 — Android SDK Extraction](#phase-1--android-sdk-extraction)
5. [Phase 2 — iOS SDK Extraction](#phase-2--ios-sdk-extraction)
6. [Phase 3 — Algorithm Migration (Dart → Native)](#phase-3--algorithm-migration-dart--native)
7. [Phase 4 — Framework Bridges](#phase-4--framework-bridges)
8. [Phase 5 — CI/CD & Publishing](#phase-5--cicd--publishing)
9. [KMP Strategy for Shared Algorithms](#kmp-strategy-for-shared-algorithms)
10. [Risk Register](#risk-register)
11. [Decision Log](#decision-log)

---

## Rationale

### Why Extract?

| Driver | Impact |
|--------|--------|
| **Multi-framework support** | Flutter, React Native, Capacitor, .NET MAUI, Cordova, pure native — all consume the same SDK |
| **Enterprise sales** | Native app teams (no Flutter) can use Tracelet directly — doubles addressable market |
| **Independent testability** | Android instrumented tests and iOS XCTests without Flutter tooling |
| **Cleaner upgrades** | SDK consumers get updates via Gradle/SPM without touching bridge code |
| **Reduced bus factor** | Native SDK developers don't need Flutter expertise |

### Why NOT Separate Repos?

| Concern | Monorepo Solution |
|---------|-------------------|
| Cross-repo version coordination | Atomic PRs across SDK + bridge in one commit |
| CI complexity | Single pipeline validates everything |
| Contributor friction | One clone, one bootstrap |
| Release ordering | Scripted publish pipeline in one repo |

**Decision**: Keep a monorepo with multiple publishable modules. Publish independent artifacts to Maven Central and CocoaPods/SPM.

---

## Target Architecture

```
Tracelet/
├── sdk/
│   ├── android/                          ← tracelet-sdk-android (Gradle library)
│   │   ├── core/                         ← Pure Kotlin, zero Flutter deps
│   │   │   ├── src/main/kotlin/com/ikolvi/tracelet/sdk/
│   │   │   │   ├── TraceletSdk.kt        ← Public SDK entry point
│   │   │   │   ├── TraceletSdkConfig.kt  ← SDK-level config (no Flutter maps)
│   │   │   │   ├── TraceletListener.kt   ← Callback interface for consumers
│   │   │   │   ├── location/             ← LocationEngine, DeadReckoning, Periodic
│   │   │   │   ├── motion/               ← MotionDetector
│   │   │   │   ├── geofence/             ← GeofenceManager
│   │   │   │   ├── http/                 ← HttpSyncManager, DeltaEncoder
│   │   │   │   ├── db/                   ← TraceletDatabase, Encryption
│   │   │   │   ├── privacy/              ← PrivacyZoneManager
│   │   │   │   ├── audit/                ← AuditTrailManager
│   │   │   │   ├── attestation/          ← DeviceAttestor
│   │   │   │   ├── schedule/             ← ScheduleManager
│   │   │   │   ├── service/              ← LocationService (foreground)
│   │   │   │   ├── receiver/             ← Boot, Alarm, Geofence receivers
│   │   │   │   ├── algorithm/            ← KalmanFilter, AdaptiveSampling, etc.
│   │   │   │   └── util/                 ← Logger, Battery, OEM, Sound, Permissions
│   │   │   └── build.gradle.kts          ← Publishable to Maven Central
│   │   └── README.md
│   │
│   └── ios/                              ← TraceletSDK (Swift Package)
│       ├── Sources/TraceletSDK/
│       │   ├── TraceletSdk.swift          ← Public SDK entry point
│       │   ├── TraceletSdkConfig.swift    ← SDK-level config
│       │   ├── TraceletDelegate.swift     ← Delegate protocol for consumers
│       │   ├── (same domain folders as Android)
│       │   └── algorithm/                ← KalmanFilter, AdaptiveSampling, etc.
│       ├── Package.swift                 ← SPM manifest
│       ├── TraceletSDK.podspec           ← CocoaPods spec
│       └── README.md
│
├── bridges/
│   ├── flutter/                          ← Current federated plugin (thin)
│   │   ├── tracelet/                     ← App-facing Dart API (unchanged)
│   │   ├── tracelet_platform_interface/  ← Platform interface (mostly unchanged)
│   │   ├── tracelet_android/             ← Thin bridge: TraceletFlutterBridge.kt
│   │   ├── tracelet_ios/                 ← Thin bridge: TraceletFlutterBridge.swift
│   │   └── tracelet_web/                 ← Web (unchanged)
│   │
│   ├── react-native/                     ← Future: RN bridge module
│   └── capacitor/                        ← Future: Capacitor plugin
│
├── algorithms/                           ← Shared test vectors & specs (JSON)
│   ├── kalman_test_vectors.json
│   ├── delta_encoding_test_vectors.json
│   └── geofence_test_vectors.json
│
├── example/                              ← Flutter example app (unchanged)
├── help/                                 ← Documentation (unchanged)
└── melos.yaml                            ← Updated for new structure
```

### Dependency Graph (Post-Extraction)

```
┌─────────────────────────────────────────────┐
│         Consumer Apps / Frameworks          │
│  (Flutter, React Native, Native, etc.)      │
└──────────────┬──────────────────────────────┘
               │ depends on
┌──────────────▼──────────────────────────────┐
│         Framework Bridge (thin)             │
│  TraceletFlutterBridge.kt / .swift          │
│  TraceletRNModule.kt / .swift               │
│  ~300–500 lines per platform                │
└──────────────┬──────────────────────────────┘
               │ depends on
┌──────────────▼──────────────────────────────┐
│           Tracelet Native SDK               │
│  tracelet-sdk-android (Maven Central)       │
│  TraceletSDK (CocoaPods / SPM)              │
│  All engines, managers, algorithms          │
│  Zero framework dependencies                │
└─────────────────────────────────────────────┘
```

---

## Current State Analysis

### Flutter Coupling Inventory

The codebase already has **excellent separation**. Only **3 files per platform** have Flutter imports:

#### Android — Flutter-Coupled Files (3 of 30)

| File | Flutter APIs | Extraction Action |
|------|-------------|-------------------|
| `TraceletAndroidPlugin.kt` | `FlutterPlugin`, `MethodChannel`, `ActivityAware` | Becomes `TraceletFlutterBridge.kt` in bridge layer |
| `EventDispatcher.kt` | `EventChannel`, `BinaryMessenger`, `StreamHandler` | Replaced by `TraceletListener` interface in SDK |
| `HeadlessTaskService.kt` | `FlutterEngine`, `DartExecutor`, `MethodChannel` | Stays in bridge layer (Flutter-specific by nature) |

#### iOS — Flutter-Coupled Files (3 of 28)

| File | Flutter APIs | Extraction Action |
|------|-------------|-------------------|
| `TraceletIosPlugin.swift` | `FlutterPlugin`, `FlutterMethodChannel` | Becomes `TraceletFlutterBridge.swift` in bridge layer |
| `EventDispatcher.swift` | `FlutterEventChannel`, `FlutterEventSink` | Replaced by `TraceletDelegate` protocol in SDK |
| `HeadlessRunner.swift` | `FlutterEngine`, `FlutterCallbackCache` | Stays in bridge layer (Flutter-specific) |

#### Core Engine Files — Already Flutter-Free (40+ files)

All `LocationEngine`, `MotionDetector`, `GeofenceManager`, `HttpSyncManager`, `TraceletDatabase`, `ConfigManager`, `StateManager`, `AuditTrailManager`, `PrivacyZoneManager`, `DeviceAttestor`, `LocationService`, receivers, and utilities — **zero Flutter imports**. These move into the SDK as-is.

#### Abstraction Points Already in Place

| Android | iOS | Purpose |
|---------|-----|---------|
| `TraceletEventSender` (interface) | `TraceletEventSending` (protocol) | Decouples event delivery from Flutter |
| `HeadlessDispatcher` (interface) | `HeadlessDispatching` (protocol) | Decouples headless execution from Flutter |
| `TraceletBootstrap` | `TraceletBootstrapIOS` | Factory pattern, no Flutter refs |

**Extraction effort is LOW** — the abstraction boundaries already exist.

### Dart-Side Algorithms to Migrate

| Algorithm | File | Lines | Complexity | Priority |
|-----------|------|-------|------------|----------|
| Kalman Filter | `kalman_filter.dart` | ~200 | High (4×4 matrix ops) | P0 — core quality |
| Location Processor | `location_processor.dart` | ~300 | Medium (filter pipeline) | P0 — core pipeline |
| Adaptive Sampling | `adaptive_sampling_engine.dart` | ~150 | Medium | P1 — battery optimization |
| Battery Budget | `battery_budget_engine.dart` | ~100 | Low | P1 — battery optimization |
| Delta Encoder | `delta_encoder.dart` | ~120 | Low (already native too) | P1 — already dual-impl |
| Trip Manager | `trip_manager.dart` | ~200 | Medium | P1 — core feature |
| Geofence Evaluator | `geofence_evaluator.dart` | ~250 | High (ray-casting, polygon) | P2 — already native geofencing |
| R-tree | `rtree.dart` | ~300 | High (spatial index) | P2 — only if evaluator moves |
| Carbon Estimator | `carbon_estimator.dart` | ~100 | Low | P3 — business logic, can stay Dart |
| Persist Decider | `persist_decider.dart` | ~50 | Low | P2 |
| Schedule Parser | `schedule_parser.dart` | ~80 | Low (already native too) | P3 — already dual-impl |
| Geo Utils | `geo_utils.dart` | ~100 | Low (Haversine, bearing) | P1 — foundational |

---

## Phase 1 — Android SDK Extraction

### 1.1 Create Gradle Library Module
- [x] Create `sdk/android/core/` as an Android library module (`com.android.library`)
- [x] Configure `build.gradle.kts` with:
  - `namespace = "com.ikolvi.tracelet.sdk"`
  - `compileSdk = 36`, `minSdk = 26`
  - All current dependencies (Play Services Location, OkHttp, Room, WorkManager, etc.)
  - Maven Central publishing plugin (`maven-publish` + `signing`)
- [ ] Create `sdk/android/gradle.properties` with group/version metadata
- [ ] Add ProGuard/R8 consumer rules

### 1.2 Move Core Code
- [x] Move all `com/tracelet/core/**` files into SDK module
- [x] Preserve package structure: `location/`, `motion/`, `geofence/`, `http/`, `db/`, etc.
- [x] Update all package declarations from `com.tracelet.core` → `com.ikolvi.tracelet.core`
- [x] Move `LocationService.kt` (foreground service) into SDK
- [x] Move all BroadcastReceivers (`BootReceiver`, `GeofenceBroadcastReceiver`, `PeriodicAlarmReceiver`) into SDK
- [x] Move `AndroidManifest.xml` service/receiver declarations into SDK module
- [x] Verify: zero `import io.flutter` in any SDK file

> **Note**: Core code currently lives in the plugin module under `com.ikolvi.tracelet.core` with the plugin bridge in `com.ikolvi.tracelet.flutter`. Physical separation into `sdk/android/` is deferred until Maven Central publishing is set up.

### 1.3 Create Public SDK API
- [x] Create `TraceletSdk.kt` — singleton entry point (1164 lines, `com.ikolvi.tracelet.core`)
  - Injectable `TraceletEventSender` pattern
  - `getInstance(context)`, `setEventSender()`, `initialize()`
  - `ready()` with async callback, `start()`/`stop()`/`startGeofences()`/`startPeriodic()`
  - All lifecycle, config, location, geofence, persistence, HTTP sync, permissions, enterprise APIs
- [x] `TraceletEventSender` interface already in place (16 event methods + `hasListener()`)
- [x] `HeadlessDispatcher` interface already in place
- [x] `TraceletBootstrap` factory pattern already in place
- [ ] Create `TraceletListener.kt` — higher-level callback interface (typed models instead of raw maps)
- [ ] Create `TraceletSdkConfig.kt` — typed config (replace raw maps)
- [ ] Create SDK-level model classes: `TraceletLocation`, `TraceletState`, `TraceletGeofence`, etc.

### 1.4 Slim Down Flutter Bridge
- [x] `TraceletAndroidPlugin.kt` — reduced from 1511 → 489 lines
  - Delegates all 60+ method channel calls to `TraceletSdk`
  - Flutter-specific only: `EventDispatcher`, `HeadlessTaskService`, Activity lifecycle, permission forwarding
- [x] `EventDispatcher.kt` — implements `TraceletEventSender` with 15 Flutter EventChannels
- [x] `HeadlessTaskService.kt` — Flutter headless Dart execution
- [x] Namespace aligned to `com.ikolvi.tracelet.flutter`
- [x] Verify: bridge is ≤500 lines (489 lines ✓)
- [ ] Update `build.gradle.kts` to depend on published SDK artifact (when Maven Central is ready)

### 1.5 Testing
- [ ] Migrate all existing Robolectric tests to SDK module (when physically separated)
- [x] Add SDK unit tests — `TraceletSdkTest.kt` (23 tests: singleton, injection, lifecycle guards, ready, config, carbon, permissions, heartbeat)
- [ ] Add bridge-level tests (mock SDK, verify MethodChannel/EventChannel wiring)
- [x] Verify existing Flutter integration tests still pass (111 integration tests ✓)
- [x] All existing Android unit tests pass (293 tests ✓)
- [ ] Create shared test vectors (JSON) for algorithm verification across platforms

---

## Phase 2 — iOS SDK Extraction

### 2.1 Create Swift Package
- [x] Create `sdk/ios/` with `Package.swift` (TraceletSDK, Swift 5.9, iOS 14+)
- [x] Configure frameworks: CoreLocation, CoreMotion, UIKit, BackgroundTasks, AVFoundation, AudioToolbox, Network, DeviceCheck
- [ ] Create `TraceletSDK.podspec` for CocoaPods distribution (parallel to SPM)

### 2.2 Move Core Code
- [x] Move all TraceletCore Swift files into `sdk/ios/Sources/TraceletSDK/`
- [x] Preserve folder structure: location/, motion/, geofence/, http/, db/, etc.
- [x] Verify: zero `import Flutter` in any SDK file
- [x] Subsystem properties made `public private(set)` for plugin access
- [x] `DeviceAttestor` made `public final class` for visibility

### 2.3 Create Public SDK API
- [x] Create `TraceletSdk.swift` — singleton entry point (1155 lines)
  - `TraceletSdk.shared`, injectable `TraceletEventSending` delegate
  - All lifecycle, config, location, geofence, persistence, HTTP sync, permissions, enterprise APIs
- [x] `TraceletEventSending` protocol already in place
- [x] `DelegateEventSender` bridges protocol to delegate pattern
- [ ] Create `TraceletDelegate.swift` — higher-level delegate protocol (typed models)
- [ ] Create SDK-level model structs: `TraceletLocation`, `TraceletState`, `TraceletGeofence`, etc.

### 2.4 Slim Down Flutter Bridge
- [x] `TraceletIosPlugin.swift` — reduced from 1190 → 379 lines
  - Delegates all method calls to `TraceletSdk.shared`
  - Flutter-specific only: EventDispatcher, HeadlessRunner
- [x] `EventDispatcher.swift` — Flutter EventChannel management
- [x] `HeadlessRunner.swift` — Flutter headless engine management
- [x] SPM dependency wired: plugin's `Package.swift` depends on `TraceletSDK` via local path
- [x] `#if canImport(TraceletSDK)` conditional imports for dual CocoaPods/SPM support
- [x] Verify: bridge is ≤500 lines (379 lines ✓)
- [ ] Update podspec to depend on `TraceletSDK` pod (when CocoaPods publishing is ready)

### 2.5 Testing
- [ ] Migrate all existing XCTests to SDK package (when physically separated)
- [x] iOS SDK unit tests pass — 109 tests, 0 failures
- [ ] Add bridge-level tests (mock SDK, verify channel wiring)
- [x] Verify existing Flutter integration tests still pass (111 integration tests ✓)
- [ ] Use shared test vectors from `algorithms/` directory

---

## Phase 3 — Algorithm Migration (Dart → Native)

### 3.1 Evaluation: KMP vs. Dual Implementation

| Approach | Pros | Cons |
|----------|------|------|
| **Kotlin Multiplatform (KMP)** | Write once, compile for JVM + iOS native. Zero algorithm drift. | Adds KMP toolchain complexity. Kotlin/Native iOS interop has quirks. Build times increase. |
| **Dual implementation** (Kotlin + Swift) | Simple build. Native-idiomatic code. No toolchain overhead. | Risk of algorithm drift. Double testing burden. |
| **C/C++ shared library** | True single source. FFI from Kotlin + Swift. | Complex build (CMake/NDK). Harder to debug. Memory management burden. |

**Recommendation**: Start with **dual implementation** using **shared test vectors** (JSON fixtures). Consider KMP later if algorithm drift becomes a real problem. Rationale:
- The algorithms are mathematically well-defined — implementations are deterministic
- Shared JSON test fixtures guarantee correctness across both platforms
- Avoids KMP toolchain complexity during the extraction phase
- Can migrate to KMP later as an incremental optimization

### 3.2 Shared Test Vectors
- [ ] Create `algorithms/kalman_test_vectors.json`:
  - Input: sequence of GPS readings (lat, lon, accuracy, speed, timestamp)
  - Expected: filtered positions, velocity estimates, covariance values
- [ ] Create `algorithms/adaptive_sampling_test_vectors.json`:
  - Input: speed, activity, battery, config
  - Expected: recommended distance filter, interval
- [ ] Create `algorithms/delta_encoding_test_vectors.json`:
  - Input: array of location maps
  - Expected: encoded output, decoded round-trip match
- [ ] Create `algorithms/location_processor_test_vectors.json`:
  - Input: raw location + config (distance filter, accuracy threshold, etc.)
  - Expected: accept/reject decision, rejection reason
- [ ] Create `algorithms/geofence_evaluator_test_vectors.json`:
  - Input: point + polygon vertices
  - Expected: inside/outside/distance results
- [ ] Create `algorithms/geo_utils_test_vectors.json`:
  - Input: coordinate pairs
  - Expected: Haversine distance, bearing

### 3.3 P0 — Core Algorithms (Must Move)
- [x] **Kalman Filter** → Ported to both Kotlin and Swift
  - `sdk/android/` and `sdk/ios/Sources/TraceletSDK/algorithm/KalmanLocationFilter.kt/.swift`
  - 4×4 state vector, prediction, update steps
  - Wired into `LocationEngine` on both platforms
- [x] **Location Processor** → Ported to both Kotlin and Swift
  - Distance filter, accuracy filter, duplicate filter, elapsed realtime filter
  - Wired into location pipeline
- [x] **Adaptive Sampling** → Ported to both Kotlin and Swift
  - Dynamic distance filter / interval adjustment based on speed, activity, battery
- [x] **Geo Utils** → Ported to both Kotlin and Swift
  - Haversine distance, initial bearing, destination point

### 3.4 P1 — Battery & Sync Algorithms
- [ ] **Adaptive Sampling Engine** → native on both platforms
  - Depends on native battery state, motion activity, speed — natural fit for native
  - Wire into `LocationEngine` to dynamically adjust `distanceFilter` / `locationUpdateInterval`
- [ ] **Battery Budget Engine** → native on both platforms
  - Reads native battery level/charging state
  - Controls sampling aggressiveness
- [ ] **Delta Encoder** → already has native implementations; remove Dart fallback or keep for web
- [ ] **Trip Manager** → native on both platforms
  - Trip start/end detection must work in headless background (no Dart runtime available)

### 3.5 P2 — Advanced Algorithms
- [ ] **Geofence Evaluator** (polygon support) → native on both platforms
  - Ray-casting algorithm for point-in-polygon
  - Native platforms already handle circular geofences via system APIs
- [ ] **R-tree** → native on both platforms (if geofence evaluator moves)
- [ ] **Persist Decider** → native (simple, moves with location pipeline)

### 3.6 P3 — Optional / Keep in Dart
- [ ] **Carbon Estimator** — pure business logic, framework-agnostic. Keep in Dart for Flutter, let other frameworks re-implement or provide as a separate utility library.
- [ ] **Schedule Parser** — already dual-implemented natively. Remove Dart version.

### 3.7 Dart-Side Cleanup
- [ ] Remove migrated algorithm implementations from `tracelet_platform_interface`
- [ ] Keep Dart models and public API unchanged (algorithms are internal)
- [ ] Update `LocationProcessor` pipeline in Dart to delegate to native via SDK
- [ ] Ensure web fallback: keep Dart algorithms in `tracelet_web` (no native SDK for web)

---

## Phase 4 — Framework Bridges

### 4.1 React Native Bridge (Future)
- [ ] Create `bridges/react-native/` with:
  - `android/src/main/kotlin/com/ikolvi/tracelet/rn/TraceletRNModule.kt`
  - `ios/TraceletRNBridge.swift`
  - `src/index.ts` — JS/TS API
- [ ] Android module: `TurboModule` or `NativeModule` → delegates to `TraceletSdk`
- [ ] iOS module: RCT bridge → delegates to `TraceletSdk.shared`
- [ ] TypeScript types mirror Dart API
- [ ] Estimated effort: ~500 lines Kotlin + ~500 lines Swift + ~300 lines TS

### 4.2 Capacitor Bridge (Future)
- [ ] Create `bridges/capacitor/` with:
  - `android/src/main/kotlin/com/ikolvi/tracelet/capacitor/TraceletCapacitorPlugin.kt`
  - `ios/TraceletCapacitorPlugin.swift`
  - `src/index.ts`
- [ ] Both platforms: thin delegation to native SDK
- [ ] Estimated effort: ~300 lines per platform + ~200 lines TS

### 4.3 Pure Native SDK Usage
- [ ] Publish Android SDK documentation with usage examples (Kotlin + Java)
- [ ] Publish iOS SDK documentation with usage examples (Swift + ObjC interop)
- [ ] No bridge needed — consumers depend directly on Maven Central / CocoaPods / SPM

---

## Phase 5 — CI/CD & Publishing

### 5.1 Maven Central (Android)
- [x] Register Sonatype Central Portal account for `com.ikolvi` group (verified via `ikolvi.com`)
- [ ] Configure GPG signing for artifacts
- [ ] Set up `maven-publish` plugin in `sdk/android/core/build.gradle.kts`:
  ```kotlin
  publishing {
      publications {
          create<MavenPublication>("release") {
              groupId = "com.ikolvi"
              artifactId = "tracelet-sdk"
              version = project.findProperty("SDK_VERSION") as String
          }
      }
  }
  ```
- [ ] CI job: on tag `sdk-android-vX.Y.Z` → build → sign → publish to Maven Central
- [ ] Set up staging → release promotion workflow

### 5.2 CocoaPods (iOS)
- [ ] Register `TraceletSDK` pod name with trunk (under ikolvi ownership)
- [ ] Configure `TraceletSDK.podspec` with proper source, version, license
- [ ] CI job: on tag `sdk-ios-vX.Y.Z` → lint → push to CocoaPods trunk
- [ ] Test pod install in isolated Xcode project

### 5.3 Swift Package Manager (iOS)
- [ ] `Package.swift` already defines the target (created in Phase 2)
- [ ] SPM resolves directly from Git tags — no registry needed
- [ ] CI job: validate `swift build` and `swift test` on each push
- [ ] Tag format: `sdk-ios-vX.Y.Z` (same tag serves both SPM and CocoaPods)

### 5.4 Flutter Plugin Updates
- [ ] Update `tracelet_android` `build.gradle.kts` to consume SDK from Maven Central
- [ ] Update `tracelet_ios` podspec to depend on `TraceletSDK` pod
- [ ] Bump Flutter plugin versions to reflect SDK dependency
- [ ] Verify `flutter pub get`, `flutter build apk`, `flutter build ios` all succeed

### 5.5 Version Strategy
- [ ] SDK versions: semver `X.Y.Z` — independent from Flutter plugin version
- [ ] Flutter plugin version: continues current scheme, adds SDK version in changelog
- [ ] Compatibility matrix: document which Flutter plugin versions require which SDK versions
- [ ] `bridges/flutter/tracelet_android/CHANGELOG.md` notes SDK version dependency

---

## KMP Strategy for Shared Algorithms

> **Status**: Deferred — evaluate after Phase 3 dual-implementation is stable.

If algorithm drift between Kotlin and Swift implementations becomes a maintenance burden, migrate to KMP:

### Structure
```
sdk/
├── shared/                               ← KMP module
│   ├── src/commonMain/kotlin/com/ikolvi/tracelet/sdk/algorithm/
│   │   ├── KalmanLocationFilter.kt       ← Shared Kotlin code
│   │   ├── LocationProcessor.kt
│   │   ├── AdaptiveSamplingEngine.kt
│   │   ├── GeoUtils.kt
│   │   └── DeltaEncoder.kt
│   ├── src/androidMain/                  ← Android-specific (if any)
│   ├── src/iosMain/                      ← iOS-specific (if any)
│   └── build.gradle.kts                  ← KMP plugin config
├── android/core/                         ← Depends on :shared
└── ios/                                  ← Consumes shared.framework
```

### KMP Considerations
- `commonMain` algorithms use only `kotlin.math`, `kotlin.collections` — no platform APIs
- Compile to JVM for Android, Kotlin/Native for iOS
- iOS consumes as `.xcframework` via SPM or CocoaPods
- Adds ~30s to build time for Kotlin/Native compilation
- Requires Kotlin 2.0+ with new native memory model

### Migration Path
1. Create KMP `:shared` module with one algorithm (Kalman filter)
2. Validate iOS framework integration in SDK tests
3. If successful, migrate remaining algorithms
4. Remove duplicate Swift implementations
5. Keep Dart implementations for web platform

---

## Risk Register

| # | Risk | Probability | Impact | Mitigation |
|---|------|-------------|--------|------------|
| R1 | Breaking API changes during extraction | Medium | High | Semantic versioning. Keep old Flutter API surface identical. Only internal wiring changes. |
| R2 | Algorithm drift (Kotlin vs Swift) | Medium | Medium | Shared JSON test vectors with ε-tolerance. CI runs both against same fixtures. |
| R3 | Maven Central publishing delays | Low | Medium | Use Sonatype Central Portal (faster). Have snapshot repo for pre-release testing. |
| R4 | Headless execution broken during migration | Medium | High | Headless dispatch stays in bridge layer — untouched during SDK extraction. Test extensively. |
| R5 | Build time increase from multi-module | Low | Low | Gradle build cache + parallel execution. Incremental compilation. |
| R6 | Flutter plugin consumers see breaking change | Low | Critical | SDK is an internal dependency — Flutter public API stays identical. Pin SDK version in plugin. |
| R7 | Android Manifest merge conflicts | Medium | Medium | SDK module owns service/receiver declarations. Bridge module has no manifest entries. Test merged manifest. |
| R8 | CocoaPods + SPM dual publishing complexity | Medium | Low | Automate with CI. CocoaPods podspec and Package.swift point to same source. |

---

## Decision Log

| # | Date | Decision | Rationale |
|---|------|----------|-----------|
| D1 | 2025-03 | Monorepo over separate repos | Atomic PRs, single CI, easier version coordination |
| D2 | 2025-03 | Maven Central over JitPack | Enterprise-grade: artifact signing, reliability, Gradle Module Metadata |
| D3 | 2025-03 | `com.ikolvi` namespace (via `ikolvi.com`) | Custom domain ownership, professional branding, verified via DNS TXT record |
| D4 | 2025-03 | Dual impl (Kotlin + Swift) before KMP | Simpler toolchain, shared test vectors prevent drift, KMP can come later |
| D5 | 2025-03 | SPM + CocoaPods dual publish for iOS | SPM is Apple's direction; CocoaPods needed for Flutter/RN integration |
| D6 | 2025-03 | Carbon Estimator stays in Dart | Pure business logic, no native API dependency, framework-specific |
| D7 | 2025-03 | Keep Dart algorithms for `tracelet_web` | No native SDK on web — Dart algorithms are the only option |
| D8 | 2025-03 | Namespace `com.ikolvi.tracelet.core` for SDK, `com.ikolvi.tracelet.flutter` for plugin bridge | Clean separation: core SDK has no framework reference in package name, bridge makes framework explicit. String literals (SharedPrefs keys, channel names, action strings) kept as `com.tracelet.*` functional identifiers. |
| D9 | 2025-03 | `#if canImport(TraceletSDK)` for dual CocoaPods/SPM | CocoaPods (Flutter build) compiles all sources in one module; SPM uses separate dependency. Conditional import handles both without code duplication. |
| D10 | 2025-03 | `TraceletEventSender` interface (Android) / `TraceletEventSending` protocol (iOS) as SDK event abstraction | Map-based API matches existing Flutter channel contract. Typed model classes (TraceletLocation, etc.) deferred until needed by non-Flutter consumers. |
| D11 | 2025-03 | Example app bundle IDs aligned to `com.ikolvi.tracelet.example` | Consistent namespace across all packages. Android applicationId and iOS PRODUCT_BUNDLE_IDENTIFIER both updated. |

---

## Execution Priority

```
Phase 1 (Android SDK)     ██████████████████████████████  ~90% complete
Phase 2 (iOS SDK)         ██████████████████████████████  ~90% complete
Phase 3 (Algorithms)      ████████████████░░░░░░░░░░░░░░  P0 done, P1-P3 remaining
Phase 5 (CI/CD)           ████░░░░░░░░░░░░░░░░░░░░░░░░░░  Sonatype verified, publishing TBD
Phase 4 (RN/Capacitor)    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  Future — demand-driven
```

### Current Metrics

| Metric | Value |
|--------|-------|
| Android SDK (`TraceletSdk.kt`) | 1164 lines |
| Android Flutter Bridge (`TraceletAndroidPlugin.kt`) | 489 lines (was 1511) |
| iOS SDK (`TraceletSdk.swift`) | 1155 lines |
| iOS Flutter Bridge (`TraceletIosPlugin.swift`) | 379 lines (was 1190) |
| Android Unit Tests | 293 passing |
| iOS SDK Tests | 109 passing |
| Flutter Integration Tests | 111 passing |
| Melos Analyze | 6/6 packages clean |
| Flutter APK Build | ✓ |
| Flutter iOS Build | ✓ (18.0MB) |

### Remaining Work (to reach 100%)

1. **Physical separation**: Move SDK code from plugin module → `sdk/android/` Gradle module. Currently shares the same module with separate packages.
2. **Typed SDK models**: Replace `Map<String, Any?>` with `TraceletLocation`, `TraceletState`, etc. for non-Flutter consumers.
3. **Maven Central publishing**: GPG signing, `maven-publish` plugin, CI pipeline.
4. **CocoaPods podspec**: Create `TraceletSDK.podspec` for iOS.
5. **Shared test vectors**: JSON fixtures for cross-platform algorithm validation.
6. **P1-P3 algorithms**: Battery Budget, Trip Manager, Geofence Evaluator, R-tree.

**Phase 1 + 2 can run in parallel** — they are fully independent.
**Phase 5 (CI/CD) should start early** — publishing pipeline is a prerequisite for Phase 1/2 completion.
**Phase 3 begins after SDK extraction stabilizes** — algorithms move into the already-extracted SDK.
**Phase 4 is demand-driven** — build bridges only when there's a customer/user need.
