# Copilot Instructions — Android Implementation (`packages/tracelet_android/`)

## Role of This Package
Kotlin-native Android implementation of the Tracelet plugin. Implements `TraceletPlatform` using
FusedLocationProviderClient, Activity Recognition, GeofencingClient, Room, OkHttp, and WorkManager.
**All code is original** — never reference or copy from transistorsoft SDKs.

## Key Files
```
tracelet_android/
├── android/
│   ├── src/main/
│   │   ├── AndroidManifest.xml
│   │   ├── kotlin/com/tracelet/
│   │   │   ├── TraceletPlugin.kt              # FlutterPlugin + ActivityAware entry point
│   │   │   ├── TraceletForegroundService.kt   # Foreground service (TYPE_LOCATION)
│   │   │   ├── engine/
│   │   │   │   ├── LocationEngine.kt          # FusedLocationProviderClient wrapper
│   │   │   │   ├── MotionDetector.kt          # ActivityRecognition + accelerometer
│   │   │   │   ├── GeofenceManager.kt         # GeofencingClient wrapper
│   │   │   │   └── SensorFusionManager.kt     # Accelerometer/gyro shake detection
│   │   │   ├── db/
│   │   │   │   ├── TraceletDatabase.kt        # Room database
│   │   │   │   ├── LocationDao.kt
│   │   │   │   ├── GeofenceDao.kt
│   │   │   │   ├── LogDao.kt
│   │   │   │   └── entities/                  # Room entity classes
│   │   │   ├── http/
│   │   │   │   └── HttpSyncManager.kt         # OkHttp + WorkManager sync
│   │   │   ├── headless/
│   │   │   │   └── HeadlessTaskService.kt     # Background FlutterEngine runner
│   │   │   ├── receivers/
│   │   │   │   ├── BootCompletedReceiver.kt
│   │   │   │   └── GeofenceBroadcastReceiver.kt
│   │   │   ├── scheduling/
│   │   │   │   └── ScheduleManager.kt
│   │   │   ├── logging/
│   │   │   │   └── TraceletLogger.kt
│   │   │   ├── sound/
│   │   │   │   └── SoundManager.kt
│   │   │   ├── permission/
│   │   │   │   └── PermissionManager.kt
│   │   │   ├── config/
│   │   │   │   ├── ConfigManager.kt
│   │   │   │   └── StateManager.kt
│   │   │   ├── streams/
│   │   │   │   ├── StreamHandler.kt           # Base EventChannel handler
│   │   │   │   ├── LocationStreamHandler.kt
│   │   │   │   ├── MotionChangeStreamHandler.kt
│   │   │   │   └── ...                        # 12 more stream handlers
│   │   │   ├── util/
│   │   │   │   ├── BatteryUtils.kt
│   │   │   │   ├── DeviceInfo.kt
│   │   │   │   └── OdometerCalculator.kt
│   │   │   └── generated/
│   │   │       └── TraceletApi.g.kt           # Pigeon-generated (DO NOT EDIT)
│   │   └── res/raw/                           # Debug sound files (.ogg)
│   ├── build.gradle.kts
│   └── proguard-rules.pro
├── lib/
│   └── tracelet_android.dart                  # Dart registration + TraceletAndroid class
├── test/
└── pubspec.yaml
```

## Coding Rules for This Package

### Kotlin Style
- **Language version**: Kotlin 1.9+ (match Flutter's Kotlin version).
- Use `data class` for simple value types.
- Use `sealed class` / `sealed interface` for state machines (motion state, tracking state).
- Use Kotlin coroutines (`suspend fun`, `CoroutineScope`) for async operations. Avoid raw threads.
- Use `kotlinx.coroutines.Dispatchers.IO` for DB/network, `Dispatchers.Main` for platform channel callbacks.
- Prefer `val` over `var`. Prefer immutability.
- Null safety: use `?` only when value is genuinely optional. No `!!` — use `requireNotNull()` or safe calls.
- Name constants in `UPPER_SNAKE_CASE` inside `companion object`.

### Architecture Patterns
- **Single Activity reference**: `TraceletPlugin` holds the `Activity?`. Pass via constructor/setter to managers that need it (PermissionManager, SoundManager).
- **Singleton managers**: `LocationEngine`, `MotionDetector`, `GeofenceManager`, `HttpSyncManager` — one instance, created in `TraceletPlugin.onAttachedToEngine()`, torn down in `onDetachedFromEngine()`.
- **EventChannel dispatch**: Each stream handler holds an `EventSink?`. Set on `onListen`, cleared on `onCancel`. Always null-check before emitting: `eventSink?.success(data)`.
- **Thread model**:
  - ALL platform channel calls arrive on **Main thread**. Reply on Main thread.
  - `LocationCallback`, `ActivityTransitionCallback` arrive on **Main thread** (Fused API default).
  - DB writes → coroutine on `Dispatchers.IO`.
  - HTTP sync → coroutine on `Dispatchers.IO`.
  - EventChannel `.success()` → **must be on Main thread**. Use `withContext(Dispatchers.Main)` if needed.

### Foreground Service (Critical)
```kotlin
// Android 14+ (API 34): MUST specify foregroundServiceType
ServiceCompat.startForeground(
    this, NOTIFICATION_ID, notification,
    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
)
```
- Declare `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>` in manifest.
- Create `NotificationChannel` before starting foreground service (Android 8+).
- The service MUST be started from foreground context (Activity or while `ACCESS_BACKGROUND_LOCATION` is granted).
- Handle `stopOnTerminate: false` by keeping the service alive after `onTaskRemoved`.

### Location Engine
- Prefer `PendingIntent`-based location updates for background reliability (survives process death).
- `LocationRequest.Builder` — ALWAYS set `setMinUpdateDistanceMeters()` from `distanceFilter`. This is KEY for battery savings.
- ALWAYS validate location results: filter out `accuracy > threshold`, `speed < 0`, `time == 0`.
- Generate UUID (`java.util.UUID.randomUUID()`) for each recorded location.

### Room Database
- Define `@Database(entities = [...], version = N)` with explicit migration paths.
- Use `@Dao` interfaces with `suspend fun` for all queries.
- NEVER run DB queries on Main thread — Room will throw.
- Use `allowMainThreadQueries()` ONLY in tests.
- Define indexes on `synced` (for HTTP sync) and `created_at` (for queries).

### Permissions
- Android 11+ (API 30): `ACCESS_BACKGROUND_LOCATION` MUST be requested **separately** from foreground location.
- Show `PermissionRationale` dialog before requesting background location.
- Return standardized status codes: 0=DENIED, 1=WHEN_IN_USE, 2=ALWAYS, 3=DENIED_FOREVER.
- Check `shouldShowRequestPermissionRationale()` to detect "Don't ask again".

### Build Configuration
- `minSdk = 26` (Android 8.0 — Oreo)
- `compileSdk = 35` (latest)
- `targetSdk = 35`
- Java target compatibility: 17
- Don't add `applicationId` — this is a library, not an app.

### Error Handling
- Every Pigeon HostApi method must catch exceptions and return error via `FlutterError`.
- Use `try/catch` around all `FusedLocationProviderClient`, `GeofencingClient`, and `Room` calls.
- Common error codes: `LOCATION_UNAVAILABLE`, `PERMISSION_DENIED`, `TIMEOUT`, `DB_ERROR`, `HTTP_ERROR`, `SERVICE_ERROR`.
- Log all errors via `TraceletLogger` before propagating.

### Testing
- Use Robolectric (`@RunWith(RobolectricTestRunner.class)`) for unit tests needing Android context.
- Use Room's `inMemoryDatabaseBuilder()` for DB tests.
- Mock `FusedLocationProviderClient` and `GeofencingClient` with Mockito-Kotlin.
- Test `MotionDetector` state transitions as a state machine (STATIONARY → MOVING → STATIONARY).
- Test `HttpSyncManager` retry logic with `MockWebServer` (OkHttp testing lib).
