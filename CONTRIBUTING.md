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
- Rust Toolchain (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)
- Cargo NDK for Android (`cargo install cargo-ndk`)
- Flutter Rust Bridge Codegen (`cargo install flutter_rust_bridge_codegen`)

### Setup

```bash
# Clone the repo
git clone https://github.com/Ikolvi/Tracelet.git
cd Tracelet

# Bootstrap all packages
melos bootstrap

# Build the Rust Core bindings for native platforms
./sdk/rust-core/build-ios.sh
./sdk/rust-core/build-android.sh

# Generate Flutter/Dart bindings from Rust Core
cd packages/tracelet_platform_interface
flutter_rust_bridge_codegen generate
cd ../..

# Run all tests
melos run test

# Format and analyze — both gate every PR
melos run format:fix
melos run format
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

> **Every contribution follows the same seven steps, in this order.** Four of them
> are missed often enough to call out up front, and a PR that skips any of them
> will be sent back before review rather than reviewed as-is:
>
> 1. **An issue exists first**, and the PR closes it with `Fixes #N`.
> 2. **The example app gets an issue verification card**, so the change can be
>    exercised on a real device by anyone, forever — not just by you, once.
> 3. **`melos run format` and `melos run analyze` are clean** — run them last,
>    after every other change including the card, and re-run them after any
>    amend. This is the single most common reason a PR arrives red.
> 4. **CI is green** — including the native Kotlin and Swift test jobs, which do
>    not run under `melos run test` and are the ones most often left red.
>
> See the [Pull Request Checklist](#pull-request-checklist) before you open the PR.

### 1. Open an Issue First

**Every change starts as a GitHub issue — bug fixes and features alike, including
ones you found yourself.** Do this *before* writing code.

```bash
gh issue create --repo Ikolvi/Tracelet --label bug     # or --label enhancement
```

Use the [issue templates](.github/ISSUE_TEMPLATE). Write real reproduction
detail: the failing code excerpt, the device/OS, and the *mechanism* of the
failure — not a one-line summary. For a feature, state the use case and the
API you expect.

The issue number is not bookkeeping. It is the anchor the rest of the workflow
hangs off: it names your branch, it appears in code comments at the lines you
changed (`// Restart the chronometer from the persisted value (#360)`), it names
your example card file, and it is what a future maintainer lands on when they
`git blame` the line three releases from now. Opening the PR without one leaves
that trail with nothing at the end of it.

If a substantial change is coming, open the issue early and describe the
approach there. It is much cheaper to redirect a design in an issue thread than
in a 30-file PR.

### 2. Create a Branch

Branch off `main`, and name the branch after the issue:

```bash
git checkout -b feat/360-notification-chronometer
# or
git checkout -b fix/357-geofence-cadence
```

### 3. Make Changes

- Follow the coding conventions in the [Copilot instructions](.github/copilot-instructions.md)
- Write tests for new functionality
- Reference the issue number in comments at non-obvious lines (`(#360)`) — this
  is the existing house style throughout the codebase
- Ensure all tests pass: `melos run test`
- Keep formatting and analysis clean as you go: `melos run format:fix`, then
  `melos run format` and `melos run analyze` (both must exit 0). Step 5 runs the
  full gate again at the end, but fixing these here keeps the diff clean rather
  than adding a reformat commit on top of a review.

### 4. Add an Issue Verification Card to the Example App

**This step is required, and it is the one contributors most often do not know
about.** Every merged fix and feature in this repo has a matching card in the
example app, and yours needs one too.

A card is a small, self-contained panel in the example app's **Issues** tab that
proves the behaviour at runtime, on a real device. Dart unit tests cannot observe
a foreground-service notification, a Live Activity, a geofence transition, or a
GPS cadence — the card is how those are verified, and how a maintainer confirms
your change on hardware without reconstructing your setup by hand.

**a. Write the card** at `example/lib/issues/issue_<N>_card.dart`, where `<N>` is
your issue number. Use `IssueCardShell` — it provides the title, description,
monospace status box and Run button, and wires the card into the tab's search:

```dart
import 'package:flutter/material.dart';
import 'package:tracelet/tracelet.dart' hide State;
import 'package:tracelet_example/issues/issue_card_shell.dart';

/// Issue #360 — the ongoing notification must render an OS-driven timer that
/// survives a repost, instead of the app rewriting the text once a minute.
///
/// Explain here what the card can actually observe at runtime, and why that
/// observation is sufficient evidence the bug is fixed.
class Issue360Card extends StatefulWidget {
  const Issue360Card({super.key});

  @override
  State<Issue360Card> createState() => _Issue360CardState();
}

class _Issue360CardState extends State<Issue360Card> {
  String _status = 'Idle';
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    return IssueCardShell(
      title: '#360 — Notification chronometer',
      description: 'Starts tracking with showTimer, then reposts the '
          'notification and checks the timer did not restart.',
      status: _status,
      running: _running,
      keywords: 'notification chronometer timer setUsesChronometer',
      onRun: _run,
    );
  }
}
```

**b. Register it** in `example/lib/issues/recent_issues_tab.dart`: add the import
alongside the others, and add `const Issue360Card(),` **at the top of the card
list** — the list is ordered newest issue first.

**c. Run it on a device and make sure it passes.** The card is evidence, so it
has to actually run.

Two rules about what a card may claim:

- **State only what it can prove.** If the card can observe the timer ticking but
  cannot observe what the OS drew on the lock screen, say so in the status
  output and report the rest as context. A card that reports "✅ PASS" for
  something it never measured is worse than no card, because it will be trusted.
- **Make it runnable from a cold start.** `IssueCardShell` calls
  `prepareIssueRun()` before your `onRun` by default, so the card does not depend
  on the home page having been initialized or on whichever card ran before it.
  Set `prepare: false` only when the card must observe an unconfigured SDK.

Use the existing cards as reference — [`issue_357_card.dart`](example/lib/issues/issue_357_card.dart)
is a good example of a card that measures a physical behaviour honestly, and
documents why the measurement is valid while sitting still.

**d. Format and analyze the new file** before moving on:

```bash
melos run format:fix
melos run format
melos run analyze
```

A freshly written card is the single most likely thing in your PR to fail the
`Analyze & Format` CI job — it is new Dart the formatter has never touched, and
a card that stubs out a code path often leaves an unused field or import behind,
which `dart analyze --fatal-infos` treats as an error rather than a hint.

### 5. Run the Full Local Gate

**CI runs more than `melos run test`.** The Kotlin and Swift test suites gate
every PR, and they are where red builds usually come from — a Dart-only local
run will pass while `Build Android` fails. Run all of it before you push,
**after** the last change you intend to make:

```bash
# 1. Format + analyze — the "Analyze & Format" job.
#    Run these last: any later edit can undo them.
#
#    `format` rewrites files and exits non-zero when it changed something, so
#    the first run "fails" while reformatting. Run format:fix, then confirm
#    format is clean, then commit whatever it rewrote.
#
#    Never fall back to a bare `dart format .` at the repo root — it walks
#    example/build/ and reformats vendored packages.
melos run format:fix
melos run format      # must exit 0
melos run analyze     # must exit 0 — `--fatal-infos`, so hints fail too

# 2. Dart tests — the "Tests (<package>)" jobs.
melos run test

# 3. Rust core tests — the "Tests (rust-core)" job.
cd sdk/rust-core && cargo test && cd ../..

# 4. Build the host Rust library — the Kotlin tests load it via JNA.
cd sdk/rust-core && cargo build && cd ../..

# 5. Kotlin tests — part of the "Build Android" job. BOTH of these.
cd example/android && ./gradlew :tracelet_android:testDebugUnitTest && cd ../..
cd sdk/android && ./gradlew :tracelet-sdk:testDebugUnitTest :tracelet-sync-sdk:testDebugUnitTest && cd ../..

# 6. Swift tests — part of the "Build iOS" job (macOS only).
cd sdk/ios && swift test && cd ../..
```

If you touched `sdk/rust-core`, also regenerate and commit the bindings — see
[Rust Core Code Generation](#rust-core-code-generation). CI fails the
"Analyze & Format" job on uncommitted generated files.

> **A note on Swift tests:** a test file that is not listed in `sdk/ios/Package.swift`'s
> `sources:` array is silently never compiled or run, and the build still reports
> success. If you add a Swift test file, add it there too, and confirm your new
> test name actually appears in the `swift test` output.

### 6. Commit

Follow the commit message format:

```
type(scope): message

feat(android): add FusedLocationProvider integration
fix(ios): fix CLLocationManager delegate crash on iOS 14
test(dart): add Config serialization round-trip tests
```

**Types**: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`
**Scopes**: `dart`, `android`, `ios`, `interface`, `example`, `ci`, or omit for root-level

Include whatever `melos run format:fix` rewrote in the commit — a formatting-only
follow-up commit means the earlier ones were pushed unformatted. And if you amend
or add commits after review feedback, run `melos run format` and
`melos run analyze` again before pushing: they are only as current as your last
edit.

### 7. Submit a Pull Request

- **Include a `Fixes #N` line** in the PR body, one per issue the PR closes, so
  GitHub links and closes them on merge
- Describe the problem, the approach, and anything you deliberately did *not* do
- **Ensure every CI check is green before requesting review.** A PR with a red
  check is not ready, even when the failure looks unrelated to your change — if
  you believe it is unrelated, say so in a comment with the evidence rather than
  leaving it unexplained
- Request review from maintainers

## Pull Request Checklist

Copy this into your PR description and tick it off. A reviewer will check these
first, and a PR missing any of them goes back before it gets a code review.

```markdown
- [ ] A GitHub issue exists for this change, and the PR body says `Fixes #N`
- [ ] Branch is named after the issue (`fix/357-…` / `feat/360-…`)
- [ ] Non-obvious changed lines carry an issue reference comment (`(#N)`)
- [ ] Example app has `example/lib/issues/issue_<N>_card.dart`, registered at the
      top of the list in `recent_issues_tab.dart`, and it passes on a device
- [ ] The card claims only what it actually observes at runtime
- [ ] Tests added for the new behaviour (Dart, Kotlin and/or Swift as applicable)
- [ ] `melos run format` exits 0 (run `melos run format:fix` first, commit the result)
- [ ] `melos run analyze` exits 0 — `--fatal-infos`, so hints fail too
- [ ] Both were re-run after the last commit, including any amend
- [ ] `melos run test` passes
- [ ] `cargo test` in `sdk/rust-core` passes
- [ ] `:tracelet_android:testDebugUnitTest` and
      `:tracelet-sdk:testDebugUnitTest :tracelet-sync-sdk:testDebugUnitTest` pass
- [ ] `swift test` in `sdk/ios` passes (macOS)
- [ ] Regenerated bindings committed, if `sdk/rust-core` or the Pigeon API changed
- [ ] Every CI check on the PR is green
```

## Rust Core Code Generation

Tracelet relies on a shared Rust Core (`sdk/rust-core`) via `flutter_rust_bridge` for Dart and `UniFFI` for iOS/Android native code. 

**Note for Native SDK Contributors:** Because all generated bindings are checked into version control, you **do not** need to install Flutter or run the codegen tools if you are only working on the Android (Kotlin) or iOS (Swift) sides of the codebase! 

If you *do* modify files in `sdk/rust-core`, you must regenerate the bindings:

1. **Dart Bindings**:
   ```bash
   cd packages/tracelet_platform_interface
   flutter_rust_bridge_codegen generate
   cd ../..
   ```
2. **iOS Bindings** (Swift via UniFFI):
   ```bash
   ./sdk/rust-core/build-ios.sh
   ```
3. **Android Bindings** (Kotlin via UniFFI):
   ```bash
   ./sdk/rust-core/build-android.sh
   ```

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

Two separate suites, and **CI gates both** — the plugin's tests and the native
SDK's tests. Running only the first is the usual reason `Build Android` goes red
on a PR that passed locally.

```bash
# The Kotlin tests load the host Rust core via JNA — build it first.
cd sdk/rust-core && cargo build && cd ../..

# Flutter plugin layer
cd example/android
./gradlew :tracelet_android:testDebugUnitTest

# Standalone native SDK
cd ../../sdk/android
./gradlew :tracelet-sdk:testDebugUnitTest :tracelet-sync-sdk:testDebugUnitTest
```

### iOS Swift Tests
```bash
cd sdk/ios
swift test
```

New test files must also be added to the `sources:` array in
`sdk/ios/Package.swift`, or they are silently never run.

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

When the plugin is consumed from **pub.dev**, the podspec dependency `s.dependency 'TraceletSDK', '~> 1.0.0'` resolves from CocoaPods trunk.

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
melos run format:fix
melos run format
melos run analyze
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
6. **Issue first, card always** — every change has a GitHub issue behind it and a
   verification card in the example app in front of it

## Reporting Issues

Use the issue templates:
- **Bug Report**: Include device, OS version, plugin version, and reproduction steps
- **Feature Request**: Describe the use case and expected behavior

File the issue even when you intend to fix it yourself in the same sitting — it
is [step 1 of the development workflow](#1-open-an-issue-first), not an
alternative to contributing a fix.

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
