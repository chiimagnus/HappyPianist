// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PianoKeyCLI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "pianokey-cli", targets: ["PianoKeyCLI"])
    ],
    targets: [
        .executableTarget(
            name: "PianoKeyCLI",
            path: "Sources/PianoKeyCLI"
        )
    ]
)
