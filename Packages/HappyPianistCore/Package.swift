// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HappyPianistCore",
    products: [
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Diagnostics",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(
            name: "DiagnosticsTests",
            dependencies: [
                "Diagnostics",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
    ]
)
