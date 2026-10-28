// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EggscapeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EggscapeCore", targets: ["EggscapeCore"]),
        .library(name: "EggscapeArt", targets: ["EggscapeArt"]),
    ],
    targets: [
        .target(name: "EggscapeCore"),
        .target(name: "EggscapeArt", dependencies: ["EggscapeCore"]),
        .executableTarget(name: "eggscape-art", dependencies: ["EggscapeArt", "EggscapeCore"]),
        .testTarget(name: "EggscapeCoreTests", dependencies: ["EggscapeCore"]),
        .testTarget(name: "EggscapeArtTests", dependencies: ["EggscapeArt", "EggscapeCore"]),
    ]
)
