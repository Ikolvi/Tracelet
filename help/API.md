# API Reference

---

## Lifecycle

| Method | Returns | Description |
|---|---|---|
| `Tracelet.ready(config)` | `State` | Initialize with configuration |
| `Tracelet.start()` | `State` | Start tracking |
| `Tracelet.stop()` | `State` | Stop tracking |
| `Tracelet.startGeofences()` | `State` | Geofence-only mode |
| `Tracelet.getState()` | `State` | Current state |
| `Tracelet.setConfig(config)` | `State` | Update configuration |
| `Tracelet.reset()` | `State` | Reset to defaults |

---

## Location

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getCurrentPosition()` | `Location` | One-shot position |
| `Tracelet.watchPosition(callback)` | `int` | High-frequency watch |
| `Tracelet.stopWatchPosition(id)` | `bool` | Stop a watch |
| `Tracelet.changePace(isMoving)` | `bool` | Force motion state |
| `Tracelet.getOdometer()` | `double` | Odometer in meters |
| `Tracelet.setOdometer(value)` | `Location` | Reset odometer |

---

## Geofencing

| Method | Returns | Description |
|---|---|---|
| `Tracelet.addGeofence(geofence)` | `bool` | Add a geofence |
| `Tracelet.addGeofences(list)` | `bool` | Add multiple |
| `Tracelet.removeGeofence(id)` | `bool` | Remove by identifier |
| `Tracelet.removeGeofences()` | `bool` | Remove all |
| `Tracelet.getGeofences()` | `List<Geofence>` | List all |
| `Tracelet.getGeofence(id)` | `Geofence?` | Get one |
| `Tracelet.geofenceExists(id)` | `bool` | Check existence |

---

## Persistence & Sync

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getLocations()` | `List<Location>` | Stored locations |
| `Tracelet.getCount()` | `int` | Location count |
| `Tracelet.destroyLocations()` | `bool` | Delete all |
| `Tracelet.destroyLocation(uuid)` | `bool` | Delete one |
| `Tracelet.insertLocation(params)` | `String` | Insert custom |
| `Tracelet.sync()` | `List<Location>` | Manual HTTP sync |

---

## Permissions & Settings

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getPermissionStatus()` | `int` | Current location status (no dialog) |
| `Tracelet.requestPermission()` | `int` | Request location + wait for result |
| `Tracelet.getNotificationPermissionStatus()` | `int` | Notification status (Android 13+) |
| `Tracelet.requestNotificationPermission()` | `int` | Request notification (Android 13+) |
| `Tracelet.getMotionPermissionStatus()` | `int` | Motion/activity recognition status |
| `Tracelet.requestMotionPermission()` | `int` | Request motion permission |
| `Tracelet.openAppSettings()` | `bool` | Open app settings |
| `Tracelet.openLocationSettings()` | `bool` | Open location settings |
| `Tracelet.openBatterySettings()` | `bool` | Open battery optimization (Android) |
| `Tracelet.requestTemporaryFullAccuracy(purpose)` | `int` | Temp full accuracy (iOS 14+) |
| `Tracelet.isPowerSaveMode` | `bool` | Battery saver active? |
| `Tracelet.isIgnoringBatteryOptimizations()` | `bool` | Battery exempt? (Android) |

---

## Utility

| Method | Returns | Description |
|---|---|---|
| `Tracelet.getSensors()` | `Sensors` | Device sensor availability |
| `Tracelet.getDeviceInfo()` | `DeviceInfo` | Device model, manufacturer, OS |
| `Tracelet.playSound(name)` | `bool` | Play debug sound |
| `Tracelet.getLog()` | `String` | Get log content |
| `Tracelet.destroyLog()` | `bool` | Clear log |
| `Tracelet.emailLog(email)` | `bool` | Email log export |
| `Tracelet.log(level, message)` | `bool` | Write custom log entry |
| `Tracelet.registerHeadlessTask(callback)` | `void` | Register headless Dart callback |

---

## Events

| Subscription | Event Type | Fires when |
|---|---|---|
| `Tracelet.onLocation(cb)` | `Location` | Every recorded location |
| `Tracelet.onMotionChange(cb)` | `Location` | Moving ↔ stationary |
| `Tracelet.onActivityChange(cb)` | `ActivityChangeEvent` | Activity changes |
| `Tracelet.onProviderChange(cb)` | `ProviderChangeEvent` | GPS/permission changes |
| `Tracelet.onGeofence(cb)` | `GeofenceEvent` | Geofence transitions |
| `Tracelet.onGeofencesChange(cb)` | `GeofencesChangeEvent` | Monitored set changes |
| `Tracelet.onHeartbeat(cb)` | `HeartbeatEvent` | Heartbeat interval |
| `Tracelet.onHttp(cb)` | `HttpEvent` | HTTP sync result |
| `Tracelet.onSchedule(cb)` | `State` | Schedule start/stop |
| `Tracelet.onConnectivityChange(cb)` | `ConnectivityChangeEvent` | Online/offline |
| `Tracelet.onPowerSaveChange(cb)` | `bool` | Battery saver toggle |
| `Tracelet.onEnabledChange(cb)` | `bool` | Tracking on/off |
| `Tracelet.onNotificationAction(cb)` | `String` | Notification tap (Android) |
| `Tracelet.onAuthorization(cb)` | `AuthorizationEvent` | Auth token refresh |
