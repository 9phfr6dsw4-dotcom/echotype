// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoType",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoTypeCore", targets: ["EchoTypeCore"])
    ],
    targets: [
        .target(name: "EchoTypeCore"),
        .testTarget(name: "EchoTypeTests", dependencies: ["EchoTypeCore"])
    ]
)
