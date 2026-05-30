// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OkForward",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OkForwardCore", targets: ["OkForwardCore"]),
        .executable(name: "OkForward", targets: ["OkForward"])
    ],
    targets: [
        .target(
            name: "OkForwardCore",
            path: "Sources/OkForwardCore"
        ),
        .executableTarget(
            name: "OkForward",
            dependencies: ["OkForwardCore"],
            path: "Sources/OkForward",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OkForwardCoreTests",
            dependencies: ["OkForwardCore"],
            path: "Tests/OkForwardCoreTests"
        )
    ]
)
