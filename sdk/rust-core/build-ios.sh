#!/bin/bash
set -e

echo "Building iOS Rust Core (Tracelet)..."

# Ensure we are in the correct directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$DIR"

# Target architectures
TARGETS=("aarch64-apple-ios" "aarch64-apple-ios-sim")

# Add rust targets
for target in "${TARGETS[@]}"; do
    rustup target add "$target"
done

echo "Compiling for iOS targets..."
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

echo "Creating XCFramework..."
OUT_DIR="out"
mkdir -p "$OUT_DIR"

# Copy architectures
mkdir -p "$OUT_DIR/ios" "$OUT_DIR/sim"
cp target/aarch64-apple-ios-sim/release/libtracelet_core.a "$OUT_DIR/sim/libtracelet_core.a"
cp target/aarch64-apple-ios/release/libtracelet_core.a "$OUT_DIR/ios/libtracelet_core.a"

# Generate Swift bindings if they don't exist
cargo run --features=uniffi/cli --bin uniffi-bindgen generate --library target/aarch64-apple-ios/release/libtracelet_core.a --language swift --out-dir "$OUT_DIR"

# Move headers to a clean directory
mkdir -p "$OUT_DIR/Headers"
cp "$OUT_DIR/tracelet_coreFFI.h" "$OUT_DIR/Headers/"
cp "$OUT_DIR/tracelet_coreFFI.modulemap" "$OUT_DIR/Headers/module.modulemap"

# Rename module to TraceletCore so Xcode/SPM loads it properly from TraceletCore.xcframework
sed -i '' 's/module tracelet_coreFFI/module TraceletCore/g' "$OUT_DIR/Headers/module.modulemap"

# Replace canImport with SWIFT_PACKAGE to support both CocoaPods and SPM
sed -i '' 's/canImport(tracelet_coreFFI)/SWIFT_PACKAGE/g' "$OUT_DIR/tracelet_core.swift"
sed -i '' 's/import tracelet_coreFFI/import TraceletCore/g' "$OUT_DIR/tracelet_core.swift"

# Copy generated Swift bindings to the iOS SDK sources
cp "$OUT_DIR/tracelet_core.swift" "../../sdk/ios/Sources/TraceletSDK/"
cp "$OUT_DIR/tracelet_coreFFI.h" "../../sdk/ios/Sources/TraceletSDK/"

# Remove old XCFramework
rm -rf "$OUT_DIR/TraceletCore.xcframework"

# Build new XCFramework
xcodebuild -create-xcframework \
    -library "$OUT_DIR/ios/libtracelet_core.a" -headers "$OUT_DIR/Headers" \
    -library "$OUT_DIR/sim/libtracelet_core.a" -headers "$OUT_DIR/Headers" \
    -output "$OUT_DIR/TraceletCore.xcframework"

echo "✅ iOS build complete. XCFramework placed in $OUT_DIR/TraceletCore.xcframework"
