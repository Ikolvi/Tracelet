# Web Platform Support

Tracelet includes experimental web support via the `tracelet_web` package. It uses standard browser APIs (Geolocation, Permissions, `fetch`, `navigator.onLine`) to provide a **foreground-only** location experience in the browser.

> **Key limitation:** The Web Geolocation API does **not** function in background tabs, minimized windows, or Service Workers. All tracking is foreground-only.

## Setup

No extra configuration is needed. Adding `tracelet` to your `pubspec.yaml` automatically pulls in `tracelet_web` on web builds. The same Dart code you use for Android/iOS works on web — unsupported features return sensible defaults or no-ops.

```yaml
dependencies:
  tracelet: ^0.4.0
```

Make sure your app can run on web:

```bash
flutter create --platforms web .   # if not already enabled
flutter run -d chrome
```

## API Compatibility Matrix

### Fully Supported

These features work identically to Android/iOS:

| Feature | API | Notes |
|---|---|---|
| **Get current position** | `getCurrentPosition()` | Browser Geolocation API. Auto-falls back from high to low accuracy on timeout. |
| **Continuous tracking** | `start()` / `stop()` | Uses `watchPosition` under the hood. |
| **Motion change events** | `onMotionChange` | Emulated via distance threshold (stationary radius). |
| **Location events** | `onLocation` | Fires for every recorded fix that passes the distance filter. |
| **Distance filter** | `GeoConfig.distanceFilter` | Applied in Dart; skips fixes below threshold. |
| **Odometer** | `getOdometer()` / `setOdometer()` | Haversine-computed cumulative distance. |
| **Pace change** | `changePace()` | Manually toggle moving/stationary state. |
| **Geofencing** | `addGeofence()` / `removeGeofence()` / `onGeofence` | Emulated: distance-based enter/exit/dwell detection computed on each location fix. |
| **Geofence CRUD** | `getGeofences()` / `geofenceExists()` / `removeGeofences()` | In-memory storage. |
| **Geofences change** | `onGeofencesChange` | Fires when active/inactive geofence sets change. |
| **Heartbeat** | `onHeartbeat` | Timer-based, fires at configured `heartbeatInterval`. |
| **HTTP sync** | `sync()` / `onHttp` | Uses browser `fetch()` API. Batch mode, headers, authorization event on 401/403. |
| **Persistence** | `getLocations()` / `getCount()` / `destroyLocations()` / `insertLocation()` | In-memory storage (not SQLite). Lost on page refresh. |
| **Logging** | `log()` / `getLog()` / `destroyLog()` | In-memory log buffer. |
| **Connectivity** | `onConnectivityChange` | Uses `online`/`offline` browser events. |
| **Enabled change** | `onEnabledChange` | Fires when `start()`/`stop()` is called. |
| **Permission check** | `getPermissionStatus()` | Uses `navigator.permissions.query()`. |
| **Permission request** | `requestPermission()` | Triggers implicit browser prompt via `getCurrentPosition()`. |
| **Provider state** | `getProviderState()` | Reports geolocation availability and online status. |
| **Device info** | `getDeviceInfo()` | Returns `navigator.userAgent`, platform, language. |
| **Sensors** | `getSensors()` | Reports availability of geolocation, notifications, online status. |
| **Watch position** | `watchPosition()` / `stopWatchPosition()` | Real-time position stream. |
| **State management** | `ready()` / `getState()` / `setConfig()` / `reset()` | Full lifecycle management. |
| **Geofence-only mode** | `startGeofences()` | Starts location tracking to power emulated geofence checks. |
| **Configuration** | All `GeoConfig`, `MotionConfig`, `HttpConfig`, `PersistenceConfig`, `LoggerConfig` fields | Applied to web engines. |

### Partially Supported

These features work but with limitations compared to native platforms:

| Feature | API | Web Behavior |
|---|---|---|
| **Notification permission** | `getNotificationPermissionStatus()` / `requestNotificationPermission()` | Uses `Notification.permission` / `Notification.requestPermission()`. Only relevant if your web app uses browser notifications. |
| **Scheduling** | `startSchedule()` / `stopSchedule()` | Foreground-only timers. Schedule stops when the tab is closed. |
| **Stationarity detection** | `MotionConfig.stopTimeout` | Timer-based: if no movement exceeds `stationaryRadius` for `stopTimeout` minutes, device is considered stationary. No accelerometer/activity recognition. |
| **Activity change** | `onActivityChange` | Always reports `unknown` activity with `medium` confidence. Browser has no Activity Recognition API. |
| **Best-of-N samples** | `getCurrentPosition(samples: N)` | The `samples` parameter is currently **ignored**. Only one fix is taken. On desktop browsers, multiple samples typically return the same network-based result anyway. |
| **Location accuracy** | `GeoConfig.desiredAccuracy` | Mapped to `enableHighAccuracy` boolean. Desktop browsers usually only have network-based location (~100m–1km accuracy). Mobile browsers with GPS can provide high accuracy. |
| **Authorization event** | `onAuthorization` | Fires on HTTP 401/403 responses during `sync()`. No OAuth flow. |

### Not Supported (Stubs / No-ops)

These features are **not available** on web. They return safe default values and never throw errors:

| Feature | API | Returns | Why |
|---|---|---|---|
| **Background tracking** | — | — | Browser kills Geolocation in background tabs. |
| **Headless execution** | `registerHeadlessTask()` | `false` | No background Dart isolates on web. |
| **Start on boot** | `AppConfig.startOnBoot` | Ignored | No concept of device boot on web. |
| **Stop on terminate** | `AppConfig.stopOnTerminate` | Ignored | Tab close = tracking stops unconditionally. |
| **Foreground service** | `ForegroundServiceConfig` | Ignored | No persistent notifications in browsers. |
| **Power save mode** | `isPowerSaveMode()` | `false` | Browser does not expose battery saver state. |
| **Battery optimization** | `isIgnoringBatteryOptimizations()` | `true` | Not applicable to web. |
| **System settings** | `requestSettings()` / `showSettings()` | `false` | Cannot open OS settings from browser. |
| **App settings** | `openAppSettings()` / `openLocationSettings()` | `false` | Cannot open OS settings from browser. |
| **Background task** | `startBackgroundTask()` | `0` | No background task API. |
| **Notification actions** | `onNotificationAction` | Never fires | No foreground service notifications. |
| **Power save change** | `onPowerSaveChange` | Never fires | No API to detect battery saver. |
| **Email log** | `emailLog()` | `false` | Cannot invoke mail client from browser reliably. |
| **Play sound** | `playSound()` | `false` | Could use `AudioContext` but not implemented. |
| **Prevent suspend** | `AppConfig.preventSuspend` | Ignored | iOS-only silent audio keep-alive. |
| **Alarm manager** | `AppConfig.scheduleUseAlarmManager` | Ignored | Android-only exact alarms. |
| **Motion permission** | `getMotionPermissionStatus()` / `requestMotionPermission()` | `3` (always granted) | No separate motion permission on web. |
| **Temporary full accuracy** | `requestTemporaryFullAccuracy()` | `0` (full) | iOS 14+ feature; browser always provides full accuracy. |
| **Elasticity** | `GeoConfig.disableElasticity` / `elasticityMultiplier` | ✅ Works | Runs in shared Dart `LocationProcessor`. |
| **Location filter** | `LocationFilter` | ✅ Works | Runs in shared Dart `LocationProcessor` — accuracy, speed, and distance filtering. |
| **Auto-stop** | `GeoConfig.stopAfterElapsedMinutes` | Ignored | Not implemented; trivial to add as a Dart timer if needed. |
| **Geofence high-accuracy mode** | `GeoConfig.geofenceModeHighAccuracy` | Ignored | Android-only; web already runs GPS for geofence checks. |
| **Persist mode** | `PersistenceConfig.persistMode` | Ignored | All locations are stored in memory. |
| **Mock detection** | `LocationFilter.rejectMockLocations` / `mockDetectionLevel` | `Location.isMock` always `false` | Browser Geolocation API has no mock/spoof detection. See [MOCK-DETECTION.md](MOCK-DETECTION.md). |

## Data Persistence

Web uses **in-memory storage** for locations and logs. Data is lost when the page is refreshed or the tab is closed. This is intentional — browser `localStorage` has a 5–10 MB limit and is synchronous, while `IndexedDB` would add significant complexity.

If you need persistent web storage, sync locations to your server via `HttpConfig` before the user navigates away.

## Geolocation Accuracy on Desktop vs Mobile

| Environment | Typical Accuracy | Source |
|---|---|---|
| Desktop browser (Wi-Fi) | 50–200 m | IP geolocation / Wi-Fi triangulation |
| Desktop browser (Ethernet) | 1–10 km | IP geolocation only |
| Mobile browser (GPS enabled) | 5–20 m | Device GPS hardware |
| Mobile browser (no GPS) | 50–500 m | Cell tower / Wi-Fi |

> **Tip:** On desktop, `enableHighAccuracy: true` often *increases* time-to-fix without improving accuracy, because there is no GPS hardware. Tracelet's web engine automatically falls back to low accuracy if a high-accuracy request times out.

## HTTPS Requirement

The browser Geolocation API requires a **secure context** (HTTPS or `localhost`). If your app is served over plain HTTP on a non-localhost domain, all geolocation calls will fail.

```bash
# Development — localhost is always secure
flutter run -d chrome

# Production — must be HTTPS
flutter build web
# Deploy to HTTPS-enabled hosting
```

## Browser Permissions

Unlike Android/iOS, browser geolocation permission is **per-origin** and cannot be programmatically escalated. The browser shows its own prompt when `getCurrentPosition()` or `watchPosition()` is first called. There is no "Always Allow" / "When In Use" distinction — the browser either grants or denies.

| Status Code | Browser State |
|---|---|
| `0` (notDetermined) | `prompt` — user has not been asked yet |
| `2` (whenInUse) | `granted` — mapped to whenInUse since there is no "always" on web |
| `4` (deniedForever) | `denied` — user must manually re-enable in browser settings |

## Example

The example app works on web with no code changes:

```bash
cd example
flutter run -d chrome
```

The app automatically detects the web platform and:
- Skips headless task registration
- Hides Android-only UI (battery optimization, notification permission)
- Shows "Tracelet Web" in the app bar
- All buttons work — unsupported features log a message instead of crashing

## Known Limitations

1. **No background tracking** — Tracking stops when the tab loses focus or is minimized. This is a browser limitation, not a Tracelet limitation.
2. **No real activity recognition** — Activity is always reported as `unknown`. The [Generic Sensor API](https://developer.mozilla.org/en-US/docs/Web/API/Sensor_APIs) could provide accelerometer data in the future.
3. **In-memory only** — Locations and logs are lost on page refresh. Use HTTP sync for persistence.
4. **Single accuracy level** — `desiredAccuracy` maps to a boolean (`enableHighAccuracy`). There is no fine-grained control like on native platforms.
5. **No geofence limit management** — Unlike iOS (which rotates nearest-20), web keeps all geofences in memory and checks all of them on every fix. Performance may degrade with thousands of geofences.
6. **Browser-dependent behavior** — Different browsers implement the Geolocation API differently. Safari may require explicit user interaction before prompting. Firefox may use different location providers than Chrome.
