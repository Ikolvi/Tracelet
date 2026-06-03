#!/bin/bash
set -e

echo "Building iOS Rust Core and Sync (Tracelet)..."

# Ensure we are in the correct directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR"

# Source utility functions (create_framework, generate_dummy_symbols)
source ./build-ios-utils.sh

# Target architectures
TARGETS=("aarch64-apple-ios" "aarch64-apple-ios-sim")

# Add rust targets
for target in "${TARGETS[@]}"; do
    rustup target add "$target"
done

echo "Compiling for iOS targets..."
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

echo "Creating XCFrameworks..."
OUT_DIR="out"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

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

DUMMY_SWIFT_CORE="$OUT_DIR/core/TraceletCore+Dummy.swift"
generate_dummy_symbols "target/aarch64-apple-ios/release/libtracelet_core.a" "$DUMMY_SWIFT_CORE" "TraceletCore"
cp "$DUMMY_SWIFT_CORE" "../../packages/tracelet_ios/ios/tracelet_ios/Sources/tracelet_ios/"

rm -rf "$OUT_DIR/TraceletCore.xcframework"
xcodebuild -create-xcframework \
    -library "target/aarch64-apple-ios/release/libtracelet_core.a" -headers "$OUT_DIR/core/Headers" \
    -library "target/aarch64-apple-ios-sim/release/libtracelet_core.a" -headers "$OUT_DIR/core/Headers" \
    -output "$OUT_DIR/TraceletCore.xcframework"


# --- SYNC FRAMEWORK ---
cargo run -p tracelet_sync --features=uniffi/cli --bin sync-uniffi-bindgen generate --library target/aarch64-apple-ios/release/libtracelet_sync.a --language swift --out-dir "$OUT_DIR/sync"

mkdir -p "$OUT_DIR/sync/Headers/TraceletSyncFFI"
cp "$OUT_DIR/sync/tracelet_syncFFI.h" "$OUT_DIR/sync/Headers/TraceletSyncFFI/"
cp "$OUT_DIR/sync/tracelet_syncFFI.modulemap" "$OUT_DIR/sync/Headers/TraceletSyncFFI/module.modulemap"

sed -i '' 's/module tracelet_syncFFI/module TraceletSyncFFI/g' "$OUT_DIR/sync/Headers/TraceletSyncFFI/module.modulemap"
sed -i '' 's/canImport(tracelet_syncFFI)/SWIFT_PACKAGE/g' "$OUT_DIR/sync/tracelet_sync.swift"
sed -i '' 's/import tracelet_syncFFI/import TraceletSyncFFI\
import TraceletSDK/g' "$OUT_DIR/sync/tracelet_sync.swift"

mkdir -p "../../packages/tracelet_sync/ios/tracelet_sync/Sources/tracelet_sync"
cp "$OUT_DIR/sync/tracelet_sync.swift" "../../packages/tracelet_sync/ios/tracelet_sync/Sources/tracelet_sync/"
cp "$OUT_DIR/sync/tracelet_syncFFI.h" "../../packages/tracelet_sync/ios/tracelet_sync/Sources/tracelet_sync/"

DUMMY_SWIFT_SYNC="$OUT_DIR/sync/TraceletSyncFFI+Dummy.swift"
generate_dummy_symbols "target/aarch64-apple-ios/release/libtracelet_sync.a" "$DUMMY_SWIFT_SYNC" "TraceletSyncFFI"
cp "$DUMMY_SWIFT_SYNC" "../../packages/tracelet_sync/ios/tracelet_sync/Sources/tracelet_sync/"

rm -rf "$OUT_DIR/TraceletSyncFFI.xcframework"
xcodebuild -create-xcframework \
    -library "target/aarch64-apple-ios/release/libtracelet_sync.a" -headers "$OUT_DIR/sync/Headers" \
    -library "target/aarch64-apple-ios-sim/release/libtracelet_sync.a" -headers "$OUT_DIR/sync/Headers" \
    -output "$OUT_DIR/TraceletSyncFFI.xcframework"

# Copy the built xcframework to the plugin's ios directory so CocoaPods can vendor it
rm -rf "../../packages/tracelet_sync/ios/tracelet_sync/TraceletSyncFFI.xcframework"
cp -R "$OUT_DIR/TraceletSyncFFI.xcframework" "../../packages/tracelet_sync/ios/tracelet_sync/TraceletSyncFFI.xcframework"


# --- SYMBOL VERIFICATION ---
echo "Verifying symbols for TraceletCore..."
if nm -gU "$OUT_DIR/TraceletCore.xcframework/ios-arm64/libtracelet_core.a" 2>/dev/null | grep -i 'reqwest'; then
    echo "❌ ERROR: Heavy dependencies leaked into TraceletCore!"
    exit 1
fi
echo "✅ TraceletCore symbol verification passed. No heavy dependencies found."

echo "✅ iOS build complete."
