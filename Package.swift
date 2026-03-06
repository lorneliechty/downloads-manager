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
        .executable(
            name: "dm-app",
            targets: ["dm-app"]
        ),
        .executable(
            name: "dm-test",
            targets: ["dm-test"]
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
        .executableTarget(
            name: "dm-app",
            dependencies: ["DownloadsManager"],
            path: "Sources/dm-app"
        ),
        .executableTarget(
            name: "dm-test",
            dependencies: ["DownloadsManager"],
            path: "Sources/dm-test"
        ),
    ]
)
