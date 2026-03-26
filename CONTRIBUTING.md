# Contributing to Tracelet

Thank you for considering contributing to Tracelet! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.

## Getting Started

### Prerequisites

- Flutter SDK 3.22+
- Dart SDK 3.4+
- Melos (`dart pub global activate melos`)
- Android Studio (for Android development)
- Xcode 15+ (for iOS development, macOS only)

### Setup

```bash
# Clone the repo
git clone https://ikolvi.com.git
cd tracelet

# Bootstrap all packages
melos bootstrap

# Run all tests
melos run test

# Run analyzer
melos run analyze
```

## Project Structure

This is a federated Flutter plugin with 4 packages:

| Package | Language | Purpose |
|---|---|---|
| `tracelet` | Dart | App-facing API |
| `tracelet_platform_interface` | Dart | Abstract interface + Pigeon definitions |
| `tracelet_android` | Kotlin | Android implementation |
| `tracelet_ios` | Swift | iOS implementation |

## Development Workflow

### 1. Create a Branch

```bash
git checkout -b feat/my-feature
# or
git checkout -b fix/my-bugfix
```

### 2. Make Changes

- Follow the coding conventions in the [Copilot instructions](.github/copilot-instructions.md)
- Write tests for new functionality
- Ensure all tests pass: `melos run test`
- Ensure no analyzer issues: `melos run analyze`
- Format code: `melos run format:fix`

### 3. Commit

Follow the commit message format:

```
type(scope): message

feat(android): add FusedLocationProvider integration
fix(ios): fix CLLocationManager delegate crash on iOS 14
test(dart): add Config serialization round-trip tests
```

**Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`
**Scopes**: `dart`, `android`, `ios`, `interface`, `example`, `ci`, or omit for root-level

### 4. Submit a Pull Request

- Fill out the PR template
- Ensure CI passes
- Request review from maintainers

## Pigeon Code Generation

When modifying the platform interface API:

1. Edit `packages/tracelet_platform_interface/pigeons/tracelet_api.dart`
2. Run: `melos run pigeon`
3. Commit the generated files alongside your changes

## Testing

### Dart Tests
```bash
melos run test
```

### Android Kotlin Tests
```bash
cd example/android
./gradlew :tracelet_android:testDebugUnitTest
```

### Coverage
```bash
melos run coverage
```

### Integration Tests
```bash
cd packages/tracelet/example
flutter test integration_test/
```

## Local Development with Native SDKs

Tracelet separates the **Flutter plugin layer** (`packages/tracelet_android`, `packages/tracelet_ios`) from the **standalone native SDKs** (`sdk/android`, `sdk/ios`). During local development, changes to native SDK source code are picked up automatically — no publishing required.

### How It Works

#### Android — Gradle Composite Builds

Both `packages/tracelet_android/android/settings.gradle` and `example/android/settings.gradle.kts` use Gradle's [composite build](https://docs.gradle.org/current/userguide/composite_builds.html) feature to substitute the Maven artifact with the local module:

```gradle
includeBuild("../../sdk/android") {
    dependencySubstitution {
        substitute(module("com.ikolvi:tracelet-sdk")).using(project(":tracelet-sdk"))
    }
}
```

When the plugin is consumed from **pub.dev**, the local `sdk/android` path doesn't exist, so Gradle resolves `com.ikolvi:tracelet-sdk` from Maven Central.

#### iOS — SPM (local) + CocoaPods (pub.dev)

The Flutter plugin's `Package.swift` references the SDK via a relative path:

```swift
.package(name: "TraceletSDK", path: "../../../../sdk/ios")
```

The example app's `Podfile` also overrides the CocoaPod:

```ruby
pod 'TraceletSDK', :path => '../../'
```

When the plugin is consumed from **pub.dev**, the podspec dependency `s.dependency 'TraceletSDK', '~> 0.1.0'` resolves from CocoaPods trunk.

### Making and Testing Native SDK Changes

```bash
# 1. Edit native SDK source directly
#    Android: sdk/android/tracelet-sdk/src/main/kotlin/...
#    iOS:     sdk/ios/Sources/TraceletSDK/...

# 2. Run the example app — local SDK changes are picked up automatically
cd example && flutter run

# 3. Run Android Kotlin tests (includes SDK compilation)
cd example/android && ./gradlew :tracelet_android:testDebugUnitTest

# 4. Run iOS Swift tests
cd sdk/ios && swift test

# 5. Validate everything
melos run analyze
melos exec -- "dart format --set-exit-if-changed ."
```

### For External Contributors (git-based override)

If you're testing a fork or branch against your own app (not the monorepo), add overrides to your `pubspec.yaml`:

```yaml
dependency_overrides:
  tracelet:
    git:
      url: https://github.com/YourFork/Tracelet.git
      ref: your-branch
      path: packages/tracelet
  tracelet_android:
    git:
      url: https://github.com/YourFork/Tracelet.git
      ref: your-branch
      path: packages/tracelet_android
  tracelet_ios:
    git:
      url: https://github.com/YourFork/Tracelet.git
      ref: your-branch
      path: packages/tracelet_ios
  tracelet_platform_interface:
    git:
      url: https://github.com/YourFork/Tracelet.git
      ref: your-branch
      path: packages/tracelet_platform_interface
```

> **Note:** Git-based overrides include the native SDK source (since it's in the same repo), so composite build substitution works. However, for production use, the native SDK must be published to Maven Central / CocoaPods trunk.

## Golden Rules

1. **Never copy code from flutter_background_geolocation** — all native code is original
2. **Type-safety first** — use Pigeon, avoid `dynamic`
3. **Battery consciousness** — never poll, use event-driven APIs
4. **Error handling** — never swallow exceptions
5. **Test everything** — ≥90% coverage for Dart, comprehensive native tests

## Reporting Issues

Use the issue templates:
- **Bug Report**: Include device, OS version, plugin version, and reproduction steps
- **Feature Request**: Describe the use case and expected behavior

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
