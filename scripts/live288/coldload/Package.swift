// swift-tools-version:5.9
// Build 288 cold-load CLI (macOS, run under sandbox-exec with network denied): shipping LiveSpeechEngines loader.
import PackageDescription

let package = Package(
    name: "ColdLoad288",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1")],
    targets: [.executableTarget(name: "ColdLoad288", dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")],
                                path: "Sources/ColdLoad288")]
)
