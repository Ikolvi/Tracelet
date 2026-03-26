# Native SDK — Installation & Usage

> **Use Tracelet without Flutter.** The native SDKs are framework-agnostic — usable from pure Kotlin/Swift apps, React Native, Capacitor, or any other framework.

The native SDKs mirror the Flutter plugin's structured configuration pattern. Dart developers and native developers use the **same** config hierarchy: `Config → GeoConfig, AppConfig, HttpConfig, LoggerConfig, ...`

> For detailed platform-specific documentation with full API references, see:
> - [Android SDK README](../sdk/android/README.md) — Maven Central, Gradle, permissions, ProGuard
> - [iOS SDK README](../sdk/ios/README.md) — CocoaPods, SPM, Info.plist, capabilities

---

## Android — Maven Central

### Gradle (Kotlin DSL)

```kotlin
dependencies {
    implementation("com.ikolvi:tracelet-sdk:0.1.0")
}
```

### Gradle (Groovy)

```groovy
dependencies {
    implementation 'com.ikolvi:tracelet-sdk:0.1.0'
}
```

### Requirements

| Requirement | Value |
|---|---|
| `minSdk` | **26** (Android 8.0) |
| `compileSdk` | **34+** |
| Kotlin | **1.9+** |
| Java | **17** |

### Quick Start

```kotlin
import com.ikolvi.tracelet.sdk.TraceletSdk
import com.ikolvi.tracelet.sdk.TraceletListener
import com.ikolvi.tracelet.sdk.model.*

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()

        val sdk = TraceletSdk.getInstance(this)

        // 1. Listen to events
        sdk.addListener(object : TraceletListener {
            override fun onLocation(location: Map<String, Any?>) {
                Log.d("Tracelet", "[location] $location")
            }
            override fun onMotionChange(data: Map<String, Any?>) {
                Log.d("Tracelet", "[motionchange] isMoving: ${data["isMoving"]}")
            }
        })

        // 2. Configure & ready — same structure as Dart Config
        sdk.ready(TraceletConfig(
            geo = GeoConfig(
                desiredAccuracy = DesiredAccuracy.HIGH,
                distanceFilter = 10.0,
                filter = LocationFilter(
                    trackingAccuracyThreshold = 100,
                    maxImpliedSpeed = 80,
                ),
            ),
            app = AppConfig(
                stopOnTerminate = false,
                startOnBoot = true,
                foregroundService = ForegroundServiceConfig(
                    notificationTitle = "My App",
                    notificationText = "Tracking your location",
                ),
            ),
            persistence = PersistenceConfig(
                maxDaysToPersist = 7,
                maxRecordsToPersist = 5000,
            ),
            logger = LoggerConfig(
                debug = true,
                logLevel = LogLevel.VERBOSE,
            ),
        )) { state ->
            // 3. Start tracking
            if (state["enabled"] == false) {
                sdk.start()
            }
        }
    }
}
```

### Published Artifact

- **Group**: `com.ikolvi`
- **Artifact**: `tracelet-sdk`
- **Repository**: [Maven Central](https://central.sonatype.com/artifact/com.ikolvi/tracelet-sdk)

---

## iOS — CocoaPods

### Podfile

```ruby
platform :ios, '14.0'

target 'MyApp' do
  use_frameworks!
  pod 'TraceletSDK', '~> 0.1.0'
end
```

Then run:

```bash
pod install
```

---

## iOS — Swift Package Manager

### Xcode UI

1. **File → Add Package Dependencies...**
2. Enter: `https://github.com/Ikolvi/Tracelet.git`
3. Set version rule: **Up to Next Major** from `0.1.0`
4. Add the `TraceletSDK` library to your target

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/Ikolvi/Tracelet.git", from: "0.1.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "TraceletSDK", package: "Tracelet")
        ]
    )
]
```

### Requirements

| Requirement | Value |
|---|---|
| iOS | **14.0+** |
| Swift | **5.9+** |
| Xcode | **15.0+** |

### Quick Start

```swift
import TraceletSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate, TraceletDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let sdk = TraceletSdk.shared

        // 1. Listen to events
        sdk.delegate = self

        // 2. Configure & ready — same structure as Dart Config
        let state = sdk.ready(config: TraceletConfig(
            geo: .init(
                desiredAccuracy: .high,
                distanceFilter: 10.0,
                filter: .init(
                    trackingAccuracyThreshold: 100,
                    maxImpliedSpeed: 80
                )
            ),
            app: .init(
                stopOnTerminate: false,
                startOnBoot: true,
                preventSuspend: true
            ),
            persistence: .init(
                maxDaysToPersist: 7,
                maxRecordsToPersist: 5000
            ),
            logger: .init(
                debug: true,
                logLevel: .verbose
            )
        ))

        // 3. Start tracking
        if state["enabled"] as? Bool == false {
            sdk.start()
        }

        return true
    }

    // MARK: - TraceletDelegate

    func tracelet(_ sdk: TraceletSdk, didUpdateLocation location: [String: Any]) {
        print("[location] \(location)")
    }

    func tracelet(_ sdk: TraceletSdk, didChangeMotion data: [String: Any]) {
        print("[motionchange] isMoving: \(data["isMoving"] ?? false)")
    }
}
```

### Info.plist

Add the required privacy keys to your app's `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to track your route.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Background location is required for route recording.</string>

<key>NSMotionUsageDescription</key>
<string>Motion data is used to detect movement and save battery.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
    <string>processing</string>
</array>
```

---

## Configuration Parity

The native SDKs use the **same configuration hierarchy** as the Dart plugin. Every config group, property name, and default value is identical:

| Config Group | Dart | Kotlin | Swift |
|---|---|---|---|
| Top-level | `Config(...)` | `TraceletConfig(...)` | `TraceletConfig(...)` |
| Location | `GeoConfig(...)` | `GeoConfig(...)` | `TraceletGeoConfig(...)` |
| Filtering | `LocationFilter(...)` | `LocationFilter(...)` | `TraceletLocationFilter(...)` |
| Lifecycle | `AppConfig(...)` | `AppConfig(...)` | `TraceletAppConfig(...)` |
| Notification | `ForegroundServiceConfig(...)` | `ForegroundServiceConfig(...)` | `TraceletForegroundServiceConfig(...)` |
| HTTP sync | `HttpConfig(...)` | `HttpConfig(...)` | `TraceletHttpConfig(...)` |
| Logging | `LoggerConfig(...)` | `LoggerConfig(...)` | `TraceletLoggerConfig(...)` |
| Motion | `MotionConfig(...)` | `MotionConfig(...)` | `TraceletMotionConfig(...)` |
| Geofence | `GeofenceConfig(...)` | `GeofenceConfig(...)` | `TraceletGeofenceConfig(...)` |
| Persistence | `PersistenceConfig(...)` | `PersistenceConfig(...)` | `TraceletPersistenceConfig(...)` |
| Audit trail | `AuditConfig(...)` | `AuditConfig(...)` | `TraceletAuditConfig(...)` |
| Privacy zones | `PrivacyZoneConfig(...)` | `PrivacyZoneConfig(...)` | `TraceletPrivacyZoneConfig(...)` |
| Encryption | `SecurityConfig(...)` | `SecurityConfig(...)` | `TraceletSecurityConfig(...)` |
| Attestation | `AttestationConfig(...)` | `AttestationConfig(...)` | `TraceletAttestationConfig(...)` |

> **Note:** Swift config types are prefixed with `Tracelet` to avoid namespace collisions (e.g., `TraceletGeoConfig` instead of `GeoConfig`). Kotlin types live under the `com.ikolvi.tracelet.sdk.model` package and don't need prefixes.

Both native SDKs also support the raw dictionary API for backward compatibility or dynamic configuration:

```kotlin
// Kotlin — raw map (still works)
sdk.ready(mapOf("geo" to mapOf("distanceFilter" to 10.0)))
```

```swift
// Swift — raw dictionary (still works)
sdk.ready(config: ["geo": ["distanceFilter": 10.0]])
```

---

## Typed Models

Beyond configuration, the native SDKs provide typed models for geofences and privacy zones.

### Geofences

```kotlin
// Kotlin
import com.ikolvi.tracelet.sdk.model.TraceletGeofence

sdk.addGeofence(TraceletGeofence(
    identifier = "office",
    latitude = 37.4220,
    longitude = -122.0841,
    radius = 200.0,
    notifyOnEntry = true,
    notifyOnDwell = true,
    loiteringDelay = 30000,
))
```

```swift
// Swift
sdk.addGeofence(TraceletGeofence(
    identifier: "office",
    latitude: 37.4220,
    longitude: -122.0841,
    radius: 200.0,
    notifyOnEntry: true,
    notifyOnDwell: true,
    loiteringDelay: 30000
))
```

### Privacy Zones

```kotlin
// Kotlin
import com.ikolvi.tracelet.sdk.model.TraceletPrivacyZone

sdk.addPrivacyZone(TraceletPrivacyZone(
    identifier = "home",
    latitude = 37.4220,
    longitude = -122.0841,
    radius = 500.0,
    action = TraceletPrivacyZone.ACTION_EXCLUDE,
))
```

```swift
// Swift
sdk.addPrivacyZone(TraceletPrivacyZone(
    identifier: "home",
    latitude: 37.4220,
    longitude: -122.0841,
    radius: 500.0,
    action: TraceletPrivacyZone.actionExclude
))
```

Privacy zone actions:

| Action | Kotlin | Swift | Behavior |
|---|---|---|---|
| Exclude | `ACTION_EXCLUDE` (0) | `actionExclude` (0) | Drop location entirely |
| Degrade | `ACTION_DEGRADE` (1) | `actionDegrade` (1) | Snap to grid at `degradedAccuracyMeters` |
| Event only | `ACTION_EVENT_ONLY` (2) | `actionEventOnly` (2) | Dispatch but don't persist |

---

## Round-Trip Serialization

All config classes support `toMap()` and `fromMap()` for round-trip serialization:

```kotlin
// Kotlin
val config = TraceletConfig(geo = GeoConfig(distanceFilter = 50.0))
val map = config.toMap()
val restored = TraceletConfig.fromMap(map) // identical to original
```

```swift
// Swift
let config = TraceletConfig(geo: .init(distanceFilter: 50.0))
let map = config.toMap()
let restored = TraceletConfig.fromMap(map) // identical to original
```

This is useful for persisting config to disk, transmitting via network, or bridging across FFI boundaries.

---

## Objective-C Compatibility (iOS)

For Objective-C codebases, the iOS SDK provides `@objc`-compatible wrapper classes that mirror each Swift config struct:

| Swift Struct | ObjC Wrapper |
|---|---|
| `TraceletConfig` | `TraceletConfigObjC` |
| `TraceletGeoConfig` | `TraceletGeoConfigObjC` |
| `TraceletAppConfig` | `TraceletAppConfigObjC` |
| ... | ... (all 14 config groups) |

```objc
// Objective-C
#import <TraceletSDK/TraceletSDK-Swift.h>

TraceletGeoConfigObjC *geo = [[TraceletGeoConfigObjC alloc]
    initWithDesiredAccuracy:0   // HIGH
    distanceFilter:50.0
    disableElasticity:NO
    elasticityMultiplier:1.0
    stationaryRadius:25.0
    locationUpdateInterval:1000
    fastestLocationUpdateInterval:500
    speedJumpFilter:300
    periodicLocationInterval:900
    periodicDesiredAccuracy:2
    periodicUseForegroundService:NO
    locationFilter:nil];

TraceletConfigObjC *config = [[TraceletConfigObjC alloc]
    initWithGeo:geo
    /* ... remaining sub-configs ... */];

[sdk readyWithObjCConfig:config];
```

> The Swift struct API is the primary interface. ObjC wrappers are an additional compatibility layer.

---

## Capabilities

Both native SDKs include the full Tracelet engine:

- Background location tracking with motion detection
- Geofencing (circular + polygon) with unlimited proximity-based loading
- SQLite persistence with optional encryption
- HTTP auto-sync with retry, delta encoding, and batch upload
- SSL certificate pinning
- Kalman filter GPS smoothing
- Adaptive sampling (speed/activity/battery-aware)
- Battery budget engine
- Trip detection
- Dead reckoning (accelerometer + gyroscope)
- Audit trail (tamper-proof SHA chain)
- Privacy zones
- Device attestation (Play Integrity / App Attest)
- Schedule-based tracking
- Health check API
- Carbon footprint estimator
- GDPR/CCPA compliance reports

---

## Version History

| Version | Date | Notes |
|---|---|---|
| 0.1.0 | March 2026 | Initial release — full feature parity with Flutter plugin |
