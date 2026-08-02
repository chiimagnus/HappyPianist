// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HappyPianistCore",
    products: [
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "MusicXML", targets: ["MusicXML"]),
        .library(name: "MIDI", targets: ["MIDI"]),
        .library(name: "HappyPianistTestFixtures", targets: ["HappyPianistTestFixtures"]),
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
        .target(
            name: "MusicXML",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .target(
            name: "MIDI",
            dependencies: [
                "Diagnostics",
            ]
        ),
        .target(
            name: "HappyPianistTestFixtures",
            resources: [
                .copy("Resources/Fixtures"),
            ]
        ),
        .testTarget(
            name: "MusicXMLTests",
            dependencies: [
                "MusicXML",
                "HappyPianistTestFixtures",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(
            name: "MIDITests",
            dependencies: [
                "MIDI",
                "Diagnostics",
            ]
        ),
    ]
)
