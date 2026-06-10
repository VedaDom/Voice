// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceApp",
            path: "Sources/VoiceApp",
            resources: [.copy("Fonts")]
        ),
        .testTarget(
            name: "VoiceAppTests",
            dependencies: ["VoiceApp"],
            path: "Tests/VoiceAppTests"
        ),
    ]
)
