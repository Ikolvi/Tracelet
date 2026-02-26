# Polygon Geofences

Tracelet supports **polygon geofences** — arbitrary shapes defined by a list
of vertices instead of a center + radius circle. The device's position is
tested against the polygon boundary using the **ray-casting algorithm** for
efficient point-in-polygon containment checks.

---

## Circular vs. Polygon Geofences

| Feature | Circular | Polygon |
|---------|----------|---------|
| Shape | Circle (center + radius) | Arbitrary polygon (≥ 3 vertices) |
| Definition | `latitude`, `longitude`, `radius` | `latitude`, `longitude`, `vertices` |
| Accuracy | Good for small areas | Precise boundary matching |
| Use case | POIs, stores, landmarks | Campuses, parking lots, neighborhoods, zones |
| Requires high-accuracy mode | No (OS handles it) | Yes (`geofenceModeHighAccuracy: true`) |

---

## How to Use

### 1. Enable High-Accuracy Geofence Mode

Polygon geofences are evaluated in-app (not by the OS), so you need
`geofenceModeHighAccuracy: true` for the enter/exit transitions to fire:

```dart
await Tracelet.ready(Config(
  geo: GeoConfig(
    geofenceModeHighAccuracy: true,  // ← required for polygon geofences
  ),
));
```

### 2. Add a Polygon Geofence

Set `vertices` to a list of `[latitude, longitude]` pairs (≥ 3 vertices).
When `vertices` has 3+ entries, the `radius` field is ignored and polygon
containment is used instead:

```dart
await Tracelet.addGeofence(Geofence(
  identifier: 'campus',
  latitude: 37.422,    // centroid — used for proximity sorting
  longitude: -122.084,
  radius: 0,           // ignored when vertices are present
  notifyOnEntry: true,
  notifyOnExit: true,
  vertices: [
    [37.4235, -122.0865],  // NW corner
    [37.4240, -122.0820],  // NE corner
    [37.4210, -122.0810],  // SE corner
    [37.4200, -122.0850],  // SW corner
  ],
));
```

### 3. Start Geofence Monitoring

```dart
// Option A: Full tracking (geofences + location tracking)
await Tracelet.start();

// Option B: Geofence-only mode (no continuous location tracking)
await Tracelet.startGeofences();
```

### 4. Listen for Events

Polygon geofences fire the same events as circular geofences:

```dart
Tracelet.onGeofence((event) {
  print('${event.action} → ${event.identifier}');
  // "ENTER → campus" or "EXIT → campus"
});

Tracelet.onGeofencesChange((event) {
  print('Inside: ${event.on.length} geofences');
  print('Left:   ${event.off.length} geofences');
});
```

---

## Vertex Format

Each vertex is a list of two doubles: `[latitude, longitude]`.

```dart
vertices: [
  [lat1, lng1],  // Vertex 1
  [lat2, lng2],  // Vertex 2
  [lat3, lng3],  // Vertex 3
  // ... more vertices
]
```

**Rules:**
- Minimum 3 vertices (triangle). No maximum limit.
- Vertices can be ordered clockwise or counter-clockwise — the algorithm
  handles both.
- The polygon is automatically closed — you do NOT need to repeat the first
  vertex as the last.
- Self-intersecting polygons are supported but may produce unexpected results
  (the algorithm counts edge crossings, so overlapping areas toggle inside/
  outside).

### The `latitude`/`longitude` Fields

When using polygon geofences, the `latitude` and `longitude` fields on the
`Geofence` object represent the **centroid** (center of mass) of the polygon.
They are used for:

1. **Proximity sorting** — iOS limits monitoring to 20 regions. The plugin
   selects the 20 nearest geofences based on distance to the centroid.
2. **Platform registration** — iOS `CLCircularRegion` requires a center point.
   The OS uses this for coarse enter/exit detection, while the in-app polygon
   check provides the precise boundary.

Set the centroid to a reasonable center point of your polygon. You can compute
it as the average of all vertices:

```dart
double centroidLat = vertices.map((v) => v[0]).reduce((a, b) => a + b) / vertices.length;
double centroidLng = vertices.map((v) => v[1]).reduce((a, b) => a + b) / vertices.length;
```

---

## How It Works

### Ray-Casting Algorithm

The algorithm determines if a point lies inside a polygon by casting a
horizontal ray from the test point to the right (positive X direction) and
counting how many polygon edges it crosses:

- **Odd crossings** → point is **inside** the polygon
- **Even crossings** → point is **outside** the polygon

```
    ┌──────────────┐
    │              │
    │    ● ──── ✕ ──── ✕ ──►  (2 crossings = outside? No — point is inside)
    │         P    │             This example shows a concave polygon;
    │              │             the actual count depends on the shape.
    └──────────────┘

    P ● ────── ✕ ──────────►  (1 crossing = inside ✓)
    │          │
    └──────────┘
```

This runs in O(n) time where n = number of vertices. Even with complex
polygons of 100+ vertices, the computation takes microseconds.

### Evaluation Flow

On every location update (when `geofenceModeHighAccuracy` is enabled):

```
Location update
  │
  ├─ For each stored geofence:
  │   │
  │   ├─ Has ≥3 vertices? → isPointInPolygon(lat, lng, vertices)
  │   │
  │   └─ Otherwise → circular distance check (distance ≤ radius?)
  │
  ├─ Compare with previous state (was inside? is now inside?)
  │
  ├─ Fire ENTER if: was outside, now inside
  │
  └─ Fire EXIT if: was inside, now outside
```

### Input Validation

Both Android and iOS implementations validate vertex data before running the
algorithm:

- Each inner vertex array must have at least 2 elements (lat + lng)
- If any vertex has fewer than 2 elements, `isPointInPolygon` returns `false`
  (treats the geofence as inactive rather than crashing)

---

## Examples

### Rectangle (4 vertices)

```dart
// A parking lot
await Tracelet.addGeofence(Geofence(
  identifier: 'parking_lot_a',
  latitude: 37.7850,
  longitude: -122.4095,
  radius: 0,
  vertices: [
    [37.7855, -122.4100],  // NW
    [37.7855, -122.4090],  // NE
    [37.7845, -122.4090],  // SE
    [37.7845, -122.4100],  // SW
  ],
));
```

### Triangle (3 vertices)

```dart
// A triangular zone
await Tracelet.addGeofence(Geofence(
  identifier: 'zone_alpha',
  latitude: 40.748,
  longitude: -73.985,
  radius: 0,
  vertices: [
    [40.7500, -73.9870],
    [40.7490, -73.9830],
    [40.7460, -73.9860],
  ],
));
```

### Complex Polygon (L-shape, 6 vertices)

```dart
// An L-shaped building footprint
await Tracelet.addGeofence(Geofence(
  identifier: 'building_l',
  latitude: 51.5074,
  longitude: -0.1278,
  radius: 0,
  vertices: [
    [51.5080, -0.1290],  // Top-left
    [51.5080, -0.1270],  // Top-right
    [51.5075, -0.1270],  // Inner corner top
    [51.5075, -0.1260],  // Inner corner right
    [51.5065, -0.1260],  // Bottom-right
    [51.5065, -0.1290],  // Bottom-left
  ],
));
```

### Dynamic Polygon at Current Location

```dart
// Create a ~200m square around the current position
final loc = await Tracelet.getCurrentPosition();
const offset = 0.0018; // ~200m at mid-latitudes

await Tracelet.addGeofence(Geofence(
  identifier: 'here_${DateTime.now().millisecondsSinceEpoch}',
  latitude: loc.coords.latitude,
  longitude: loc.coords.longitude,
  radius: 0,
  vertices: [
    [loc.coords.latitude + offset, loc.coords.longitude - offset],
    [loc.coords.latitude + offset, loc.coords.longitude + offset],
    [loc.coords.latitude - offset, loc.coords.longitude + offset],
    [loc.coords.latitude - offset, loc.coords.longitude - offset],
  ],
));
```

---

## Mixing Circular and Polygon Geofences

You can use both types simultaneously. The evaluation logic checks each
geofence independently:

```dart
// Circular geofence — coffee shop
await Tracelet.addGeofence(Geofence(
  identifier: 'coffee_shop',
  latitude: 37.785,
  longitude: -122.409,
  radius: 50, // 50m circle
  notifyOnEntry: true,
));

// Polygon geofence — office campus
await Tracelet.addGeofence(Geofence(
  identifier: 'campus',
  latitude: 37.422,
  longitude: -122.084,
  radius: 0,
  vertices: [
    [37.4235, -122.0865],
    [37.4240, -122.0820],
    [37.4210, -122.0810],
    [37.4200, -122.0850],
  ],
));
```

Both geofences fire events through the same `onGeofence()` and
`onGeofencesChange()` streams.

---

## Configuration

| Setting | Default | Effect on Polygon Geofences |
|---------|---------|-----------------------------|
| `geofenceModeHighAccuracy` | `false` | **Must be `true`** for polygon geofences to work. Enables in-app evaluation on every GPS fix. |
| `geofenceInitialTriggerEntry` | `true` | Fire ENTER event immediately if already inside the polygon when monitoring starts |
| `geofenceProximityRadius` | `1000` | Proximity radius (meters) for selecting which geofences to monitor. Uses the centroid distance. |

---

## Knock-Out Mode

Polygon geofences work with knock-out mode (`extras: {'knockOut': true}` is
not needed — use the global config):

When `geofenceModeKnockOut` is enabled:
- After an EXIT event, the geofence is automatically removed from the database
- Works identically for both circular and polygon geofences

---

## Platform Implementation

| Platform | File | Method |
|----------|------|--------|
| All      | `geo_utils.dart` | Shared Dart `GeoUtils.isPointInPolygon()` |
| All      | `geofence_evaluator.dart` | Shared Dart `GeofenceEvaluator.evaluateProximity()` |

The ray-casting algorithm and geofence proximity evaluation run in shared Dart code (`tracelet_platform_interface/lib/src/algorithms/`), so they work identically on Android, iOS, web, and future desktop platforms. The evaluator is called on every location update when high-accuracy mode is active.

---

## Limitations

1. **Requires `geofenceModeHighAccuracy: true`** — polygon containment is
   computed in-app, not by the OS. Without high-accuracy mode, the OS only
   handles circular regions and polygon vertices are ignored.

2. **Battery impact** — high-accuracy mode runs the full GPS pipeline
   continuously (even in geofence-only mode). This consumes more battery than
   standard OS-managed circular geofences. Use circular geofences when a
   circle is sufficient.

3. **No DWELL events for polygons** — the `notifyOnDwell` / `loiteringDelay`
   parameters only work with OS-managed circular geofences. Polygon geofences
   only fire ENTER and EXIT events.

4. **iOS 20-region limit** — iOS monitors at most 20 `CLCircularRegion`s. The
   OS uses the centroid + a large radius for coarse monitoring. If you have
   more than 20 polygon geofences, the plugin rotates the nearest 20 based on
   centroid distance.

---

## FAQ

**Q: Does it use more battery than circular geofences?**
Yes, when using high-accuracy mode. The GPS is polled at the configured
`distanceFilter` interval rather than relying on OS-managed region monitoring.
For pure proximity alerts where a circle is sufficient, use circular geofences.

**Q: How many vertices can a polygon have?**
There is no hard limit. The algorithm runs in O(n) time, so even 1000+
vertices work fine. However, storing large vertex arrays in SQLite and
serializing them through platform channels has a practical overhead. Keep it
under 100 vertices for best performance.

**Q: Can I update a polygon's vertices at runtime?**
Remove the geofence and re-add it with the new vertices:
```dart
await Tracelet.removeGeofence('campus');
await Tracelet.addGeofence(Geofence(
  identifier: 'campus',
  latitude: 37.422,
  longitude: -122.084,
  radius: 0,
  vertices: updatedVertices,
));
```

**Q: Do polygon geofences persist across app restarts?**
Yes. Like circular geofences, polygon definitions (including vertices) are
stored in SQLite and re-registered on boot/restart.

**Q: Can I use polygon geofences without tracking?**
Yes, via `Tracelet.startGeofences()` with `geofenceModeHighAccuracy: true`.
This starts the GPS pipeline for proximity evaluation without dispatching
location events.
