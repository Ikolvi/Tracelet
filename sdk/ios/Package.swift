// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TraceletSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "TraceletSDK",
            targets: ["TraceletSDK"]
        ),
    ],
    targets: [
        .target(
            name: "TraceletSDK",
            dependencies: [],
            path: "Sources/TraceletSDK",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "TraceletSDKTests",
            dependencies: ["TraceletSDK"],
            path: "Tests/TraceletSDKTests"
        ),
    ]
)
