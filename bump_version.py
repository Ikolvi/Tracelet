import os
import re

version_from = "3.8.0-beta"
version_to = "3.8.0-beta.2"

# `3.8.0-beta.2` rather than `3.8.0-beta2`: dotted numeric identifiers are the
# semver form, and both pub and CocoaPods order `3.8.0-beta.2` after
# `3.8.0-beta`. `beta2` would be a single alphanumeric identifier, which still
# sorts later but reads as an unrelated tag rather than the second beta.

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

    # The docs site reads the navbar version and the version switcher from this
    # manifest, so it has to move with the packages or the site advertises a
    # release that does not exist.
    ('website/versions.json', f'"label": "{version_from}"', f'"label": "{version_to}"'),

    # Bumping the localStorage key is deliberate: it re-shows the "what's new"
    # bell for readers who already dismissed it on the previous build.
    ('website/components/NotificationBell.tsx', f"tracelet_notif_{version_from}_seen", f"tracelet_notif_{version_to}_seen"),
    ('website/app/en/notifications.json', f'"New in {version_from}"', f'"New in {version_to}"'),
]

for file_path, old_str, new_str in exact_replacements:
    if os.path.exists(file_path):
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        if old_str in content:
            content = content.replace(old_str, new_str)
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"Updated {file_path}")
        else:
            print(f"Warning: '{old_str}' not found in {file_path}")
    else:
        print(f"Warning: File {file_path} does not exist.")

# 2. Update changelogs.
#
# Entries for this release were written under a `## Unreleased` heading as the
# work landed, so the release step PROMOTES that heading rather than prepending
# a second block — otherwise the same fixes would appear twice, once under the
# version and once under "Unreleased" forever.
detailed_changelogs = [
    'sdk/android/CHANGELOG.md',
    'sdk/ios/CHANGELOG.md',
    'packages/tracelet/CHANGELOG.md',
    'packages/tracelet_platform_interface/CHANGELOG.md',
    'packages/tracelet_web/CHANGELOG.md',
]

# Packages that carry the new host-API plumbing but had no hand-written entry.
plugin_changelogs = [
    'packages/tracelet_android/CHANGELOG.md',
    'packages/tracelet_ios/CHANGELOG.md',
]

generic_changelogs = [
    'packages/tracelet_sync/CHANGELOG.md',
    'packages/tracelet_supabase/CHANGELOG.md',
    'packages/tracelet_firebase/CHANGELOG.md',
    'packages/tracelet_doctor/CHANGELOG.md',
]

plugin_addition = f"""## {version_to}

**FEAT**: implements the `getCurrentLocationTuning` host API, which reports the location-filter thresholds actually in force in the native processor rather than echoing the configured values ([#303](https://github.com/Ikolvi/Tracelet/issues/303)).

"""

generic_addition = f"""## {version_to}

Version alignment with tracelet {version_to}.

"""

for cl in detailed_changelogs:
    if not os.path.exists(cl):
        print(f"Warning: File {cl} does not exist.")
        continue
    with open(cl, 'r', encoding='utf-8') as f:
        content = f.read()
    if f"## {version_to}" in content:
        print(f"Skipped {cl} (already at {version_to})")
        continue
    # `[ \t]*` not `\s*`: \s matches newlines, so the greedy form swallowed the
    # blank line after the heading and glued it to the first entry.
    if re.search(r'^## Unreleased[ \t]*$', content, flags=re.M):
        content = re.sub(r'^## Unreleased[ \t]*$', f'## {version_to}', content, count=1, flags=re.M)
        with open(cl, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Promoted Unreleased -> {version_to} in {cl}")
    else:
        content = generic_addition + content
        with open(cl, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Added generic entry to {cl} (no Unreleased section found)")

for cl, addition in [(c, plugin_addition) for c in plugin_changelogs] + \
                    [(c, generic_addition) for c in generic_changelogs]:
    if not os.path.exists(cl):
        print(f"Warning: File {cl} does not exist.")
        continue
    with open(cl, 'r', encoding='utf-8') as f:
        content = f.read()
    if f"## {version_to}" not in content:
        content = addition + content
        with open(cl, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Added entry to {cl}")

print(f"\nBumped {version_from} -> {version_to}")
