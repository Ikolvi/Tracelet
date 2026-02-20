# Copilot Instructions — App-Facing Dart API (`packages/tracelet/`)

## Role of This Package
This is the **only package that app developers depend on**. It re-exports the public API and delegates
all platform calls to `tracelet_platform_interface`. It contains **zero** native code.

## Key Files
```
tracelet/
├── lib/
│   ├── tracelet.dart                  # Barrel export (the single import for consumers)
│   ├── src/
│   │   ├── tracelet.dart              # Main Tracelet class (static singleton API)
│   │   ├── models/                    # All public model classes
│   │   │   ├── config.dart            # Config + sub-configs
│   │   │   ├── location.dart
│   │   │   ├── state.dart
│   │   │   ├── geofence.dart
│   │   │   ├── geofence_event.dart
│   │   │   ├── provider_change_event.dart
│   │   │   ├── activity_change_event.dart
│   │   │   ├── http_event.dart
│   │   │   ├── heartbeat_event.dart
│   │   │   ├── headless_event.dart
│   │   │   ├── sensors.dart
│   │   │   ├── device_info.dart
│   │   │   └── ...
│   │   └── events/                    # EventChannel stream wrappers
│   └── tracelet.dart
├── test/                              # Unit tests (mock platform)
├── example/                           # Full demo app
└── pubspec.yaml
```

## Coding Rules for This Package

### API Design
- The `Tracelet` class uses **static methods only** (singleton pattern, like `BackgroundGeolocation`).
- Every public method returns a `Future<T>` (async) — never block.
- Event listeners use callback pattern: `Tracelet.onLocation((Location loc) { ... })`. Internally backed by EventChannel `Stream.listen()`.
- The `ready(Config)` method MUST be called before any other method. Document this prominently.
- All methods delegate to `TraceletPlatform.instance.methodName(...)`. No business logic in this package.

### Model Classes
- Every model has `factory Model.fromMap(Map<String, dynamic> map)` and `Map<String, dynamic> toMap()`.
- Use `_ensureBool()`, `_ensureInt()`, `_ensureDouble()` helpers for cross-platform type normalization (iOS returns int for bool, etc.).
- All model properties are `final`. Models are immutable.
- Override `toString()` for debug-friendly output.
- Override `==` and `hashCode` where identity comparison is needed.

### Config
- `Config` is a compound object with sub-configs: `GeoConfig`, `AppConfig`, `HttpConfig`, `LoggerConfig`, `MotionConfig`, `GeofenceConfig`.
- Sub-configs are optional in the constructor (have sensible defaults).
- `Config.toMap()` produces a flat map (merged keys) for backward compatibility, OR a nested map — decide in implementation.
- Provide `Config.fromMap()` that handles both flat and nested forms.

### Documentation
- Every public class, method, property, and parameter has `///` dartdoc comments.
- Include `/// Example` with code block in every method's doc.
- Use `{@macro tracelet.some_concept}` for shared documentation blocks.

### Testing
- Mock `TraceletPlatform` using `MockTraceletPlatform with MockPlatformInterfaceMixin`.
- Test that every `Tracelet.method()` calls the correct platform method with correct args.
- Test all model serialization round-trips with real-world JSON samples.
- Test edge cases: empty config, null optional fields, large location batches.

### Exports
- `tracelet.dart` barrel file exports everything a consumer needs. Consumer writes:
  ```dart
  import 'package:tracelet/tracelet.dart' as tl;
  ```
  The `as tl` namespace prefix is recommended to avoid class name conflicts (`Location`, `State`, etc.).
