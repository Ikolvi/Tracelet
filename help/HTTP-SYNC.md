# HTTP Sync Guide

Tracelet's HTTP sync engine uploads recorded locations from the local SQLite
database to your server. It handles batching, retry with exponential backoff,
connectivity monitoring, and offline queuing — all configurable from Dart.

---

## Quick Start

```dart
await Tracelet.ready(Config.balanced().copyWith(
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
`"location"`). Extra static fields can be injected at the **root** of the body
via `extras` (and as query parameters / extra fields via `params`). This covers
most server schemas without any code — see
[Do I need a custom sync body builder?](#do-i-need-a-custom-sync-body-builder)
before reaching for `setSyncBodyBuilder`.

---

## Interval-Based Sync

By default, `autoSync` flushes locations to the server each time one is
recorded. For fleet/logistics apps that need a **fixed business-defined
cadence**, set `syncInterval`:

```dart
HttpConfig(
  url: 'https://api.example.com/locations',
  autoSync: true,
  syncInterval: 45,   // Flush every 45 seconds
  batchSync: true,     // Recommended with interval sync
)
```

### How It Works

| syncInterval | Behavior |
|---|---|
| `0` (default) | Sync on every location insert (original behavior) |
| `> 0` | A repeating timer fires every N seconds and flushes all pending locations |

When `syncInterval > 0`:
- `onLocationInserted()` **does not** trigger a sync — the timer handles it.
- The timer calls the same sync engine used by manual `Tracelet.sync()`.
- If a sync is already in progress when the timer fires, it's skipped (no overlap).
- The timer respects `disableAutoSyncOnCellular` — if active, the timer-triggered sync checks connectivity before proceeding.
- `autoSync` must be `true` for the timer to start.
- Maximum value: `3600` (1 hour). Values above are clamped.

### Recommended Pairings

| Config | Why |
|---|---|
| `batchSync: true` | Multiple locations accumulate between timer ticks — send them in one request |
| `maxBatchSize: 50` | Prevent very large batches if interval is long |

### Manual Sync Still Works

`Tracelet.sync()` works normally regardless of `syncInterval`. Use it for
force-flush scenarios (e.g., trip end, app foregrounding).

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

With a custom sync body builder, a request that **times out after its body was
sent** is not retried: the server may already be processing it, and a retry
would deliver the batch twice. The rows stay queued for the next sync
([#437](https://github.com/Ikolvi/Tracelet/issues/437)).

### What's NOT Retried (Permanent Errors)

| Status Code | Meaning                | Retried? |
|-------------|------------------------|----------|
| `400`       | Bad Request             | ❌ No    |
| `401`       | Unauthorized            | 🔄 Special (see [401 Authorization Retry](#401-authorization-retry)) |
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

- **Nothing triggered mid-sync is dropped.** A location recorded while a batch
  is uploading is picked up by the same run before it finishes.
- **Oldest first.** Batches are always taken oldest-first.
  `locationsOrderDirection` sets the order of the locations *inside* each
  request, not which rows are sent.
- **A failure ends the run.** The rows stay queued, and the next trigger
  (a new location, `syncInterval`, or `sync()`) tries again, so a down server
  is not hammered in a loop.
- **Manual and automatic syncs don't overlap.** `sync()` waits for an
  auto-sync in progress, so the same rows are never sent twice by the two.

On 3.8.8 and earlier, auto-sync uploaded one batch per newly recorded location
and dropped triggers that arrived during an upload, so with `maxBatchSize: 1`
the queue never shrank ([#437](https://github.com/Ikolvi/Tracelet/issues/437)).

---

## Trip Summaries

Every completed trip is stored once on the device, under the `trip_id` its
locations and driving events carry, and goes out with the next sync as a
**root-level `trips` array**, in the same POST as `location` (and `telematics`):

```json
{
  "location": [ ... ],
  "trips": [
    {
      "trip_id": "9f2c0f1e-4c31-4b2a-9a77-1d0f3b5e7c88",
      "started_at": "2026-08-20T08:52:11.000Z",
      "ended_at": "2026-08-20T09:14:11.000Z",
      "distance": 18420.0,
      "duration": 1320.0,
      "average_speed": 13.95,
      "start_location": { "latitude": 24.81, "longitude": 67.05 },
      "stop_location": { "latitude": 24.8607, "longitude": 67.0011 },
      "synced": false
    }
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `trip_id` | String | The trip's UUIDv4 — join key with `location` and `telematics` rows |
| `started_at` / `ended_at` | ISO 8601 | Trip bounds, UTC |
| `distance` | double | Metres along the trip's waypoints |
| `duration` | double | Seconds |
| `average_speed` | double | `distance / duration` in m/s; `0` for a zero-length trip |
| `start_location` / `stop_location` | object or null | `{latitude, longitude}`; null when no fix was available |
| `synced` | bool | Always `false` in a payload |

- **One summary per trip**, keyed on `trip_id`. Use it as your upsert key in
  case a retry delivers the same request again.
- **Marked sent only when the request succeeds**; a failed flush leaves the
  trip pending. A trip that ends after its last location was uploaded still
  goes out on its own request.
- **`trips` is absent when there is nothing to send**, and existing consumers
  can ignore it.
- **Custom body builders** receive the same objects as `context.trips`
  (headless: `event['trips']`). Include them — a trip handed to the builder is
  marked sent once the request succeeds.
- The device keeps up to 1,000 summaries; beyond that the oldest are dropped.
- Trip detection runs in the SDK session. A journey made entirely under
  killed-state tracking (after the process was restarted) produces no trip
  and no summary; its locations carry `trip_id: null`.

Added in [#401](https://github.com/Ikolvi/Tracelet/issues/401); before it, the
summary only existed as the `onTrip()` event.

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
  autoSyncDelay: 10000,   // Delay in ms before dispatching the request
  batchSync: true,
)
```

This is useful for battery savings — instead of one HTTP request per
location, the engine waits until a threshold is reached or groups rapid updates into a single batch using the debounce delay.

The threshold counts every queued location, and is checked when a new one is
recorded. A parked device that stays below it records nothing new, so pair a
threshold with `syncInterval` if the last few points must still go out. On
3.8.8 and earlier the threshold was ignored on Android and iOS
([#437](https://github.com/Ikolvi/Tracelet/issues/437)).

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

## 401 Authorization Retry

When the server returns **401 Unauthorized**, Tracelet can automatically
refresh your authorization token and retry the request — even when the app
is killed (headless mode).

### How It Works

1. HTTP sync receives a `401` response
2. Tracelet invokes the headless headers callback registered via
   `registerHeadlessHeadersCallback()`
3. Your Dart callback refreshes the token and calls
   `Tracelet.setDynamicHeaders()` with updated headers
4. The original request is retried **once** with the refreshed headers
5. If the retry also fails, it's treated as a permanent failure

This works in both **foreground** (app is open) and **killed-state**
(headless) modes. In headless mode, Tracelet spins up a temporary Dart
isolate to execute your callback.

### Setup

```dart
// 1. Register the headless headers callback (top-level or static function)
@pragma('vm:entry-point')
static void onHeadersRefresh(HeadlessEvent event) async {
  final refreshToken = await secureStorage.read(key: 'refreshToken');
  final response = await http.post(
    Uri.parse('https://auth.example.com/token'),
    body: {'refresh_token': refreshToken},
  );
  final newToken = jsonDecode(response.body)['access_token'];
  await Tracelet.setDynamicHeaders({
    'Authorization': 'Bearer $newToken',
  });
}

// 2. Register during app initialization
await Tracelet.registerHeadlessHeadersCallback(onHeadersRefresh);

// 3. Also set a foreground callback for proactive refresh
Tracelet.setHeadersCallback(() async {
  final token = await authService.getFreshToken();
  return {'Authorization': 'Bearer $token'};
});
```

### Timeout

The native side waits up to **10 seconds** for the Dart callback to call
`setDynamicHeaders()`. If the callback doesn't respond in time (e.g.,
network timeout during token refresh), the 401 is treated as a permanent
failure and sync stops for that batch.

### Platform Details

| | Android | iOS |
|---|---|---|
| Synchronization | `CountDownLatch` | `DispatchSemaphore` |
| Headless channel | `com.tracelet/methods` on headless engine | `com.tracelet/methods` on headless engine |
| Timeout | 10 seconds | 10 seconds |

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
| `autoSyncDelay`             | `int`             | `10000`    | Delay before auto-sync dispatch in ms      |
| `httpTimeout`               | `int`             | `60000`    | Request timeout in ms                      |
| `params`                    | `Map`             | `{}`       | Extra body parameters                      |
| `locationsOrderDirection`   | `LocationOrder`   | `asc`      | Sort order for pending locations           |
| `extras`                    | `Map`             | `{}`       | Extra data on each location                |
| `disableAutoSyncOnCellular` | `bool`            | `false`    | Wi-Fi-only auto-sync                       |
| `maxRetries`                | `int`             | `10`       | Max retry attempts for transient failures  |
| `retryBackoffBase`          | `int`             | `1000`     | Base backoff delay in ms                   |
| `retryBackoffCap`           | `int`             | `300000`   | Max backoff delay in ms (5 min)            |
| `sslPinningCertificates`    | `List<String>`    | `[]`       | Base64 X.509 certificates for SSL pinning  |
| `sslPinningFingerprints`    | `List<String>`    | `[]`       | SHA-256 fingerprints (`sha256/...`)        |

---

## Dynamic Headers

Static headers defined in `HttpConfig.headers` are set at initialization time
and don't change. **Dynamic headers** let you update HTTP headers at runtime
without reconfiguring the plugin — perfect for OAuth token refresh.

### Basic Usage

```dart
// Set headers that change at runtime (e.g., after token refresh)
await Tracelet.setDynamicHeaders({
  'Authorization': 'Bearer $freshToken',
  'X-Session-Id': sessionId,
});
```

Dynamic headers are merged with static `HttpConfig.headers` before each
request. When keys overlap, **dynamic headers win**.

### Automatic Refresh via Callback

For seamless OAuth integration, register a callback that provides fresh
headers on demand:

```dart
Tracelet.setHeadersCallback(() async {
  final token = await authService.getFreshToken();
  return {'Authorization': 'Bearer $token'};
});
```

The callback is invoked before each foreground sync request. Call
`Tracelet.refreshHeaders()` to force a manual refresh.

### Platform Behavior

| | Android | iOS |
|---|---|---|
| Storage | `@Volatile` field in `ConfigManager` | Volatile property in `ConfigManager` |
| Merge point | `getMergedHttpHeaders()` in `HttpSyncManager.sendRequest()` | `getMergedHttpHeaders()` in `HttpSyncManager.sendRequest()` |
| Thread safety | Volatile read on sync thread | Main-thread access |

---

## Route Context

Route context lets you tag locations with business-level metadata — task IDs,
driver IDs, session IDs — that travels with each location through the sync
queue.

### Setting Context

```dart
await Tracelet.setRouteContext(RouteContext(
  taskId: 'delivery-42',
  driverId: 'driver-7',
  trackingSessionId: uuid.v4(),
  startedAt: DateTime.now().toIso8601String(),
  custom: {'region': 'eu-west'},
));
```

### Clearing Context

```dart
await Tracelet.clearRouteContext();
```

### RouteContext Fields

| Field | Type | Description |
|---|---|---|
| `ownerId` | `String?` | Business owner identifier |
| `driverId` | `String?` | Driver or user identifier |
| `taskId` | `String?` | Task, order, or delivery identifier |
| `trackingSessionId` | `String?` | Unique session ID |
| `startedAt` | `String?` | ISO 8601 session start time |
| `custom` | `Map<String, String>` | Arbitrary key-value metadata |

### How It Works

Route context is **volatile** on the native side — it is not persisted to
UserDefaults/SharedPreferences or the SQLite database. The Dart layer captures
the context at the time each location is recorded and attaches it to the
location data before persistence. This means:

- Changing context mid-session only affects **future** locations
- Previously recorded locations retain their original context
- Context survives across sync retries (it's part of the location payload)

---

## SSL Pinning

SSL pinning ensures your app only communicates with servers presenting known
certificates, preventing man-in-the-middle attacks even if the device's
certificate store is compromised.

### Fingerprint Pinning (recommended)

Pin by SHA-256 certificate fingerprint — easy to rotate and doesn't require
embedding full certificates:

```dart
Config(
  http: HttpConfig(
    url: 'https://api.example.com/locations',
    sslPinningFingerprints: [
      'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=', // backup
    ],
  ),
)
```

**To get your server's fingerprint:**

```bash
openssl s_client -connect api.example.com:443 < /dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 \
  | sed 's/://g' \
  | awk -F= '{print "sha256/" $2}' \
  | base64
```

### Certificate Pinning

Pin by embedding the full Base64-encoded X.509 certificate:

```dart
Config(
  http: HttpConfig(
    url: 'https://api.example.com/locations',
    sslPinningCertificates: [
      'MIIBkTCB+wIJAL...base64...==',
    ],
  ),
)
```

### Platform Implementation

| | Android | iOS |
|---|---|---|
| Fingerprint pinning | OkHttp `CertificatePinner` | `URLSessionDelegate` with `SecTrust` + `CC_SHA256` |
| Certificate pinning | OkHttp `HandshakeCertificates` (okhttp-tls) | `URLSessionDelegate` with `SecCertificate` comparison |
| Failure behavior | Connection refused, logged as error | Connection refused, logged as error |

### Best Practices

- Always include a **backup fingerprint** for certificate rotation
- Test with `openssl` before deploying
- Pin leaf certificates, not root CAs (more secure, less fragile)
- When rotating certificates, deploy the new fingerprint to the app **before** rotating the server certificate

---

## Custom Sync Body Builder

By default, Tracelet sends locations in a standard JSON format wrapped in a
root property. The sync body builder lets you **fully control** the HTTP
request body — restructure the payload, add metadata, filter fields, or
match any server API schema.

### Do I need a custom sync body builder?

**Most apps don't.** The default body already nests your locations under
`httpRootProperty` and injects your `HttpConfig.extras` at the root, which
matches the large majority of server schemas through config alone — and it
works identically in foreground, background, and killed state with nothing
extra to register.

**You do NOT need a builder** if your server accepts a body like this:

```json
{
  "location": [ /* batch of location records */ ],
  "is_live_ping": false,
  "meta": { "appVersion": "2.1.0", "platform": "android" }
}
```

Produce it entirely from `HttpConfig`:

```dart
http: tl.HttpConfig(
  url: 'https://api.example.com/telemetry',
  headers: { 'Authorization': 'Bearer $token' },
  httpRootProperty: 'location',   // key the locations array sits under (default)
  extras: {                       // injected at the ROOT of the body
    'is_live_ping': false,
    'meta': { 'appVersion': '2.1.0', 'platform': 'android' },
  },
),
```

**You DO need a custom builder only when:**

- the body must be built **dynamically per sync** — a value that changes between
  syncs and can't be a static `extras` set once at `ready()`; **or**
- the schema can't be expressed as "locations under one root key + flat extras"
  (locations must be renamed/reshaped, split across fields, or nested
  differently).

| Your need | Use |
|---|---|
| Default body, optionally with static extra fields | `HttpConfig.extras` + `httpRootProperty` — **no builder** |
| Dynamic auth token in background/killed state | `registerHeadlessHeadersCallback` (token refresh) — still **no body builder** |
| A body shape config can't express | `setSyncBodyBuilder` (foreground) **and** `registerHeadlessSyncBodyBuilder` (background/killed) |

> ⚠️ **If you use a custom builder _and_ need background/killed-state sync, you
> must register the [headless](#headless-background-callbacks) variant too.** The
> foreground `setSyncBodyBuilder` cannot run while the app is suspended —
> registering only it means background syncs have no body to send and are
> deferred until the app is next opened (a common cause of "locations stored but
> not syncing on the fly").

### Foreground Usage

```dart
Tracelet.setSyncBodyBuilder((SyncBodyContext context) async {
  // Map the locations, noting that coords and activity are nested objects!
  final mappedPoints = context.locations.map((loc) {
    final coords = loc['coords'] as Map;
    final activity = loc['activity'] as Map;
    
    return {
      'lat': coords['latitude'],
      'lng': coords['longitude'],
      'timestamp': loc['timestamp'],
      'is_moving': loc['is_moving'],
      'activity_type': activity['type'],
    };
  }).toList();

  return {
    'deviceId': myDeviceId,
    'taskId': currentTaskId,
    'points': mappedPoints,
    'sentAt': DateTime.now().toIso8601String(),
    'metadata': {'appVersion': '2.1.0'},
  };
});
```

The callback receives a `SyncBodyContext` containing the batch of locations. Note that the locations conform to the nested schema defined in [LOCATION-MAP-FORMAT.md](LOCATION-MAP-FORMAT.md).
The returned `Map` is JSON-encoded and used as the **complete** HTTP request
body — `httpRootProperty`, `params`, and default wrapping are all bypassed.

Pass `null` to clear the builder and revert to the default format:

```dart
Tracelet.setSyncBodyBuilder(null);
```

### SyncBodyContext Fields

| Field | Type | Description |
|---|---|---|
| `locations` | `List<Map<String, Object?>>` | Batch of location maps about to be synced |

### How It Works

When the native sync engine is about to send a batch, it invokes the
`onBuildCustomSyncBody` callback. In foreground mode, this calls Dart via
a dedicated `com.tracelet/sync_body` MethodChannel:

```
Native sync thread                    Main thread                     Dart
────────────────                      ───────────                     ────
onBuildCustomSyncBody()
  ├─ post to main ──────────────────► invokeMethod("buildSyncBody")
  │                                     ├────────────────────────────► setSyncBodyBuilder callback
  │                                     │                               ├─ build custom Map
  │   (blocked on latch/semaphore)      │  ◄────────────────────────────┤ return JSON string
  │  ◄──────────────────────────────────┘
  ├─ use custom JSON as request body
  └─ send HTTP request
```

The MethodChannel handler is set up lazily on the first call to
`setSyncBodyBuilder()`. The native side blocks its sync thread (not the
main thread) for up to **10 seconds** waiting for the Dart response.

### Platform Details

| | Android | iOS |
|---|---|---|
| Channel | `MethodChannel("com.tracelet/sync_body")` | `FlutterMethodChannel("com.tracelet/sync_body")` |
| Sync mechanism | `CountDownLatch` on sync executor | `DispatchSemaphore` on sync queue |
| Timeout | 10 seconds | 10 seconds |
| Fallback | Headless `requestCustomSyncBody()` | Default body if `nil` returned |
| Body encoding | JSON string returned from Dart | JSON string returned from Dart |

---

## Headless (Background) Callbacks

When the app is terminated (killed state), the native sync engine runs without
the Flutter engine. To support token refresh and custom payloads in this state,
register headless callbacks.

### Headless Headers Callback

Handles 401 responses in the background by refreshing auth tokens:

```dart
@pragma('vm:entry-point')
static void myHeadlessHeadersCallback(HeadlessEvent event) async {
  // Read refresh token from secure storage
  final refreshToken = await secureStorage.read('refreshToken');
  final newToken = await authApi.refresh(refreshToken);

  // Update headers — native side retries the failed request
  await Tracelet.setDynamicHeaders({
    'Authorization': 'Bearer $newToken',
  });
}

// Register during app startup:
await Tracelet.registerHeadlessHeadersCallback(myHeadlessHeadersCallback);
```

### Headless Sync Body Builder

Produces custom request bodies in the background when the app is killed:

```dart
@pragma('vm:entry-point')
static void myHeadlessSyncBody(HeadlessEvent event) async {
  final locations = event.event['locations'] as List;
  final body = {
    'deviceId': await getDeviceId(),
    'points': locations,
  };

  // Send the custom body back to the native sync engine
  await Tracelet.setSyncBodyResponse(body);
}

// Register during app startup:
await Tracelet.registerHeadlessSyncBodyBuilder(myHeadlessSyncBody);
```

The headless callback receives a `HeadlessEvent` with `name == 'syncBodyBuild'`.
You **must** call `Tracelet.setSyncBodyResponse()` to return the custom body
to the native side — the native sync thread blocks on a latch/semaphore
waiting for this response (10-second timeout).

### Requirements

- Callbacks must be **top-level or static** functions
- Annotate with `@pragma('vm:entry-point')` to prevent tree-shaking
- Register during `Tracelet.ready()` initialization
- The native side stores callback handles in UserDefaults (iOS) / SharedPreferences (Android)
