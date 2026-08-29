import os
import re

version_from = "3.8.7"
version_to = "3.8.8"

# A quality-converging one-shot release. Targeted requests keep the provider
# warm until horizontal accuracy reaches the caller's threshold or deadline,
# return the best observed fallback at timeout, and expose caller-owned
# cancellation so obsolete acquisition generations cannot deliver late.

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

    # The Dart-side constant the Doctor bug report prints (#398). Also synced by
    # scripts/sync_native_versions.py for the Melos path; listed here too so a
    # hand-run bump cannot ship a report naming the previous version.
    ('packages/tracelet/lib/src/version.dart',
     f"const String traceletVersion = '{version_from}';",
     f"const String traceletVersion = '{version_to}';"),

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

    # NOTE: website/versions.json is deliberately NOT bumped here. VersionSwitch
    # reads the newest published version from pub.dev at runtime, prereleases
    # included, so the badge is correct the moment a release publishes and wrong
    # for nobody in between — a release step cannot be, because it runs before
    # the publish. `current.label` there is only the offline fallback.
    #
    # The version *archives* in that file are still edited by hand, via
    # `scripts/version-cut.js`, since cutting an archive is a separate decision
    # from bumping a version.

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
    # tracelet_doctor writes real entries under `## Unreleased` (its Doctor cards
    # and bug-report sections ship independently of the core), so it belongs on
    # the promote list, not the generic one. Treated as generic it got a "Version
    # alignment" stub prepended while its actual entries stayed stranded under
    # "Unreleased" — invisible in the released changelog, and re-promoted into
    # whatever version happened to bump next.
    #
    # This list is safe for packages that have no Unreleased section: the loop
    # below falls back to the generic entry when there is nothing to promote.
    'packages/tracelet_doctor/CHANGELOG.md',
    # The Pigeon host-API plumbing lives in these two, so config/transport work
    # lands here with real hand-written `## Unreleased` entries (#320, #321).
    # They used to sit on `plugin_changelogs`, which PREPENDS a fixed blurb
    # instead of promoting: their genuine entries would have stayed stranded
    # under "Unreleased" forever while a stale note shipped as the release
    # description. Same failure the tracelet_doctor comment above describes.
    'packages/tracelet_android/CHANGELOG.md',
    'packages/tracelet_ios/CHANGELOG.md',
    # tracelet_sync carries a real #340 entry this cycle (the sync-body-source
    # lifecycle report on iOS) — same reasoning as tracelet_doctor above.
    'packages/tracelet_sync/CHANGELOG.md',
]

generic_changelogs = [
    'packages/tracelet_supabase/CHANGELOG.md',
    'packages/tracelet_firebase/CHANGELOG.md',
]

generic_addition = f"""## {version_to}

Version alignment with tracelet {version_to}.

"""

def merge_unreleased_into(content, version):
    """Fold an `## Unreleased` block into an existing `## <version>` section.

    Returns the new content, or None when there is no Unreleased block to move.
    Entries are placed at the top of the version's section, matching the
    newest-first ordering used throughout these changelogs.
    """
    m = re.search(r'^## Unreleased[ \t]*\n', content, flags=re.M)
    if not m:
        return None
    nxt = re.search(r'^## ', content[m.end():], flags=re.M)
    body = content[m.end():m.end() + nxt.start()] if nxt else content[m.end():]
    rest = content[:m.start()] + (content[m.end() + nxt.start():] if nxt else '')
    vm = re.search(rf'^## {re.escape(version)}[ \t]*\n\n', rest, flags=re.M)
    if not vm:
        return None
    return rest[:vm.end()] + body.strip('\n') + '\n\n' + rest[vm.end():]


def has_version_heading(content, version):
    """Whether `content` already carries a `## <version>` heading.

    Anchored to a whole line rather than a substring search. A plain
    `f"## {version_to}" in content` check is wrong whenever the new version is a
    prefix of an existing one — promoting `3.8.0-beta.2` to `3.8.0` matched the
    existing `## 3.8.0-beta.2` heading and silently skipped every changelog, so
    the release shipped with its entries still stranded under `## Unreleased`.
    """
    return re.search(rf'^## {re.escape(version)}[ \t]*$', content, flags=re.M) is not None


for cl in detailed_changelogs:
    if not os.path.exists(cl):
        print(f"Warning: File {cl} does not exist.")
        continue
    with open(cl, 'r', encoding='utf-8') as f:
        content = f.read()
    if has_version_heading(content, version_to):
        # The heading already exists — but there may still be an `## Unreleased`
        # block above it, written after the heading was created (a follow-up fix
        # for a version that has not shipped yet). Skipping outright stranded
        # those entries permanently, so fold them into the existing section.
        merged = merge_unreleased_into(content, version_to)
        if merged is None:
            print(f"Skipped {cl} (already at {version_to}, nothing to promote)")
            continue
        with open(cl, 'w', encoding='utf-8') as f:
            f.write(merged)
        print(f"Merged Unreleased into the existing {version_to} section in {cl}")
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

for cl in generic_changelogs:
    addition = generic_addition
    if not os.path.exists(cl):
        print(f"Warning: File {cl} does not exist.")
        continue
    with open(cl, 'r', encoding='utf-8') as f:
        content = f.read()
    if not has_version_heading(content, version_to):
        content = addition + content
        with open(cl, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Added entry to {cl}")

print(f"\nBumped {version_from} -> {version_to}")
