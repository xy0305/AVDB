// swift-tools-version:5.9
// Build 287 CI bench: the shipping LiveSubtitleCore / LiveAudioReader / LiveSpeechEngines / LiveAppleTranslation
// sources (copied in by prepare_bench287.py) driven on macOS with real WhisperKit + Core ML NLLB + FFmpeg HLS.
import PackageDescription

let package = Package(
    name: "LiveBench287",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
        .package(url: "https://github.com/kingslay/FFmpegKit.git", from: "6.1.3"),
    ],
    targets: [
        .executableTarget(
            name: "LiveBench287",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FFmpegKit", package: "FFmpegKit"),
            ],
            path: "Sources/LiveBench287"
        ),
    ]
)
