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
    targets: [
        // UI-free logic: core link, framing, supervision. Everything here is testable from the self-test.
        .target(name: "ZoeKit", path: "app/Sources/ZoeKit"),
        // The menu-bar app.
        .executableTarget(name: "Zoe", dependencies: ["ZoeKit"], path: "app/Sources/Zoe"),
        // Plain-executable test suite (Swift Testing / XCTest aren't available with the Command Line Tools).
        .executableTarget(name: "SelfTest", dependencies: ["ZoeKit"], path: "app/Sources/SelfTest"),
    ]
)
