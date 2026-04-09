// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "icloud_storage_plus_foundation",
    platforms: [
        .macOS("10.15"),
    ],
    products: [
        .library(
            name: "icloud_storage_plus_foundation",
            targets: ["icloud_storage_plus_foundation"]
        ),
    ],
    targets: [
        .target(
            name: "icloud_storage_plus_foundation",
            path: ".",
            exclude: ["Package.swift", "Tests"]
        ),
        .testTarget(
            name: "icloud_storage_plus_foundationTests",
            dependencies: ["icloud_storage_plus_foundation"],
            path: "Tests/icloud_storage_plus_foundationTests"
        ),
    ]
)
