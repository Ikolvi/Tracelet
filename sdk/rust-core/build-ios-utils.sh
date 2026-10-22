#!/bin/bash

# Generates a shallow iOS framework from a static library and its headers.
create_framework() {
    local NAME=$1
    local LIB=$2
    local HEADERS=$3
    local OUT=$4
    local PLATFORM=$5

    local FWK="$OUT/$NAME.framework"
    mkdir -p "$FWK/Headers"
    mkdir -p "$FWK/Modules"

    cp "$LIB" "$FWK/$NAME"
    cp "$HEADERS"/*.h "$FWK/Headers/"
    cp "$HEADERS"/module.modulemap "$FWK/Modules/module.modulemap"

    cat <<EOF > "$FWK/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.ikolvi.$NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF
}

# Wraps a DYNAMIC library (.dylib) into a shallow iOS .framework.
#
# Shipping the Rust core as a dynamic framework (instead of a static .a) keeps
# the FRB/uniffi symbols in the framework's OWN embedded, code-signed binary.
# They are therefore never removed by the consuming app's archive strip
# (STRIP_INSTALLED_PRODUCT=YES, STRIP_STYLE=all) and do not need to be exported
# from the app executable. The Dart loader opens it directly via
# ExternalLibrary.open('<NAME>.framework/<NAME>'). This is the iOS analogue of
# the Android ExternalLibrary.open(...) path and is the only delivery that is
# robust under Swift Package Manager (which cannot set the consumer app's
# STRIP_INSTALLED_PRODUCT build setting).
create_dynamic_framework() {
    local NAME=$1
    local DYLIB=$2
    local HEADERS=$3
    local OUT=$4

    local FWK="$OUT/$NAME.framework"
    rm -rf "$FWK" "$OUT/$NAME.framework.dSYM"
    mkdir -p "$FWK/Headers"
    mkdir -p "$FWK/Modules"

    cp "$DYLIB" "$FWK/$NAME"
    # The install name must be @rpath-relative so the framework resolves when
    # embedded under <App>.app/Frameworks/<NAME>.framework/<NAME>.
    install_name_tool -id "@rpath/$NAME.framework/$NAME" "$FWK/$NAME"

    # #424: archives warned "Upload Symbols Failed" and Rust frames were
    # unsymbolicated, because nothing produced a dSYM. dsymutil reads the debug
    # map from the binary (the DWARF stays in cargo's object files), so it runs
    # before the strip; the strip keeps LC_UUID, so the dSYM still matches.
    # `-S -x` drops debug and local symbols only — the exported uniffi_*/frb_*
    # symbols are global and must survive (the symbol verification checks).
    dsymutil "$FWK/$NAME" -o "$OUT/$NAME.framework.dSYM"
    strip -S -x "$FWK/$NAME"
    cp "$HEADERS"/*.h "$FWK/Headers/"
    cp "$HEADERS"/module.modulemap "$FWK/Modules/module.modulemap"
    # A module bundled inside a .framework must be declared as a `framework
    # module` so Clang resolves the header from the framework's Headers/
    # directory. A bare `module` declaration triggers
    # -Wincomplete-framework-module-declaration and then "header not found",
    # breaking `import TraceletCore`.
    sed -i '' 's/^module /framework module /' "$FWK/Modules/module.modulemap"

    cat <<EOF > "$FWK/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.ikolvi.$NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF
}

# Generates dummy Swift methods for exported Rust symbols to prevent Dead Code Stripping in Xcode.
generate_dummy_symbols() {
    local LIB_PATH=$1
    local DUMMY_SWIFT_OUT=$2
    local EXTENSION_NAME=$3

    local NM_OUTPUT=$(nm -g "$LIB_PATH" 2>/dev/null | grep -E " T _frb| T _store_dart" | awk '{print $3}' | sed 's/^_//' | sort | uniq)

    echo "import Foundation" > "$DUMMY_SWIFT_OUT"
    echo "" >> "$DUMMY_SWIFT_OUT"
    for symbol in $NM_OUTPUT; do
        echo "@_silgen_name(\"$symbol\") func dummy_${EXTENSION_NAME}_$symbol()" >> "$DUMMY_SWIFT_OUT"
    done
    echo "" >> "$DUMMY_SWIFT_OUT"
    echo "public var _${EXTENSION_NAME}_dummy_sink: [Any] = []" >> "$DUMMY_SWIFT_OUT"
    echo "" >> "$DUMMY_SWIFT_OUT"
    echo "public struct ${EXTENSION_NAME}Dummy {" >> "$DUMMY_SWIFT_OUT"
    echo "    @inline(never)" >> "$DUMMY_SWIFT_OUT"
    echo "    public static func enforceBundling() {" >> "$DUMMY_SWIFT_OUT"
    echo "        let dummyArray: [Any] = [" >> "$DUMMY_SWIFT_OUT"
    for symbol in $NM_OUTPUT; do
        echo "            dummy_${EXTENSION_NAME}_$symbol as Any," >> "$DUMMY_SWIFT_OUT"
    done
    echo "        ]" >> "$DUMMY_SWIFT_OUT"
    echo "        _${EXTENSION_NAME}_dummy_sink = dummyArray" >> "$DUMMY_SWIFT_OUT"
    echo "        if ProcessInfo.processInfo.environment[\"DEBUG_DUMMY_FRB\"] != nil {" >> "$DUMMY_SWIFT_OUT"
    echo "            print(_${EXTENSION_NAME}_dummy_sink)" >> "$DUMMY_SWIFT_OUT"
    echo "        }" >> "$DUMMY_SWIFT_OUT"
    echo "    }" >> "$DUMMY_SWIFT_OUT"
    echo "}" >> "$DUMMY_SWIFT_OUT"
}
