import Foundation
import UIKit
import SwiftUI
import CoreML
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// System-reading half of the thermal / battery guard (the decision itself is pure, in AICoverPolicy.swift).
extension AICoverEnhanceGuard {
    static func check(manual: Bool) -> Verdict {
        let thermal: Int
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = 0
        case .fair: thermal = 1
        case .serious: thermal = 2
        default: thermal = 3
        }
        let battery = currentBattery()
        return verdict(manual: manual, thermalLevel: thermal, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                       battery: battery.level, charging: battery.charging)
    }
    private static func currentBattery() -> (level: Float, charging: Bool) {
        let read = {
            let d = UIDevice.current
            if !d.isBatteryMonitoringEnabled { d.isBatteryMonitoringEnabled = true }
            return (d.batteryLevel, d.batteryState == .charging || d.batteryState == .full)
        }
        return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
    }
}

/// Enhanced rasters persist across launches in Caches/AICover (HEIC/JPEG), keyed by model
/// version + source URL + native size. Bounded to `limitBytes` with oldest-first eviction.
final class AICoverDiskCache: @unchecked Sendable {
    static let shared = AICoverDiskCache()
    static let limitBytes = 300 * 1024 * 1024
    let directory: URL
    private let memory = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "avdb.aicover.disk", qos: .utility)

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AICover", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        memory.countLimit = 12
    }

    static func key(source: String, width: Int, height: Int, version: String = AICoverSREngine.modelVersion) -> String {
        let raw = version + "|" + source + "|\(width)x\(height)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func url(_ key: String) -> URL { directory.appendingPathComponent(key + ".jpg") }

    func image(key: String) -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let path = url(key)
        guard let data = try? Data(contentsOf: path), let image = UIImage(data: data) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    func contains(key: String) -> Bool {
        memory.object(forKey: key as NSString) != nil || FileManager.default.fileExists(atPath: url(key).path)
    }

    func store(_ image: UIImage, key: String) {
        memory.setObject(image, forKey: key as NSString)
        guard let cg = image.cgImage else { return }
        let target = url(key)
        queue.async { [directory] in
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return }
            try? (data as Data).write(to: target, options: .atomic)
            Self.trim(directory: directory, limit: Self.limitBytes)
        }
    }

    func totalBytes() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clear() {
        memory.removeAllObjects()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    static func trim(directory: URL, limit: Int) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        var files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []).compactMap { u -> (URL, Int, Date)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
        var total = files.reduce(0) { $0 + $1.1 }
        guard total > limit else { return }
        files.sort { $0.2 < $1.2 }
        for f in files where total > limit { try? FileManager.default.removeItem(at: f.0); total -= f.1 }
    }
}

/// Single shared engine; the model is loaded lazily the first time a cover is enhanced.
actor AICoverEnhancer {
    static let shared = AICoverEnhancer()
    private var engine: AICoverSREngine?

    var modelAvailable: Bool { AICoverSREngine.bundledModelURL() != nil }

    private func loadedEngine() throws -> AICoverSREngine {
        if let engine { return engine }
        guard let url = AICoverSREngine.bundledModelURL() else { throw AICoverSRError.modelMissing }
        #if targetEnvironment(simulator)
        let units: MLComputeUnitsBox = .init(.cpuOnly)
        #else
        let units: MLComputeUnitsBox = .init(.all)
        #endif
        let e = try AICoverSREngine(modelURL: url, computeUnits: units.value)
        engine = e
        return e
    }

    /// Runs off the main actor at user-initiated priority. Progress is delivered on the main actor.
    func enhance(_ image: UIImage, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> UIImage {
        guard let cg = image.cgImage else { throw AICoverSRError.badInput }
        let engine = try loadedEngine()
        let task = Task.detached(priority: .userInitiated) { () throws -> CGImage in
            try engine.upscale(cg, progress: { p in Task { @MainActor in progress(p) } },
                               isCancelled: { Task.isCancelled })
        }
        let out = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        return UIImage(cgImage: out)
    }
}

struct MLComputeUnitsBox: @unchecked Sendable { let value: MLComputeUnits; init(_ v: MLComputeUnits) { value = v } }

/// Per-detail-page state for the hero cover.
@MainActor
final class AICoverEnhanceModel: ObservableObject {
    enum Phase: Equatable { case idle, ineligible, running(Double), done, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var enhanced: UIImage?
    @Published private(set) var original: UIImage?
    @Published private(set) var nativeSize: CGSize = .zero
    @Published var showingOriginal = false
    /// Build 286: a cover long-press ends with a touch-up; the hero tap must not also open the viewer.
    var lastCompareEnded = Date.distantPast
    var viewerTapAllowed: Bool { Date().timeIntervalSince(lastCompareEnded) > 0.4 }
    private var key: String?
    private var task: Task<Void, Never>?
    private var input: UIImage?
    private var source = ""

    var isEnhanced: Bool { enhanced != nil }
    var isRunning: Bool { if case .running = phase { return true }; return false }
    var progress: Double { if case .running(let p) = phase { return p }; return 0 }
    var canEnhance: Bool { input != nil && phase != .ineligible && AICoverEnhanceMode.current != .off }
    var outputSize: CGSize? { enhanced.map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) } }

    func display(_ fallback: UIImage) -> UIImage {
        guard !showingOriginal, let enhanced else { return fallback }
        return enhanced
    }

    /// Called whenever the resolved hero artwork changes. `nativeWidth/Height` are the winner's
    /// real front pixels (before any display cap); HQ covers become `.ineligible`.
    func prepare(image: UIImage?, source: String, nativeWidth: Int, nativeHeight: Int,
                 mode: AICoverEnhanceMode = .current, autoAllowed: Bool? = nil) {
        let newKey = image == nil ? nil : AICoverDiskCache.key(source: source, width: nativeWidth, height: nativeHeight)
        guard newKey != key || mode.rawValue != lastMode else { return }
        lastMode = mode.rawValue
        task?.cancel(); task = nil
        key = newKey; input = image; self.source = source; enhanced = nil; original = image; showingOriginal = false
        nativeSize = CGSize(width: nativeWidth, height: nativeHeight)
        guard image != nil, let newKey else { phase = .idle; return }
        guard mode != .off, AICoverEnhancePolicy.eligible(source: source, nativeWidth: nativeWidth, nativeHeight: nativeHeight) else {
            phase = .ineligible; return
        }
        if let cached = AICoverDiskCache.shared.image(key: newKey) {
            enhanced = cached; phase = .done; return
        }
        phase = .idle
        if mode == .auto, autoAllowed ?? (AICoverEnhanceGuard.check(manual: false) == .ok) { start(manual: false) }
    }
    private var lastMode = ""

    func start(manual: Bool = true) {
        guard let image = input, let key,
              AICoverEnhancePolicy.eligible(source: source, nativeWidth: Int(nativeSize.width), nativeHeight: Int(nativeSize.height)) else { return }
        if case .running = phase { return }
        if let msg = AICoverEnhanceGuard.message(AICoverEnhanceGuard.check(manual: manual)) {
            phase = .failed(msg); return
        }
        phase = .running(0)
        task = Task { [weak self] in
            guard let model = self else { return }
            do {
                let out = try await AICoverEnhancer.shared.enhance(image) { p in
                    guard case .running = model.phase else { return }
                    model.phase = .running(p)
                }
                guard !Task.isCancelled, model.key == key else { return }
                AICoverDiskCache.shared.store(out, key: key)
                withAnimation(.easeInOut(duration: 0.45)) { model.enhanced = out; model.phase = .done }
            } catch {
                guard !Task.isCancelled, model.key == key else { return }
                let text = (error as? AICoverSRError) == .modelMissing ? "AI 模型缺失" : "AI 增强失败"
                model.phase = .failed(text)
            }
        }
    }

    /// Manual toggle from the button: enhance, or switch back to the original raster.
    func toggle() {
        if enhanced != nil { showingOriginal.toggle(); return }
        start(manual: true)
    }

    func cancel() { task?.cancel(); task = nil; if case .running = phase { phase = .idle } }
}
