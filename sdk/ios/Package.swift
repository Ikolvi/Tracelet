// swift-tools-version:5.9
import PackageDescription

// SwiftPM manifest for running TraceletSDK unit tests on an iOS simulator via
// `xcodebuild test`. The production build still ships as the CocoaPods pod
// (TraceletSDK.podspec); this manifest exists only to give the XCTest suites a
// runnable target. The Rust core is consumed as the prebuilt
// TraceletCore.xcframework (same binary the podspec vendors).
let package = Package(
    name: "TraceletSDK",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "TraceletSDK", targets: ["TraceletSDK"]),
    ],
    targets: [
        // Points at the canonical build output of sdk/rust-core/build-ios.sh —
        // the same path TraceletSDK.podspec vendors. `*.xcframework` is
        // gitignored, so a copy under sdk/ios/ only exists on machines that have
        // manually placed one; CI checks out without it and SwiftPM fails with
        // "does not contain a binary artifact". Run build-ios.sh first.
        .binaryTarget(name: "TraceletCore", path: "../rust-core/out/TraceletCore.xcframework"),
        .target(
            name: "TraceletSDK",
            dependencies: ["TraceletCore"],
            path: "Sources/TraceletSDK",
            // The Rust symbols are provided by `import TraceletCore` (the
            // xcframework). The loose FFI modulemap/header in Sources are for
            // the pod's static-lib link path and would make this a mixed
            // Swift+C target, which SwiftPM disallows — exclude them.
            exclude: [
                "tracelet_coreFFI.modulemap",
                "tracelet_coreFFI.h",
            ]
        ),
        .testTarget(
            name: "TraceletSDKTests",
            dependencies: ["TraceletSDK"],
            path: "Tests/TraceletSDKTests",
            // Only the actively-maintained suite is wired up; the other files in
            // this directory are stale against the current SDK API.
            sources: [
                "LocationEngineRuntimeProviderOptionsTests.swift",
                "MotionDetectorTests.swift",
                "BatteryBudgetRemoteConfigTests.swift",
                "ConfigManagerNumericCoercionTests.swift",
                "SignificantChangesBackgroundSessionTests.swift",
                // #280: pure LocationMapper API (buildLocationMap) — current, not
                // stale — wired up so the persisted-metadata mapping is covered.
                "LocationMapperTests.swift",
                // Geofence transition decision trace. Pins the `[geofence]` tag
                // and field names that the Doctor bug report filters on, so the
                // trace cannot silently drift into being Android-only.
                "GeofenceManagerTransitionLogTests.swift",
            ]
        ),
    ]
)
