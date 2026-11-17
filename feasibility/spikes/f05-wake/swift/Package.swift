// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "F05Wake",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
    ],
    targets: [
        .executableTarget(
            name: "F05Wake",
            dependencies: [.product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")],
            path: "Sources/F05Wake"
        ),
    ]
)
