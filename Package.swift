// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchIsland",
            path: "Sources/NotchIsland",
            exclude: ["JuiceFlow/LICENSE"]
        ),
        .testTarget(
            name: "NotchIslandTests",
            dependencies: ["NotchIsland"],
            path: "Tests/NotchIslandTests"
        ),
    ]
)
