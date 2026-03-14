# Tracelet — React Native Support Plan

> **Goal**: Expose Tracelet's battle-tested native engines (Kotlin/Swift) to React Native via the New Architecture (TurboModules + JSI), delivering the same production-grade background geolocation experience that Flutter users already enjoy.
>
> **Last updated**: March 2026

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Decision Records](#architecture-decision-records)
3. [Monorepo Integration Strategy](#monorepo-integration-strategy)
4. [Package Structure](#package-structure)
5. [Phase 0 — Foundation & Scaffolding](#phase-0--foundation--scaffolding)
6. [Phase 1 — Core Native Module](#phase-1--core-native-module)
7. [Phase 2 — Event System](#phase-2--event-system)
8. [Phase 3 — Feature Parity Matrix](#phase-3--feature-parity-matrix)
9. [Phase 4 — Headless & Background Execution](#phase-4--headless--background-execution)
10. [Phase 5 — Enterprise Features](#phase-5--enterprise-features)
11. [Phase 6 — Testing & Quality](#phase-6--testing--quality)
12. [Phase 7 — Documentation & Publishing](#phase-7--documentation--publishing)
13. [API Surface Design](#api-surface-design)
14. [Native Code Reuse Strategy](#native-code-reuse-strategy)
15. [Migration Path for Existing RN Users](#migration-path-for-existing-rn-users)
16. [Risk Register](#risk-register)
17. [Release Timeline](#release-timeline)

---

## Executive Summary

Tracelet's native engines — `LocationEngine`, `MotionDetector`, `GeofenceManager`, `HttpSyncManager`, `TraceletDatabase`, etc. — are already **framework-agnostic** Kotlin/Swift classes. They communicate with Flutter through thin `MethodChannel`/`EventChannel` adapters (`TraceletAndroidPlugin.kt`, `TraceletIosPlugin.swift`). This separation means we can expose the **same native engines** to React Native through a new adapter layer, without duplicating any geolocation logic.

**Key principles**:
- **Zero native code duplication** — Android/iOS engines are shared between Flutter and React Native
- **New Architecture first** — TurboModules (JSI) for synchronous/async calls, Fabric-compatible
- **Old Architecture bridge** — Backward compatibility via auto-generated bridge for RN < 0.73
- **TypeScript-first API** — Full TypeScript definitions, no `any` types
- **Codegen via Nitro/Spec** — Use React Native Codegen (or Nitro Modules) for type-safe native↔JS bindings
- **Battery-conscious** — Same battery-first design philosophy inherited from native engines

---

## Architecture Decision Records

### ADR-1: TurboModules + JSI (New Architecture)

**Decision**: Build exclusively on React Native's New Architecture using TurboModules.

**Rationale**:
- JSI provides synchronous access to native code — eliminates JSON serialization overhead of the old bridge
- TurboModules support lazy initialization — the module loads only when first accessed
- React Native has officially deprecated the old bridge architecture as of RN 0.76+
- Codegen generates type-safe C++/ObjC++/Java bindings from a TypeScript spec
- Aligns with Meta's long-term direction — future-proof

**Trade-off**: Apps still on old architecture (RN < 0.73) need an interop layer (auto-provided by RN).

### ADR-2: Shared Native Engines (No Code Duplication)

**Decision**: The React Native package imports the same native engine classes used by `tracelet_android` and `tracelet_ios`.

**Rationale**:
- Single source of truth for GPS fusion, motion detection, geofencing, HTTP sync, SQLite persistence
- Bug fixes and improvements automatically benefit both Flutter and React Native
- Halves the native testing surface

**Implementation**:
- **Android**: The RN package's `build.gradle.kts` declares a dependency on `tracelet-android-core` (a pure Kotlin library extracted from the Flutter plugin, or uses source symlinks via Gradle `sourceSets`)
- **iOS**: The RN podspec includes the shared Swift sources via CocoaPods subspecs or Swift Package Manager

### ADR-3: Event Delivery via NativeEventEmitter

**Decision**: Use React Native's `NativeEventEmitter` pattern for all 15 event streams.

**Rationale**:
- Established RN pattern for native → JS communication
- Maps directly to Tracelet's existing `EventChannel` model
- Supports addListener/removeListener lifecycle
- Works with both old and new architecture

### ADR-4: Monorepo Cohabitation

**Decision**: The React Native package lives inside the existing Tracelet monorepo at `packages/tracelet_react_native/`.

**Rationale**:
- Shared CI/CD pipeline
- Version-locked with native engine changes
- Single PR for cross-framework features

### ADR-5: npm Publishing, Not pub.dev

**Decision**: Publish to npm as `@tracelet/react-native`.

**Rationale**:
- Standard React Native distribution channel
- Scoped package prevents name squatting
- Decoupled versioning from Dart packages (different ecosystem cadence)

---

## Monorepo Integration Strategy

### Current Structure (Flutter-only)
```
Tracelet/
├── packages/
│   ├── tracelet/                          # Flutter app-facing API
│   ├── tracelet_platform_interface/       # Dart abstract interface
│   ├── tracelet_android/                  # Flutter Android plugin (Kotlin)
│   ├── tracelet_ios/                      # Flutter iOS plugin (Swift)
│   └── tracelet_web/                      # Flutter web plugin
├── example/                               # Flutter example app
└── melos.yaml
```

### Proposed Structure (Multi-framework)
```
Tracelet/
├── packages/
│   ├── tracelet/                          # Flutter app-facing API
│   ├── tracelet_platform_interface/       # Dart abstract interface
│   ├── tracelet_android/                  # Flutter Android plugin (thin adapter)
│   ├── tracelet_ios/                      # Flutter iOS plugin (thin adapter)
│   ├── tracelet_web/                      # Flutter web plugin
│   └── tracelet_react_native/             # ← NEW: React Native package
│       ├── package.json
│       ├── tsconfig.json
│       ├── babel.config.js
│       ├── react-native.config.js
│       ├── src/                           # TypeScript API
│       │   ├── index.tsx
│       │   ├── NativeTracelet.ts          # TurboModule spec
│       │   ├── Tracelet.ts                # Public API class
│       │   ├── types/
│       │   │   ├── Config.ts
│       │   │   ├── Location.ts
│       │   │   ├── Geofence.ts
│       │   │   ├── State.ts
│       │   │   └── Events.ts
│       │   └── hooks/
│       │       ├── useLocation.ts
│       │       ├── useGeofences.ts
│       │       └── useTraceletState.ts
│       ├── android/
│       │   ├── build.gradle.kts
│       │   └── src/main/kotlin/com/tracelet/reactnative/
│       │       ├── TraceletModule.kt       # TurboModule implementation
│       │       ├── TraceletPackage.kt      # ReactPackage
│       │       └── EventAdapter.kt         # EventEmitter adapter
│       ├── ios/
│       │   ├── TraceletReactNative.podspec
│       │   └── Sources/
│       │       ├── TraceletModule.swift     # TurboModule implementation
│       │       ├── TraceletModule.mm        # ObjC++ bridge (Codegen)
│       │       └── EventAdapter.swift       # RCTEventEmitter adapter
│       ├── example/                         # React Native example app
│       │   ├── package.json
│       │   ├── App.tsx
│       │   ├── android/
│       │   └── ios/
│       └── __tests__/
│           ├── Tracelet.test.ts
│           └── hooks.test.ts
├── native/                                 # ← NEW: Shared native engines
│   ├── android/
│   │   └── tracelet-core/                  # Pure Kotlin library (no Flutter deps)
│   │       ├── build.gradle.kts
│   │       └── src/main/kotlin/com/tracelet/core/
│   │           ├── LocationEngine.kt
│   │           ├── MotionDetector.kt
│   │           ├── GeofenceManager.kt
│   │           ├── HttpSyncManager.kt
│   │           ├── TraceletDatabase.kt
│   │           ├── ConfigManager.kt
│   │           ├── StateManager.kt
│   │           ├── ScheduleManager.kt
│   │           ├── AuditTrailManager.kt
│   │           ├── PrivacyZoneManager.kt
│   │           └── ...
│   └── ios/
│       └── TraceletCore/                   # Pure Swift package (no Flutter deps)
│           ├── Package.swift
│           └── Sources/TraceletCore/
│               ├── LocationEngine.swift
│               ├── MotionDetector.swift
│               ├── GeofenceManager.swift
│               ├── HttpSyncManager.swift
│               ├── TraceletDatabase.swift
│               ├── ConfigManager.swift
│               ├── StateManager.swift
│               ├── ScheduleManager.swift
│               ├── AuditTrailManager.swift
│               ├── PrivacyZoneManager.swift
│               └── ...
├── example/                                # Flutter example app
└── melos.yaml                              # Updated to include RN package scripts
```

### Native Code Extraction Plan

The most critical enabler is extracting shared native engines from the Flutter plugin wrappers into framework-agnostic libraries.

#### Android: `native/android/tracelet-core/`

1. Create a pure Kotlin library module (no Flutter dependencies)
2. Move all engine classes from `packages/tracelet_android/android/src/main/kotlin/com/tracelet/tracelet_android/` → `native/android/tracelet-core/src/main/kotlin/com/tracelet/core/`
3. Remove all `io.flutter.*` imports from engine classes
4. Define a `TraceletEngineCallback` interface for engine → framework communication:

```kotlin
// native/android/tracelet-core/
interface TraceletEngineCallback {
    fun onLocation(location: Map<String, Any?>)
    fun onMotionChange(event: Map<String, Any?>)
    fun onActivityChange(event: Map<String, Any?>)
    fun onGeofence(event: Map<String, Any?>)
    fun onGeofencesChange(event: Map<String, Any?>)
    fun onHeartbeat(event: Map<String, Any?>)
    fun onHttp(event: Map<String, Any?>)
    fun onProviderChange(event: Map<String, Any?>)
    fun onPowerSaveChange(isPowerSave: Boolean)
    fun onConnectivityChange(event: Map<String, Any?>)
    fun onEnabledChange(enabled: Boolean)
    fun onNotificationAction(action: String)
    fun onAuthorization(event: Map<String, Any?>)
    fun onSchedule(event: Map<String, Any?>)
}
```

5. Update `packages/tracelet_android/` to depend on `tracelet-core` and implement a `FlutterEngineCallback` that bridges to `EventDispatcher`
6. `packages/tracelet_react_native/android/` depends on `tracelet-core` and implements a `ReactNativeEngineCallback` that bridges to `RCTDeviceEventEmitter`

#### iOS: `native/ios/TraceletCore/`

1. Create a Swift Package (`Package.swift`) with no Flutter dependencies
2. Move all engine classes from `packages/tracelet_ios/ios/tracelet_ios/Sources/tracelet_ios/` → `native/ios/TraceletCore/Sources/TraceletCore/`
3. Remove all `Flutter` framework imports from engine classes
4. Define a `TraceletEngineDelegate` protocol:

```swift
// native/ios/TraceletCore/
protocol TraceletEngineDelegate: AnyObject {
    func onLocation(_ location: [String: Any?])
    func onMotionChange(_ event: [String: Any?])
    func onActivityChange(_ event: [String: Any?])
    func onGeofence(_ event: [String: Any?])
    func onGeofencesChange(_ event: [String: Any?])
    func onHeartbeat(_ event: [String: Any?])
    func onHttp(_ event: [String: Any?])
    func onProviderChange(_ event: [String: Any?])
    func onPowerSaveChange(_ isPowerSave: Bool)
    func onConnectivityChange(_ event: [String: Any?])
    func onEnabledChange(_ enabled: Bool)
    func onAuthorization(_ event: [String: Any?])
    func onSchedule(_ event: [String: Any?])
}
```

5. Update `packages/tracelet_ios/` to depend on `TraceletCore` via SPM local package and implement `FlutterEngineDelegate`
6. `packages/tracelet_react_native/ios/` depends on `TraceletCore` via podspec subspecs and implements `ReactNativeEngineDelegate`

---

## Phase 0 — Foundation & Scaffolding

**Goal**: Set up the React Native package skeleton and extract shared native code.

### 0.1 Native Core Extraction (Android)
- [ ] Create `native/android/tracelet-core/` Kotlin library module
- [ ] Define `TraceletEngineCallback` interface
- [ ] Move engine classes, remove Flutter imports, depend on callback interface
- [ ] Add Gradle composite build or `includeBuild` in root `settings.gradle.kts`
- [ ] Update `packages/tracelet_android/` to depend on `tracelet-core`
- [ ] Implement `FlutterEngineCallback` in tracelet_android
- [ ] Verify all existing Flutter Android tests still pass

### 0.2 Native Core Extraction (iOS)
- [ ] Create `native/ios/TraceletCore/` Swift Package
- [ ] Define `TraceletEngineDelegate` protocol
- [ ] Move engine classes, remove Flutter imports, depend on delegate protocol
- [ ] Update `packages/tracelet_ios/` podspec to depend on `TraceletCore` local pod
- [ ] Implement `FlutterEngineDelegate` in tracelet_ios
- [ ] Verify all existing Flutter iOS tests still pass

### 0.3 React Native Package Scaffolding
- [ ] Initialize `packages/tracelet_react_native/` with `npx create-react-native-library@latest`
- [ ] Configure `package.json` with:
  - `name`: `@tracelet/react-native`
  - `main`: CommonJS entry
  - `module`: ESM entry
  - `types`: TypeScript declarations
  - `react-native`: RN entry point
  - Scripts: `build`, `lint`, `test`, `typecheck`
  - Peer dependencies: `react`, `react-native` (>= 0.73)
- [ ] Set up TypeScript (`tsconfig.json`) with strict mode
- [ ] Set up ESLint + Prettier (aligned with project style)
- [ ] Set up Jest for unit testing
- [ ] Configure `react-native.config.js` for auto-linking
- [ ] Create `android/build.gradle.kts` with dependency on `tracelet-core`
- [ ] Create `ios/TraceletReactNative.podspec` with dependency on `TraceletCore`

### 0.4 CI/CD Integration
- [ ] Add npm-specific scripts to `melos.yaml` (or a parallel `package.json` workspace)
- [ ] Add GitHub Actions workflow: `rn-ci.yml`
  - Lint TypeScript
  - Type-check
  - Run Jest tests
  - Build Android (Gradle)
  - Build iOS (xcodebuild)
- [ ] Add Detox or Maestro config for E2E testing
- [ ] Configure Changesets or semantic-release for npm publishing

### 0.5 Example App
- [ ] Create `packages/tracelet_react_native/example/` React Native app
- [ ] Minimum viable app: show current location on a map
- [ ] Wire up auto-linking so the example uses the local package source

---

## Phase 1 — Core Native Module

**Goal**: Implement the TurboModule that bridges JS ↔ native engines for lifecycle and location methods.

### 1.1 TurboModule Spec (TypeScript Codegen)

```typescript
// src/NativeTracelet.ts
import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  // Lifecycle
  ready(config: Object): Promise<Object>;
  start(): Promise<Object>;
  stop(): Promise<Object>;
  startGeofences(): Promise<Object>;
  startPeriodic(): Promise<Object>;
  getState(): Promise<Object>;
  setConfig(config: Object): Promise<Object>;
  reset(config?: Object): Promise<Object>;

  // Location
  getCurrentPosition(options: Object): Promise<Object>;
  getLastKnownLocation(options?: Object): Promise<Object | null>;
  watchPosition(options: Object): Promise<number>;
  stopWatchPosition(watchId: number): Promise<boolean>;
  changePace(isMoving: boolean): Promise<boolean>;
  getOdometer(): Promise<number>;
  setOdometer(value: number): Promise<Object>;

  // Geofencing
  addGeofence(geofence: Object): Promise<boolean>;
  addGeofences(geofences: Object[]): Promise<boolean>;
  removeGeofence(identifier: string): Promise<boolean>;
  removeGeofences(): Promise<boolean>;
  getGeofences(): Promise<Object[]>;
  getGeofence(identifier: string): Promise<Object | null>;
  geofenceExists(identifier: string): Promise<boolean>;

  // Persistence
  getLocations(query?: Object): Promise<Object[]>;
  getCount(): Promise<number>;
  destroyLocations(): Promise<boolean>;
  destroyLocation(uuid: string): Promise<boolean>;
  insertLocation(location: Object): Promise<string>;

  // HTTP Sync
  sync(): Promise<Object[]>;

  // Permissions
  requestPermission(): Promise<number>;
  getPermissionStatus(): Promise<number>;
  requestNotificationPermission(): Promise<number>;
  getNotificationPermissionStatus(): Promise<number>;
  requestMotionPermission(): Promise<number>;
  getMotionPermissionStatus(): Promise<number>;
  requestTemporaryFullAccuracy(purposeKey: string): Promise<number>;
  canScheduleExactAlarms(): Promise<boolean>;

  // Utilities
  isPowerSaveMode(): Promise<boolean>;
  getProviderState(): Promise<Object>;
  getSensors(): Promise<Object>;
  getDeviceInfo(): Promise<Object>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TraceletReactNative');
```

### 1.2 Android TurboModule Implementation

```kotlin
// android/src/main/kotlin/com/tracelet/reactnative/TraceletModule.kt
class TraceletModule(reactContext: ReactApplicationContext) :
    NativeTraceletSpec(reactContext),   // Generated by Codegen
    TraceletEngineCallback {           // From tracelet-core

    private lateinit var engine: TraceletEngine  // Facade from tracelet-core

    override fun getName() = NAME

    override fun ready(config: ReadableMap, promise: Promise) {
        engine = TraceletEngine.getInstance(reactApplicationContext)
        engine.setCallback(this)
        engine.ready(config.toHashMap(), promise::resolve, promise::reject)
    }

    // ... delegate all methods to engine

    // TraceletEngineCallback implementations → emit events
    override fun onLocation(location: Map<String, Any?>) {
        sendEvent("onLocation", Arguments.makeNativeMap(location))
    }

    companion object {
        const val NAME = "TraceletReactNative"
    }
}
```

### 1.3 iOS TurboModule Implementation

```swift
// ios/Sources/TraceletModule.swift
@objc(TraceletReactNative)
class TraceletModule: RCTEventEmitter, TraceletEngineDelegate {

    private lazy var engine = TraceletEngine.shared

    override func supportedEvents() -> [String] {
        return [
            "onLocation", "onMotionChange", "onActivityChange",
            "onProviderChange", "onGeofence", "onGeofencesChange",
            "onHeartbeat", "onHttp", "onSchedule",
            "onPowerSaveChange", "onConnectivityChange",
            "onEnabledChange", "onAuthorization"
        ]
    }

    @objc func ready(_ config: NSDictionary,
                     resolve: @escaping RCTPromiseResolveBlock,
                     reject: @escaping RCTPromiseRejectBlock) {
        engine.delegate = self
        engine.ready(config: config as! [String: Any]) { state in
            resolve(state)
        } onError: { error in
            reject("ERR_READY", error.localizedDescription, error)
        }
    }

    // TraceletEngineDelegate → sendEvent
    func onLocation(_ location: [String: Any?]) {
        sendEvent(withName: "onLocation", body: location)
    }
}
```

### 1.4 Lifecycle & Location Methods
- [ ] Implement `ready()`, `start()`, `stop()`, `getState()`, `setConfig()`, `reset()`
- [ ] Implement `getCurrentPosition()`, `getLastKnownLocation()`
- [ ] Implement `watchPosition()`, `stopWatchPosition()`
- [ ] Implement `changePace()`, `getOdometer()`, `setOdometer()`
- [ ] Verify foreground location tracking works on both platforms
- [ ] Write unit tests for all lifecycle transitions

---

## Phase 2 — Event System

**Goal**: Deliver all 15 event streams to JavaScript via `NativeEventEmitter`.

### 2.1 Event Architecture

```
┌──────────────────────────────┐
│  React Native App (JS)       │
│  ─────────────────────────── │
│  const emitter =             │
│    new NativeEventEmitter(   │
│      NativeModules.Tracelet  │
│    );                        │
│  emitter.addListener(        │
│    'onLocation', callback    │
│  );                          │
└────────────┬─────────────────┘
             │ JSI / Bridge
┌────────────▼─────────────────┐
│  TraceletModule (Native)     │
│  ─────────────────────────── │
│  Implements RCTEventEmitter  │
│  (iOS) / sends events via    │
│  RCTDeviceEventEmitter       │
│  (Android)                   │
└────────────┬─────────────────┘
             │ Callback/Delegate
┌────────────▼─────────────────┐
│  TraceletCore Engines        │
│  (Shared Kotlin/Swift)       │
│  LocationEngine              │
│  MotionDetector              │
│  GeofenceManager             │
│  etc.                        │
└──────────────────────────────┘
```

### 2.2 Event Mapping

| Tracelet Event               | RN Event Name            | Payload Type       |
|------------------------------|--------------------------|--------------------|
| `onLocation`                 | `onLocation`             | `Location`         |
| `onMotionChange`             | `onMotionChange`         | `MotionChangeEvent`|
| `onActivityChange`           | `onActivityChange`       | `ActivityChangeEvent`|
| `onProviderChange`           | `onProviderChange`       | `ProviderChangeEvent`|
| `onGeofence`                 | `onGeofence`             | `GeofenceEvent`    |
| `onGeofencesChange`          | `onGeofencesChange`      | `GeofencesChangeEvent`|
| `onHeartbeat`                | `onHeartbeat`            | `HeartbeatEvent`   |
| `onHttp`                     | `onHttp`                 | `HttpEvent`        |
| `onSchedule`                 | `onSchedule`             | `HeadlessEvent`    |
| `onPowerSaveChange`          | `onPowerSaveChange`      | `boolean`          |
| `onConnectivityChange`       | `onConnectivityChange`   | `ConnectivityChangeEvent`|
| `onEnabledChange`            | `onEnabledChange`        | `boolean`          |
| `onNotificationAction`       | `onNotificationAction`   | `string`           |
| `onAuthorization`            | `onAuthorization`        | `AuthorizationEvent`|
| `onWatchPosition`            | `onWatchPosition`        | `Location`         |

### 2.3 Implementation Tasks
- [ ] Implement `supportedEvents()` on iOS (`RCTEventEmitter`)
- [ ] Implement event emission on Android via `RCTDeviceEventEmitter`
- [ ] Create TypeScript `EventEmitter` wrapper with typed listeners
- [ ] Add `startObserving()` / `stopObserving()` lifecycle management
- [ ] Verify no events are lost when JS listener is not attached (buffer or drop)
- [ ] Test all 15 event types end-to-end on both platforms

---

## Phase 3 — Feature Parity Matrix

**Goal**: Implement remaining API surface to reach full parity with Flutter.

### 3.1 Geofencing
- [ ] `addGeofence()` / `addGeofences()` — circular + polygon
- [ ] `removeGeofence()` / `removeGeofences()`
- [ ] `getGeofences()` / `getGeofence()` / `geofenceExists()`
- [ ] Geofence event delivery (enter/exit/dwell)
- [ ] Test geofence CRUD and event delivery on both platforms

### 3.2 Persistence (SQLite)
- [ ] `getLocations(query?)` with SQLQuery support
- [ ] `getCount()`
- [ ] `destroyLocations()` / `destroyLocation(uuid)`
- [ ] `insertLocation(location)`
- [ ] Test persistence CRUD on both platforms

### 3.3 HTTP Sync
- [ ] `sync()` manual trigger
- [ ] Auto-sync via config (`HttpConfig.autoSync`, `autoSyncThreshold`)
- [ ] Batch sync support
- [ ] `onHttp` event delivery
- [ ] Test sync lifecycle on both platforms

### 3.4 Permissions
- [ ] All 8 permission methods (location, notification, motion, temporary full accuracy, exact alarms)
- [ ] Platform-specific permission flows (Android 13+ notifications, iOS 14+ temporary accuracy)
- [ ] Test permission request and status flows

### 3.5 Utilities
- [ ] `isPowerSaveMode()`, `getProviderState()`, `getSensors()`, `getDeviceInfo()`
- [ ] Provider change detection

### 3.6 Dart-Only Algorithms (Port to TypeScript)

Some algorithms currently run in Dart and need TypeScript equivalents:

| Algorithm | Dart Source | TypeScript Target | Complexity |
|-----------|-------------|-------------------|------------|
| KalmanLocationFilter | `packages/tracelet/lib/src/kalman/` | `src/algorithms/KalmanFilter.ts` | High |
| TripManager | `packages/tracelet/lib/src/trip/` | `src/algorithms/TripManager.ts` | Medium |
| BatteryBudgetEngine | `packages/tracelet/lib/src/battery/` | `src/algorithms/BatteryBudget.ts` | Medium |
| LocationProcessor | `packages/tracelet/lib/src/location/` | `src/algorithms/LocationProcessor.ts` | Medium |
| GeofenceEvaluator | `packages/tracelet/lib/src/geofence/` | `src/algorithms/GeofenceEvaluator.ts` | Low |
| DeltaEncoder | native code | Already in native | N/A |

- [ ] Port KalmanLocationFilter to TypeScript with identical parameters
- [ ] Port TripManager to TypeScript
- [ ] Port BatteryBudgetEngine to TypeScript
- [ ] Port LocationProcessor to TypeScript
- [ ] Port GeofenceEvaluator (ray-casting point-in-polygon) to TypeScript
- [ ] Add numerical precision tests comparing Dart and TS outputs against reference data

---

## Phase 4 — Headless & Background Execution

**Goal**: Support background/headless task execution in React Native — the hardest problem.

### 4.1 The Challenge

Flutter has `HeadlessTaskService` / `HeadlessRunner` which can start a `FlutterEngine` in the background. React Native has no direct equivalent. We need platform-specific solutions.

### 4.2 Android Headless Execution

**Strategy**: Use `HeadlessJsTaskService` (React Native's built-in headless JS support).

```kotlin
class TraceletHeadlessService : HeadlessJsTaskService() {
    override fun getTaskConfig(intent: Intent): HeadlessJsTaskConfig {
        val data = intent.extras?.let { Arguments.fromBundle(it) }
        return HeadlessJsTaskConfig(
            "TraceletHeadlessTask",
            data,
            5000,  // timeout
            true   // allow in foreground
        )
    }
}
```

JS registration:
```typescript
// index.js (app entry, NOT component)
import { AppRegistry } from 'react-native';
import { Tracelet } from '@tracelet/react-native';

AppRegistry.registerHeadlessTask(
  'TraceletHeadlessTask',
  () => async (event) => {
    // Handle background event (location, geofence, schedule, etc.)
    console.log('Headless event:', event);
  }
);
```

- [ ] Implement `TraceletHeadlessService` (Android)
- [ ] Register headless task in `AndroidManifest.xml`
- [ ] Bridge headless events from native core
- [ ] Test headless execution after app termination

### 4.3 iOS Headless/Background Execution

**Strategy**: iOS doesn't have React Native headless JS. Options:

1. **Native-only processing** (recommended): Background events are processed entirely in native code (TraceletCore). Events are queued and delivered to JS when the app resumes.
2. **Background fetch + JS execution**: Use `BGAppRefreshTask` to wake the app and execute JS, but this is unreliable and rate-limited.

- [ ] Implement native-only background processing on iOS
- [ ] Queue background events in SQLite for delivery on app resume
- [ ] Implement `getBackgroundEvents()` API for retrieving queued events
- [ ] Document iOS background limitations vs. Android

### 4.4 Foreground Service (Android)

- [ ] Expose foreground notification customization via config
- [ ] Support notification actions (Android)
- [ ] Handle `onNotificationAction` events

---

## Phase 5 — Enterprise Features

**Goal**: Port enterprise features that are already implemented in TraceletCore.

### 5.1 Audit Trail
- [ ] Expose `AuditConfig` in TypeScript
- [ ] SHA-256 chain hash fields on `Location` type
- [ ] `getAuditTrail()` API
- [ ] Test chain integrity verification

### 5.2 Privacy Zones
- [ ] Expose `PrivacyZoneConfig` in TypeScript
- [ ] Add/remove privacy zones API
- [ ] Verify location exclusion/obfuscation in privacy zones

### 5.3 Compliance Reporting
- [ ] Expose `generateComplianceReport()` API
- [ ] TypeScript types for compliance report data

### 5.4 Encrypted SQLite (SQLCipher)
- [ ] Expose `SecurityConfig` in TypeScript
- [ ] `isDatabaseEncrypted()` / `encryptDatabase()` APIs
- [ ] Test encryption/decryption lifecycle

### 5.5 Carbon Estimator
- [ ] Expose carbon estimation APIs and config
- [ ] TypeScript types for carbon data

---

## Phase 6 — Testing & Quality

### 6.1 Unit Tests (Jest)
- [ ] TypeScript API tests (mocked native module)
- [ ] Config serialization/deserialization tests
- [ ] Algorithm ports: KalmanFilter, TripManager, BatteryBudget numerical accuracy tests
- [ ] Event type mapping tests
- [ ] Coverage target: ≥90% TypeScript line coverage

### 6.2 Native Unit Tests
- [ ] Android: JUnit tests for `TraceletModule` ↔ `TraceletEngine` bridge
- [ ] iOS: XCTest for `TraceletModule` ↔ `TraceletEngine` bridge
- [ ] Verify native module method dispatch matches spec

### 6.3 Integration Tests
- [ ] Android: Detox or Maestro E2E tests
  - Start/stop tracking lifecycle
  - Location event delivery
  - Geofence enter/exit
  - HTTP sync round-trip
  - Permission flows
- [ ] iOS: Detox or Maestro E2E tests (same scenarios)
- [ ] Background/headless execution tests (manual + CI with device farm)

### 6.4 Performance Benchmarks
- [ ] JSI bridge overhead measurement (< 1ms per call)
- [ ] Event throughput: handle 10 location events/sec without frame drops
- [ ] Memory leak detection (long-running tracking sessions)
- [ ] Battery comparison: RN vs Flutter implementation (should be nearly identical since engines are shared)

### 6.5 Compatibility Matrix

| React Native Version | Support Level |
|----------------------|---------------|
| 0.76+ (New Arch)    | Full (TurboModule) |
| 0.73–0.75           | Full (interop layer) |
| < 0.73              | Not supported |

| Platform  | Minimum Version |
|-----------|-----------------|
| Android   | API 26 (8.0)    |
| iOS       | 14.0            |

---

## Phase 7 — Documentation & Publishing

### 7.1 Documentation
- [ ] `README.md` with quick start, installation, basic usage
- [ ] `INSTALL-ANDROID.md` — Android-specific setup (permissions, services, ProGuard)
- [ ] `INSTALL-IOS.md` — iOS-specific setup (capabilities, Info.plist, background modes)
- [ ] `API.md` — Full API reference (auto-generated from TypeDoc)
- [ ] `MIGRATION.md` — Guide for users migrating from `react-native-background-geolocation`
- [ ] `BACKGROUND-GUIDE.md` — Platform-specific background execution details
- [ ] `HOOKS.md` — React hooks usage guide
- [ ] `EXAMPLE.md` — Example app walkthrough

### 7.2 Publishing Pipeline
- [ ] Configure npm publish automation (GitHub Actions)
- [ ] Scoped package: `@tracelet/react-native`
- [ ] Semantic versioning aligned with native engine releases
- [ ] Changelog automation (Changesets or conventional-commits)
- [ ] Publish pre-release versions to npm for testing (`@tracelet/react-native@next`)

### 7.3 Developer Experience
- [ ] TypeDoc API documentation site
- [ ] Example app with all features demonstrated
- [ ] Expo config plugin for managed workflow: `@tracelet/expo-plugin`

---

## API Surface Design

### Public TypeScript API

```typescript
// @tracelet/react-native

// ─── Singleton ───
class Tracelet {
  // Lifecycle
  static ready(config: Config): Promise<State>;
  static start(): Promise<State>;
  static stop(): Promise<State>;
  static startGeofences(): Promise<State>;
  static startPeriodic(): Promise<State>;
  static getState(): Promise<State>;
  static setConfig(config: Partial<Config>): Promise<State>;
  static reset(config?: Config): Promise<State>;

  // Location
  static getCurrentPosition(options?: CurrentPositionOptions): Promise<Location>;
  static getLastKnownLocation(options?: LastKnownLocationOptions): Promise<Location | null>;
  static watchPosition(options: WatchPositionOptions): Promise<number>;
  static stopWatchPosition(watchId: number): Promise<boolean>;
  static changePace(isMoving: boolean): Promise<boolean>;
  static getOdometer(): Promise<number>;
  static setOdometer(value: number): Promise<Location>;

  // Geofencing
  static addGeofence(geofence: Geofence): Promise<boolean>;
  static addGeofences(geofences: Geofence[]): Promise<boolean>;
  static removeGeofence(identifier: string): Promise<boolean>;
  static removeGeofences(): Promise<boolean>;
  static getGeofences(): Promise<Geofence[]>;
  static getGeofence(identifier: string): Promise<Geofence | null>;
  static geofenceExists(identifier: string): Promise<boolean>;

  // Persistence
  static getLocations(query?: SQLQuery): Promise<Location[]>;
  static getCount(): Promise<number>;
  static destroyLocations(): Promise<boolean>;
  static destroyLocation(uuid: string): Promise<boolean>;
  static insertLocation(location: Partial<Location>): Promise<string>;

  // HTTP Sync
  static sync(): Promise<Location[]>;

  // Permissions
  static requestPermission(): Promise<AuthorizationStatus>;
  static getPermissionStatus(): Promise<AuthorizationStatus>;
  static requestNotificationPermission(): Promise<AuthorizationStatus>;
  static getNotificationPermissionStatus(): Promise<AuthorizationStatus>;
  static requestMotionPermission(): Promise<AuthorizationStatus>;
  static getMotionPermissionStatus(): Promise<AuthorizationStatus>;
  static requestTemporaryFullAccuracy(purposeKey: string): Promise<AccuracyAuthorization>;
  static canScheduleExactAlarms(): Promise<boolean>;

  // Utilities
  static isPowerSaveMode(): Promise<boolean>;
  static getProviderState(): Promise<ProviderChangeEvent>;
  static getSensors(): Promise<Sensors>;
  static getDeviceInfo(): Promise<DeviceInfo>;

  // Events
  static onLocation(callback: (location: Location) => void): Subscription;
  static onMotionChange(callback: (event: MotionChangeEvent) => void): Subscription;
  static onActivityChange(callback: (event: ActivityChangeEvent) => void): Subscription;
  static onProviderChange(callback: (event: ProviderChangeEvent) => void): Subscription;
  static onGeofence(callback: (event: GeofenceEvent) => void): Subscription;
  static onGeofencesChange(callback: (event: GeofencesChangeEvent) => void): Subscription;
  static onHeartbeat(callback: (event: HeartbeatEvent) => void): Subscription;
  static onHttp(callback: (event: HttpEvent) => void): Subscription;
  static onSchedule(callback: (event: HeadlessEvent) => void): Subscription;
  static onPowerSaveChange(callback: (isPowerSave: boolean) => void): Subscription;
  static onConnectivityChange(callback: (event: ConnectivityChangeEvent) => void): Subscription;
  static onEnabledChange(callback: (enabled: boolean) => void): Subscription;
  static onNotificationAction(callback: (action: string) => void): Subscription;
  static onAuthorization(callback: (event: AuthorizationEvent) => void): Subscription;
}

// ─── React Hooks ───
function useLocation(): Location | null;
function useTraceletState(): State | null;
function useGeofences(): Geofence[];
function useGeofenceEvent(): GeofenceEvent | null;
function useMotionChange(): MotionChangeEvent | null;

// ─── Subscription ───
interface Subscription {
  remove(): void;
}
```

### Configuration Types

```typescript
interface Config {
  geo?: GeoConfig;
  app?: AppConfig;
  http?: HttpConfig;
  logger?: LoggerConfig;
  motion?: MotionConfig;
  geofence?: GeofenceConfig;
  persistence?: PersistenceConfig;
  audit?: AuditConfig;
  privacyZone?: PrivacyZoneConfig;
}

interface GeoConfig {
  desiredAccuracy?: DesiredAccuracy;
  distanceFilter?: number;
  locationUpdateInterval?: number;
  fastestLocationUpdateInterval?: number;
  stationaryRadius?: number;
  locationTimeout?: number;
  activityType?: ActivityType;
  disableElasticity?: boolean;
  elasticityMultiplier?: number;
  enableAdaptiveMode?: boolean;
  batteryBudgetPerHour?: number;
  enableSparseUpdates?: boolean;
  sparseDistanceThreshold?: number;
  sparseMaxIdleSeconds?: number;
  periodicLocationInterval?: number;
  geofenceModeHighAccuracy?: boolean;
  enableTimestampMeta?: boolean;
  filter?: LocationFilter;
}

// ... (all other config types mirror Dart exactly)
```

---

## Native Code Reuse Strategy

### Dependency Graph (After Extraction)

```
┌─────────────────────────────────────────────────────┐
│                  Application Layer                   │
├──────────────────────┬──────────────────────────────┤
│  Flutter App         │  React Native App            │
│  (Dart)              │  (TypeScript)                │
├──────────────────────┼──────────────────────────────┤
│  tracelet            │  @tracelet/react-native      │
│  (Dart API)          │  (TypeScript API)            │
├──────────────────────┼──────────────────────────────┤
│  tracelet_android    │  TraceletModule.kt           │
│  tracelet_ios        │  TraceletModule.swift         │
│  (Flutter adapters)  │  (React Native adapters)     │
├──────────────────────┴──────────────────────────────┤
│              TraceletCore (Shared)                    │
│  ┌─────────────────────────────────────────────────┐│
│  │ LocationEngine · MotionDetector · GeofenceManager││
│  │ HttpSyncManager · TraceletDatabase · ConfigManager│
│  │ StateManager · ScheduleManager · AuditTrailManager│
│  │ PrivacyZoneManager · DeltaEncoder · Logger       ││
│  └─────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────┤
│              Platform APIs                           │
│  Android: FusedLocation, Activity Recognition, Room  │
│  iOS: CoreLocation, CoreMotion, BGTaskScheduler      │
└─────────────────────────────────────────────────────┘
```

### Build Integration

**Android** (Gradle composite build):
```kotlin
// native/android/tracelet-core/build.gradle.kts
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.tracelet.core"
    compileSdk = 35
    defaultConfig { minSdk = 26 }
}

dependencies {
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
```

```kotlin
// packages/tracelet_android/android/build.gradle.kts
dependencies {
    implementation(project(":tracelet-core"))  // via composite build
    implementation("io.flutter:flutter_embedding_debug:1.0.0")
}
```

```kotlin
// packages/tracelet_react_native/android/build.gradle.kts
dependencies {
    implementation(project(":tracelet-core"))  // via composite build
    implementation("com.facebook.react:react-android")
}
```

**iOS** (Swift Package Manager):
```swift
// native/ios/TraceletCore/Package.swift
let package = Package(
    name: "TraceletCore",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "TraceletCore", targets: ["TraceletCore"]),
    ],
    targets: [
        .target(name: "TraceletCore"),
        .testTarget(name: "TraceletCoreTests", dependencies: ["TraceletCore"]),
    ]
)
```

---

## Migration Path for Existing RN Users

For developers currently using `react-native-background-geolocation` (transistorsoft) or similar packages:

### API Mapping Guide

| Transistorsoft API | Tracelet Equivalent |
|--------------------|---------------------|
| `BackgroundGeolocation.ready(config)` | `Tracelet.ready(config)` |
| `BackgroundGeolocation.start()` | `Tracelet.start()` |
| `BackgroundGeolocation.stop()` | `Tracelet.stop()` |
| `BackgroundGeolocation.getCurrentPosition()` | `Tracelet.getCurrentPosition()` |
| `BackgroundGeolocation.onLocation(cb)` | `Tracelet.onLocation(cb)` |
| `BackgroundGeolocation.onMotionChange(cb)` | `Tracelet.onMotionChange(cb)` |
| `BackgroundGeolocation.onGeofence(cb)` | `Tracelet.onGeofence(cb)` |
| `BackgroundGeolocation.addGeofence(g)` | `Tracelet.addGeofence(g)` |
| `BackgroundGeolocation.changePace(bool)` | `Tracelet.changePace(bool)` |
| `BackgroundGeolocation.getState()` | `Tracelet.getState()` |

### Config Mapping

| Transistorsoft Config | Tracelet Config |
|-----------------------|-----------------|
| `desiredAccuracy` | `geo.desiredAccuracy` |
| `distanceFilter` | `geo.distanceFilter` |
| `stopTimeout` | `motion.stopTimeout` |
| `url` | `http.url` |
| `headers` | `http.headers` |
| `autoSync` | `http.autoSync` |
| `batchSync` | `http.batchSync` |
| `maxBatchSize` | `http.maxBatchSize` |
| `logLevel` | `logger.level` |

### Key Differences
1. **Nested config** — Tracelet uses structured sub-configs (`geo.*`, `http.*`, `motion.*`) instead of flat config
2. **Apache 2.0 license** — No commercial license required
3. **TypeScript-first** — Full type safety, no `any` types
4. **React hooks** — `useLocation()`, `useTraceletState()`, etc.
5. **Battery budget** — Unique `batteryBudgetPerHour` feature

---

## Risk Register

| # | Risk | Impact | Probability | Mitigation |
|---|------|--------|-------------|------------|
| R1 | Native core extraction breaks existing Flutter tests | High | Medium | Run full Flutter test suite after each extraction step. Use feature flags during migration. |
| R2 | TurboModule Codegen limitations with complex types | Medium | Medium | Fallback to `ReadableMap`/`NSDictionary` for complex nested objects. Use manual type conversion layer. |
| R3 | iOS headless JS execution is unreliable | High | High | Accept native-only background processing on iOS. Document clearly. Queue events for delivery on app resume. |
| R4 | Expo managed workflow compatibility | Medium | Medium | Build Expo config plugin early. Test with Expo SDK 52+. |
| R5 | Bundle size increase from dual-framework native code | Low | Low | TraceletCore is shared — not duplicated. JS bundle adds ~40KB gzipped. |
| R6 | React Native version fragmentation | Medium | Medium | Target 0.73+ only. Use interop layer for backward compat. |
| R7 | Dart algorithm ports have numerical drift | Medium | Low | Use reference test vectors. Compare Dart and TS outputs to < 1e-10 tolerance. |
| R8 | Maintenance burden of two JS frameworks | High | High | Shared native core minimizes this. TypeScript algorithms are tested independently. CI gate prevents regression. |

---

## Release Timeline

### v0.1.0-alpha — Foundation
- Native core extraction (Android + iOS)
- Package scaffolding
- Lifecycle methods (ready/start/stop)
- Foreground location tracking
- Basic event delivery (onLocation, onMotionChange)

### v0.2.0-alpha — Core Features
- All 15 event streams
- Geofencing (circular + polygon)
- SQLite persistence APIs
- Permission management

### v0.3.0-beta — Parity
- HTTP sync
- Headless execution (Android)
- iOS background queueing
- Kalman filter + location processor (TypeScript)
- Trip detection (TypeScript)

### v0.4.0-beta — Enterprise
- Audit trail
- Privacy zones
- Battery budget engine (TypeScript)
- Compliance reporting

### v1.0.0 — Stable
- Full feature parity with Flutter package
- ≥90% test coverage
- Complete documentation
- Expo config plugin
- Published to npm as `@tracelet/react-native`

---

## Appendix A: File-by-File Creation Checklist

| File | Purpose |
|------|---------|
| `packages/tracelet_react_native/package.json` | npm package manifest |
| `packages/tracelet_react_native/tsconfig.json` | TypeScript config |
| `packages/tracelet_react_native/babel.config.js` | Babel for Metro |
| `packages/tracelet_react_native/react-native.config.js` | Auto-linking |
| `packages/tracelet_react_native/.eslintrc.js` | ESLint rules |
| `packages/tracelet_react_native/jest.config.js` | Jest test config |
| `packages/tracelet_react_native/src/index.tsx` | Package entry |
| `packages/tracelet_react_native/src/NativeTracelet.ts` | TurboModule spec |
| `packages/tracelet_react_native/src/Tracelet.ts` | Public API singleton |
| `packages/tracelet_react_native/src/types/Config.ts` | Config types |
| `packages/tracelet_react_native/src/types/Location.ts` | Location types |
| `packages/tracelet_react_native/src/types/Geofence.ts` | Geofence types |
| `packages/tracelet_react_native/src/types/State.ts` | State types |
| `packages/tracelet_react_native/src/types/Events.ts` | Event types |
| `packages/tracelet_react_native/src/types/Enums.ts` | Enum types |
| `packages/tracelet_react_native/src/hooks/useLocation.ts` | Location hook |
| `packages/tracelet_react_native/src/hooks/useTraceletState.ts` | State hook |
| `packages/tracelet_react_native/src/hooks/useGeofences.ts` | Geofences hook |
| `packages/tracelet_react_native/src/algorithms/KalmanFilter.ts` | Kalman port |
| `packages/tracelet_react_native/src/algorithms/TripManager.ts` | Trip port |
| `packages/tracelet_react_native/src/algorithms/BatteryBudget.ts` | Battery port |
| `packages/tracelet_react_native/src/algorithms/LocationProcessor.ts` | Filter port |
| `packages/tracelet_react_native/src/algorithms/GeofenceEvaluator.ts` | Geofence port |
| `packages/tracelet_react_native/android/build.gradle.kts` | Android build |
| `packages/tracelet_react_native/android/src/main/.../TraceletModule.kt` | TurboModule |
| `packages/tracelet_react_native/android/src/main/.../TraceletPackage.kt` | ReactPackage |
| `packages/tracelet_react_native/android/src/main/.../EventAdapter.kt` | Event bridge |
| `packages/tracelet_react_native/ios/TraceletReactNative.podspec` | CocoaPods spec |
| `packages/tracelet_react_native/ios/Sources/TraceletModule.swift` | TurboModule |
| `packages/tracelet_react_native/ios/Sources/TraceletModule.mm` | ObjC++ bridge |
| `packages/tracelet_react_native/ios/Sources/EventAdapter.swift` | Event bridge |
| `native/android/tracelet-core/build.gradle.kts` | Core Android lib |
| `native/android/tracelet-core/src/main/kotlin/...` | Extracted engines |
| `native/ios/TraceletCore/Package.swift` | Core iOS package |
| `native/ios/TraceletCore/Sources/...` | Extracted engines |

## Appendix B: Shared vs. Platform-Specific Code

| Component | Shared (TraceletCore) | Flutter Adapter | RN Adapter | TypeScript |
|-----------|----------------------|-----------------|------------|------------|
| LocationEngine | ✅ | Thin bridge | Thin bridge | — |
| MotionDetector | ✅ | Thin bridge | Thin bridge | — |
| GeofenceManager | ✅ | Thin bridge | Thin bridge | — |
| HttpSyncManager | ✅ | Thin bridge | Thin bridge | — |
| TraceletDatabase | ✅ | Thin bridge | Thin bridge | — |
| ConfigManager | ✅ | Thin bridge | Thin bridge | — |
| StateManager | ✅ | Thin bridge | Thin bridge | — |
| ScheduleManager | ✅ | Thin bridge | Thin bridge | — |
| KalmanFilter | — | Dart | — | TS port |
| TripManager | — | Dart | — | TS port |
| BatteryBudget | — | Dart | — | TS port |
| LocationProcessor | — | Dart | — | TS port |
| GeofenceEvaluator | — | Dart | — | TS port |
| EventDispatcher | — | EventChannel | NativeEventEmitter | — |
| HeadlessRunner | — | FlutterEngine | HeadlessJsTask (Android) | — |
