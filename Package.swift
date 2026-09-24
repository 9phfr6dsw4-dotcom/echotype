// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoType",
    platforms: [.macOS(.v26)],
    targets: [
        .testTarget(name: "EchoTypeTests")
    ]
)
