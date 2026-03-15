// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tracelet_ios",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(name: "tracelet-ios", targets: ["tracelet_ios"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "tracelet_ios",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("tracelet_ios/PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("UIKit"),
                .linkedFramework("BackgroundTasks"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Network"),
            ]
        )
    ]
)
