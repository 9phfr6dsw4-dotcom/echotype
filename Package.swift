// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoType",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoTypeCore", targets: ["EchoTypeCore"]),
        .executable(name: "EchoTypeApp", targets: ["EchoTypeApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.2"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0")
    ],
    targets: [
        .target(name: "EchoTypeCore", resources: [.copy("Resources/model-manifest.json")]),
        .executableTarget(
            name: "EchoTypeApp",
            dependencies: [
                "EchoTypeCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .testTarget(name: "EchoTypeTests", dependencies: ["EchoTypeCore"])
    ]
)
