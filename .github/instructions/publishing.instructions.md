---
applyTo: "**/pubspec.yaml,**/CHANGELOG.md,**/*.podspec,**/gradle.properties"
---

# Publishing Instructions

## CRITICAL — Do Not Manually Publish

**NEVER run `dart pub publish` manually.** All publishing is done via the GitHub Actions workflow.

### How to Publish
1. Bump versions and update changelogs locally (see checklists below)
2. Commit and push to `main`
3. Go to GitHub → Actions → **"Release (Native SDKs + pub.dev)"** → **Run workflow**
4. Options:
   - `dry_run`: Build + lint only, publish nothing (use first to verify)
   - `skip_native_sdks`: Skip Maven Central + CocoaPods (if native SDKs unchanged)
   - `skip_flutter`: Skip pub.dev (publish only native SDKs)

### Why Not Manual?
- Manual publish risks **partial releases** (some packages published, others not)
- pub.dev versions are **immutable** — a partially published version cannot be fixed, only bumped
- The workflow handles: validation → native SDKs (parallel) → Flutter packages (sequential with 30s indexing delays) → tagging
- The workflow checks if versions are already published and skips them (idempotent)

### If You Accidentally Publish Manually
If some packages were published at version X.Y.Z but not all:
1. Bump ALL packages to X.Y.(Z+1)
2. Add changelog entry: `**CHORE**: Re-release — X.Y.Z was partially published without all fixes.`
3. Push and trigger the release workflow
4. The workflow will skip already-published native SDKs (Maven Central / CocoaPods check)

## Three Distribution Channels
| Channel | Artifact | Registry |
|---------|----------|----------|
| Android SDK | `com.ikolvi:tracelet-sdk` | Maven Central |
| iOS SDK | `TraceletSDK` | CocoaPods / SPM |
| Flutter | 5 federated packages | pub.dev |

Native SDKs version independently from Flutter. Flutter packages are always version-locked together.

## Publishing Order (STRICT)
1. **Native SDKs** (independent, parallel OK): Android → Maven Central, iOS → CocoaPods
2. **Flutter packages** (sequential, wait for each to appear on pub.dev):
   1. `tracelet_platform_interface` (no Tracelet deps)
   2. `tracelet_android` (depends on interface)
   3. `tracelet_ios` (depends on interface)
   4. `tracelet_web` (depends on interface)
   5. `tracelet` (depends on all above)

pub.dev resolves deps at publish time — a package cannot reference a version that doesn't exist yet.

## Pre-Release Checklist
### Flutter (all 5 packages must match version)
- Bump `version:` in all 5 `packages/*/pubspec.yaml`
- Update cross-package `^X.Y.Z` constraints (see below)
- Add entries to all 5 `packages/*/CHANGELOG.md` with `**FEAT**:`/`**FIX**:`/`**PERF**:` prefixes

### Cross-Package Dependency Constraints
When publishing version X.Y.Z, ALL constraints must point to the version being published:
```yaml
# tracelet_android/pubspec.yaml, tracelet_ios/pubspec.yaml, tracelet_web/pubspec.yaml
tracelet_platform_interface: ^X.Y.Z

# tracelet/pubspec.yaml
tracelet_platform_interface: ^X.Y.Z
tracelet_android: ^X.Y.Z
tracelet_ios: ^X.Y.Z
tracelet_web: ^X.Y.Z
```
Never publish with stale constraints pointing to older versions.

### Native SDKs (only if changed)
- Android: `sdk/android/gradle.properties` → `SDK_VERSION`, `sdk/android/CHANGELOG.md`
- iOS: `TraceletSDK.podspec` → `s.version`, `sdk/ios/CHANGELOG.md`

## Git Tag Convention
| Component | Format | Example |
|-----------|--------|---------|
| Android SDK | `sdk-android-vX.Y.Z` | `sdk-android-v1.0.1` |
| iOS SDK | `sdk-ios-vX.Y.Z` | `sdk-ios-v1.0.1` |
| Flutter interface | `tracelet_platform_interface-vX.Y.Z` | `tracelet_platform_interface-v1.8.1` |
| Flutter Android | `tracelet_android-vX.Y.Z` | `tracelet_android-v1.8.1` |
| Flutter iOS | `tracelet_ios-vX.Y.Z` | `tracelet_ios-v1.8.1` |
| Flutter Web | `tracelet_web-vX.Y.Z` | `tracelet_web-v1.8.1` |
| Flutter app-facing | `tracelet-vX.Y.Z` | `tracelet-v1.8.1` |

## Automated Release
Trigger via GitHub Actions: `.github/workflows/release.yml` → Run workflow.
Options: `dry_run`, `skip_native_sdks`, `skip_flutter`.

## Manual Flutter Publish (EMERGENCY ONLY — prefer GitHub Actions workflow)
```bash
# Only use if GitHub Actions is down. Risk of partial publish!
# Publish in strict order — wait 30s between each for pub.dev indexing
cd packages/tracelet_platform_interface && dart pub publish --force
cd packages/tracelet_android && dart pub publish --force
cd packages/tracelet_ios && dart pub publish --force
cd packages/tracelet_web && dart pub publish --force
cd packages/tracelet && dart pub publish --force
git push origin --tags
```

## Key File Locations
| What | Path |
|------|------|
| Flutter versions | `packages/*/pubspec.yaml` |
| Flutter changelogs | `packages/*/CHANGELOG.md` |
| Android SDK version | `sdk/android/gradle.properties` |
| iOS SDK version | `TraceletSDK.podspec` |
| Release CI | `.github/workflows/release.yml` |

## Troubleshooting
- **pub.dev dep resolution fails**: Publish in order; `^X.Y.Z` must reference already-published versions.
- **Maven Central stuck**: Run `closeAndReleaseSonatypeStagingRepository` separately.
- **CocoaPods 409**: Version exists — bump `s.version`.
- **Use `melos version`** to automate Flutter version bumps + changelog generation.
