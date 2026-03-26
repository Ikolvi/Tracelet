# Native SDK — Installation & Usage

> **Use Tracelet without Flutter.** The native SDKs are framework-agnostic — usable from pure Kotlin/Swift apps, React Native, Capacitor, or any other framework.

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
import com.ikolvi.tracelet.core.TraceletSdk
import com.ikolvi.tracelet.core.TraceletEventSender

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()

        val sdk = TraceletSdk.getInstance(this)

        // Set up event listener
        sdk.setEventSender(object : TraceletEventSender {
            override fun sendLocation(location: Map<String, Any?>) {
                // Handle location update
            }
            override fun sendMotionChange(isMoving: Boolean, location: Map<String, Any?>) {
                // Handle motion state change
            }
            override fun hasListener(): Boolean = true
            // ... implement other event methods
        })

        // Configure and start
        sdk.ready(mapOf(
            "distanceFilter" to 50.0,
            "desiredAccuracy" to -1,        // NAVIGATION
            "stopOnTerminate" to false,
            "startOnBoot" to true,
            "enableHeadless" to false,
            "foregroundService" to true,
            "notification" to mapOf(
                "title" to "Tracking",
                "text" to "Location active"
            )
        )) { state ->
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

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        let sdk = TraceletSdk.shared

        // Set up event delegate
        sdk.setEventSender(MyEventDelegate())

        // Configure and start
        sdk.ready([
            "distanceFilter": 50.0,
            "desiredAccuracy": -1,
            "stopOnTerminate": false,
            "startOnBoot": true,
            "preventSuspend": true
        ]) { state in
            if state["enabled"] as? Bool == false {
                sdk.start()
            }
        }

        return true
    }
}

class MyEventDelegate: NSObject, TraceletEventSending {
    func sendLocation(_ location: [String: Any]) {
        // Handle location update
    }
    func sendMotionChange(_ isMoving: Bool, location: [String: Any]) {
        // Handle motion state change
    }
    // ... implement other protocol methods
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

## Capabilities

Both native SDKs include the full Tracelet engine:

- Background location tracking with motion detection
- Geofencing (circular + polygon)
- SQLite persistence with optional encryption
- HTTP auto-sync with retry, delta encoding, and batch upload
- Kalman filter GPS smoothing
- Adaptive sampling (speed/activity/battery-aware)
- Battery budget engine
- Trip detection
- Dead reckoning (accelerometer + gyroscope)
- Audit trail
- Privacy zones
- Device attestation (Play Integrity / App Attest)
- Schedule-based tracking
- Health check API

---

## Version History

| Version | Date | Notes |
|---|---|---|
| 0.1.0 | March 2026 | Initial release — full feature parity with Flutter plugin |
