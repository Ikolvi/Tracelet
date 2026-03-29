# Publishing Guide

> Complete reference for releasing Tracelet — native SDKs and Flutter packages.

## Architecture Overview

Tracelet ships **three independent distribution channels**:

| Channel | Artifact | Registry | Current Version |
|---------|----------|----------|-----------------|
| Android SDK | `com.ikolvi:tracelet-sdk` | Maven Central | See `sdk/android/gradle.properties` |
| iOS SDK | `TraceletSDK` | CocoaPods / SPM | See `TraceletSDK.podspec` |
| Flutter | 5 federated packages | pub.dev | See `packages/tracelet/pubspec.yaml` |

The native SDKs (Android + iOS) version independently from Flutter packages. Flutter packages are always version-locked together.

---

## Publishing Order

```
┌──────────────────────────────────────────────────────────┐
│  1. Native SDKs (independent, can publish in parallel)   │
│     ├── Android SDK → Maven Central                      │
│     └── iOS SDK     → CocoaPods                          │
├──────────────────────────────────────────────────────────┤
│  2. Flutter packages (strict sequential order)           │
│     ├── tracelet_platform_interface  (no Tracelet deps)  │
│     ├── tracelet_android             (depends on ^above) │
│     ├── tracelet_ios                 (depends on ^above) │
│     ├── tracelet_web                 (depends on ^above) │
│     └── tracelet                     (depends on all)    │
└──────────────────────────────────────────────────────────┘
```

**Why this order matters:**
- pub.dev resolves dependencies at publish time — a package cannot reference a version that doesn't exist yet.
- `tracelet_android`, `tracelet_ios`, and `tracelet_web` all depend on `tracelet_platform_interface`, so interface must be published first.
- The app-facing `tracelet` package depends on all implementations, so it publishes last.

---

## Pre-Release Checklist

Before triggering a release, update these files manually:

### Flutter packages (all 5 must match)
- [ ] `packages/tracelet/pubspec.yaml` — bump `version:`
- [ ] `packages/tracelet_platform_interface/pubspec.yaml` — bump `version:`
- [ ] `packages/tracelet_android/pubspec.yaml` — bump `version:` + update `tracelet_platform_interface: ^X.Y.Z`
- [ ] `packages/tracelet_ios/pubspec.yaml` — bump `version:` + update `tracelet_platform_interface: ^X.Y.Z`
- [ ] `packages/tracelet_web/pubspec.yaml` — bump `version:` + update `tracelet_platform_interface: ^X.Y.Z`
- [ ] `packages/tracelet/pubspec.yaml` — update dependencies for `tracelet_android`, `tracelet_ios`, `tracelet_web` to `^X.Y.Z`
- [ ] All 5 `CHANGELOG.md` files — add entry with `**FEAT**:` / `**FIX**:` / `**PERF**:` prefix

### Android SDK (only if native SDK changed)
- [ ] `sdk/android/gradle.properties` — update `SDK_VERSION=X.Y.Z`
- [ ] `sdk/android/CHANGELOG.md`

### iOS SDK (only if native SDK changed)
- [ ] `TraceletSDK.podspec` (repo root) — update `s.version`
- [ ] `sdk/ios/CHANGELOG.md`

### Cross-package dependency constraints
When publishing version X.Y.Z, ensure all `^X.Y.Z` constraints point to the version being published:
```yaml
# tracelet_android/pubspec.yaml
tracelet_platform_interface: ^X.Y.Z  # ← must match

# tracelet/pubspec.yaml
tracelet_android: ^X.Y.Z             # ← must match
tracelet_ios: ^X.Y.Z                 # ← must match
tracelet_web: ^X.Y.Z                 # ← must match
tracelet_platform_interface: ^X.Y.Z  # ← must match
```

---

## Automated Release (Recommended)

The GitHub Actions workflow at `.github/workflows/release.yml` handles the full pipeline:

```bash
# Trigger from GitHub UI: Actions → Release → Run workflow
# Options:
#   dry_run: true          → Build & lint only, no publish
#   skip_native_sdks: true → Publish only Flutter packages
#   skip_flutter: true     → Publish only native SDKs
```

### Pipeline stages

1. **Validate** — lint, analyze, dry-run checks, extract version numbers
2. **Publish Android SDK** → Maven Central (parallel with iOS)
   - `./gradlew :tracelet-sdk:assembleRelease`
   - `./gradlew :tracelet-sdk:testReleaseUnitTest`
   - `./gradlew publishToSonatype closeAndReleaseSonatypeStagingRepository`
   - Creates git tag: `sdk-android-vX.Y.Z`
3. **Publish iOS SDK** → CocoaPods (parallel with Android)
   - `swift build` + `swift test`
   - `pod lib lint TraceletSDK.podspec --allow-warnings`
   - `pod trunk push TraceletSDK.podspec --allow-warnings` (with 3-retry backoff)
   - Creates git tag: `sdk-ios-vX.Y.Z`
4. **Publish Flutter** → pub.dev (sequential, after native SDKs)
   - `dart pub publish --force` for each package in dependency order
   - 30s pause between packages for pub.dev indexing
   - Creates git tags: `tracelet_platform_interface-vX.Y.Z`, etc.

### Required secrets (GitHub repository settings)

| Secret | Purpose | Used by |
|--------|---------|---------|
| `OSSRH_USERNAME` | Maven Central login | Android SDK |
| `OSSRH_PASSWORD` | Maven Central password | Android SDK |
| `SIGNING_KEY` | GPG private key (ASCII-armored) | Android SDK |
| `SIGNING_PASSWORD` | GPG key passphrase | Android SDK |
| `COCOAPODS_TRUNK_TOKEN` | CocoaPods trunk auth | iOS SDK |
| `PUB_CREDENTIALS` | pub.dev OIDC credentials JSON | Flutter |

---

## Manual Release (Per-Channel)

### Android SDK → Maven Central

```bash
cd sdk/android

# 1. Local validation
./gradlew :tracelet-sdk:assembleRelease
./gradlew :tracelet-sdk:testReleaseUnitTest

# 2. Publish to local Maven (smoke test)
./gradlew :tracelet-sdk:publishReleasePublicationToMavenLocal

# 3. Publish to Maven Central
export OSSRH_USERNAME="..."
export OSSRH_PASSWORD="..."
export SIGNING_KEY="$(cat /path/to/private-key.asc)"
export SIGNING_PASSWORD="..."
./gradlew publishToSonatype closeAndReleaseSonatypeStagingRepository

# 4. Tag
git tag sdk-android-vX.Y.Z && git push origin sdk-android-vX.Y.Z
```

**Maven coordinates:** `com.ikolvi:tracelet-sdk:X.Y.Z`

### iOS SDK → CocoaPods

```bash
# 1. Build + test
cd sdk/ios
swift build -Xswiftc -suppress-warnings
swift test

# 2. Lint podspec
cd /path/to/Tracelet   # repo root
pod lib lint TraceletSDK.podspec --allow-warnings --verbose

# 3. Publish
export COCOAPODS_TRUNK_TOKEN="..."
pod trunk push TraceletSDK.podspec --allow-warnings --verbose

# 4. Tag
git tag sdk-ios-vX.Y.Z && git push origin sdk-ios-vX.Y.Z
```

**Pod name:** `TraceletSDK`
**SPM URL:** `https://github.com/Ikolvi/Tracelet.git` (tag-based)

### Flutter → pub.dev

```bash
# Publish in strict order — wait for each to appear on pub.dev before next

# 1. Platform interface (no deps)
cd packages/tracelet_platform_interface
dart pub publish --force

# 2. Platform implementations (wait 30s after step 1)
cd packages/tracelet_android && dart pub publish --force
cd packages/tracelet_ios && dart pub publish --force
cd packages/tracelet_web && dart pub publish --force

# 3. App-facing package (wait 30s after step 2)
cd packages/tracelet && dart pub publish --force

# 4. Tags
git tag tracelet_platform_interface-vX.Y.Z
git tag tracelet_android-vX.Y.Z
git tag tracelet_ios-vX.Y.Z
git tag tracelet_web-vX.Y.Z
git tag tracelet-vX.Y.Z
git push origin --tags
```

---

## Version Bumping with Melos

For Flutter packages, melos can automate version bumps and changelog generation:

```bash
melos version   # Interactive — bumps all packages, updates CHANGELOGs
```

This updates all 5 Flutter package versions and cross-references in a single commit. Native SDK versions must still be bumped manually.

---

## File Locations Quick Reference

| What | Path |
|------|------|
| Flutter package versions | `packages/*/pubspec.yaml` |
| Flutter changelogs | `packages/*/CHANGELOG.md` |
| Android SDK version | `sdk/android/gradle.properties` → `SDK_VERSION` |
| Android build config | `sdk/android/tracelet-sdk/build.gradle.kts` |
| Android Maven config | `sdk/android/build.gradle.kts` |
| iOS SDK version | `TraceletSDK.podspec` (repo root) → `s.version` |
| iOS SPM manifest | `sdk/ios/Package.swift` |
| Release CI workflow | `.github/workflows/release.yml` |
| CI workflow | `.github/workflows/ci.yml` |
| GPG signing keys | `gpg-signing-key-*.asc` (repo root) |

---

## Git Tag Convention

| Component | Tag format | Example |
|-----------|-----------|---------|
| Android SDK | `sdk-android-vX.Y.Z` | `sdk-android-v1.0.1` |
| iOS SDK | `sdk-ios-vX.Y.Z` | `sdk-ios-v1.0.1` |
| Flutter interface | `tracelet_platform_interface-vX.Y.Z` | `tracelet_platform_interface-v1.8.1` |
| Flutter Android | `tracelet_android-vX.Y.Z` | `tracelet_android-v1.8.1` |
| Flutter iOS | `tracelet_ios-vX.Y.Z` | `tracelet_ios-v1.8.1` |
| Flutter Web | `tracelet_web-vX.Y.Z` | `tracelet_web-v1.8.1` |
| Flutter app-facing | `tracelet-vX.Y.Z` | `tracelet-v1.8.1` |

---

## Troubleshooting

**pub.dev dependency resolution fails:**
Ensure the `^X.Y.Z` constraint in dependent packages points to a version that already exists on pub.dev. Publish in order.

**Maven Central staging repo stuck:**
Run `./gradlew closeAndReleaseSonatypeStagingRepository` separately. Check [oss.sonatype.org](https://oss.sonatype.org) for pending staging repos.

**CocoaPods trunk push fails with 409:**
The version already exists. Bump `s.version` in `TraceletSDK.podspec`.

**CocoaPods trunk push timeout:**
The CI workflow retries 3 times with 30s → 60s → 120s backoff. For manual runs, wait and retry.
