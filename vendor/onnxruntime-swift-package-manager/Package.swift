// swift-tools-version:5.9
// Vendored from microsoft/onnxruntime-swift-package-manager 1.24.2 (MIT, see LICENSE; revision
// b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2). The upstream GitHub repository returned 404 from 2026-11-20, so
// SwiftPM could no longer clone it. Only the inference bindings are kept (no training, extensions or tests);
// the ONNX Runtime binary itself is still Microsoft's release archive, verified by its SHA-256 checksum.

import PackageDescription

let package = Package(
    name: "onnxruntime",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "onnxruntime", type: .static, targets: ["OnnxRuntimeBindings"]),
    ],
    targets: [
        .target(name: "OnnxRuntimeBindings",
                dependencies: ["onnxruntime"],
                path: "objectivec",
                cxxSettings: [.define("SPM_BUILD")]),
        .binaryTarget(name: "onnxruntime",
                      url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip",
                      checksum: "f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54"),
    ],
    cxxLanguageStandard: .cxx17
)
