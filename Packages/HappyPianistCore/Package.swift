// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HappyPianistCore",
    platforms: [
        .macOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "MusicXML", targets: ["MusicXML"]),
        .library(name: "MIDI", targets: ["MIDI"]),
        .library(name: "Practice", targets: ["Practice"]),
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
            name: "Practice",
            dependencies: [
                "Diagnostics",
                "MusicXML",
                "MIDI",
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
        .testTarget(
            name: "PracticeTests",
            dependencies: [
                "Practice",
                "Diagnostics",
                "MusicXML",
                "HappyPianistTestFixtures",
            ]
        ),
    ]
)
