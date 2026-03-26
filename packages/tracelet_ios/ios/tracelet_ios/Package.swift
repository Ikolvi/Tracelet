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
    dependencies: [
        .package(name: "TraceletSDK", path: "../../../../sdk/ios"),
    ],
    targets: [
        .target(
            name: "tracelet_ios",
            dependencies: [
                .product(name: "TraceletSDK", package: "TraceletSDK"),
            ],
            path: "Sources/tracelet_ios",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
