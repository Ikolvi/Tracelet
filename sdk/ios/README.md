# Tracelet iOS SDK

[![CocoaPods](https://img.shields.io/cocoapods/v/TraceletSDK.svg)](https://cocoapods.org/pods/TraceletSDK)
[![SPM](https://img.shields.io/badge/SPM-compatible-green.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> **Production-grade background geolocation for iOS — no Flutter required.**

Battery-conscious motion-detection intelligence, geofencing, SQLite persistence, HTTP sync, and headless execution for pure Swift/Objective-C apps.

## Installation

### CocoaPods

Add to your `Podfile`:

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

### Swift Package Manager — Xcode UI

1. **File → Add Package Dependencies...**
2. Enter: `https://github.com/Ikolvi/Tracelet.git`
3. Set version rule: **Up to Next Major** from `0.1.0`
4. Add the `TraceletSDK` library to your target

### Swift Package Manager — Package.swift

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

## Quick Start

```swift
import TraceletSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate, TraceletDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let sdk = TraceletSdk.shared

        // 1. Listen to events
        sdk.delegate = self

        // 2. Configure & ready
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
                startOnBoot: true
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

## Configuration

The SDK uses the same structured config pattern as the Flutter plugin. All settings have sensible defaults — only override what you need.

### TraceletConfig

Top-level compound configuration. Organizes settings into logical groups:

```swift
TraceletConfig(
    geo: .init(...),          // Location accuracy, sampling, filtering
    app: .init(...),          // Lifecycle, scheduling
    http: .init(...),         // Server sync settings
    logger: .init(...),       // Logging and debug sounds
    motion: .init(...),       // Motion detection sensitivity
    geofence: .init(...),     // Geofence proximity and triggers
    persistence: .init(...),  // Database retention
    audit: .init(...),        // [Enterprise] Tamper-proof audit trail
    privacyZone: .init(...),  // [Enterprise] Privacy zones
    security: .init(...),     // [Enterprise] Database encryption
    attestation: .init(...)   // [Enterprise] Device attestation
)
```

### TraceletGeoConfig

```swift
TraceletGeoConfig(
    desiredAccuracy: .high,                // .high, .medium, .low
    distanceFilter: 10.0,                  // meters between updates
    stationaryRadius: 25.0,               // meters to detect movement
    locationTimeout: 60,                   // seconds for fix timeout
    activityType: .automotiveNavigation,   // CLActivityType mapping
    disableElasticity: false,             // speed-based distance scaling
    elasticityMultiplier: 1.0,            // elasticity scale factor
    stopAfterElapsedMinutes: -1,          // auto-stop (-1 = disabled)
    enableAdaptiveMode: false,            // multi-factor distance filter
    enableSparseUpdates: false,           // drop duplicate locations
    sparseDistanceThreshold: 50.0,        // meters for deduplication
    enableDeadReckoning: false,           // IMU fallback on GPS loss
    batteryBudgetPerHour: 0.0,            // auto-tune to battery budget
    filter: .init(                         // GPS denoising
        trackingAccuracyThreshold: 100,   // min accuracy to record
        maxImpliedSpeed: 80,              // reject GPS spikes (m/s)
        useKalmanFilter: true,            // Extended Kalman smoothing
        rejectMockLocations: false,       // drop spoofed locations
        mockDetectionLevel: .disabled
    ),

    // Periodic mode
    periodicLocationInterval: 900,        // seconds (15 min default)
    periodicDesiredAccuracy: .medium,

    // iOS-specific
    useSignificantChangesOnly: false,     // WiFi/cell transitions only
    showsBackgroundLocationIndicator: false, // blue status bar arrow
    pausesLocationUpdatesAutomatically: false,
    locationAuthorizationRequest: .always
)
```

### TraceletAppConfig

```swift
TraceletAppConfig(
    stopOnTerminate: false,               // keep tracking after app killed
    startOnBoot: true,                    // restart on device boot
    heartbeatInterval: 60,               // seconds (-1 to disable)
    schedule: ["1-7 09:00-17:00"],        // Mon-Sun 9am-5pm
    preventSuspend: true,                 // silent audio keep-alive
    remoteConfigUrl: "https://api.example.com/config"
)
```

### TraceletHttpConfig

```swift
TraceletHttpConfig(
    url: "https://api.example.com/locations",
    method: .post,
    headers: ["Authorization": "Bearer token"],
    batchSync: true,
    maxBatchSize: 100,
    autoSync: true,
    httpTimeout: 60000,
    disableAutoSyncOnCellular: false,     // Wi-Fi only sync
    maxRetries: 10,
    retryBackoffBase: 1000,              // exponential backoff
    retryBackoffCap: 300000,
    enableDeltaCompression: true,         // 60-80% payload reduction
    sslPinningFingerprints: [             // certificate pinning
        "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    ]
)
```

### TraceletMotionConfig

```swift
TraceletMotionConfig(
    stopTimeout: 5,                       // minutes to declare stationary
    disableMotionActivityUpdates: false,  // accelerometer-only mode
    activityRecognitionInterval: 10000,   // ms between samples
    minimumActivityRecognitionConfidence: 75,
    stopOnStationary: false,              // auto-stop on stationary
    shakeThreshold: 2.5,                  // m/s² for motion trigger
    stillThreshold: 0.4,                  // m/s² for stillness
    stillSampleCount: 25                  // samples for stop detection
)
```

### TraceletGeofenceConfig

```swift
TraceletGeofenceConfig(
    geofenceProximityRadius: 1000,        // activation radius (meters)
    geofenceInitialTriggerEntry: true,    // fire ENTER if already inside
    geofenceModeKnockOut: false           // remove after EXIT
)
```

### TraceletPersistenceConfig

```swift
TraceletPersistenceConfig(
    persistMode: .all,                    // .all, .location, .geofence, .none
    maxDaysToPersist: 14,
    maxRecordsToPersist: 5000
)
```

### TraceletLoggerConfig

```swift
TraceletLoggerConfig(
    logLevel: .verbose,                   // .verbose, .debug, .info, .warn, .error
    logMaxDays: 3,
    debug: true                           // audible debug sounds
)
```

### Enterprise Features

```swift
// Tamper-proof location audit trail
TraceletAuditConfig(enabled: true, hashAlgorithm: .sha256)

// Geographic privacy zones
TraceletPrivacyZoneConfig(enabled: true)

// At-rest SQLite encryption (NSFileProtectionComplete)
TraceletSecurityConfig(encryptDatabase: true)

// Device attestation (App Attest)
TraceletAttestationConfig(enabled: true, refreshInterval: 3600)
```

## Event Delegate

Implement `TraceletDelegate` and override only the callbacks you need:

```swift
extension MyViewController: TraceletDelegate {

    func tracelet(_ sdk: TraceletSdk, didUpdateLocation location: [String: Any]) {
        guard let coords = location["coords"] as? [String: Any],
              let lat = coords["latitude"] as? Double,
              let lng = coords["longitude"] as? Double else { return }
        print("Location: \(lat), \(lng)")
    }

    func tracelet(_ sdk: TraceletSdk, didChangeMotion data: [String: Any]) {
        let isMoving = data["isMoving"] as? Bool ?? false
        print("Moving: \(isMoving)")
    }

    func tracelet(_ sdk: TraceletSdk, didTriggerGeofence data: [String: Any]) {
        let identifier = data["identifier"] as? String ?? ""
        let action = data["action"] as? String ?? ""  // ENTER, EXIT, DWELL
        print("Geofence \(action): \(identifier)")
    }

    func tracelet(_ sdk: TraceletSdk, didSyncHttp data: [String: Any]) {
        let success = data["success"] as? Bool ?? false
        let status = data["status"] as? Int ?? 0
        print("HTTP \(success ? "OK" : "FAIL"): \(status)")
    }

    func tracelet(_ sdk: TraceletSdk, didChangeActivity data: [String: Any]) {
        let activity = data["activity"] as? String ?? ""
        print("Activity: \(activity)")
    }

    func tracelet(_ sdk: TraceletSdk, didEndTrip data: [String: Any]) {
        let distance = data["distance"] as? Double ?? 0
        print("Trip ended: \(distance)m")
    }

    func tracelet(_ sdk: TraceletSdk, didAdjustBudget data: [String: Any]) {
        let newDF = data["distanceFilter"] as? Double ?? 0
        print("Budget adjusted: distanceFilter=\(newDF)")
    }
}
```

## Info.plist

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

### Xcode Capabilities

Enable these in your target's **Signing & Capabilities**:

- **Background Modes** → Location updates, Background fetch, Background processing
- **Push Notifications** (if using remote triggers)

## Permissions

```swift
// Check permission status
let status = sdk.getPermissionStatus()
// 0 = notDetermined, 1 = denied, 2 = whenInUse, 3 = always, 4 = deniedForever

// Request permission (escalation flow)
let result = sdk.requestPermission()
if result == 2 {
    // Got whenInUse — show rationale dialog, then upgrade:
    let upgraded = sdk.requestPermission()  // → always
}

// iOS 14+ temporary full accuracy
sdk.requestTemporaryFullAccuracy(purposeKey: "TrackRoute")

// Open settings
sdk.openAppSettings()
sdk.openLocationSettings()
```

## Geofencing

### Typed API (Recommended)

```swift
// Add circular geofence
sdk.addGeofence(TraceletGeofence(
    identifier: "office",
    latitude: 37.4220,
    longitude: -122.0841,
    radius: 200.0,
    notifyOnEntry: true,
    notifyOnExit: true,
    notifyOnDwell: true,
    loiteringDelay: 30000
))

// Add polygon geofence
sdk.addGeofence(TraceletGeofence(
    identifier: "campus",
    latitude: 0,
    longitude: 0,
    radius: 0,
    vertices: [
        [37.422, -122.084],
        [37.423, -122.084],
        [37.423, -122.083],
        [37.422, -122.083],
    ]
))

// Add multiple geofences at once
sdk.addGeofences([geofence1, geofence2, geofence3])

// Remove
sdk.removeGeofence("office")
sdk.removeGeofences()
```

### Dictionary API

```swift
// Add circular geofence
sdk.addGeofence([
    "identifier": "office",
    "latitude": 37.4220,
    "longitude": -122.0841,
    "radius": 200.0,
    "notifyOnEntry": true,
    "notifyOnExit": true,
    "notifyOnDwell": true,
    "loiteringDelay": 30000,
])
```

### Privacy Zones

```swift
// Exclude locations inside the zone entirely
sdk.addPrivacyZone(TraceletPrivacyZone(
    identifier: "home",
    latitude: 37.4220,
    longitude: -122.0841,
    radius: 500.0,
    action: TraceletPrivacyZone.actionExclude
))

// Degrade precision inside the zone
sdk.addPrivacyZone(TraceletPrivacyZone(
    identifier: "office",
    latitude: 37.7749,
    longitude: -122.4194,
    radius: 300.0,
    action: TraceletPrivacyZone.actionDegrade,
    degradedAccuracyMeters: 500.0
))

// Event-only: dispatch but don't persist
sdk.addPrivacyZone(TraceletPrivacyZone(
    identifier: "hospital",
    latitude: 37.7631,
    longitude: -122.4576,
    radius: 200.0,
    action: TraceletPrivacyZone.actionEventOnly
))

// Add multiple privacy zones at once
sdk.addPrivacyZones([zone1, zone2, zone3])
```

## HTTP Sync

```swift
// Manual sync
sdk.sync()

// Dynamic headers (e.g., rotating auth tokens)
sdk.setDynamicHeaders(["Authorization": "Bearer new-token"])
```

## Background Behavior

### Prevent Suspend

For maximum background runtime, enable the silent audio keep-alive:

```swift
TraceletConfig(
    app: .init(preventSuspend: true)
)
```

### iOS 17+ / 18+ Session APIs

The SDK automatically uses `CLBackgroundActivitySession` (iOS 17+) and `CLServiceSession` (iOS 18+) for extended background runtime when available.

### Background Task Protection

All critical operations (persist, HTTP sync, headless engine boot) are wrapped in `beginBackgroundTask` for safe background execution.

## Tracking Modes

```swift
sdk.start()           // Continuous GPS tracking
sdk.startGeofences()  // Geofence-only mode
sdk.startPeriodic()   // One-shot periodic fixes
sdk.stop()            // Stop all tracking
```

## Lifecycle Methods

```swift
sdk.getState()               // Current tracking state
sdk.setConfig(configMap)     // Update config at runtime
sdk.reset()                  // Reset to defaults
sdk.getCurrentPosition()     // One-shot location request
sdk.getLastKnownLocation()   // Cached location (no battery cost)
sdk.getOdometer()            // Total distance traveled
sdk.getHealth()              // Diagnostic snapshot
sdk.getLocations()           // Read persisted locations
sdk.getCount()               // Count persisted locations
sdk.destroyLocations()       // Clear database
sdk.sync()                   // Manual HTTP sync
sdk.getLog()                 // Read log entries
sdk.emailLog("dev@co.com")   // Email logs for debugging
```

## Objective-C Compatibility

For Objective-C codebases, use the `ObjC` wrapper classes. These mirror the Swift structs but use `NSObject`-based classes with Int-based enum values.

### Configuration

```objc
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
    periodicDesiredAccuracy:2   // MEDIUM
    periodicUseForegroundService:NO
    locationFilter:nil];

TraceletConfigObjC *config = [[TraceletConfigObjC alloc]
    initWithGeo:geo
    app:[[TraceletAppConfigObjC alloc] init]
    foregroundService:[[TraceletForegroundServiceConfigObjC alloc] init]
    http:[[TraceletHttpConfigObjC alloc] init]
    logger:[[TraceletLoggerConfigObjC alloc] init]
    motion:[[TraceletMotionConfigObjC alloc] init]
    geofence:[[TraceletGeofenceConfigObjC alloc] init]
    persistence:[[TraceletPersistenceConfigObjC alloc] init]
    audit:[[TraceletAuditConfigObjC alloc] init]
    privacyZone:[[TraceletPrivacyZoneConfigObjC alloc] init]
    security:[[TraceletSecurityConfigObjC alloc] init]
    attestation:[[TraceletAttestationConfigObjC alloc] init]];

TraceletSdk *sdk = [[TraceletSdk alloc] init];
[sdk readyWithObjCConfig:config];
```

### Runtime Updates

```objc
TraceletConfigObjC *updatedConfig = [[TraceletConfigObjC alloc]
    initWithGeo:[[TraceletGeoConfigObjC alloc] initWithDesiredAccuracy:2
        distanceFilter:100.0
        disableElasticity:NO
        elasticityMultiplier:1.0
        stationaryRadius:25.0
        locationUpdateInterval:1000
        fastestLocationUpdateInterval:500
        speedJumpFilter:300
        periodicLocationInterval:0
        periodicDesiredAccuracy:2
        periodicUseForegroundService:NO
        locationFilter:nil]
    app:[[TraceletAppConfigObjC alloc] init]
    foregroundService:[[TraceletForegroundServiceConfigObjC alloc] init]
    http:[[TraceletHttpConfigObjC alloc] init]
    logger:[[TraceletLoggerConfigObjC alloc] init]
    motion:[[TraceletMotionConfigObjC alloc] init]
    geofence:[[TraceletGeofenceConfigObjC alloc] init]
    persistence:[[TraceletPersistenceConfigObjC alloc] init]
    audit:[[TraceletAuditConfigObjC alloc] init]
    privacyZone:[[TraceletPrivacyZoneConfigObjC alloc] init]
    security:[[TraceletSecurityConfigObjC alloc] init]
    attestation:[[TraceletAttestationConfigObjC alloc] init]];

[sdk setConfigWithObjC:updatedConfig];
```

> **Note**: The Swift struct API is the primary interface. ObjC wrappers are provided as a compatibility layer — use Swift directly when possible for a better developer experience.

## Serialization

All config types support round-trip serialization via `toMap()` and `fromMap()`:

### Swift

```swift
// Serialize to dictionary
let config = TraceletConfig(
    geo: TraceletGeoConfig(desiredAccuracy: .high, distanceFilter: 50.0),
    logger: TraceletLoggerConfig(logLevel: .debug, debug: true)
)
let map: [String: Any] = config.toMap()

// Deserialize from dictionary
let restored = TraceletConfig.fromMap(map)

// Sub-configs also support fromMap()
let geoMap: [String: Any] = ["desiredAccuracy": 0, "distanceFilter": 100.0]
let geo = TraceletGeoConfig.fromMap(geoMap)  // Missing keys use defaults
```

### Objective-C

```objc
// Serialize
NSDictionary *map = [config toMap];

// Deserialize
TraceletConfigObjC *restored = [TraceletConfigObjC fromMap:map];
TraceletGeoConfigObjC *geo = [TraceletGeoConfigObjC fromMap:geoMap];
```

This is useful for:
- Persisting config to UserDefaults or a database
- Loading config from a remote JSON endpoint
- Passing config across process boundaries

## Capabilities

- Background location tracking with motion detection
- Geofencing (circular + polygon) with unlimited proximity-based loading
- SQLite persistence with optional encryption (NSFileProtectionComplete)
- HTTP auto-sync with retry, exponential backoff, delta encoding
- SSL certificate pinning
- Kalman filter GPS smoothing
- Adaptive sampling (speed/activity/battery-aware)
- Battery budget engine
- Trip detection
- Dead reckoning (accelerometer + gyroscope + compass)
- Audit trail (tamper-proof SHA chain)
- Privacy zones
- Device attestation (App Attest)
- Schedule-based tracking
- Health check API
- Prevent suspend (silent audio keep-alive)
- iOS 17+ / 18+ session APIs
- Background task protection
- Carbon footprint estimator
- GDPR/CCPA compliance reports

## Published Packages

| Manager | Package | Link |
|---|---|---|
| CocoaPods | `TraceletSDK` | [CocoaPods](https://cocoapods.org/pods/TraceletSDK) |
| SPM | `TraceletSDK` | [GitHub](https://github.com/Ikolvi/Tracelet.git) |

## Version History

| Version | Date | Notes |
|---|---|---|
| 0.1.0 | March 2026 | Initial release — full feature parity with Flutter plugin |

## License

Apache 2.0 — see [LICENSE](../../LICENSE) for details.

All native code is written from scratch. Only Apple frameworks used (CoreLocation, CoreMotion, UIKit, BackgroundTasks, SQLite3). No third-party CocoaPods dependencies.
