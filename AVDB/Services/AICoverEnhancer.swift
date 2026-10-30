import Foundation
import UIKit
import SwiftUI
import CoreML
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Network

/// System-reading half of the battery guard (no thermal gating since build 289) (the decision itself is pure, in AICoverPolicy.swift).
extension AICoverEnhanceGuard {
    static func check(manual: Bool) -> Verdict {
        let battery = currentBattery()
        return verdict(manual: manual, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
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

/// Build 290: enhanced rasters are NOT kept long-term on the phone. The cloud (R2) is the store; locally there is only a
/// bounded in-memory cache plus a small disk LRU in Caches/AICover (cap from 设置 → 本地缓存上限, default 200 MB).
/// Keys: SHA-256 of model version + source URL + native size (unchanged since 285, so the old cache is reused/trimmed).
final class AICoverDiskCache: @unchecked Sendable {
    static let shared = AICoverDiskCache()
    static var limitBytes: Int { AICoverCloudSettings.shared.capBytes }
    let directory: URL
    private let memory = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "avdb.aicover.disk", qos: .utility)
    private let capOverride: Int?

    init(directory: URL? = nil, capBytes: Int? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AICover", isDirectory: true)
        self.directory = base
        capOverride = capBytes
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var dir = base; try? dir.setResourceValues(values)
        memory.countLimit = 12
        memory.totalCostLimit = 96 * 1024 * 1024
    }
    var cap: Int { capOverride ?? Self.limitBytes }

    static func key(source: String, width: Int, height: Int, version: String = AICoverSREngine.modelVersion) -> String {
        let raw = version + "|" + source + "|\(width)x\(height)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func url(_ key: String) -> URL { directory.appendingPathComponent(key + ".jpg") }

    private func remember(_ image: UIImage, key: String) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    func image(key: String) -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let path = url(key)
        guard let data = try? Data(contentsOf: path), let image = UIImage(data: data) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        remember(image, key: key)
        return image
    }

    func contains(key: String) -> Bool {
        memory.object(forKey: key as NSString) != nil || FileManager.default.fileExists(atPath: url(key).path)
    }

    /// Stores already-encoded bytes (what was uploaded / downloaded) and trims to the LRU cap.
    func store(_ image: UIImage, encoded: Data, key: String, completion: (@Sendable (URL?) -> Void)? = nil) {
        remember(image, key: key)
        let target = url(key)
        queue.async { [directory, cap] in
            let ok = (try? encoded.write(to: target, options: .atomic)) != nil
            Self.trim(directory: directory, limit: cap)
            completion?(ok && FileManager.default.fileExists(atPath: target.path) ? target : nil)
        }
    }

    func store(_ image: UIImage, key: String) {
        guard let enc = AICoverEncoder.encode(image) else { remember(image, key: key); return }
        store(image, encoded: enc.data, key: key)
    }

    func totalBytes() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    func fileCount() -> Int { ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).count }

    func clear() {
        memory.removeAllObjects()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    func trimNow() { queue.async { [directory, cap] in Self.trim(directory: directory, limit: cap) } }

    static func trim(directory: URL, limit: Int) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []).compactMap { u -> (id: String, bytes: Int, lastUse: Date)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u.path, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
        for path in AICoverLRU.evictions(files, cap: limit, protectBefore: AICoverMigration.protectBefore()) { try? FileManager.default.removeItem(atPath: path) }
    }
}

/// Upload encoding: high-quality JPEG (q 0.9); HEIC at the same quality if it is smaller; always ≤ 3 MiB
/// (quality steps down, then the raster is scaled down, before giving up).
enum AICoverEncoder {
    struct Encoded { let data: Data; let contentType: String }
    static func encode(_ image: UIImage, limit: Int = AICoverCloudConfig.maxUploadBytes) -> Encoded? {
        guard var cg = image.cgImage else { return nil }
        for _ in 0..<3 {
            for q in [0.9, 0.85, 0.8, 0.72, 0.65] {
                let jpeg = data(cg, type: UTType.jpeg, quality: q)
                let heic = data(cg, type: UTType.heic, quality: q)
                let best: Encoded? = {
                    switch (jpeg, heic) {
                    case let (j?, h?): return h.count < j.count ? Encoded(data: h, contentType: "image/heic") : Encoded(data: j, contentType: "image/jpeg")
                    case let (j?, nil): return Encoded(data: j, contentType: "image/jpeg")
                    case let (nil, h?): return Encoded(data: h, contentType: "image/heic")
                    default: return nil
                    }
                }()
                if let best, best.data.count <= limit { return best }
            }
            guard let smaller = scaled(cg, factor: 0.8) else { return nil }
            cg = smaller
        }
        return nil
    }
    static func data(_ cg: CGImage, type: UTType, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
    static func scaled(_ cg: CGImage, factor: Double) -> CGImage? {
        let w = max(1, Int(Double(cg.width) * factor)), h = max(1, Int(Double(cg.height) * factor))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

/// Wi‑Fi / cellular flag for 「仅 Wi‑Fi 上传」 + one-time migration of the pre-290 on-disk cache.
enum AICoverCloudRuntime {
    nonisolated(unsafe) private static var monitor: NWPathMonitor?
    static func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in AICoverNetworkState.isExpensive = path.isExpensive || path.usesInterfaceType(.cellular) }
        m.start(queue: DispatchQueue(label: "avdb.aicover.path", qos: .utility))
        monitor = m
        migrate()
    }
    /// Build 290 migration: the 285–289 cache (≤ 300 MB of enhanced covers, keyed by an opaque hash, no 番号) is
    /// uploaded opportunistically — each file the next time its detail page resolves it (local hit → PUT on Wi‑Fi only,
    /// utility priority) — and protected from LRU eviction for a 30-day grace window so that can happen; afterwards
    /// (or after 清除缓存) everything is trimmed to the LRU cap.
    static func migrate() {
        AICoverMigration.begin()
        Task.detached(priority: .background) { AICoverDiskCache.shared.trimNow() }
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
/// Build 290 flow: local memory/disk LRU → cloud GET (≤ 2.5 s, never blocks the original cover, which is already shown)
/// → miss: enhance on device, show, encode (JPEG q0.9 / HEIC if smaller, ≤ 3 MiB), keep in the LRU, upload in background.
@MainActor
final class AICoverEnhanceModel: ObservableObject {
    enum Phase: Equatable { case idle, ineligible, running(Double), done, failed(String) }
    enum Origin: String { case cloud, local, cache }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var enhanced: UIImage?
    @Published private(set) var original: UIImage?
    @Published private(set) var nativeSize: CGSize = .zero
    @Published private(set) var cloudFetching = false
    @Published private(set) var origin: Origin?
    @Published var showingOriginal = false
    /// Build 286: a cover long-press ends with a touch-up; the hero tap must not also open the viewer.
    var lastCompareEnded = Date.distantPast
    var viewerTapAllowed: Bool { Date().timeIntervalSince(lastCompareEnded) > 0.4 }
    private var key: String?
    private var task: Task<Void, Never>?
    private var input: UIImage?
    private var source = ""
    private var number: String?
    private var cloudChecked = false
    var cloudClient: () -> AICoverCloudClient = { AICoverCloudClient() }
    var uploads: AICoverUploadQueue = .shared
    var settings: AICoverCloudSettings = .shared
    var cache: AICoverDiskCache = .shared

    var isEnhanced: Bool { enhanced != nil }
    var isRunning: Bool { if case .running = phase { return true }; return false }
    var progress: Double { if case .running(let p) = phase { return p }; return 0 }
    var canEnhance: Bool { input != nil && phase != .ineligible && AICoverEnhanceMode.current != .off }
    var outputSize: CGSize? { enhanced.map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) } }
    var cloudName: String? {
        guard let key else { return nil }
        return AICoverCloudName.make(number: number, width: Int(nativeSize.width), height: Int(nativeSize.height), fallbackHash: key)
    }

    func display(_ fallback: UIImage) -> UIImage {
        guard !showingOriginal, let enhanced else { return fallback }
        return enhanced
    }

    /// Called whenever the resolved hero artwork changes. `nativeWidth/Height` are the winner's
    /// real front pixels (before any display cap); HQ covers become `.ineligible`.
    func prepare(image: UIImage?, source: String, nativeWidth: Int, nativeHeight: Int, number: String? = nil,
                 mode: AICoverEnhanceMode = .current, autoAllowed: Bool? = nil) {
        let newKey = image == nil ? nil : AICoverDiskCache.key(source: source, width: nativeWidth, height: nativeHeight)
        guard newKey != key || mode.rawValue != lastMode else { return }
        lastMode = mode.rawValue
        task?.cancel(); task = nil; cloudFetching = false; cloudChecked = false
        key = newKey; input = image; self.source = source; self.number = number; enhanced = nil; original = image; showingOriginal = false
        origin = nil
        nativeSize = CGSize(width: nativeWidth, height: nativeHeight)
        guard image != nil, let newKey else { phase = .idle; return }
        guard mode != .off, AICoverEnhancePolicy.eligible(source: source, nativeWidth: nativeWidth, nativeHeight: nativeHeight) else {
            phase = .ineligible; return
        }
        if let cached = cache.image(key: newKey) {
            enhanced = cached; phase = .done; origin = .cache
            uploadLocalIfNeeded(key: newKey)          // 290 migration: pre-290 / not-yet-uploaded files go up opportunistically
            return
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
        let name = cloudName
        let useCloud = settings.enabled && !cloudChecked
        let client = cloudClient()
        task = Task { [weak self] in
            guard let model = self else { return }
            // 1. Cloud copy (short timeout). Any failure → silent local fallback.
            if useCloud, let name, client.configured {
                model.cloudFetching = true
                let result = await client.fetch(name: name)
                model.cloudFetching = false
                model.cloudChecked = true
                guard !Task.isCancelled, model.key == key else { return }
                switch result {
                case .hit(let data, _):
                    if let img = await Self.decode(data) {
                        model.settings.countHit(); model.settings.markInCloud(name)
                        model.cache.store(img, encoded: data, key: key)
                        withAnimation(.easeInOut(duration: 0.45)) { model.enhanced = img; model.phase = .done; model.origin = .cloud }
                        return
                    }
                    model.settings.countFailure("云端图片无法解码")
                case .miss: model.settings.countMiss()
                case .unavailable(let why): model.settings.countFailure(why)
                }
            }
            // 2. Local enhancement (as before).
            do {
                let out = try await AICoverEnhancer.shared.enhance(image) { p in
                    guard case .running = model.phase else { return }
                    model.phase = .running(p)
                }
                guard !Task.isCancelled, model.key == key else { return }
                withAnimation(.easeInOut(duration: 0.45)) { model.enhanced = out; model.phase = .done; model.origin = .local }
                model.persistAndUpload(out, key: key, name: name)
            } catch {
                guard !Task.isCancelled, model.key == key else { return }
                let text = (error as? AICoverSRError) == .modelMissing ? "AI 模型缺失" : "AI 增强失败"
                model.phase = .failed(text)
            }
        }
    }

    nonisolated private static func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data) }.value
    }

    /// Encode off the main thread, keep in the LRU (bounded), queue the background upload.
    private func persistAndUpload(_ image: UIImage, key: String, name: String?) {
        let cache = self.cache, uploads = self.uploads, settings = self.settings
        Task.detached(priority: .utility) {
            guard let enc = AICoverEncoder.encode(image) else { cache.store(image, key: key); return }
            cache.store(image, encoded: enc.data, key: key)
            guard settings.enabled, !settings.quotaFull(), let name else { return }
            await uploads.enqueue(.init(name: name, contentType: enc.contentType, fileURL: nil, data: enc.data))
        }
    }

    /// A local LRU hit that the cloud doesn't know about yet (pre-290 cache or an earlier failed upload): upload it, Wi‑Fi only.
    private func uploadLocalIfNeeded(key: String) {
        guard settings.enabled, !settings.quotaFull(), let name = cloudName, !settings.isInCloud(name),
              !AICoverNetworkState.isExpensive else { return }
        let file = cache.url(key), uploads = self.uploads
        Task.detached(priority: .background) {
            guard let data = try? Data(contentsOf: file), !data.isEmpty else { return }
            let isHEIC = data.count > 12 && String(decoding: data[4..<12], as: UTF8.self).hasPrefix("ftyphei")
            var payload = data, type = isHEIC ? "image/heic" : "image/jpeg"
            if data.count > AICoverCloudConfig.maxUploadBytes, let img = UIImage(data: data), let enc = AICoverEncoder.encode(img) {
                payload = enc.data; type = enc.contentType
            }
            await uploads.enqueue(.init(name: name, contentType: type, fileURL: nil, data: payload))
        }
    }

    /// Manual toggle from the button: enhance, or switch back to the original raster.
    func toggle() {
        if enhanced != nil { showingOriginal.toggle(); return }
        start(manual: true)
    }

    func cancel() { task?.cancel(); task = nil; cloudFetching = false; if case .running = phase { phase = .idle } }
}
