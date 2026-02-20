# Copilot Instructions — Platform Interface (`packages/tracelet_platform_interface/`)

## Role of This Package
Defines the **contract** between the app-facing `tracelet` package and platform implementations
(`tracelet_android`, `tracelet_ios`). Contains the abstract `TraceletPlatform` class, Pigeon definitions,
and the default `MethodChannelTracelet` implementation.

## Key Files
```
tracelet_platform_interface/
├── lib/
│   ├── tracelet_platform_interface.dart   # Barrel export
│   ├── src/
│   │   ├── tracelet_platform.dart         # Abstract class (PlatformInterface)
│   │   ├── method_channel_tracelet.dart   # Default MethodChannel implementation
│   │   ├── types/                         # Shared type definitions
│   │   │   ├── config_types.dart
│   │   │   ├── location_types.dart
│   │   │   ├── event_types.dart
│   │   │   └── ...
│   │   └── event_channel_names.dart       # 14 EventChannel path constants
│   └── generated/                         # Pigeon-generated code (DO NOT EDIT)
│       └── tracelet_api.g.dart
├── pigeons/
│   └── tracelet_api.dart                  # Pigeon definition file (SOURCE OF TRUTH)
├── test/
└── pubspec.yaml
```

## Coding Rules for This Package

### TraceletPlatform (Abstract)
```dart
abstract class TraceletPlatform extends PlatformInterface {
  TraceletPlatform() : super(token: _token);
  static final Object _token = Object();

  static TraceletPlatform _instance = MethodChannelTracelet();
  static TraceletPlatform get instance => _instance;
  static set instance(TraceletPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // Every method from the public API is declared here as:
  Future<Map<String, dynamic>> ready(Map<String, dynamic> config) {
    throw UnimplementedError('ready() has not been implemented.');
  }
  // ... etc for ALL methods
}
```

- Every method **throws `UnimplementedError`** by default.
- Parameters and return types use `Map<String, dynamic>` or primitives — not model classes. Model classes live in the app-facing package. This keeps the interface lean.
- Platform implementations override these methods.

### MethodChannelTracelet (Default Implementation)
- Implements `TraceletPlatform`.
- Uses `MethodChannel('com.tracelet/methods')` for request/response calls.
- Uses 14 `EventChannel`s for streaming events.
- This is the **fallback** implementation. Platform packages may override with Pigeon-backed implementations for type safety.

### Pigeon Definitions (`pigeons/tracelet_api.dart`)
- **Source of truth** for the Dart↔Native communication contract.
- Define `@HostApi()` interface (`TraceletHostApi`) with all methods that Dart calls on Native.
- Define `@FlutterApi()` interface (`TraceletFlutterApi`) with callbacks that Native calls on Dart (headless events).
- Define Pigeon `class`es for all structured data — keep them flat (no nested Pigeon classes; flatten manually).
- Use `@ConfigurePigeon` to set output paths:
  ```dart
  @ConfigurePigeon(PigeonOptions(
    dartOut: 'lib/src/generated/tracelet_api.g.dart',
    kotlinOut: '../tracelet_android/android/src/main/kotlin/com/tracelet/generated/TraceletApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.tracelet.generated'),
    swiftOut: '../tracelet_ios/ios/Classes/generated/TraceletApi.g.swift',
  ))
  ```

### Generated Code
- Files in `lib/src/generated/` and platform equivalents are auto-generated. **Never edit manually.**
- Generated files ARE committed to version control (reproducible builds without build step).
- Re-generate with: `melos run pigeon` or `dart run pigeon --input pigeons/tracelet_api.dart`

### EventChannel Constants
```dart
const String kEventChannelBase = 'com.tracelet/events';
const String kEventLocation = '$kEventChannelBase/location';
const String kEventMotionChange = '$kEventChannelBase/motionchange';
// ... 12 more
```
- These constants are shared between Dart and used by Android/iOS to register handlers.
- Use the same string values on the native side.

### Testing
- Test that `TraceletPlatform` default methods throw `UnimplementedError`.
- Test that `MethodChannelTracelet` correctly serializes/deserializes method calls.
- Test Pigeon codec round-trips for all message types.
- Use `TestDefaultBinaryMessengerBinding` to mock MethodChannel calls.

### Versioning
- This package is versioned independently but stays in lockstep with `tracelet`.
- Breaking changes here require major version bumps in all packages.
