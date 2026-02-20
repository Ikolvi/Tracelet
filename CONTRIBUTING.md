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

### Coverage
```bash
melos run coverage
```

### Integration Tests
```bash
cd packages/tracelet/example
flutter test integration_test/
```

## Golden Rules

1. **Never copy code from transistorsoft** — all native code is original
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
