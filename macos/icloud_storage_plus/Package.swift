// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to
// build this package.

import PackageDescription

let package = Package(
    name: "icloud_storage_plus",
    platforms: [
        .macOS("10.15"),
    ],
    products: [
        // If the plugin name contains "_", replace with "-" for the library name.
        .library(name: "icloud-storage-plus", targets: ["icloud_storage_plus"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "icloud_storage_plus",
            dependencies: [],
            resources: [
                // If this plugin requires a privacy manifest (e.g. uses required
                // reason APIs), add `PrivacyInfo.xcprivacy` under
                // `Sources/icloud_storage_plus/` and uncomment:
                // .process("PrivacyInfo.xcprivacy"),
            ],
            cSettings: [
                .headerSearchPath("include/icloud_storage_plus"),
            ]
        ),
    ]
)

