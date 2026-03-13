# Delta Encoding

Delta encoding compresses HTTP sync payloads by transmitting only the
**differences** between consecutive locations instead of full records.
Achieves **60–80% size reduction** for high-frequency tracking batches.

Implemented natively on all three platforms (Dart, Kotlin, Swift) so encoding
runs on-device before network transmission.

---

## Quick Start

```dart
import 'package:tracelet/tracelet.dart' as tl;

await tl.Tracelet.ready(tl.Config(
  http: tl.HttpConfig(
    url: 'https://api.example.com/locations',
    batchSync: true,                // Required — delta encoding needs batches
    enableDeltaCompression: true,   // Enable delta encoding
    deltaCoordinatePrecision: 6,    // 6 decimal places ≈ 0.11m precision
  ),
));
```

---

## How It Works

### Encoding Process

```
Batch of N locations:
  Location 1 → Full reference record  (ref: true)
  Location 2 → Delta from Location 1
  Location 3 → Delta from Location 2
  ...
  Location N → Delta from Location N-1
```

1. **First location** is emitted as a full record with all fields and a
   `ref: true` marker.
2. **Subsequent locations** contain a single `d` field with a dictionary of
   deltas — only the fields that changed from the previous record.
3. Zero deltas are omitted entirely, further reducing payload size.

### Coordinate Precision

Coordinate deltas are converted to integers by multiplying by $10^{\text{precision}}$:

```
deltaLat = (lat - prevLat) × 10^precision
```

| Precision | Resolution | Use Case |
|-----------|------------|----------|
| 5 | ~1.1 m | Fleet tracking, logistics |
| 6 | ~0.11 m | Default — good balance |
| 7 | ~0.011 m | Survey-grade applications |

### Heading Wrap-Around

Heading deltas use shortest-arc calculation to avoid wrapping artifacts:

```
rawDelta = heading - prevHeading
if rawDelta > 180  → delta = rawDelta - 360
if rawDelta < -180 → delta = rawDelta + 360
```

Example: 350° → 10° produces a delta of +20°, not −340°.

---

## Field Mapping

Delta-encoded records use shortened field names to reduce payload size:

| Short | Full Field | Encoding |
|-------|-----------|----------|
| `u` | `uuid` | Full string (always unique) |
| `t` | timestamp | Δ seconds since previous location |
| `la` | latitude | Δ integer: `(lat − prevLat) × 10^precision` |
| `lo` | longitude | Δ integer: `(lng − prevLng) × 10^precision` |
| `s` | speed | Δ float: `speed − prevSpeed` |
| `h` | heading | Δ float: shortest arc |
| `a` | accuracy | Δ float: `accuracy − prevAccuracy` |
| `al` | altitude | Δ float: `altitude − prevAltitude` |
| `b` | battery level | Δ float: `level − prevLevel` |

---

## Payload Example

### Before (Standard)

```json
[
  {"uuid":"a1","timestamp":"2024-01-15T10:00:00Z","coords":{"latitude":51.509865,"longitude":-0.118092,"speed":1.2,"heading":45.0,"accuracy":5.0,"altitude":30.0},"battery":{"level":0.85,"is_charging":false}},
  {"uuid":"a2","timestamp":"2024-01-15T10:00:05Z","coords":{"latitude":51.509870,"longitude":-0.118090,"speed":1.3,"heading":46.0,"accuracy":5.0,"altitude":30.0},"battery":{"level":0.85,"is_charging":false}},
  {"uuid":"a3","timestamp":"2024-01-15T10:00:10Z","coords":{"latitude":51.509880,"longitude":-0.118085,"speed":1.4,"heading":47.0,"accuracy":4.5,"altitude":30.0},"battery":{"level":0.85,"is_charging":false}}
]
```

### After (Delta-Encoded)

```json
[
  {"ref":true,"u":"a1","t":"2024-01-15T10:00:00Z","la":51509865,"lo":-118092,"s":1.2,"h":45.0,"a":5.0,"al":30.0,"b":0.85},
  {"u":"a2","d":{"t":5,"la":5,"lo":2,"s":0.1,"h":1.0}},
  {"u":"a3","d":{"t":5,"la":10,"lo":5,"s":0.1,"h":1.0,"a":-0.5}}
]
```

Fields with zero delta (altitude, battery) are omitted from the `d` dictionary.

---

## Configuration

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `enableDeltaCompression` | `bool` | `false` | Enable delta compression for HTTP sync payloads |
| `deltaCoordinatePrecision` | `int` | `6` | Decimal places for coordinate precision |

### Requirements

- **`batchSync: true`** must be enabled — delta encoding operates on batches.
- The server must decode delta payloads. See [Server Decoding](#server-decoding).

---

## Server Decoding

Your server needs to reconstruct full locations from delta payloads. Pseudocode:

```python
def decode_batch(batch):
    result = []
    prev = None
    for record in batch:
        if record.get('ref'):
            # Reference record — convert to full format
            loc = {
                'uuid': record['u'],
                'timestamp': record['t'],
                'latitude': record['la'] / 10**precision,
                'longitude': record['lo'] / 10**precision,
                'speed': record['s'],
                'heading': record['h'],
                'accuracy': record['a'],
                'altitude': record['al'],
                'battery': record['b'],
            }
        else:
            # Delta record — add deltas to previous
            d = record['d']
            loc = {
                'uuid': record['u'],
                'timestamp': add_seconds(prev['timestamp'], d.get('t', 0)),
                'latitude': prev['latitude'] + d.get('la', 0) / 10**precision,
                'longitude': prev['longitude'] + d.get('lo', 0) / 10**precision,
                'speed': prev['speed'] + d.get('s', 0),
                'heading': (prev['heading'] + d.get('h', 0)) % 360,
                'accuracy': prev['accuracy'] + d.get('a', 0),
                'altitude': prev['altitude'] + d.get('al', 0),
                'battery': prev['battery'] + d.get('b', 0),
            }
        result.append(loc)
        prev = loc
    return result
```

---

## Compression Ratios

Typical savings depend on tracking frequency and movement patterns:

| Scenario | Locations/batch | Reduction |
|----------|----------------|-----------|
| Walking, 5s interval | 100 | ~75% |
| Driving, 10s interval | 50 | ~65% |
| Stationary monitoring | 200 | ~80% |
| Mixed urban commute | 150 | ~70% |

Higher precision values (7+) slightly reduce savings due to larger integer deltas.

---

## Cross-Platform Implementation

Delta encoding is implemented identically on all three platforms:

| Platform | File | Language |
|----------|------|----------|
| Dart | `tracelet_platform_interface/.../delta_encoder.dart` | Dart |
| Android | `tracelet_android/android/.../DeltaEncoder.kt` | Kotlin |
| iOS | `tracelet_ios/ios/.../DeltaEncoder.swift` | Swift |

The native implementations handle encoding on-device before HTTP transmission.
The Dart implementation provides `encode()` and `decode()` for testing and
client-side batch processing.

---

## Related Guides

- [HTTP Sync](HTTP-SYNC.md) — Full HTTP sync configuration and behavior
- [Configuration](CONFIGURATION.md) — All config groups with property tables
- [Adaptive Sampling](ADAPTIVE-SAMPLING.md) — Controls how often locations are sampled
