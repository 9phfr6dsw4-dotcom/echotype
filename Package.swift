// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoType",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoTypeCore", targets: ["EchoTypeCore"])
    ],
    targets: [
        .target(name: "EchoTypeCore", resources: [.copy("Resources/model-manifest.json")]),
        .testTarget(name: "EchoTypeTests", dependencies: ["EchoTypeCore"])
    ]
)
