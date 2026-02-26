# Trip Detection

Tracelet automatically detects **trips** — contiguous periods of device motion
between two stationary states. When a trip ends, a `TripEvent` is dispatched
containing distance, duration, start/stop locations, and the full route
polyline.

---

## How It Works

Trip detection is powered by the existing motion detection system. No extra
permissions or sensors are required.

```
   Motion: stationary ──► moving ──────────────────► stationary
   Trip:                  ┌─ START                   └─ END
                          │  record waypoints           dispatch TripEvent
                          │  accumulate distance
                          └──────────────────────────┘
```

### Lifecycle

1. **Trip Start** — the motion detector fires `isMoving: true` (device
   transitions from stationary to moving). The trip manager records the start
   location and timestamp.

2. **Waypoint Collection** — every accepted tracking location during the trip
   is appended to the waypoints list. Distance is accumulated segment by
   segment (each waypoint to the next).

3. **Trip End** — the motion detector fires `isMoving: false` (device becomes
   stationary again). The trip manager:
   - Records the stop location
   - Computes total duration
   - Dispatches a `TripEvent` with the full summary

> **Note:** Trip events are only dispatched at trip **end** (when the device
> becomes stationary). There is no trip-start event — the `isMoving` field in
> `TripEvent` is always `false`.

---

## How to Use

### Subscribe to Trip Events

```dart
Tracelet.onTrip((trip) {
  print('Trip ended!');
  print('  Distance: ${trip.distance.toStringAsFixed(0)} m');
  print('  Duration: ${trip.duration.toStringAsFixed(0)} s');
  print('  Average speed: ${trip.averageSpeed.toStringAsFixed(1)} m/s');
  print('  Waypoints: ${trip.waypoints.length}');
  print('  From: ${trip.startLocation.coords.latitude}, '
        '${trip.startLocation.coords.longitude}');
  print('  To:   ${trip.stopLocation.coords.latitude}, '
        '${trip.stopLocation.coords.longitude}');
});
```

### Full Setup Example

```dart
import 'package:tracelet/tracelet.dart' as tl;

Future<void> startTracking() async {
  await tl.Tracelet.ready(tl.Config(
    geo: tl.GeoConfig(
      distanceFilter: 10.0,
    ),
    motion: tl.MotionConfig(
      stopTimeout: 5,     // minutes of stillness before declaring stationary
    ),
  ));

  // Subscribe to trips
  tl.Tracelet.onTrip((trip) {
    sendTripToServer(trip.toMap());
  });

  // Subscribe to locations (optional, trips work independently)
  tl.Tracelet.onLocation((location) {
    print('Location: ${location.coords.latitude}');
  });

  await tl.Tracelet.start();
}
```

---

## TripEvent API

### Properties

| Property         | Type             | Description |
|------------------|------------------|-------------|
| `isMoving`       | `bool`           | Always `false` (trips only dispatch on end) |
| `distance`       | `double`         | Total distance in meters |
| `duration`       | `double`         | Total duration in seconds |
| `startLocation`  | `Location`       | Location when the trip started |
| `stopLocation`   | `Location`       | Location when the trip ended |
| `waypoints`      | `List<Location>` | Ordered intermediate locations (route polyline) |
| `averageSpeed`   | `double`         | Computed: `distance / duration` (m/s), `0.0` if duration is zero |

### Methods

| Method          | Returns            | Description |
|-----------------|--------------------|-------------|
| `toMap()`       | `Map<String, Object?>` | Serialize to a platform map |
| `fromMap(map)`  | `TripEvent`        | Factory: deserialize from a platform map |

### Example: Computing Stats

```dart
Tracelet.onTrip((trip) {
  final distanceKm = trip.distance / 1000;
  final durationMin = trip.duration / 60;
  final speedKmh = trip.averageSpeed * 3.6;

  print('${distanceKm.toStringAsFixed(1)} km '
        'in ${durationMin.toStringAsFixed(0)} min '
        '@ ${speedKmh.toStringAsFixed(0)} km/h');

  // Build a GeoJSON LineString from waypoints
  final coordinates = trip.waypoints.map((wp) =>
    [wp.coords.longitude, wp.coords.latitude]
  ).toList();

  final geojson = {
    'type': 'LineString',
    'coordinates': coordinates,
  };
});
```

---

## Configuration

Trip detection requires no dedicated configuration. It uses the existing
motion detection and location tracking settings:

| Setting               | Effect on Trips |
|-----------------------|-----------------|
| `distanceFilter`      | Controls waypoint density. Lower = more waypoints, higher = fewer |
| `stopTimeout`         | Minutes of stillness before declaring stationary → ending the trip |
| `disableStopDetection`| If `true`, trips never end (device never goes stationary) |
| `stopOnStationary`    | If `true`, tracking stops on stationary — the trip-end event still fires before stopping |
| `useKalmanFilter`     | If `true`, waypoint coordinates are Kalman-smoothed for cleaner routes |

### Recommended Settings

| Use Case             | `distanceFilter` | `stopTimeout` | Notes |
|----------------------|:----------------:|:-------------:|-------|
| Driving              | 50–100           | 5             | Fewer waypoints, standard stop detection |
| Cycling              | 20–50            | 3–5           | Medium density |
| Walking / Running    | 10–20            | 2–3           | High density, faster stop detection |
| Fleet tracking       | 50–200           | 5–10          | Battery-optimized |

---

## Waypoint Format

Each waypoint in `trip.waypoints` is a full `Location` object, but only
core fields are populated:

| Field               | Populated? | Source |
|---------------------|:----------:|--------|
| `coords.latitude`   | ✅         | GPS fix |
| `coords.longitude`  | ✅         | GPS fix |
| `timestamp`         | ✅         | GPS fix timestamp |
| `coords.accuracy`   | ✅         | From location event |
| `coords.speed`      | ✅         | From location event |
| Other coords fields | ✅         | From location event |

---

## Interaction with Other Features

### Kalman Filter

When `useKalmanFilter: true`, the waypoints stored during a trip use
**smoothed** coordinates. This produces cleaner route polylines. The trip
`distance` is computed from raw GPS coordinates for accuracy.

### Geofence-Only Mode

Trip detection only works when **tracking** is active (`Tracelet.start()`).
It does **not** fire in geofence-only mode (`Tracelet.startGeofences()`)
because location tracking is not running continuously.

### Schedules

When using time-based schedules, trips naturally start and end within the
scheduled tracking window. If the device is mid-trip when the schedule window
closes and `stop()` is called, the trip data is discarded (the trip manager
is reset on stop).

### Motion Detection Modes

| Mode | Trip Detection |
|------|----------------|
| Full (Activity Recognition) | ✅ Works — transitions from AR activity changes |
| Accelerometer-only (`disableMotionActivityUpdates: true`) | ✅ Works — transitions from accelerometer motion detection |

---

## Edge Cases

### What happens if...

**...tracking is stopped mid-trip?**
The trip manager is reset. No partial trip event is dispatched. This is by
design — a trip requires both a start and stop transition.

**...the app is killed and restarted?**
Trip state is in-memory only (not persisted). If the app is killed during a
trip and later relaunched by `startOnBoot`, the trip data from the previous
session is lost. A new trip starts on the next moving→stationary cycle.

**...multiple `isMoving: true` events fire in a row?**
The trip manager guards against this. Only the first `isMoving: true` event
starts a trip. Subsequent moving events are ignored until the device goes
stationary and a new trip can begin.

**...the device never becomes stationary?**
The trip never ends. Waypoints continue accumulating. The trip-end event only
fires when `isMoving: false` is received (or `stop()` is called, which resets
without dispatching).

**...`stopTimeout` is very short (e.g., 1 minute)?**
Short stops at traffic lights or briefly pausing may incorrectly end a trip.
Use `stopTimeout: 5` (5 minutes) for driving to avoid false trip-ends.

---

## Platform Implementation

| Platform | File | Key Method |
|----------|------|------------|
| All      | `trip_manager.dart` | Shared Dart `TripManager.onMotionStateChanged()` / `onLocationReceived()` |
| All      | `trip_event.dart` | `TripEvent` model class |

Trip detection runs in shared Dart code (`tracelet_platform_interface/lib/src/algorithms/trip_manager.dart`), so it works identically on Android, iOS, web, and future desktop platforms.

The trip manager is wired into the plugin entry point:
- The motion detector’s state change callback feeds `onMotionStateChanged()`
- The location engine’s tracking callback feeds `onLocationReceived()`
- Trip-end events are dispatched via a Dart `StreamController.broadcast()`

---

## FAQ

**Q: Does trip detection use extra battery?**
No. It piggybacks on existing motion detection and location tracking. No
additional sensors, GPS requests, or wake-ups are required.

**Q: Can I detect trip starts in real time?**
Currently, only trip-end events are dispatched. To detect the start of motion
in real time, use `Tracelet.onMotionChange()`:
```dart
Tracelet.onMotionChange((location) {
  // location.isMoving == true means motion started
});
```

**Q: Can I persist trips to a server?**
Yes. Serialize with `trip.toMap()` and send via your HTTP layer:
```dart
Tracelet.onTrip((trip) async {
  await http.post(
    Uri.parse('https://api.example.com/trips'),
    body: jsonEncode(trip.toMap()),
    headers: {'Content-Type': 'application/json'},
  );
});
```

**Q: Are waypoints the same as `onLocation` events?**
Yes — each waypoint corresponds to a location event that passed through
the distance filter and accuracy filter during the trip. The waypoint list
is a subset of all `onLocation` events (only those during the trip).

**Q: Can I use trip detection without subscribing to `onLocation`?**
Yes. `onTrip()` works independently. You don't need to subscribe to
`onLocation()` or `onMotionChange()` for trip detection to function.
