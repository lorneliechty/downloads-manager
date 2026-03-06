// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DownloadsManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DownloadsManager",
            targets: ["DownloadsManager"]
        ),
        .executable(
            name: "dm",
            targets: ["dm-cli"]
        ),
    ],
    targets: [
        .target(
            name: "DownloadsManager",
            path: "Sources/DownloadsManager"
        ),
        .executableTarget(
            name: "dm-cli",
            dependencies: ["DownloadsManager"],
            path: "Sources/dm-cli"
        ),
        .testTarget(
            name: "DownloadsManagerTests",
            dependencies: ["DownloadsManager"],
            path: "Tests/DownloadsManagerTests"
        ),
    ]
)
