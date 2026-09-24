// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoType",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoTypeCore", targets: ["EchoTypeCore"]),
        .executable(name: "EchoTypeApp", targets: ["EchoTypeApp"])
    ],
    targets: [
        .target(name: "EchoTypeCore", resources: [.copy("Resources/model-manifest.json")]),
        .executableTarget(name: "EchoTypeApp", dependencies: ["EchoTypeCore"]),
        .testTarget(name: "EchoTypeTests", dependencies: ["EchoTypeCore"])
    ]
)
