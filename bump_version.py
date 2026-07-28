import os

version_from = "3.6.13"
version_to = "3.6.14"

# 1. Bump version strings
exact_replacements = [
    ('sdk/android/gradle.properties', f'SDK_VERSION={version_from}', f'SDK_VERSION={version_to}'),
    ('TraceletSDK.podspec', f"s.version = '{version_from}'", f"s.version = '{version_to}'"),
    ('sdk/ios/TraceletSDK.podspec', f"s.version = '{version_from}'", f"s.version = '{version_to}'"),
    ('packages/tracelet_platform_interface/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    ('packages/tracelet_android/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    ('packages/tracelet_ios/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    ('packages/tracelet_web/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    ('packages/tracelet/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    ('packages/tracelet_sync/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    ('packages/tracelet_supabase/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    ('packages/tracelet_firebase/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    ('packages/tracelet_doctor/pubspec.yaml', f'version: {version_from}', f'version: {version_to}'),
    
    ('packages/tracelet_android/pubspec.yaml', f'tracelet_platform_interface: ^{version_from}', f'tracelet_platform_interface: ^{version_to}'),
    ('packages/tracelet_ios/pubspec.yaml', f'tracelet_platform_interface: ^{version_from}', f'tracelet_platform_interface: ^{version_to}'),
    ('packages/tracelet_web/pubspec.yaml', f'tracelet_platform_interface: ^{version_from}', f'tracelet_platform_interface: ^{version_to}'),
    
    ('packages/tracelet/pubspec.yaml', f'tracelet_platform_interface: ^{version_from}', f'tracelet_platform_interface: ^{version_to}'),
    ('packages/tracelet/pubspec.yaml', f'tracelet_android: ^{version_from}', f'tracelet_android: ^{version_to}'),
    ('packages/tracelet/pubspec.yaml', f'tracelet_ios: ^{version_from}', f'tracelet_ios: ^{version_to}'),
    ('packages/tracelet/pubspec.yaml', f'tracelet_web: ^{version_from}', f'tracelet_web: ^{version_to}'),
    
    ('packages/tracelet_sync/pubspec.yaml', f'tracelet: ^{version_from}', f'tracelet: ^{version_to}'),
    
    ('packages/tracelet_supabase/pubspec.yaml', f'tracelet: ^{version_from}', f'tracelet: ^{version_to}'),
    ('packages/tracelet_supabase/pubspec.yaml', f'tracelet_sync: ^{version_from}', f'tracelet_sync: ^{version_to}'),
    
    ('packages/tracelet_firebase/pubspec.yaml', f'tracelet: ^{version_from}', f'tracelet: ^{version_to}'),
    ('packages/tracelet_firebase/pubspec.yaml', f'tracelet_sync: ^{version_from}', f'tracelet_sync: ^{version_to}'),
    ('packages/tracelet_firebase/pubspec.yaml', f'tracelet_platform_interface: ^{version_from}', f'tracelet_platform_interface: ^{version_to}'),
    
    ('packages/tracelet_doctor/pubspec.yaml', f'tracelet: ^{version_from}', f'tracelet: ^{version_to}'),
    
    ('packages/tracelet_android/android/build.gradle', f'implementation("com.ikolvi:tracelet-sdk:{version_from}")', f'implementation("com.ikolvi:tracelet-sdk:{version_to}")'),
    ('packages/tracelet_android/android/build.gradle', f'api("com.ikolvi:tracelet-sdk:{version_from}")', f'api("com.ikolvi:tracelet-sdk:{version_to}")'),
    
    ('packages/tracelet_ios/ios/tracelet_ios.podspec', f"s.version = '{version_from}'", f"s.version = '{version_to}'"),
    ('packages/tracelet_ios/ios/tracelet_ios.podspec', f"s.dependency 'TraceletSDK', '{version_from}'", f"s.dependency 'TraceletSDK', '{version_to}'"),
    
    ('packages/tracelet_sync/android/build.gradle.kts', f'compileOnly("com.ikolvi:tracelet-sdk:{version_from}")', f'compileOnly("com.ikolvi:tracelet-sdk:{version_to}")'),
    ('packages/tracelet_sync/android/build.gradle.kts', f'implementation("com.ikolvi:tracelet-sync-sdk:{version_from}")', f'implementation("com.ikolvi:tracelet-sync-sdk:{version_to}")'),
    
    ('packages/tracelet_sync/ios/tracelet_sync.podspec', f"s.version = '{version_from}'", f"s.version = '{version_to}'"),
    ('packages/tracelet_sync/ios/tracelet_sync.podspec', f"s.dependency 'TraceletSDK', '{version_from}'", f"s.dependency 'TraceletSDK', '{version_to}'"),
]

for file_path, old_str, new_str in exact_replacements:
    if os.path.exists(file_path):
        with open(file_path, 'r') as f:
            content = f.read()
        if old_str in content:
            content = content.replace(old_str, new_str)
            with open(file_path, 'w') as f:
                f.write(content)
            print(f"Updated {file_path}")
        else:
            print(f"Warning: '{old_str}' not found in {file_path}")
    else:
        print(f"Warning: File {file_path} does not exist.")

# 2. Update Changelogs
changelogs = [
    'sdk/android/CHANGELOG.md',
    'sdk/ios/CHANGELOG.md',
    'packages/tracelet_android/CHANGELOG.md',
    'packages/tracelet_ios/CHANGELOG.md',
    'packages/tracelet/CHANGELOG.md',
]
generic_changelogs = [
    'packages/tracelet_platform_interface/CHANGELOG.md',
    'packages/tracelet_web/CHANGELOG.md',
    'packages/tracelet_sync/CHANGELOG.md',
    'packages/tracelet_supabase/CHANGELOG.md',
    'packages/tracelet_firebase/CHANGELOG.md',
    'packages/tracelet_doctor/CHANGELOG.md',
]

changelog_addition = f"""## {version_to}

**FIX**: geofence `ENTER`/`EXIT` flapping for a stationary device inside the radius (high-accuracy mode). The evaluator used a single `distance <= radius` threshold for both entry and exit, so a motionless device whose GPS fixes jittered across the boundary emitted repeated `ENTER`/`EXIT` events. Exit now applies hysteresis — the device `ENTER`s at the true radius but only `EXIT`s once it is farther than `radius + max(radius * 0.1, 20 m)` from the center — so boundary jitter no longer flips the state. Applied in both the pure-Dart evaluator (the active high-accuracy path) and the Rust core used by the native SDKs ([#268](https://github.com/Ikolvi/Tracelet/issues/268)).

**FEAT**: (Android) add `Tracelet.requestTermination()` to stop the GPS foreground service from a headless Dart isolate. When an FCM silent push runs a background task while the app is terminated, `Tracelet.stop()` is unavailable because it relies on Pigeon, which headless isolates cannot reach — so the foreground service kept polling and draining battery until the app was reopened. A new `requestTermination` handler on the `com.tracelet/methods` MethodChannel (registered on the headless `FlutterEngine`) calls `TraceletSdk.stop()`, letting background handlers shut tracking down cleanly ([#267](https://github.com/Ikolvi/Tracelet/issues/267)).

"""
generic_addition = f"""## {version_to}

Version alignment with tracelet {version_to}.

"""

for cl in changelogs:
    if os.path.exists(cl):
        with open(cl, 'r') as f:
            content = f.read()
        if f"## {version_to}" not in content:
            content = changelog_addition + content
            with open(cl, 'w') as f:
                f.write(content)
            print(f"Added entry to {cl}")

for cl in generic_changelogs:
    if os.path.exists(cl):
        with open(cl, 'r') as f:
            content = f.read()
        if f"## {version_to}" not in content:
            content = generic_addition + content
            with open(cl, 'w') as f:
                f.write(content)
            print(f"Added entry to {cl}")
