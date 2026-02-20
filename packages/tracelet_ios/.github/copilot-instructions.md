# Copilot Instructions — iOS Implementation (`packages/tracelet_ios/`)

## Role of This Package
Swift-native iOS implementation of the Tracelet plugin. Implements `TraceletPlatform` using
CoreLocation, CoreMotion, BackgroundTasks, URLSession, and raw SQLite3.
**All code is original** — never reference or copy from transistorsoft SDKs (TSLocationManager.xcframework).

## Key Files
```
tracelet_ios/
├── ios/
│   ├── Classes/
│   │   ├── TraceletPlugin.swift               # FlutterPlugin entry point
│   │   ├── engine/
│   │   │   ├── LocationEngine.swift           # CLLocationManager wrapper
│   │   │   ├── MotionDetector.swift           # CMMotionActivityManager + accelerometer
│   │   │   ├── GeofenceManager.swift          # CLCircularRegion + CLMonitor (iOS 17+)
│   │   │   └── SensorManager.swift            # CMMotionManager raw sensor access
│   │   ├── db/
│   │   │   ├── TraceletDatabase.swift         # SQLite3 database manager
│   │   │   ├── LocationStore.swift            # Location CRUD operations
│   │   │   ├── GeofenceStore.swift            # Geofence CRUD operations
│   │   │   └── LogStore.swift                 # Log CRUD operations
│   │   ├── http/
│   │   │   └── HttpSyncManager.swift          # URLSession background upload
│   │   ├── headless/
│   │   │   └── HeadlessRunner.swift           # Background FlutterEngine runner
│   │   ├── scheduling/
│   │   │   └── ScheduleManager.swift
│   │   ├── logging/
│   │   │   └── TraceletLogger.swift
│   │   ├── sound/
│   │   │   └── SoundManager.swift             # AudioServices sounds
│   │   ├── permission/
│   │   │   └── PermissionManager.swift
│   │   ├── config/
│   │   │   ├── ConfigManager.swift
│   │   │   └── StateManager.swift
│   │   ├── streams/
│   │   │   ├── StreamHandler.swift            # Base FlutterStreamHandler
│   │   │   ├── LocationStreamHandler.swift
│   │   │   ├── MotionChangeStreamHandler.swift
│   │   │   └── ...                            # 12 more stream handlers
│   │   ├── util/
│   │   │   ├── BatteryUtils.swift
│   │   │   ├── DeviceInfo.swift
│   │   │   └── OdometerCalculator.swift
│   │   └── generated/
│   │       └── TraceletApi.g.swift            # Pigeon-generated (DO NOT EDIT)
│   ├── Resources/                              # Debug sound files (.caf/.aiff)
│   ├── tracelet_ios.podspec
│   └── Package.swift                          # SPM support (Flutter 3.24+)
├── lib/
│   └── tracelet_ios.dart                      # Dart registration + TraceletIOS class
├── test/
└── pubspec.yaml
```

## Coding Rules for This Package

### Swift Style
- **Swift version**: 5.9+ (match Xcode 15+).
- Use `struct` for value types (configs, events, location data). Use `class` only when reference semantics / inheritance needed (managers, delegates).
- Use `let` over `var` everywhere possible.
- Use Swift concurrency (`async/await`, `Task`, `@MainActor`) for async operations. Avoid raw GCD unless needed for performance (SQLite serial queue).
- Use `Result<Success, Failure>` for operations that can fail.
- Prefer `guard let` over `if let` for early exits.
- Use `[weak self]` in ALL closures that capture `self` to prevent retain cycles.
- Extension-based organization: group `CLLocationManagerDelegate` methods in a `extension LocationEngine: CLLocationManagerDelegate { }`.

### Architecture Patterns
- **Singleton managers**: `LocationEngine.shared`, `GeofenceManager.shared`, etc. Created lazily, torn down on plugin deregistration.
- **Delegate pattern**: `CLLocationManagerDelegate`, `FlutterPlugin`, custom delegate protocols between managers.
- **EventChannel dispatch**: `FlutterEventSink?` held per stream handler. Always dispatch on main thread:
  ```swift
  DispatchQueue.main.async { [weak self] in
      self?.eventSink?(data)
  }
  ```
- **Thread model**:
  - Platform channel calls arrive on **Main thread**. Reply on Main thread.
  - `CLLocationManagerDelegate` calls arrive on **the thread that created the manager** — create on Main.
  - `CMMotionActivityManager` callbacks can arrive on arbitrary queue — dispatch results to Main.
  - SQLite operations → dedicated serial `DispatchQueue` (never Main).
  - HTTP operations → `URLSession` manages its own threads.

### CLLocationManager (Critical)
```swift
let manager = CLLocationManager()
manager.delegate = self
manager.desiredAccuracy = kCLLocationAccuracyBest
manager.distanceFilter = config.distanceFilter
manager.allowsBackgroundLocationUpdates = true    // REQUIRED for background
manager.showsBackgroundLocationIndicator = true   // Blue pill indicator
manager.pausesLocationUpdatesAutomatically = false // We manage pausing ourselves
manager.activityType = .other                      // Or from config
```

- **Always** set `allowsBackgroundLocationUpdates = true` — without this, no background updates.
- **Always** request `.authorizedAlways` for production background tracking.
- iOS 17+: Create `CLBackgroundActivitySession()` to keep app alive in background.
- iOS 17+: Use `CLServiceSession(authorization: .always)` for maintaining auth state.
- Fallback: `startMonitoringSignificantLocationChanges()` to relaunch after termination.

### Geofencing — 20-Region Limit Workaround
iOS hard-limits apps to **20 monitored `CLCircularRegion`s**. Our workaround:
```swift
// On each location update:
// 1. Sort ALL registered geofences by distance from current location
// 2. Take the nearest 20
// 3. Diff with currently monitored regions
// 4. Stop monitoring regions no longer in top-20
// 5. Start monitoring new top-20 regions
func updateMonitoredGeofences(currentLocation: CLLocation) {
    let sorted = allGeofences.sorted { 
        $0.distance(from: currentLocation) < $1.distance(from: currentLocation) 
    }
    let nearest20 = Array(sorted.prefix(20))
    // ... diff and swap
}
```
- Persist ALL geofences in SQLite, monitor only nearest 20 at runtime.
- Fire `onGeofencesChange` when swapping monitored regions.
- iOS 17+: Use `CLMonitor` with `CircularGeographicCondition` (may have different limits).

### SQLite (Raw C API)
- Use SQLite3 C API via Swift bridging (`import SQLite3`).
- NO third-party dependencies (no GRDB, no FMDB) — keep deps at zero.
- Create database file at: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!/tracelet/tracelet.db`
- **Always** use `sqlite3_prepare_v2` + bind parameters. NEVER string-interpolate SQL.
- Use a dedicated serial `DispatchQueue` for ALL database operations:
  ```swift
  private let dbQueue = DispatchQueue(label: "com.tracelet.db", qos: .utility)
  ```
- Run migrations via a `schema_version` table. Check version on open, apply migrations sequentially.

### Background Execution Strategy
Priority order of background execution mechanisms:
1. **`CLBackgroundActivitySession`** (iOS 17+): Best — keeps app running with location updates.
2. **`allowsBackgroundLocationUpdates + UIBackgroundModes:location`**: Standard — works iOS 9+.
3. **`startMonitoringSignificantLocationChanges()`**: Relaunch after termination (coarse, ~500m).
4. **`BGTaskScheduler`**: For periodic HTTP sync, NOT for location tracking.
5. **`UIApplication.beginBackgroundTask()`**: For short tasks (~30s) — wrapping sync operations.

Do NOT use:
- Silent audio playback (App Store rejection).
- VOIP background mode (misuse).
- Continuous background fetch with short intervals.

### HTTP Background Upload
```swift
let config = URLSessionConfiguration.background(withIdentifier: "com.tracelet.sync")
config.isDiscretionary = false          // Don't defer — upload when ready
config.sessionSendsLaunchEvents = true  // Relaunch app on completion
let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
```
- Background `URLSession` survives app suspension and termination.
- Implement `URLSessionDelegate.urlSessionDidFinishEvents(forBackgroundURLSession:)` to signal completion.
- Store upload task mapping in UserDefaults for resumption.

### Info.plist Documentation
This package does NOT modify the consumer's Info.plist. Document required entries in `INSTALL-IOS.md`:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
    <string>processing</string>
</array>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>...</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>...</string>
<key>NSMotionUsageDescription</key>
<string>...</string>
```

### Permission Handling
```swift
// Sequential authorization flow:
// 1. requestWhenInUseAuthorization()
// 2. requestAlwaysAuthorization() — ONLY after whenInUse is granted
//    (iOS 13+ "provisional always" flow)
// 3. Motion permission is requested automatically on first CMMotionActivityManager use
```
- Return standardized status codes matching Android: 0=DENIED, 1=WHEN_IN_USE, 2=ALWAYS, 3=DENIED_FOREVER.
- Use `CLLocationManager.authorizationStatus` (class property, works iOS 14+).
- iOS 14+: Check `manager.accuracyAuthorization` for `.fullAccuracy` vs `.reducedAccuracy`.
- `requestTemporaryFullAccuracyAuthorization(withPurposeKey:)` — key must exist in `NSLocationTemporaryUsageDescriptionDictionary`.

### Error Handling
- Every Pigeon HostApi method wraps logic in `do/catch` → return `FlutterError` on failure.
- Common error codes (match Android): `LOCATION_UNAVAILABLE`, `PERMISSION_DENIED`, `TIMEOUT`, `DB_ERROR`, `HTTP_ERROR`, `REGION_MONITORING_FAILURE`.
- Log all errors via `TraceletLogger` before propagating.
- Handle `CLError.denied`, `CLError.locationUnknown`, `CLError.network` explicitly.

### Podspec & Package.swift
- `ios.deployment_target = '14.0'`
- Frameworks: `CoreLocation`, `CoreMotion`, `UIKit`, `BackgroundTasks`, `AVFoundation` (sounds), `MessageUI` (email log)
- No third-party CocoaPods dependencies.
- Support both CocoaPods (podspec) and Swift Package Manager (Package.swift) for Flutter 3.24+.

### Testing
- XCTest for all manager classes.
- Mock `CLLocationManager` via protocol extraction:
  ```swift
  protocol LocationManaging {
      var delegate: CLLocationManagerDelegate? { get set }
      func requestAlwaysAuthorization()
      func startUpdatingLocation()
      // ...
  }
  extension CLLocationManager: LocationManaging { }
  ```
- Test `GeofenceManager` nearest-20 rotation with synthetic geofence datasets.
- Test `MotionDetector` state machine transitions.
- In-memory SQLite (`:memory:`) for database tests.
- Test `HttpSyncManager` retry logic with mock `URLProtocol`.
