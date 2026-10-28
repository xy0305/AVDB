// Port of 网页视频实时 LUT @author You @version 6.7.5.
// Source metadata retained in THIRD_PARTY/lut-v6.7.5.txt; no license inferred.
import SwiftUI
import AVFoundation
import CoreImage
import MediaPipeTasksVision
import UIKit
import JavaScriptCore
import KSPlayer
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct LUTParameters: Equatable {
    // temperature, tint, saturation, brightness, contrast, highlights, shadows
    var values: [Double] = [0, 0, 0, 0, 0, 0, 0]
    static let names = ["色温", "色调", "饱和度", "亮度", "对比度", "高光", "阴影"]
}

// Each invocation owns an isolated JavaScriptCore VM; no DOM, network or WebGL.
// Analysis is called only from the detached worker. Cube generation uses its own VM.
enum NativeLUT {
    private static func engine() -> JSContext? {
        guard let url = Bundle.main.url(forResource: "OriginalLUT", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { return nil }
        context.evaluateScript(source)
        guard context.exception == nil else { return nil }
        return context
    }
    static func analyze(bytes: [UInt8], width: Int, height: Int, box: [String: Int]?) -> (LUTParameters, String)? {
        guard let context = engine(),
              let result = context.objectForKeyedSubscript("OriginalLUT")?.objectForKeyedSubscript("analyzeFrame")?.call(withArguments: [bytes, width, height, box as Any? ?? NSNull()]),
              context.exception == nil, !result.isNull, !result.isUndefined,
              let dict = result.toDictionary(), let params = dict["params"] as? [String: Any] else { return nil }
        let keys = ["temp", "tint", "sat", "bright", "contrast", "highlight", "shadow"]
        let values = keys.compactMap { (params[$0] as? NSNumber)?.doubleValue }
        guard values.count == 7, values.allSatisfy({ $0.isFinite }) else { return nil }
        return (LUTParameters(values: values), dict["stage"] as? String ?? "标准")
    }
    static func cube(_ p: LUTParameters) -> Data? {
        guard p.values.count == 7, p.values.allSatisfy({ $0.isFinite }), let context = engine(),
              let result = context.objectForKeyedSubscript("OriginalLUT")?.objectForKeyedSubscript("cubeRGBA")?.call(withArguments: [p.values]),
              context.exception == nil, let numbers = result.toArray() as? [NSNumber], numbers.count == 33*33*33*4 else { return nil }
        let floats = numbers.map { $0.floatValue }
        guard floats.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { return nil }
        return floats.withUnsafeBytes { Data($0) }
    }
}

// Mobile equivalents: bounded local sampling, safe cube interchange, per-item presets.
struct LUTArchive: Codable, Equatable {
    var size: Int
    var rgba: Data
    var domainMin: [Double] = [0,0,0]
    var domainMax: [Double] = [1,1,1]
    static func parse(_ text: String) throws -> LUTArchive {
        guard text.utf8.count <= 24*1024*1024 else { throw LUTError.invalid("CUBE 超过 24 MiB") }
        var n = 0, lo = [0.0,0,0], hi = [1.0,1,1], data = [Float]()
        var seenSize = false, seenMin = false, seenMax = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("TITLE ") { continue }
            let v = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if v[0] == "LUT_3D_SIZE" {
                guard !seenSize, v.count == 2, let dim = Int(v[1]), (2...65).contains(dim) else { throw LUTError.invalid("仅支持 2…65 的 3D CUBE") }
                n = dim; seenSize = true; continue
            }
            if v[0] == "DOMAIN_MIN" || v[0] == "DOMAIN_MAX" {
                let a = v.dropFirst().compactMap(Double.init)
                guard a.count == 3, a.allSatisfy({ $0.isFinite && abs($0) <= 16 }) else { throw LUTError.invalid("无效 DOMAIN") }
                if v[0] == "DOMAIN_MIN" { guard !seenMin else { throw LUTError.invalid("重复 DOMAIN") }; lo = a; seenMin = true }
                else { guard !seenMax else { throw LUTError.invalid("重复 DOMAIN") }; hi = a; seenMax = true }
                continue
            }
            let a = v.compactMap(Float.init)
            guard seenSize, a.count == 3, a.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }), data.count < n*n*n*4 else { throw LUTError.invalid("无效或越界的 RGB 数据（不支持 1D/混合 CUBE）") }
            data.append(contentsOf: a); data.append(1)
        }
        guard seenSize, data.count == n*n*n*4, (0..<3).allSatisfy({ hi[$0] > lo[$0] }) else { throw LUTError.invalid("CUBE 维数/条目/DOMAIN 不匹配") }
        return LUTArchive(size: n, rgba: data.withUnsafeBytes { Data($0) }, domainMin: lo, domainMax: hi)
    }
    func text() -> String {
        var out = "TITLE \"AVDB SDR v8.3\"\n# Red fastest; nonlinear sRGB; strength/enhancements not baked\nLUT_3D_SIZE \(size)\nDOMAIN_MIN \(domainMin.map(String.init(describing:)).joined(separator: " "))\nDOMAIN_MAX \(domainMax.map(String.init(describing:)).joined(separator: " "))\n"
        rgba.withUnsafeBytes { raw in
            let f = raw.bindMemory(to: Float.self)
            for i in stride(from: 0, to: f.count, by: 4) { out += String(format: "%.8f %.8f %.8f\n", locale: Locale(identifier: "en_US_POSIX"), f[i], f[i+1], f[i+2]) }
        }
        return out
    }
}
enum LUTError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(s) = self { return s }; return nil }
}
struct LUTPreset: Codable {
    var values: [Double]
    var faithful: Bool
    var cube: LUTArchive?
}
struct LUTFullResult {
    var parameters: LUTParameters
    var info: [Double]
    var after: [Double]
    var pixels: [[Double]]
    var summary: String
}
struct LUTFrame: @unchecked Sendable { let image: CGImage }
extension NativeLUT {
    static func bake(_ p: LUTParameters, faithful: Bool, size: Int = 33) -> Data? {
        if !faithful && size == 33 { return cube(p) }
        guard p.values.count == 7, p.values.allSatisfy({ $0.isFinite && abs($0) <= 100 }), let ctx = engine() else { return nil }
        let script = faithful ? "Desktop83.cubeRGBA(inputValues, inputSize)" : "OriginalLUT.generateLutData(inputValues, inputSize)"
        ctx.setObject(p.values, forKeyedSubscript: "inputValues" as NSString)
        ctx.setObject(size, forKeyedSubscript: "inputSize" as NSString)
        // Safe-mode exports at 65 are trilinear resamples of the exact applied 33 cube.
        if !faithful { guard let data = cube(p) else { return nil }; return resample(data, to: size) }
        guard let values = ctx.evaluateScript(script)?.toArray() as? [NSNumber], ctx.exception == nil, values.count == size*size*size*4 else { return nil }
        let f = values.map { $0.floatValue }; guard f.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { return nil }
        return f.withUnsafeBytes { Data($0) }
    }
    static func resample(_ data: Data, to n: Int) -> Data? {
        guard [33,65].contains(n), data.count == 33*33*33*16 else { return nil }
        let f = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var out = [Float](); out.reserveCapacity(n*n*n*4)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let q = [r,g,b].map { Double($0)*32/Double(n-1) }, low = q.map { Int(floor($0)) }, frac = q.enumerated().map { $0.element-Double(low[$0.offset]) }
            for c in 0..<3 {
                var v = 0.0
                for z in 0...1 { for y in 0...1 { for x in 0...1 {
                    let ix = min(32,low[0]+x), iy = min(32,low[1]+y), iz = min(32,low[2]+z)
                    v += Double(f[((iz*33+iy)*33+ix)*4+c])*(x==0 ? 1-frac[0]:frac[0])*(y==0 ? 1-frac[1]:frac[1])*(z==0 ? 1-frac[2]:frac[2])
                } } }
                out.append(Float(v))
            }; out.append(1)
        } } }
        return out.withUnsafeBytes { Data($0) }
    }
    static func fullAnalyze(_ frames: [LUTFrame], faithful: Bool) -> LUTFullResult? {
        guard let ctx = engine() else { return nil }
        var samples = [[[Double]]](), safe = [[Double]]()
        var detectionText = ""
        for frame in frames {
            if Task.isCancelled { return nil }
            let image = frame.image, w = image.width, h = image.height
            var bytes = [UInt8](repeating: 0, count: w*h*4)
            guard let draw = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            draw.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            // Same raster sent to model and sampler, not an independently flipped buffer.
            guard let provider = CGDataProvider(data: Data(bytes) as CFData), let raster = CGImage(width: w,height: h,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: w*4,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent) else { continue }
            let detection = OriginalFaceLandmarker.shared.region(image: raster); detectionText = detection.description
            let args: [Any] = [bytes,w,h,detection.box as Any? ?? NSNull()]
            if let a = ctx.objectForKeyedSubscript("Desktop83")?.objectForKeyedSubscript("select")?.call(withArguments: args)?.toArray() as? [[NSNumber]] { samples.append(a.map { $0.map(\.doubleValue) }) }
            if !faithful, let p = analyze(bytes: bytes,width: w,height: h,box: detection.box) { safe.append(p.0.values) }
        }
        guard let d = ctx.objectForKeyedSubscript("Desktop83")?.objectForKeyedSubscript("analyze")?.call(withArguments: [samples])?.toDictionary(), ctx.exception == nil,
              let values = d["values"] as? [Double], values.count == 7,
              let info = d["info"] as? [Double], let after = d["after"] as? [Double], let pixels = d["pixels"] as? [[Double]] else { return nil }
        var p = values
        if !faithful {
            guard !safe.isEmpty else { return nil }
            p = (0..<7).map { i in let a = safe.map { $0[i] }.sorted(); return a[a.count/2] }
        }
        return LUTFullResult(parameters: LUTParameters(values: p),info: info,after: after,pixels: pixels,summary: "\(faithful ? "v8.3 原版数值" : "267 保护") · \(d["stage"] ?? "") · 有效帧 \(d["frames"] ?? 0) · \(d["direction"] ?? "") · \(detectionText)")
    }
    static func adjustedStats(_ pixels: [[Double]], _ p: LUTParameters, faithful: Bool) -> [Double]? {
        guard let ctx = engine(), !pixels.isEmpty else { return nil }
        ctx.setObject(pixels, forKeyedSubscript: "samplePixels" as NSString)
        ctx.setObject(p.values, forKeyedSubscript: "sampleParams" as NSString)
        let script = faithful ? "Desktop83.stats(samplePixels.map(x=>Desktop83.pixel(x,sampleParams,true)))" : "Object.values(OriginalLUT.sampleSkinStats(OriginalLUT.applyParamsToSkinArray(samplePixels.flat(),{temp:sampleParams[0],tint:sampleParams[1],sat:sampleParams[2],bright:sampleParams[3],contrast:sampleParams[4],highlight:sampleParams[5],shadow:sampleParams[6]})))"
        return ctx.evaluateScript(script)?.toArray() as? [Double]
    }
}

/// One decoded frame, two CoreImage branches. Never touches the main actor per frame.
final class LUTRevealState: @unchecked Sendable {
    private let lock = NSLock()
    private var start: TimeInterval?
    private var covered = false
    private var active = false
    private var reduceMotion = false
    private var split: Double?
    func setSplit(_ value: Double?) { lock.lock(); split = value; lock.unlock() }
    func begin(reduceMotion: Bool) {
        lock.lock(); defer { lock.unlock() }
        self.reduceMotion = reduceMotion; active = true
        start = covered ? nil : ProcessInfo.processInfo.systemUptime
    }
    func setCovered(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        covered = value
        if !value && active { start = ProcessInfo.processInfo.systemUptime }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        active = false; start = nil
    }
    /// Left original initially occupies half the frame, then shrinks to zero.
    func originalFraction(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        lock.lock(); defer { lock.unlock() }
        if let split { return split }
        guard active, !reduceMotion else { return 0 }
        guard let start else { return 0.5 }
        return max(0, min(0.5, 0.5 * (1 - max(0, now - start - 0.35))))
    }
    static func composite(original: CIImage, filtered: CIImage, originalFraction: Double) -> CIImage {
        let extent = original.extent
        let fraction = max(0, min(1, originalFraction))
        guard fraction > 0 else { return filtered.cropped(to: extent) }
        let left = CGRect(x: extent.minX, y: extent.minY, width: extent.width * fraction, height: extent.height)
        return original.cropped(to: left).composited(over: filtered).cropped(to: extent)
    }
}

@MainActor
final class NativeLUTController: ObservableObject {
    @Published var faithful = false
    @Published var sampleProgress = 0.0
    @Published var sampling = false
    @Published var statisticsBefore: [Double] = []
    @Published var statisticsAfter: [Double] = []
    @Published var predicted = LUTParameters()
    @Published var exportSize = 33
    @Published var exportedURL: URL?
    @Published var presetAuto = true
    private var importedCube: LUTArchive?
    private var cachedFaithful = false
    private var samplePixels = [[Double]]()
    private var decodedFrames = [LUTFrame]()
    private var lastDecodedTime = -Double.infinity
    private var sampleTask: Task<Void, Never>?
    private var sampleTimeout: Task<Void, Never>?
    private var imageGenerator: AVAssetImageGenerator?
    private var workRevision = 0
    private var statsTask: Task<Void, Never>?
    private var statsRevision = 0
    private var sampleWorker: Task<LUTFullResult?, Never>?
    private var exportTask: Task<Void, Never>?
    private var exportRevision = 0
    private var presetURL: URL? {
        guard let url = (item?.asset as? AVURLAsset)?.url,
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return base.appendingPathComponent("LUTPresets", isDirectory: true).appendingPathComponent(hash+".json")
    }
    func switchMode(_ next: Bool) {
        cancelSampling(); buildGeneration += 1; buildTask?.cancel(); faithful = next; importedCube = nil; cachedCube = nil; cachedParameters = nil
        parameters = LUTParameters(); predicted = parameters; statisticsBefore = []; statisticsAfter = []
        samplePixels = []; enabled = false; item?.videoComposition = original
        status = next ? "v8.3 原版数值：使用桌面模板/0.67亮度/0.57对比度/0.92过曝阈值；不等同267保护模式" : "267 保护模式：保留中性肤色、近白及有界安全搜索"
    }
    func cancelSampling() {
        workRevision += 1; analysisGeneration += 1; sampleTask?.cancel(); sampleWorker?.cancel(); sampleTimeout?.cancel()
        imageGenerator?.cancelAllCGImageGeneration(); imageGenerator = nil
        sampling = false; busy = false; requested = false; decodedFrames = []; sampleProgress = 0
        status = "分析已停止；晚到结果已隔离"
    }
    private func accept(_ result: LUTFullResult?, revision: Int, source: Int) {
        guard revision == workRevision, source == generation else { return }
        sampling = false; busy = false; sampleTimeout?.cancel(); imageGenerator = nil; decodedFrames = []
        guard let result else { status = "没有足够有效肤色数据；未自动套用默认模板，可手动调参或导入 CUBE"; return }
        parameters = result.parameters; predicted = parameters; importedCube = nil
        statisticsBefore = result.info; samplePixels = result.pixels; statisticsAfter = result.after
        enabled = true; sampleProgress = 1; apply(); refreshStatistics(); status = result.summary
    }
    private func finishFrames(_ frames: [LUTFrame], revision: Int, source: Int) {
        let mode = faithful
        sampleWorker?.cancel()
        let worker = Task.detached(priority: .userInitiated) { NativeLUT.fullAnalyze(frames, faithful: mode) }
        sampleWorker = worker
        sampleTask = Task { [weak self] in
            let result = await worker.value
            guard !Task.isCancelled else { return }
            self?.accept(result, revision: revision, source: source)
        }
    }
    func sampleLocalAsset(_ supplied: AVAsset? = nil) {
        cancelSampling()
        guard let asset = supplied ?? item?.asset, let url = (asset as? AVURLAsset)?.url, url.isFileURL else {
            status = "仅本地视频允许随机多时间点取样；网络素材请播放后积累已解码帧，不额外下载"; return
        }
        let revision = workRevision, source = generation
        sampling = true; sampleProgress = 0; status = "本地有限采样：24点 / 20秒超时；不会扫全片"
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
        imageGenerator = generator
        sampleTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.workRevision == revision else { return }
            self.cancelSampling(); self.status = "采样超时，已取消，原播放不受影响"
        }
        sampleTask = Task { [weak self] in
            guard let self else { return }
            do {
                let duration = try await asset.load(.duration).seconds
                guard duration.isFinite, duration > 0 else { throw LUTError.invalid("视频时长不可用") }
                var frames = [LUTFrame]()
                for i in 0..<24 {
                    try Task.checkCancellation()
                    guard revision == workRevision, source == generation else { return }
                    let time = duration * (0.05 + 0.9*(Double(i)+0.5)/24)
                    if let (cg, _) = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) { frames.append(LUTFrame(image: cg)) }
                    sampleProgress = Double(i+1)/24
                }
                guard revision == workRevision, source == generation, !Task.isCancelled else { return }
                finishFrames(frames, revision: revision, source: source)
            } catch {
                guard revision == workRevision, !Task.isCancelled else { return }
                cancelSampling(); status = "本地采样失败：\(error.localizedDescription)"
            }
        }
    }
    func importMedia(_ urls: [URL]) {
        // Picker access is explicit. Decode only user-selected local files; never persist source images.
        cancelSampling(); let revision = workRevision, source = generation
        sampling = true
        sampleTask = Task { [weak self] in
            guard let self else { return }
            var frames = [LUTFrame]()
            for (index,url) in urls.prefix(24).enumerated() {
                guard revision == workRevision, !Task.isCancelled else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let cg = CGImageSourceCreateThumbnailAtIndex(src,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:640,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) { frames.append(LUTFrame(image:cg)) }
                sampleProgress = Double(index+1)/Double(min(24,urls.count))
            }
            guard revision == workRevision, !Task.isCancelled else { return }
            finishFrames(frames,revision:revision,source:source)
        }
    }
    func refreshStatistics() {
        statsRevision += 1; let revision = statsRevision
        statsTask?.cancel(); let pixels = samplePixels, params = parameters, mode = faithful
        guard importedCube == nil, !pixels.isEmpty else { statisticsAfter = []; return }
        statsTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            let after = await Task.detached { NativeLUT.adjustedStats(pixels,params,faithful:mode) }.value
            guard !Task.isCancelled, let self, self.statsRevision == revision else { return }
            self.statisticsAfter = after ?? []
        }
    }
    func manualChange(_ i: Int, _ value: Double) { cancelSampling(); importedCube = nil; parameters.values[i] = value; enabled = true; apply(); refreshStatistics() }
    func restorePrediction() { cancelSampling(); importedCube = nil; parameters = predicted; enabled = true; apply(); refreshStatistics() }
    func importCube(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 24*1024*1024 else { throw LUTError.invalid("CUBE 超过 24 MiB") }
            let archive = try LUTArchive.parse(String(contentsOf: url,encoding: .utf8))
            cancelSampling(); importedCube = archive; enabled = true; apply(); statisticsAfter = []
            status = "已导入 \(archive.size)³ CUBE（真实 DOMAIN）；手动调参会改回参数 LUT"
        } catch { status = "CUBE 导入失败：\(error.localizedDescription)" }
    }
    func exportCube() {
        exportRevision += 1; let revision = exportRevision
        exportTask?.cancel()
        let params = parameters, mode = faithful, size = exportSize, imported = importedCube
        exportTask = Task { [weak self] in
            let archive = await Task.detached(priority: .userInitiated) { () -> LUTArchive? in
                if let imported { return imported }
                guard let data = NativeLUT.bake(params,faithful:mode,size:size) else { return nil }
                return LUTArchive(size:size,rgba:data)
            }.value
            guard !Task.isCancelled, let self, self.exportRevision == revision, let archive else { return }
            do {
                let text = await Task.detached { archive.text() }.value
                guard !Task.isCancelled, self.exportRevision == revision else { return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("AVDB-LUT-\(UUID().uuidString).cube")
                try text.write(to:url,atomically:true,encoding:.utf8); exportedURL = url
                status = "CUBE 已生成，可分享/存储到文件；不含锐化、去色带或强度混合"
            } catch { status = error.localizedDescription }
        }
    }
    func savePreset(universal: Bool = false) {
        guard let url = universal ? universalPresetURL : presetURL else { return }
        do {
            let preset = LUTPreset(values: parameters.values,faithful:faithful,cube:importedCube)
            let data = try JSONEncoder().encode(preset)
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:url,options:.atomic); status = universal ? "已设为通用 LUT" : "已保存当前素材关联 LUT"
        } catch { status = error.localizedDescription }
    }
    private var universalPresetURL: URL? { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("LUTPresets/universal.json") }
    func loadPreset(universal: Bool = false) {
        let url = universal ? universalPresetURL : presetURL
        guard let url, let data = try? Data(contentsOf:url), data.count <= 8*1024*1024,
              let preset = try? JSONDecoder().decode(LUTPreset.self,from:data), preset.values.count == 7,
              preset.values.allSatisfy({ $0.isFinite && abs($0) <= 100 }) else { return }
        if let c = preset.cube { guard (2...65).contains(c.size), c.rgba.count == c.size*c.size*c.size*16, c.domainMin.count == 3, c.domainMax.count == 3 else { return } }
        cancelSampling(); faithful = preset.faithful; parameters = LUTParameters(values:preset.values)
        importedCube = preset.cube; enabled = true; cachedCube = nil; cachedParameters = nil; apply()
    }
    func deletePreset(universal: Bool = false) {
        if let url = universal ? universalPresetURL : presetURL { try? FileManager.default.removeItem(at:url) }
        status = universal ? "已删除通用 LUT" : "已删除当前素材关联"
    }
    func clearAllPresets() {
        if let url = universalPresetURL?.deletingLastPathComponent() { try? FileManager.default.removeItem(at:url) }
        exportedURL = nil; samplePixels = []; statisticsBefore = []; statisticsAfter = []; status = "已清除全部本地预设与分析统计；源图从未保存"
    }

    @Published var enabled = false
    @Published var status = "LUT 未启用（仅 SDR 文件视频）"
    @Published var parameters = LUTParameters()
    @Published var strength = 1.0
    @Published var sharpen = false
    @Published var sharpness = 0.10
    @Published var deband = false
    @Published var threshold = 0.002
    @Published var radius = 8.0
    @Published var comparison = false
    @Published var divider = 0.5
    @Published var safePerformance = true
    private var buildTask: Task<Void, Never>?
    private var buildGeneration = 0
    private var cachedCube: Data?
    private var cachedParameters: LUTParameters?
    private weak var avPlayer: AVPlayer?
    func updateComparison() { reveal.setSplit(comparison ? divider : nil) }
    func pauseComparison() { avPlayer?.pause(); comparison = true; updateComparison() }
    private var constrained: Bool {
        safePerformance && (ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical)
    }
    private var lastConstrained = false
    private static let debandKernel: CIKernel? = {
        guard let url = Bundle.main.url(forResource: "Enhancement", withExtension: "metallib"), let data = try? Data(contentsOf: url) else { return nil }
        return try? CIKernel(functionName: "avdbDeband", fromMetalLibraryData: data)
    }()
    private weak var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var original: AVVideoComposition?
    private var requested = true
    private var busy = false
    private var generation = 0
    private var analysisGeneration = 0
    private let reveal = LUTRevealState()
    func setPanelCovered(_ covered: Bool) { reveal.setCovered(covered) }
    private var composition: AVVideoComposition?
    private let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    private(set) var supported = false
    private var formatTask: Task<Void, Never>?
    private var formatTimeout: Task<Void, Never>?

    private func finishFormatCheck(_ token: Int, _ next: AVPlayerItem, message: String, ready: Bool = false) {
        guard generation == token, item === next else { return }
        formatTimeout?.cancel(); formatTimeout = nil
        formatTask?.cancel(); formatTask = nil
        supported = ready; enabled = false; status = message
        if ready {
            let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            next.add(out); output = out
            if presetAuto { loadPreset(universal: true); loadPreset() }
        }
    }

    func tick(_ player: KSAVPlayer?) {
        // A transient backend/layer gap is not an item change; do not destroy format state.
        guard let next = player?.player.currentItem else { return }
        avPlayer = player?.player
        if lastConstrained != constrained { lastConstrained = constrained; apply() }
        if item !== next {
            detach(); item = next; original = next.videoComposition
            status = "检查视频格式…"
            let token = generation
            // Reject known HLS before any remote AVAsset property loading.
            if (next.asset as? AVURLAsset)?.url.pathExtension.lowercased() == "m3u8" {
                finishFormatCheck(token, next, message: "HLS 不支持原生 composition LUT")
                return
            }
            formatTimeout = Task { [weak self, weak next] in
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                guard let self, let next, self.generation == token, self.item === next else { return }
                // Invalidate first: even a property loader ignoring cancellation cannot publish late.
                self.finishFormatCheck(token, next, message: "格式检查超时，LUT 已禁用；视频可继续播放")
                self.generation += 1
            }
            formatTask = Task { [weak self, weak next] in
                guard let self, let next else { return }
                do {
                    let tracks = try await next.asset.loadTracks(withMediaType: .video)
                    try Task.checkCancellation()
                    guard let track = tracks.first else {
                        finishFormatCheck(token, next, message: "未发现视频轨道，LUT 已禁用")
                        return
                    }
                    let descriptions = try await track.load(.formatDescriptions)
                    try Task.checkCancellation()
                    guard !descriptions.isEmpty else {
                        finishFormatCheck(token, next, message: "视频格式信息为空，LUT 已禁用")
                        return
                    }
                    let hdr = descriptions.contains { d in
                        guard let extensions = CMFormatDescriptionGetExtensions(d) else { return false }
                        let ext = extensions as NSDictionary
                        let transfer = ext[kCMFormatDescriptionExtension_TransferFunction] as? String
                        return transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                    }
                    let playable = try await next.asset.load(.isComposable)
                    guard generation == token, item === next else { return }
                    try Task.checkCancellation()
                    guard generation == token, item === next else { return }
                    guard playable && !hdr else {
                        finishFormatCheck(token, next, message: hdr ? "HDR 不支持 LUT" : "此视频不支持原生 composition LUT（HLS/非可合成流）")
                        return
                    }
                    finishFormatCheck(token, next, message: "SDR 就绪，点击开启 LUT", ready: true)
                } catch {
                    guard !Task.isCancelled else { return }
                    finishFormatCheck(token, next, message: "格式检查失败，LUT 已禁用：\(error.localizedDescription)")
                }
            }
        }
        if supported && enabled && requested && !busy { analyze() }
    }
    func detach() {
        cancelSampling(); statsRevision += 1; statsTask?.cancel(); exportRevision += 1; exportTask?.cancel()
        importedCube = nil; statisticsBefore = []; statisticsAfter = []; samplePixels = []; exportedURL = nil
        generation += 1
        buildGeneration += 1; buildTask?.cancel(); cachedCube = nil; cachedParameters = nil
        sharpen = false; deband = false; comparison = false; reveal.setSplit(nil)
        analysisGeneration += 1
        reveal.cancel()
        formatTask?.cancel(); formatTask = nil
        formatTimeout?.cancel(); formatTimeout = nil
        enabled = false
        status = "等待播放器视频轨道；LUT 未启用"
        if let item { item.videoComposition = original; if let output { item.remove(output) } }
        item = nil; output = nil; original = nil; composition = nil
        supported = false; busy = false; requested = true
    }
    func toggle() {
        guard supported else { return }
        enabled.toggle()
        if enabled && cachedCube == nil {
            requested = true
            buildGeneration += 1; buildTask?.cancel()
            item?.videoComposition = original
            return
        }
        if !enabled { analysisGeneration += 1; busy = false }
        apply()
    }
    func reanalyze() {
        cancelSampling(); lastDecodedTime = -Double.infinity
        guard supported else { return }
        analysisGeneration += 1; busy = false; reveal.cancel()
        buildGeneration += 1; buildTask?.cancel()
        item?.videoComposition = original
        requested = true; status = "等待原始解码帧…"
    }
    func reset() {
        cancelSampling(); importedCube = nil; statsRevision += 1; statsTask?.cancel()
        statisticsBefore = []; statisticsAfter = []; samplePixels = []
        exportRevision += 1; exportTask?.cancel(); exportedURL = nil
        analysisGeneration += 1; busy = false; reveal.cancel()
        enabled = false; sharpen = false; deband = false; comparison = false; reveal.setSplit(nil)
        buildGeneration += 1; buildTask?.cancel()
        parameters = LUTParameters(); composition = nil
        cachedCube = nil; cachedParameters = nil
        item?.videoComposition = original; requested = true; status = "已重置"
    }
    func apply() {
        guard supported, let item else { return }
        buildGeneration += 1
        let revision = buildGeneration, sourceGeneration = generation
        buildTask?.cancel()
        let useLUT = enabled && strength > 0
        let useSharpen = sharpen && !constrained
        let useDeband = deband && !constrained
        guard useLUT || useSharpen || useDeband else {
            reveal.cancel(); composition = nil; item.videoComposition = original
            status = constrained && (sharpen || deband) ? "节能/高温保护：增强已旁路" : "原始画面（全部增强已旁路）"
            return
        }
        let params = parameters
        let mode = faithful, imported = importedCube
        let dimension = imported?.size ?? 33
        let domainMin = imported?.domainMin ?? [0,0,0], domainMax = imported?.domainMax ?? [1,1,1]
        let amount = min(1, max(0, strength)), sharp = min(0.20, max(0, sharpness))
        let limit = min(0.003, max(0.001, threshold)), sampleRadius = min(16, max(4, radius))
        let kernel = Self.debandKernel
        let ci = context, reveal = self.reveal
        // Strength/comparison/enhancement changes do not change LUT-domain data.
        let reusableCube = cachedParameters == params && cachedFaithful == mode && imported == nil ? cachedCube : nil
        buildTask = Task { [weak self, weak item] in
            do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            let cube: Data?
            if useLUT {
                if let imported { cube = imported.rgba }
                else if let reusableCube { cube = reusableCube }
                else { cube = await Task.detached(priority: .userInitiated) { NativeLUT.bake(params, faithful: mode) }.value }
            } else { cube = nil }
            guard let self, let item, !Task.isCancelled, self.generation == sourceGeneration, self.buildGeneration == revision, self.item === item else { return }
            if useLUT && cube == nil { self.status = "原版 LUT 引擎失败"; return }
            if useDeband && kernel == nil { self.status = "Metal 去色带不可用；未伪装为模糊" }
            if let cube, imported == nil { self.cachedCube = cube; self.cachedParameters = params; self.cachedFaithful = mode }
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let comp = AVVideoComposition(asset: item.asset, applyingCIFiltersWithHandler: { request in
                let source = request.sourceImage, extent = source.extent
                var result = source
                var lutSource = source
                if domainMin != [0,0,0] || domainMax != [1,1,1] {
                    let scale = (0..<3).map { 1 / (domainMax[$0]-domainMin[$0]) }
                    lutSource = (source.matchedFromWorkingSpace(to:cs) ?? source).applyingFilter("CIColorMatrix", parameters: ["inputRVector":CIVector(x:scale[0],y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:scale[1],z:0,w:0),"inputBVector":CIVector(x:0,y:0,z:scale[2],w:0),"inputBiasVector":CIVector(x:-domainMin[0]*scale[0],y:-domainMin[1]*scale[1],z:-domainMin[2]*scale[2],w:0)]).matchedToWorkingSpace(from:cs) ?? source
                }
                // A true image dissolve, not scaled parameters. Red-fastest CUBE domain.

                if let cube, let mapped = CIFilter(name: "CIColorCubeWithColorSpace", parameters: ["inputCubeDimension":dimension,"inputCubeData":cube,"inputColorSpace":cs,kCIInputImageKey:lutSource])?.outputImage {
                    if amount == 1 { result = mapped }
                    else { result = mapped.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": source, "inputTime": 1-amount]) }
                }
                if useDeband, let kernel {
                    // Threshold measured in nonlinear SDR sRGB, not linear working RGB.
                    if let nonlinear = result.matchedFromWorkingSpace(to: cs), let output = kernel.apply(extent: extent, roiCallback: { _, rect in rect.insetBy(dx: -sampleRadius, dy: -sampleRadius) }, arguments: [nonlinear.clampedToExtent(), limit, sampleRadius]), let working = output.matchedToWorkingSpace(from: cs) {
                        result = working.cropped(to: extent)
                    }
                }
                if useSharpen && sharp > 0 { result = result.clampedToExtent().applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: sharp]).cropped(to: extent) }
                request.finish(with: LUTRevealState.composite(original: source, filtered: result, originalFraction: reveal.originalFraction()).cropped(to: extent), context: ci)
            })
            self.composition = comp
            reveal.begin(reduceMotion: UIAccessibility.isReduceMotionEnabled)
            item.videoComposition = comp
            if !useDeband || kernel != nil { self.status = self.constrained ? "节能/高温：锐化与去色带旁路；LUT 保留" : "SDR 增强已应用；去色带为实验功能" }
        }
    }
    private func analyze() {
        guard let item, let output, item.videoComposition == nil else { return }
        let time = item.currentTime()
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastDecodedTime >= 0.8, output.hasNewPixelBuffer(forItemTime: time), let buffer = output.copyPixelBuffer(forItemTime:time,itemTimeForDisplay:nil) else { return }
        if let transfer = CVBufferCopyAttachment(buffer,kCVImageBufferTransferFunctionKey,nil) as? String,
           transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            cancelSampling(); enabled = false; supported = false; status = "HDR 解码帧已禁用 LUT"; return
        }
        lastDecodedTime = now
        let image = CIImage(cvPixelBuffer:buffer), extent = image.extent
        let scale = min(1,640/max(extent.width,extent.height))
        let resized = image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
        guard let cg = context.createCGImage(resized,from:resized.extent,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) else { return }
        if decodedFrames.isEmpty {
            sampling = true
            let revision = workRevision
            sampleTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds:15_000_000_000)
                guard !Task.isCancelled, let self, self.workRevision == revision else { return }
                self.cancelSampling(); self.status = "已解码帧积累超时；请恢复播放后重试"
            }
        }
        decodedFrames.append(LUTFrame(image:cg)); sampleProgress = Double(decodedFrames.count)/8
        status = "仅积累已解码原始帧 \(decodedFrames.count)/8；请保持播放（不请求新流）"
        if decodedFrames.count >= 8 {
            requested = false; busy = true
            finishFrames(decodedFrames,revision:workRevision,source:generation)
        }
    }

}

// Foundation-only geometry shared by native inference and independent oracle tests.
enum OriginalLandmarkGeometry {
    static func region(faces: [[[Double]]], width: Int, height: Int) -> [String: Int]? {
        guard let landmarks = faces.first, !landmarks.isEmpty else { return nil }
        var x1 = Double.infinity, y1 = Double.infinity
        var x2 = -Double.infinity, y2 = -Double.infinity
        for lm in landmarks {
            let x = lm[0], y = lm[1]
            x1 = min(x1, x); y1 = min(y1, y)
            x2 = max(x2, x); y2 = max(y2, y)
        }
        let cx = (x1+x2)/2, cy = (y1+y2)/2
        let hw = (x2-x1)/2 * 1.0, hh = (y2-y1)/2 * 1.0
        let w = Double(width), h = Double(height)
        return ["x1": max(0, Int(floor((cx-hw)*w))),
                "y1": max(0, Int(floor((cy-hh)*h))),
                "x2": min(width, Int(ceil((cx+hw)*w))),
                "y2": min(height, Int(ceil((cy+hh)*h)))]
    }
}

/// Official Tasks Vision 0.10.14, model float16/1. No Vision or rectangle substitute.
/// Serializes the stateful VIDEO tracker and uses increasing wall-clock timestamps, as original.
private final class OriginalFaceLandmarker: @unchecked Sendable {
    static let shared = OriginalFaceLandmarker()
    private let lock = NSLock()
    private var task: FaceLandmarker?
    private var lastTimestamp = -1
    private let inferenceThread = LUTInferenceThread()

    func region(image: CGImage) -> (box: [String: Int]?, description: String) {
        inferenceThread.sync { self.detectRegion(image: image) }
    }
    private func detectRegion(image: CGImage) -> (box: [String: Int]?, description: String) {
        lock.lock(); defer { lock.unlock() }
        do {
            if task == nil {
                guard let path = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
                    return (nil, "全画面回退（MediaPipe 模型缺失）")
                }
                let options = FaceLandmarkerOptions()
                options.baseOptions.modelAssetPath = path
                options.baseOptions.delegate = .GPU
                options.runningMode = .video
                options.numFaces = 1
                options.minFaceDetectionConfidence = 0.3
                options.minFacePresenceConfidence = 0.3
                options.minTrackingConfidence = 0.5 // JS 0.10.14 default
                options.outputFaceBlendshapes = false
                options.outputFacialTransformationMatrixes = false
                task = try FaceLandmarker(options: options)
            }
            let timestamp = max(lastTimestamp + 1, Int(ProcessInfo.processInfo.systemUptime * 1000))
            lastTimestamp = timestamp
            let input = try MPImage(uiImage: UIImage(cgImage: image, scale: 1, orientation: .up))
            let result = try task!.detect(videoFrame: input, timestampInMilliseconds: timestamp)
            guard let landmarks = result.faceLandmarks.first, !landmarks.isEmpty else {
                return (nil, "全画面回退（MediaPipe 未检测到人脸）")
            }
            let box = OriginalLandmarkGeometry.region(faces: [landmarks.map { [Double($0.x), Double($0.y)] }], width: image.width, height: image.height)
            return (box, "MediaPipe 第一人脸关键点 ROI")
        } catch {
            // Original catches inference exceptions and only then uses the center fallback.
            return (nil, "全画面回退（MediaPipe 错误：\(error.localizedDescription)）")
        }
    }
}

struct NativeLUTPanel: View {
    @ObservedObject var model: NativeLUTController
    @Environment(\.dismiss) private var dismiss
    @State private var pickCube = false
    @State private var pickImages = false
    @ViewBuilder private var fullSections: some View {
            Section("v8.3 完整数值与分析") {
                Picker("数值模式", selection: Binding(get: { model.faithful }, set: { model.switchMode($0) })) {
                    Text("267 保护模式").tag(false)
                    Text("v8.3 原版数值").tag(true)
                }
                Text(model.faithful ? "忠实桌面像素公式、三个模板和搜索范围；采样改为手机有界方案，非桌面FFmpeg逐帧复刻。" : "267 安全数值策略保留：中性保护、有界亮度、近白保护；不同于桌面原版模板。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("本地当前视频：24时间点有限取样") { model.sampleLocalAsset() }
                Button("播放并积累8个已解码帧") { model.reanalyze(); if !model.enabled { model.toggle() } }
                Button("选择本地图片分析（1…24张）") { pickImages = true }
                ProgressView(value: model.sampleProgress)
                Button("停止采样 / 取消全部", role: .cancel) { model.cancelSampling() }
                Text("仅处理显式选择的图片或当前本地素材。图片不保存、不上传；统计只在内存。原版的“四图校准”是内置目标区间来源，不是原版可导入四图按钮；此处多图是新增离线分析入口。网络流不随机抓帧、不新增流下载；HLS composition 与 HDR 仍禁用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("CUBE / 本地自动关联") {
                Button("导入已有 .cube") { pickCube = true }
                Picker("新导出维数", selection: $model.exportSize) { Text("33³（推荐）").tag(33); Text("65³（更大）").tag(65) }
                Button("生成导出 CUBE") { model.exportCube() }
                if let url = model.exportedURL { ShareLink("分享 / 存储到文件", item: url) }
                Text("CUBE 按真实红色最快索引与 DOMAIN 导入；外部 LUT 原样导出。保护模式65³是已应用33³的三线性重采样；不增加源精度。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("素材就绪时加载本地关联 / 通用 LUT", isOn: $model.presetAuto)
                Button("保存当前素材 LUT 关联") { model.savePreset() }
                Button("设为通用 LUT") { model.savePreset(universal: true) }
                Button("加载当前素材关联") { model.loadPreset() }
                Button("加载通用 LUT") { model.loadPreset(universal: true) }
                Button("删除当前素材关联", role: .destructive) { model.deletePreset() }
                Button("删除通用 LUT", role: .destructive) { model.deletePreset(universal: true) }
                Button("清除全部本地 LUT 预设及统计", role: .destructive) { model.clearAllPresets() }
                Text("等效桌面Lua自动加载与 / 键切换：App本地关联优先于通用预设；开启/关闭LUT按钮切换。不安装MPV、不改播放器下载参数。保存预设只含参数/CUBE及素材URL的SHA256键，不含源图。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("分析前后数值 / delta") {
                Text("肤色/ROI样本的统计预览，不等同全画面像素统计。外部CUBE不伪造参数统计。")
                    .font(.caption)
                ForEach(0..<min(model.statisticsBefore.count, model.statisticsAfter.count), id: \.self) { i in
                    let names = ["R/B", "R/G", "亮度", "饱和度", "对比度 σ", "高光占比", "阴影占比"]
                    if i < names.count {
                        Text("\(names[i])  \(model.statisticsBefore[i], specifier: "%.4f") → \(model.statisticsAfter[i], specifier: "%.4f")  Δ \(model.statisticsAfter[i]-model.statisticsBefore[i], specifier: "%+.4f")").font(.caption.monospacedDigit())
                    }
                }
                Button("恢复本次预测值（清除手动delta）") { model.restorePrediction() }
            }
    }
    var body: some View {
        NavigationStack {
        Form {
            Text(model.status).font(.footnote)
            fullSections

            Group {
            Button(model.enabled ? "关闭 LUT" : "开启 LUT") { model.toggle() }
            Button("重新分析原始帧") { model.reanalyze() }
            Button("重置 / 原始画面") { model.reset() }
            Section("画质增强 · SDR") {
                Text("LUT 强度 \(model.strength, specifier: "%.2f")")
                Slider(value: Binding(get: { model.strength }, set: { model.strength = $0; model.apply() }), in: 0...1)
                Toggle("轻微亮度锐化（默认关闭）", isOn: Binding(get: { model.sharpen }, set: { model.sharpen = $0; model.apply() }))
                Slider(value: Binding(get: { model.sharpness }, set: { model.sharpness = $0; model.apply() }), in: 0...0.20)
                Toggle("实验性 Metal 去色带（默认关闭）", isOn: Binding(get: { model.deband }, set: { model.deband = $0; model.apply() }))
                Text("阈值 \(model.threshold, specifier: "%.3f") · 半径 \(Int(model.radius)) 源像素 · 单次 · 无颗粒")
                Slider(value: Binding(get: { model.threshold }, set: { model.threshold = $0; model.apply() }), in: 0.001...0.003)
                Slider(value: Binding(get: { model.radius }, set: { model.radius = $0; model.apply() }), in: 4...16, step: 1)
                Toggle("低电量/高温时停用画质增强", isOn: Binding(get: { model.safePerformance }, set: { model.safePerformance = $0; model.apply() }))
            }
            Section("固定同帧对比 · 左原始 / 右处理") {
                Toggle("持续分屏", isOn: Binding(get: { model.comparison }, set: { model.comparison = $0; model.updateComparison() }))
                Slider(value: Binding(get: { model.divider }, set: { model.divider = $0; model.updateComparison() }), in: 0...1)
                Button("暂停并比较同一帧") { model.pauseComparison() }
                Text("原始分支直接使用解码请求 sourceImage；原始按钮关闭所有增强。")
            }
            ForEach(0..<7,id:\.self) { i in
                VStack(alignment:.leading) {
                    Text("\(LUTParameters.names[i]) \(Int(model.parameters.values[i]))")
                    Slider(value:Binding(get:{ model.parameters.values[i] },set:{ model.manualChange(i, $0) }),in:-100...100,step:1)
                }
            }
            }
            Section {
                Text("原文件的容器、编码及 HDR 支持取决于设备；LUT 仅支持可分析的 SDR。开启或分析后，点右上角返回播放；分析无需停留在此面板等待。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .navigationTitle("LUT 调色")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: {
                    Label("返回播放", systemImage: "checkmark")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 48)
                }
                .accessibilityLabel("完成 LUT 设置，返回播放")
                .accessibilityHint("关闭面板，保留调色设置与播放进度")
            }
        }
        }.presentationDetents([.medium,.large])
        .fileImporter(isPresented: $pickCube, allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data]) { result in
            if case let .success(url) = result { model.importCube(url) }
        }
        .fileImporter(isPresented: $pickImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { model.importMedia(urls) }
        }
    }
}

// One dedicated OS thread, not a DispatchQueue (which may migrate GPU contexts).
// Model creation, VIDEO inference and all future use stay on this same thread.
private final class LUTInferenceThread: @unchecked Sendable {
    private let condition = NSCondition()
    private var jobs = [() -> Void]()
    private var thread: Thread!
    init() {
        thread = Thread { [self] in
            while true {
                condition.lock()
                while jobs.isEmpty { condition.wait() }
                let job = jobs.removeFirst(); condition.unlock()
                autoreleasepool { job() }
            }
        }
        thread.name = "AVDB.LUT.MediaPipeGPU"; thread.qualityOfService = .userInitiated; thread.start()
    }
    func sync<T>(_ operation: @escaping () -> T) -> T {
        let signal = DispatchSemaphore(value: 0)
        var value: T?
        condition.lock(); jobs.append { value = operation(); signal.signal() }; condition.signal(); condition.unlock()
        signal.wait(); return value!
    }
}
