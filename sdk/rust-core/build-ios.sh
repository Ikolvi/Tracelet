#!/bin/bash
set -e

echo "Building iOS Rust Core and Sync (Tracelet)..."

# Ensure we are in the correct directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR"

# Source utility functions (create_framework, generate_dummy_symbols)
source ./build-ios-utils.sh

# Target architectures
TARGETS=("aarch64-apple-ios" "aarch64-apple-ios-sim" "x86_64-apple-ios")

# Add rust targets
for target in "${TARGETS[@]}"; do
    rustup target add "$target"
done

echo "Compiling for iOS targets..."
export RUSTFLAGS="-C embed-bitcode=no"
# #424: line tables and function names for a dSYM. The shared release profile
# strips debug info (right for Android's .so), so the iOS build overrides it
# here; create_dynamic_framework moves it into a .dSYM and strips the binary,
# so the shipped framework is no larger.
export CARGO_PROFILE_RELEASE_DEBUG=line-tables-only
export CARGO_PROFILE_RELEASE_STRIP=none
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim
cargo build --release --target x86_64-apple-ios

echo "Creating XCFrameworks..."
OUT_DIR="out"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Merge simulator architectures
mkdir -p "$OUT_DIR/sim"
lipo -create -output "$OUT_DIR/sim/libtracelet_core.a" \
    target/aarch64-apple-ios-sim/release/libtracelet_core.a \
    target/x86_64-apple-ios/release/libtracelet_core.a

lipo -create -output "$OUT_DIR/sim/libtracelet_sync.a" \
    target/aarch64-apple-ios-sim/release/libtracelet_sync.a \
    target/x86_64-apple-ios/release/libtracelet_sync.a

# Merge simulator architectures for the DYNAMIC libraries (cdylib). These are
# packaged into dynamic frameworks below so the Rust symbols survive the
# consuming app's archive strip (see create_dynamic_framework).
lipo -create -output "$OUT_DIR/sim/libtracelet_core.dylib" \
    target/aarch64-apple-ios-sim/release/libtracelet_core.dylib \
    target/x86_64-apple-ios/release/libtracelet_core.dylib

lipo -create -output "$OUT_DIR/sim/libtracelet_sync.dylib" \
    target/aarch64-apple-ios-sim/release/libtracelet_sync.dylib \
    target/x86_64-apple-ios/release/libtracelet_sync.dylib


# --- CORE FRAMEWORK ---
cargo run -p tracelet_core --features=uniffi/cli --bin uniffi-bindgen generate --library target/aarch64-apple-ios/release/libtracelet_core.a --language swift --out-dir "$OUT_DIR/core"

mkdir -p "$OUT_DIR/core/Headers/TraceletCore"
cp "$OUT_DIR/core/tracelet_coreFFI.h" "$OUT_DIR/core/Headers/TraceletCore/"
cp "$OUT_DIR/core/tracelet_coreFFI.modulemap" "$OUT_DIR/core/Headers/TraceletCore/module.modulemap"

sed -i '' 's/module tracelet_coreFFI/module TraceletCore/g' "$OUT_DIR/core/Headers/TraceletCore/module.modulemap"
sed -i '' 's/canImport(tracelet_coreFFI)/SWIFT_PACKAGE/g' "$OUT_DIR/core/tracelet_core.swift"
sed -i '' 's/import tracelet_coreFFI/import TraceletCore/g' "$OUT_DIR/core/tracelet_core.swift"

cp "$OUT_DIR/core/tracelet_core.swift" "../../sdk/ios/Sources/TraceletSDK/"
cp "$OUT_DIR/core/tracelet_coreFFI.h" "../../sdk/ios/Sources/TraceletSDK/"

# NOTE: No +Dummy.swift is generated. The Rust core now ships as a DYNAMIC
# framework and the Dart loader opens it at runtime via
# ExternalLibrary.open('TraceletCore.framework/TraceletCore'). The old dummy
# @_silgen_name declarations were only needed to stop Xcode dead-stripping the
# FRB symbols from the APP binary under the static-.a/DynamicLibrary.process()
# model. Under the dynamic framework they create build-time UNDEFINED references
# to symbols that no longer live in the app binary — breaking the iOS link.

rm -rf "$OUT_DIR/TraceletCore.xcframework"
# Package the cdylib as a dynamic framework per slice so the FRB symbols live in
# the framework's own embedded/signed binary (strip-proof; loaded via
# ExternalLibrary.open('TraceletCore.framework/TraceletCore')).
create_dynamic_framework "TraceletCore" "target/aarch64-apple-ios/release/libtracelet_core.dylib" "$OUT_DIR/core/Headers/TraceletCore" "$OUT_DIR/fwk/device"
create_dynamic_framework "TraceletCore" "$OUT_DIR/sim/libtracelet_core.dylib" "$OUT_DIR/core/Headers/TraceletCore" "$OUT_DIR/fwk/sim"
# -debug-symbols needs absolute paths; it carries each slice's dSYM into the
# xcframework, and from there into the app's archive (#424).
ABS_OUT="$(cd "$OUT_DIR" && pwd)"
xcodebuild -create-xcframework \
    -framework "$OUT_DIR/fwk/device/TraceletCore.framework" \
    -debug-symbols "$ABS_OUT/fwk/device/TraceletCore.framework.dSYM" \
    -framework "$OUT_DIR/fwk/sim/TraceletCore.framework" \
    -debug-symbols "$ABS_OUT/fwk/sim/TraceletCore.framework.dSYM" \
    -output "$OUT_DIR/TraceletCore.xcframework"


# --- SYNC FRAMEWORK ---
cargo run -p tracelet_sync --features=uniffi/cli --bin sync-uniffi-bindgen generate --library target/aarch64-apple-ios/release/libtracelet_sync.a --language swift --out-dir "$OUT_DIR/sync"

mkdir -p "$OUT_DIR/sync/Headers/TraceletSyncFFI"
cp "$OUT_DIR/sync/tracelet_syncFFI.h" "$OUT_DIR/sync/Headers/TraceletSyncFFI/"
cp "$OUT_DIR/sync/tracelet_syncFFI.modulemap" "$OUT_DIR/sync/Headers/TraceletSyncFFI/module.modulemap"

sed -i '' 's/module tracelet_syncFFI/module TraceletSyncFFI/g' "$OUT_DIR/sync/Headers/TraceletSyncFFI/module.modulemap"
sed -i '' 's/canImport(tracelet_syncFFI)/SWIFT_PACKAGE/g' "$OUT_DIR/sync/tracelet_sync.swift"
sed -i '' 's/import tracelet_syncFFI/import TraceletSyncFFI/g' "$OUT_DIR/sync/tracelet_sync.swift"
sed -i '' 's/import Foundation/import Foundation\
import TraceletSDK/g' "$OUT_DIR/sync/tracelet_sync.swift"

mkdir -p "../../packages/tracelet_sync/ios/tracelet_sync/Sources/tracelet_sync/"
cp "$OUT_DIR/sync/tracelet_sync.swift" "../../packages/tracelet_sync/ios/tracelet_sync/Sources/tracelet_sync/"
cp "$OUT_DIR/sync/tracelet_syncFFI.h" "../../packages/tracelet_sync/ios/tracelet_sync/Sources/tracelet_sync/"

# No +Dummy.swift — see the TraceletCore note above. TraceletSyncFFI also ships
# as a dynamic framework and is opened at runtime, so the dummy symbol-retention
# hack is obsolete and would break the link.

rm -rf "$OUT_DIR/TraceletSyncFFI.xcframework"
# Same dynamic-framework packaging as TraceletCore — keeps sync FRB symbols in
# the framework's own embedded/signed binary (strip-proof).
create_dynamic_framework "TraceletSyncFFI" "target/aarch64-apple-ios/release/libtracelet_sync.dylib" "$OUT_DIR/sync/Headers/TraceletSyncFFI" "$OUT_DIR/fwk-sync/device"
create_dynamic_framework "TraceletSyncFFI" "$OUT_DIR/sim/libtracelet_sync.dylib" "$OUT_DIR/sync/Headers/TraceletSyncFFI" "$OUT_DIR/fwk-sync/sim"
xcodebuild -create-xcframework \
    -framework "$OUT_DIR/fwk-sync/device/TraceletSyncFFI.framework" \
    -debug-symbols "$ABS_OUT/fwk-sync/device/TraceletSyncFFI.framework.dSYM" \
    -framework "$OUT_DIR/fwk-sync/sim/TraceletSyncFFI.framework" \
    -debug-symbols "$ABS_OUT/fwk-sync/sim/TraceletSyncFFI.framework.dSYM" \
    -output "$OUT_DIR/TraceletSyncFFI.xcframework"

# Copy the built xcframework to the plugin's ios directory so CocoaPods can vendor it
rm -rf "../../packages/tracelet_sync/ios/tracelet_sync/TraceletSyncFFI.xcframework"
cp -R "$OUT_DIR/TraceletSyncFFI.xcframework" "../../packages/tracelet_sync/ios/tracelet_sync/TraceletSyncFFI.xcframework"


# --- SYMBOL VERIFICATION ---
CORE_BIN="$OUT_DIR/TraceletCore.xcframework/ios-arm64/TraceletCore.framework/TraceletCore"
echo "Verifying TraceletCore.framework is a dynamic library that exports FRB symbols..."
if ! file "$CORE_BIN" | grep -q 'dynamically linked shared library'; then
    echo "❌ ERROR: TraceletCore is not a dynamic library — it would be stripped from archived apps!"
    exit 1
fi
if ! nm -gU "$CORE_BIN" 2>/dev/null | grep -q '_frb_get_rust_content_hash'; then
    echo "❌ ERROR: frb_get_rust_content_hash not exported from TraceletCore.framework!"
    exit 1
fi
if nm -gU "$CORE_BIN" 2>/dev/null | grep -i 'reqwest'; then
    echo "❌ ERROR: Heavy dependencies leaked into TraceletCore!"
    exit 1
fi
echo "✅ TraceletCore symbol verification passed (dynamic + FRB symbols exported, no heavy deps)."

# #424: every slice must carry a dSYM whose UUIDs match its binary, or the
# archive's symbol upload still fails.
echo "Verifying dSYMs ship inside the xcframeworks..."
for XCF in "$OUT_DIR/TraceletCore.xcframework" "$OUT_DIR/TraceletSyncFFI.xcframework"; do
    NAME="$(basename "$XCF" .xcframework)"
    for SLICE in "$XCF"/ios-*; do
        BIN="$SLICE/$NAME.framework/$NAME"
        DSYM="$SLICE/dSYMs/$NAME.framework.dSYM"
        if [ ! -d "$DSYM" ]; then
            echo "❌ ERROR: no dSYM in $SLICE"
            exit 1
        fi
        BIN_UUIDS="$(dwarfdump --uuid "$BIN" | awk '{print $2}' | sort)"
        DSYM_UUIDS="$(dwarfdump --uuid "$DSYM" | awk '{print $2}' | sort)"
        if [ -z "$BIN_UUIDS" ] || [ "$BIN_UUIDS" != "$DSYM_UUIDS" ]; then
            echo "❌ ERROR: dSYM UUIDs do not match the binary in $SLICE"
            exit 1
        fi
    done
done
echo "✅ dSYMs present with matching UUIDs."

# Surface sccache effectiveness (compile requests / cache hits / misses). Guarded
# so local builds without sccache still succeed under `set -e`.
command -v sccache >/dev/null 2>&1 && sccache --show-stats || true

echo "✅ iOS build complete."
