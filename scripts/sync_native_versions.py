#!/usr/bin/env python3
import os
import re
import yaml

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def read_version():
    pubspec_path = os.path.join(ROOT_DIR, "packages", "tracelet", "pubspec.yaml")
    with open(pubspec_path, "r") as f:
        data = yaml.safe_load(f)
    return data.get("version")

def extract_latest_changelog():
    changelog_path = os.path.join(ROOT_DIR, "CHANGELOG.md")
    if not os.path.exists(changelog_path):
        return None
    with open(changelog_path, "r") as f:
        content = f.read()
    
    # Extract the top version block
    match = re.search(r'(## \d+\.\d+\.\d+.*?(?=\n## \d+\.\d+\.\d+|$))', content, re.DOTALL)
    if match:
        return match.group(1).strip()
    return None

def prepend_changelog(filepath, latest_changelog):
    if not latest_changelog: return
    if not os.path.exists(filepath): return
    with open(filepath, "r") as f:
        content = f.read()
    
    # Prepend right after the # Changelog title
    new_content = re.sub(r'(# Changelog\n\n)', r'\1' + latest_changelog + '\n\n', content)
    with open(filepath, "w") as f:
        f.write(new_content)

def update_file(filepath, pattern, replacement):
    filepath = os.path.join(ROOT_DIR, filepath)
    if not os.path.exists(filepath): return
    with open(filepath, "r") as f:
        content = f.read()
    new_content = re.sub(pattern, replacement, content)
    with open(filepath, "w") as f:
        f.write(new_content)

def main():
    version = read_version()
    if not version:
        print("Could not find version in tracelet pubspec.yaml")
        return
    
    print(f"Syncing native SDKs to version {version}...")

    # Update Android SDK version
    update_file("sdk/android/gradle.properties", r'SDK_VERSION=.*', f'SDK_VERSION={version}')

    # Update the Dart-side version constant the Doctor report reads (#398).
    # Hand-maintaining it would guarantee drift, and a bug report naming the
    # wrong version is worse than one naming none.
    update_file(
        "packages/tracelet/lib/src/version.dart",
        r"const String traceletVersion = '.*';",
        f"const String traceletVersion = '{version}';",
    )
    
    # Update iOS SDK versions — root podspec, the sub podspec under sdk/ios
    # (was previously missed and drifted behind), and both plugin podspecs.
    update_file("TraceletSDK.podspec", r"s\.version\s*=\s*'.*'", f"s.version = '{version}'")
    update_file("sdk/ios/TraceletSDK.podspec", r"s\.version\s*=\s*'.*'", f"s.version = '{version}'")
    update_file("packages/tracelet_ios/ios/tracelet_ios.podspec", r"s\.version\s*=\s*'.*'", f"s.version = '{version}'")
    update_file("packages/tracelet_sync/ios/tracelet_sync.podspec", r"s\.version\s*=\s*'.*'", f"s.version = '{version}'")

    # Update iOS SDK dependencies (exact pin) — BOTH plugins depend on TraceletSDK.
    update_file("packages/tracelet_ios/ios/tracelet_ios.podspec", r"s\.dependency 'TraceletSDK',\s*'.*'", f"s.dependency 'TraceletSDK', '{version}'")
    update_file("packages/tracelet_sync/ios/tracelet_sync.podspec", r"s\.dependency 'TraceletSDK',\s*'.*'", f"s.dependency 'TraceletSDK', '{version}'")

    # Update Android Flutter Plugin dependencies. tracelet_android pins with
    # `api(...)`, not `implementation(...)`, so match either Gradle keyword.
    update_file("packages/tracelet_android/android/build.gradle", r'(api|implementation)\("com\.ikolvi:tracelet-sdk:[^"]*"\)', f'\\1("com.ikolvi:tracelet-sdk:{version}")')
    update_file("packages/tracelet_sync/android/build.gradle.kts", r'compileOnly\("com\.ikolvi:tracelet-sdk:.*"\)', f'compileOnly("com.ikolvi:tracelet-sdk:{version}")')
    update_file("packages/tracelet_sync/android/build.gradle.kts", r'implementation\("com\.ikolvi:tracelet-sync-sdk:.*"\)', f'implementation("com.ikolvi:tracelet-sync-sdk:{version}")')

    latest_changelog = extract_latest_changelog()
    if latest_changelog:
        print("Syncing CHANGELOGs...")
        prepend_changelog(os.path.join(ROOT_DIR, "sdk", "android", "CHANGELOG.md"), latest_changelog)
        prepend_changelog(os.path.join(ROOT_DIR, "sdk", "ios", "CHANGELOG.md"), latest_changelog)

    print("Done!")

if __name__ == "__main__":
    main()
