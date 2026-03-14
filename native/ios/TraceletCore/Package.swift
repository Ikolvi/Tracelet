// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TraceletCore",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "TraceletCore", targets: ["TraceletCore"]),
    ],
    targets: [
        .target(
            name: "TraceletCore",
            linkerSettings: [
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreMotion"),
                .linkedFramework("UIKit"),
                .linkedFramework("BackgroundTasks"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
