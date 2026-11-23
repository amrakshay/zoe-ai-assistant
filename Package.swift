// swift-tools-version: 6.2
// Zoe: SwiftPM only, builds with the Command Line Tools (no Xcode project).
import PackageDescription

let package = Package(
    name: "Zoe",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Zoe", targets: ["Zoe"]),
        .executable(name: "zoe-selftest", targets: ["SelfTest"]),
        // Whisper in its own process (#41); bundled next to the app's executable.
        .executable(name: "zoe-stt", targets: ["ZoeSTT"]),
    ],
    dependencies: [
        // ONNX Runtime (MIT) for Silero VAD; same package and version as the F05 wake-word spike.
        // ONNX Runtime 1.24.2, vendored: the upstream package repository is gone (see vendor/…/Package.swift).
        .package(path: "vendor/onnxruntime-swift-package-manager"),
        // WhisperKit (MIT) for speech-to-text; same version as the CLI used in the F04 tests.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.1"),
    ],
    targets: [
        // UI-free logic: core link, framing, supervision. Everything here is testable from the self-test.
        .target(name: "ZoeKit",
                dependencies: [.product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"), "STTWire"],
                path: "app/Sources/ZoeKit"),
        // The app ↔ zoe-stt protocol. Tiny and stable: the helper depends only on this and WhisperKit, so
        // app changes don't rebuild it (and don't make Core ML recompile Whisper for the Neural Engine).
        .target(name: "STTWire", path: "app/Sources/STTWire"),
        .executableTarget(name: "ZoeSTT",
                          dependencies: ["STTWire", .product(name: "WhisperKit", package: "argmax-oss-swift")],
                          path: "app/Sources/ZoeSTT"),
        // The menu-bar app.
        .executableTarget(name: "Zoe", dependencies: ["ZoeKit"], path: "app/Sources/Zoe"),
        // Plain-executable test suite (Swift Testing / XCTest aren't available with the Command Line Tools).
        .executableTarget(name: "SelfTest", dependencies: ["ZoeKit", "STTWire"], path: "app/Sources/SelfTest"),
    ]
)
