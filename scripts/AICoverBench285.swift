import Foundation
import CoreML
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Build 285 macOS CI harness: runs the SHIPPING tiled engine (AICoverSREngine.swift) on neutral
// fixtures with each compute-unit set, checks numerical parity against the PyTorch fp32 reference
// (same tiling) and dumps the Core ML compute plan (preferred device per op).
let args = CommandLine.arguments
let modelURL = URL(fileURLWithPath: args[1]), fixtures = URL(fileURLWithPath: args[2]), outDir = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func load(_ url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func save(_ image: CGImage, _ url: URL) {
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, nil); CGImageDestinationFinalize(d)
}
func rgba(_ image: CGImage) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let c = CGContext(data: &b, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return b
}
func psnr(_ a: CGImage, _ b: CGImage) -> Double {
    guard a.width == b.width, a.height == b.height else { return -1 }
    let x = rgba(a), y = rgba(b); var se = 0.0; var n = 0
    for i in stride(from: 0, to: x.count, by: 4) { for c in 0..<3 { let d = Double(x[i + c]) - Double(y[i + c]); se += d * d; n += 1 } }
    return 10 * log10(255 * 255 / max(se / Double(n), 1e-9))
}
var report: [String: Any] = ["host": ProcessInfo.processInfo.operatingSystemVersionString,
                             "cpu": ProcessInfo.processInfo.processorCount, "model": modelURL.lastPathComponent]
let lr = load(fixtures.appendingPathComponent("neutral_378x538.png"))
let mgs = load(fixtures.appendingPathComponent("neutral_422x600.png"))
let ref = load(fixtures.appendingPathComponent("neutral_378x538_torch_ref.png"))
var runs: [[String: Any]] = []
let units: [(String, MLComputeUnits)] = [("cpuOnly", .cpuOnly), ("cpuAndGPU", .cpuAndGPU), ("cpuAndNeuralEngine", .cpuAndNeuralEngine), ("all", .all)]
for (name, unit) in units {
    var row: [String: Any] = ["units": name]
    do {
        let t0 = Date()
        let engine = try AICoverSREngine(modelURL: modelURL, computeUnits: unit)
        row["loadSeconds"] = Date().timeIntervalSince(t0)
        row["tile"] = engine.tile; row["scale"] = engine.scale
        var ticks = 0
        let t1 = Date()
        let out = try engine.upscale(lr, progress: { _ in ticks += 1 })
        row["cover378x538Seconds"] = Date().timeIntervalSince(t1)
        row["tiles"] = ticks
        row["output"] = "\(out.width)x\(out.height)"
        row["psnrVsTorchFP32"] = psnr(out, ref)
        save(out, outDir.appendingPathComponent("neutral_378x538_\(name).png"))
        let t2 = Date()
        let out2 = try engine.upscale(lr)
        row["cover378x538WarmSeconds"] = Date().timeIntervalSince(t2)
        _ = out2
        let t3 = Date()
        let o3 = try engine.upscale(mgs)
        row["mgs422x600Seconds"] = Date().timeIntervalSince(t3)
        row["mgsOutput"] = "\(o3.width)x\(o3.height)"
    } catch { row["error"] = "\(error)" }
    print(row); runs.append(row)
}
report["runs"] = runs
// Compute plan: which device Core ML would prefer for each op (macOS 14.4+ API).
if #available(macOS 14.4, *) {
    let config = MLModelConfiguration(); config.computeUnits = .all
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let plan = try await MLComputePlan.load(contentsOf: modelURL, configuration: config)
            var counts: [String: Int] = [:]; var supported: [String: Int] = [:]; var cost = [String: Double]()
            if case let .program(program) = plan.modelStructure, let main = program.functions["main"] {
                for op in main.block.operations {
                    let usage = plan.deviceUsage(for: op)
                    let pref: String
                    switch usage?.preferred {
                    case .some(.neuralEngine(_)): pref = "ANE"
                    case .some(.gpu(_)): pref = "GPU"
                    case .some(.cpu(_)): pref = "CPU"
                    default: pref = "none"
                    }
                    counts[pref, default: 0] += 1
                    for d in usage?.supported ?? [] {
                        let k: String
                        switch d { case .neuralEngine(_): k = "ANE"; case .gpu(_): k = "GPU"; case .cpu(_): k = "CPU"; @unknown default: k = "?" }
                        supported[k, default: 0] += 1
                    }
                    cost[pref, default: 0] += plan.estimatedCost(of: op)?.weight ?? 0
                }
                report["computePlan"] = ["preferredOps": counts, "supportedOps": supported, "estimatedCostShare": cost, "ops": main.block.operations.count]
            }
        } catch { report["computePlan"] = ["error": "\(error)"] }
        sem.signal()
    }
    sem.wait()
}
let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("bench285.json"))
print(String(data: json, encoding: .utf8)!)
let ok = runs.contains { ($0["psnrVsTorchFP32"] as? Double ?? 0) > 30 }
if !ok { print("FAIL parity"); exit(1) }
print("PASS bench285 parity")
