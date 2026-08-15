#!/usr/bin/env bash
#
# Verify the CocoaPods fallback that ships to pub.dev, without running the
# release workflow. (#390)
#
# The published podspecs are not the ones in this repo: release.yml rewrites
# them to vendor a GitHub Release xcframework, and Flutter then installs the
# result as a `:path` pod, which CocoaPods refuses to download `s.source` for.
# Nothing in the monorepo exercises that shape, so a podspec can be broken for
# every published consumer while every local build stays green.
#
# This stages the published shape in a temp directory and asserts, for each
# plugin:
#
#   1. CocoaPods can still load the podspec        (a podspec's value is its
#      last expression; a stray trailing call turns it into `nil` and every
#      `pod install` dies with "Invalid podspec file")
#   2. evaluating it fetches the xcframework it vendors
#   3. a corrupt checksum sidecar is rejected
#   4. the pod links its own vendored binary       (CocoaPods only links a
#      *dependency's* vendored frameworks, so without this the UniFFI symbols
#      have no definitions at link time)
#   5. the in-repo podspec still no-ops            (no download over a locally
#      built core)
#
# Usage:
#   scripts/verify_cocoapods_fallback.sh [--version X.Y.Z]
#
# --version pins the GitHub Release to fetch from. Defaults to the version in
# the podspec, which only works once that release exists — pass the last
# published version when validating a bump before it ships.
#
# Requires: cocoapods, curl, network. No Flutter or Xcode.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

# Loads a podspec exactly the way `pod install` does, and prints the parsed name
# so a spec that evaluates to something other than a Specification is caught.
spec_name() { pod ipc spec "$1" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])'; }
spec_ldflags() { pod ipc spec "$1" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("pod_target_xcconfig",{}).get("OTHER_LDFLAGS",""))'; }

# Reproduces release.yml's "Bundle iOS SDK into <plugin>" podspec rewrite.
stage_published() {  # <plugin> <tag-prefix> <vendored-relative-path> <zip-name>
  local plugin="$1" tag_prefix="$2" vendored="$3" zip_name="$4"
  local src="$REPO_ROOT/packages/$plugin/ios"
  local dst="$STAGING/$plugin/ios"

  mkdir -p "$dst"
  cp -R "$src/." "$dst/"
  # Published packages have no monorepo above them; release.yml deletes the root
  # TraceletSDK.podspec for the same reason, and that absence is what tells the
  # podspec it is running as a published package.
  find "$dst" -name '*.xcframework' -maxdepth 3 -exec rm -rf {} + 2>/dev/null || true

  local podspec="$dst/$plugin.podspec"
  local version="$VERSION"
  [[ -n "$version" ]] || version="$(grep -m1 's.version' "$podspec" | sed "s/.*'\(.*\)'.*/\1/")"

  perl -pi -e "s|s.version = '.*'|s.version = '$version'|" "$podspec"
  perl -pi -e "s|s.dependency 'TraceletSDK'.*|s.vendored_frameworks = '$vendored'|g" "$podspec"
  perl -pi -e "s|s.source           = \{ :path => '.' \}|s.source = { :http => 'https://github.com/Ikolvi/Tracelet/releases/download/$tag_prefix-v$version/$zip_name' }|g" "$podspec"

  echo "$podspec"
}

check_plugin() {  # <plugin> <tag-prefix> <vendored-relative-path> <zip-name> <expected-framework>
  local plugin="$1" vendored="$3" expected_framework="$5"
  echo "$plugin (published shape)"

  local podspec; podspec="$(stage_published "$@")"
  local dir; dir="$(dirname "$podspec")"

  [[ "$(spec_name "$podspec")" == "$plugin" ]] \
    || fail "CocoaPods cannot load the rewritten podspec: $(pod ipc spec "$podspec" 2>&1 | grep -m1 '[^[:space:]]')"
  pass "podspec loads under CocoaPods"

  [[ -d "$dir/$vendored" ]] || fail "$vendored was not fetched during evaluation"
  pass "$(basename "$vendored") fetched"

  local ldflags; ldflags="$(spec_ldflags "$podspec")"
  [[ "$ldflags" == *"-framework \"$expected_framework\""* ]] \
    || fail "pod target does not link $expected_framework (OTHER_LDFLAGS: ${ldflags:-<empty>})"
  pass "pod target links $expected_framework"

  # A tampered archive must be refused, not linked into the app.
  rm -rf "${dir:?}/${vendored:?}"
  echo "0000000000000000000000000000000000000000000000000000000000000000" > "$dir/$vendored.sha256"
  if pod ipc spec "$podspec" >/dev/null 2>&1; then
    fail "a bad checksum sidecar was accepted"
  fi
  pass "checksum mismatch is rejected"
}

check_monorepo() {  # <plugin>
  local plugin="$1"
  local podspec="$REPO_ROOT/packages/$plugin/ios/$plugin.podspec"
  echo "$plugin (monorepo shape)"

  [[ "$(spec_name "$podspec")" == "$plugin" ]] || fail "podspec does not load in the monorepo"
  pass "podspec loads under CocoaPods"

  [[ -f "$REPO_ROOT/packages/$plugin/ios/TraceletCore.xcframework.sha256" ]] \
    && fail "a published-only checksum sidecar is committed"
  pass "no release binary fetched over the local build"
}

echo "Verifying the published CocoaPods fallback — no release run required."
echo
check_plugin tracelet_ios  tracelet_ios  'TraceletCore.xcframework'                'TraceletCore.xcframework.zip'   TraceletCore
echo
check_plugin tracelet_sync tracelet_sync 'tracelet_sync/TraceletSyncFFI.xcframework' 'TraceletSyncFFI.xcframework.zip' TraceletSyncFFI
echo
check_monorepo tracelet_ios
echo
check_monorepo tracelet_sync
echo
echo "All checks passed."
