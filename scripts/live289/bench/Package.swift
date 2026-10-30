// swift-tools-version:5.9
// Build 289 CI bench: shipping live-subtitle sources (copied in by test-live-bench289.py) on macOS with WhisperKit,
// sherpa-onnx (SenseVoice; macOS dylib from Vendor/sherpa-onnx-macos.xcframework, linked via -Xlinker flags),
// Apple Speech, Core ML NLLB and the FFmpeg reader.
import PackageDescription

let package = Package(
    name: "LiveBench289",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
        .package(url: "https://github.com/kingslay/FFmpegKit.git", from: "6.1.3"),
    ],
    targets: [
        .systemLibrary(name: "SherpaOnnxC", path: "Sources/SherpaOnnxC"),
        .executableTarget(
            name: "LiveBench289",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                "SherpaOnnxC",
            ],
            path: "Sources/LiveBench289"
        ),
    ]
)
