// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "ImprovEngines",
    platforms: [
        .visionOS(.v26),
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
    ],
    products: [
        .library(
            name: "ImprovProtocol",
            targets: ["ImprovProtocol"]
        ),
        .library(
            name: "ImprovEngines",
            targets: ["ImprovEngines"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ImprovProtocol",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .target(
            name: "ImprovEngines",
            dependencies: [
                "ImprovProtocol",
            ],
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ]
)
