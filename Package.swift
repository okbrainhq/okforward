// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OkForward",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OkForward", targets: ["OkForward"])
    ],
    targets: [
        .executableTarget(
            name: "OkForward",
            path: "Sources/OkForward"
        )
    ]
)
