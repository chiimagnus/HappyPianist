// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HappyPianistShared",
    platforms: [
        .macOS(.v14),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "HappyPianistShared",
            targets: ["HappyPianistShared"]
        ),
    ],
    targets: [
        .target(
            name: "HappyPianistShared",
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .testTarget(
            name: "HappyPianistSharedTests",
            dependencies: ["HappyPianistShared"]
        ),
    ]
)
