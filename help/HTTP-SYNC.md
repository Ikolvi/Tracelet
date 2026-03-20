# HTTP Sync Guide

Tracelet's HTTP sync engine uploads recorded locations from the local SQLite
database to your server. It handles batching, retry with exponential backoff,
connectivity monitoring, and offline queuing — all configurable from Dart.

---

## Quick Start

```dart
await Tracelet.ready(Config(
  http: HttpConfig(
    url: 'https://api.example.com/locations',
    method: HttpMethod.post,
    autoSync: true,          // Sync after each location
    batchSync: true,         // Send multiple locations per request
    maxBatchSize: 250,       // Max locations per batch
  ),
));
```

Tracelet will now automatically POST locations to your server as they're
recorded. If the server is unreachable, locations are queued in SQLite and
synced when connectivity returns.

---

## Request Format

### Single Location (default)

```json
{
  "location": {
    "uuid": "abc-123",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "speed": 12.5,
    "timestamp": "2024-01-15T10:30:00.000Z"
  }
}
```

### Batch Mode (`batchSync: true`)

```json
{
  "location": [
    { "uuid": "abc-123", "latitude": 37.7749, ... },
    { "uuid": "def-456", "latitude": 37.7750, ... }
  ]
}
```

The root property name is configurable via `httpRootProperty` (default:
`"location"`). Extra static fields can be added via `params`.

---

## Retry Strategy

When an HTTP request fails with a **transient error**, Tracelet retries
with exponential backoff and jitter:

```
delay = min(retryBackoffCap, retryBackoffBase × 2^(attempt-1)) ± jitter
```

### What's Retried (Transient Errors)

| Status Code | Meaning                | Retried? |
|-------------|------------------------|----------|
| `0`         | Network error / timeout | ✅ Yes   |
| `408`       | Request Timeout         | ✅ Yes   |
| `429`       | Too Many Requests       | ✅ Yes   |
| `500–599`   | Server Error            | ✅ Yes   |

### What's NOT Retried (Permanent Errors)

| Status Code | Meaning                | Retried? |
|-------------|------------------------|----------|
| `400`       | Bad Request             | ❌ No    |
| `401`       | Unauthorized            | ❌ No    |
| `403`       | Forbidden               | ❌ No    |
| `404`       | Not Found               | ❌ No    |
| Other 4xx   | Client error            | ❌ No    |

### Retry Configuration

| Property          | Type  | Default    | Description                                           |
|-------------------|-------|------------|-------------------------------------------------------|
| `maxRetries`      | `int` | `10`       | Max retry attempts per batch. Set to `0` to disable.  |
| `retryBackoffBase`| `int` | `1000`     | Base delay in ms (doubles each attempt)               |
| `retryBackoffCap` | `int` | `300000`   | Max delay in ms (5 minutes)                           |

### Backoff Timeline (defaults)

| Attempt | Delay (approx)  |
|---------|-----------------|
| 1       | 1 second        |
| 2       | 2 seconds       |
| 3       | 4 seconds       |
| 4       | 8 seconds       |
| 5       | 16 seconds      |
| 6       | 32 seconds      |
| 7       | 64 seconds      |
| 8       | 128 seconds     |
| 9       | 256 seconds     |
| 10      | 300 seconds (cap) |

**Jitter**: ±25% (Android) or 0–10% (iOS) random variation prevents
thundering-herd when multiple devices retry simultaneously.

---

## Connectivity Handling

Both Android and iOS monitor network connectivity and defer sync when offline:

| Behavior                    | Android | iOS    |
|-----------------------------|---------|--------|
| Detect online → offline     | ✅      | ✅     |
| Detect offline → online     | ✅      | ✅     |
| Auto-sync on reconnect      | ✅      | ✅     |
| Connectivity change event   | ✅      | ✅     |

When a sync fails due to no connectivity, a `pendingSyncOnConnect` flag is set.
As soon as the device reconnects, all pending locations are flushed automatically.

### Wi-Fi Only Sync

```dart
HttpConfig(
  url: 'https://api.example.com/locations',
  autoSync: true,
  disableAutoSyncOnCellular: true,  // Only sync on Wi-Fi
)
```

When `disableAutoSyncOnCellular` is `true`, auto-sync is skipped on cellular
connections. Manual sync via `Tracelet.sync()` still works on any connection.

---

## Batch Continuation

The sync engine processes **all pending batches** in sequence, not just one.
After a batch is successfully synced and marked in the database, the engine
fetches the next batch of unsynced locations and repeats until the database
is empty or a failure stops the loop.

```
Fetch batch → Send → Mark synced → Fetch next batch → ... → Done
```

This ensures that even with thousands of queued locations, a single sync
trigger flushes everything.

---

## HttpEvent — Monitoring Sync

Subscribe to HTTP events to monitor sync progress in your UI:

```dart
Tracelet.onHttp((HttpEvent event) {
  print('HTTP ${event.status}: ${event.success}');

  if (event.isRetry) {
    print('  Retry attempt #${event.retryCount}');
  }

  if (!event.success) {
    print('  Response: ${event.responseText}');
  }
});
```

### HttpEvent Fields

| Field          | Type     | Description                              |
|----------------|----------|------------------------------------------|
| `success`      | `bool`   | Whether the request succeeded (2xx)      |
| `status`       | `int`    | HTTP status code (0 = network error)     |
| `responseText` | `String` | Raw response body from server            |
| `isRetry`      | `bool`   | `true` if this was a retry attempt       |
| `retryCount`   | `int`    | Current retry number (0 = first attempt) |

---

## Manual Sync

Trigger sync manually when you need explicit control:

```dart
final synced = await Tracelet.sync();
print('Synced ${synced.length} locations');
```

`sync()` returns the list of successfully synced locations. It respects
the retry strategy — if the server returns 5xx, it will retry up to
`maxRetries` times before giving up.

---

## Auto-Sync Threshold

Buffer locations before syncing to reduce HTTP requests:

```dart
HttpConfig(
  url: 'https://api.example.com/locations',
  autoSync: true,
  autoSyncThreshold: 10,  // Wait until 10 locations before syncing
  batchSync: true,
)
```

This is useful for battery savings — instead of one HTTP request per
location, the engine waits until a threshold is reached.

---

## Custom Headers & Parameters

```dart
HttpConfig(
  url: 'https://api.example.com/locations',
  headers: {
    'Authorization': 'Bearer $token',
    'X-Device-Id': deviceId,
  },
  params: {
    'company_id': 'acme-corp',
    'fleet_id': 'fleet-42',
  },
  extras: {
    'driver_name': 'Alice',
  },
)
```

- **`headers`** — Added to every HTTP request
- **`params`** — Merged into the JSON request body (top-level keys)
- **`extras`** — Attached to each individual location record

---

## Configuration Examples

### Enterprise Fleet (reliable delivery)

```dart
HttpConfig(
  url: 'https://fleet.example.com/api/v2/locations',
  method: HttpMethod.post,
  autoSync: true,
  batchSync: true,
  maxBatchSize: 250,
  maxRetries: 10,
  retryBackoffBase: 1000,    // 1s → 2s → 4s → ... → 5min
  retryBackoffCap: 300000,
  disableAutoSyncOnCellular: false,
  headers: {'Authorization': 'Bearer $apiKey'},
)
```

### Battery-Conscious App (reduce HTTP traffic)

```dart
HttpConfig(
  url: 'https://api.example.com/locations',
  autoSync: true,
  autoSyncThreshold: 50,    // Buffer 50 locations
  batchSync: true,
  maxRetries: 3,             // Give up faster
  retryBackoffBase: 2000,    // Start slower
  retryBackoffCap: 60000,    // Cap at 1 minute
  disableAutoSyncOnCellular: true,
)
```

### Aggressive Sync (real-time tracking)

```dart
HttpConfig(
  url: 'https://realtime.example.com/locations',
  autoSync: true,
  autoSyncThreshold: 0,     // Sync immediately
  batchSync: false,          // One request per location
  maxRetries: 5,
  retryBackoffBase: 500,     // Fast retries
  retryBackoffCap: 30000,    // Cap at 30 seconds
)
```

### Disable Retries (debug / testing)

```dart
HttpConfig(
  url: 'https://dev.example.com/locations',
  autoSync: true,
  maxRetries: 0,             // No retries — fail immediately
)
```

---

## Platform Differences

| Behavior                              | Android                     | iOS                          |
|---------------------------------------|-----------------------------|------------------------------|
| HTTP client                           | OkHttp 4.12                 | URLSession                   |
| Retry execution                       | Blocking `Thread.sleep`     | Deferred `asyncAfter`        |
| Jitter range                          | ±25%                        | 0–10%                        |
| Connectivity monitor                  | `ConnectivityManager`       | `NWPathMonitor`              |
| Background protection during sync     | Foreground service          | `beginBackgroundTask`        |
| Timeout source                        | `httpTimeout` config        | `httpTimeout` config         |

Both platforms read `maxRetries`, `retryBackoffBase`, and `retryBackoffCap`
from the same Dart `HttpConfig` — no platform-specific configuration needed.

---

## Background / Killed-State Sync

HTTP auto-sync works in all tracking modes even when the app is killed or
the device reboots — locations are synced to your server without requiring
the Flutter engine or any UI.

### How It Works

| Platform | Mechanism |
|----------|-----------|
| **Android** | `LocationService` creates a dedicated `HttpSyncManager` during boot-mode tracking. Each persisted location triggers `onLocationInserted()` which auto-syncs via OkHttp. |
| **iOS** | `autoResumeTracking()` restores the plugin's existing `HttpSyncManager` wiring when iOS relaunches the app via significant location changes. |

### Tracking Mode Support

| Mode | Android | iOS |
|------|---------|-----|
| Continuous (0) | Auto-syncs via boot-mode `HttpSyncManager` | Auto-syncs via `autoResumeTracking()` |
| Geofences (1) | Auto-syncs via boot-mode `HttpSyncManager` | Auto-syncs via `autoResumeTracking()` |
| Periodic (2) — FG Service | Auto-syncs via boot-mode `HttpSyncManager` | Auto-syncs via `autoResumeTracking()` |
| Periodic (2) — WorkManager | Auto-syncs via `PeriodicLocationWorker` | N/A (uses `BGAppRefreshTask`) |
| Periodic (2) — Exact Alarms | Auto-syncs via `PeriodicLocationWorker` | N/A |

### Requirements

For killed-state sync to work, you must configure:

```dart
Config(
  app: AppConfig(
    stopOnTerminate: false,  // Required — keeps tracking alive
    startOnBoot: true,       // Recommended — resumes after reboot
  ),
  http: HttpConfig(
    url: 'https://api.example.com/locations',
    autoSync: true,          // Required — enables auto-sync
  ),
)
```

When the app is reopened, the plugin takes over from the boot-mode sync
manager — there is no duplication or gap in sync coverage.

---

## Configuration Reference

| Property                    | Type              | Default    | Description                                |
|-----------------------------|-------------------|------------|--------------------------------------------|
| `url`                       | `String?`         | `null`     | Server URL (null = disabled)               |
| `method`                    | `HttpMethod`      | `post`     | `post` or `put`                            |
| `headers`                   | `Map<String,String>` | `{}`    | Custom HTTP headers                        |
| `httpRootProperty`          | `String`          | `'location'` | Root JSON property name                  |
| `batchSync`                 | `bool`            | `false`    | Send all locations in one request          |
| `maxBatchSize`              | `int`             | `250`      | Max locations per batch                    |
| `autoSync`                  | `bool`            | `true`     | Auto-sync on each insert                   |
| `autoSyncThreshold`         | `int`             | `0`        | Min locations before auto-sync             |
| `httpTimeout`               | `int`             | `60000`    | Request timeout in ms                      |
| `params`                    | `Map`             | `{}`       | Extra body parameters                      |
| `locationsOrderDirection`   | `LocationOrder`   | `asc`      | Sort order for pending locations           |
| `extras`                    | `Map`             | `{}`       | Extra data on each location                |
| `disableAutoSyncOnCellular` | `bool`            | `false`    | Wi-Fi-only auto-sync                       |
| `maxRetries`                | `int`             | `10`       | Max retry attempts for transient failures  |
| `retryBackoffBase`          | `int`             | `1000`     | Base backoff delay in ms                   |
| `retryBackoffCap`           | `int`             | `300000`   | Max backoff delay in ms (5 min)            |
