// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CLIPulseCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "CLIPulseCore",
            targets: ["CLIPulseCore"]
        ),
    ],
    targets: [
        .target(
            name: "CLIPulseCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CLIPulseCoreTests",
            dependencies: ["CLIPulseCore"]
        ),
    ]
)
