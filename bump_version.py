import os

version_from = "3.6.15"
version_to = "3.7.0"

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

**FEAT**(geofence): accuracy-aware geofence EXIT for high-accuracy mode. A circular geofence now only fires EXIT once the entire GPS error circle clears the fence (`distance - accuracy > radius + buffer`), so a single high-drift, low-confidence fix no longer produces a false EXIT while a device is stationary inside a small geofence. ENTER stays accuracy-agnostic so arrivals still trigger promptly ([#274](https://github.com/Ikolvi/Tracelet/issues/274)).

**FEAT**(geofence): new `GeofenceConfig.geofenceExitAccuracyMax` (meters) to tune the accuracy-aware EXIT gating — `-1` full gating (default, most drift-resistant), `0` disables gating (fastest, most eager EXIT), and `N > 0` clamps the accuracy used in the exit test to `N` to bound the worst-case exit delay while still absorbing drift up to `N`. High-accuracy path only; no effect in standard OS region-monitoring mode ([#276](https://github.com/Ikolvi/Tracelet/issues/276)).

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
