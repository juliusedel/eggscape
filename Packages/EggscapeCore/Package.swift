// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EggscapeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EggscapeCore", targets: ["EggscapeCore"]),
    ],
    targets: [
        .target(name: "EggscapeCore"),
        .testTarget(name: "EggscapeCoreTests", dependencies: ["EggscapeCore"]),
    ]
)
