// swift-tools-version: 6.2
// Zoe: SwiftPM only, builds with the Command Line Tools (no Xcode project).
import PackageDescription

let package = Package(
    name: "Zoe",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Zoe", targets: ["Zoe"]),
        .executable(name: "zoe-selftest", targets: ["SelfTest"]),
    ],
    dependencies: [
        // ONNX Runtime (MIT) for Silero VAD; same package and version as the F05 wake-word spike.
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
        // WhisperKit (MIT) for speech-to-text; same version as the CLI used in the F04 tests.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.1"),
    ],
    targets: [
        // UI-free logic: core link, framing, supervision. Everything here is testable from the self-test.
        .target(name: "ZoeKit",
                dependencies: [.product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
                               .product(name: "WhisperKit", package: "argmax-oss-swift")],
                path: "app/Sources/ZoeKit"),
        // The menu-bar app.
        .executableTarget(name: "Zoe", dependencies: ["ZoeKit"], path: "app/Sources/Zoe"),
        // Plain-executable test suite (Swift Testing / XCTest aren't available with the Command Line Tools).
        .executableTarget(name: "SelfTest", dependencies: ["ZoeKit"], path: "app/Sources/SelfTest"),
    ]
)
