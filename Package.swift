// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EchoStack",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "EchoStack",
            targets: ["EchoStack"]
        ),
    ],
    targets: [
        .target(
            name: "EchoStack",
            path: "Sources/EchoStack"
        ),
        .testTarget(
            name: "EchoStackTests",
            dependencies: ["EchoStack"],
            path: "Tests/EchoStackTests"
        ),
    ]
)
