// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "F06Rive",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/rive-app/rive-ios", exact: "6.30.1"),
    ],
    targets: [
        .executableTarget(
            name: "RiveSpike",
            dependencies: [.product(name: "RiveRuntime", package: "rive-ios")]
        ),
        .executableTarget(name: "BaselineSpike"),
    ]
)
