import Foundation

/// Pure scheduling policy, shared by production and executable regression tests.
struct ScrubPreviewPolicy {
    private(set) var generation = 0
    private(set) var bucket: Int?
    private(set) var lastStart = -Double.infinity
    mutating func request(_ time: Double, duration: Double) -> Bool {
        let next = Int((min(max(0, time), max(0, duration)) * 2).rounded(.down))
        guard bucket != next else { return false }
        bucket = next
        generation += 1
        return true
    }
    var sampleTime: Double { Double(bucket ?? 0) / 2 }
    func delay(now: Double) -> Double { max(0, lastStart + 0.2 - now) }
    mutating func started(now: Double) { lastStart = now }
    func accepts(_ token: Int) -> Bool { bucket != nil && token == generation }
    mutating func cancel() { generation += 1; bucket = nil }
    mutating func resetSource() { cancel(); lastStart = -Double.infinity }
}

struct PreviewLRU<Value> {
    private var values: [Int: (Value, Int)] = [:]
    private var order: [Int] = []
    private(set) var bytes = 0
    let countLimit: Int
    let byteLimit: Int
    init(countLimit: Int, byteLimit: Int) {
        self.countLimit = countLimit
        self.byteLimit = byteLimit
    }
    mutating func value(for key: Int) -> Value? {
        guard let value = values[key]?.0 else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return value
    }
    mutating func insert(_ value: Value, key: Int, cost: Int) {
        guard cost <= byteLimit else { return }
        if let previous = values[key] { bytes -= previous.1 }
        order.removeAll { $0 == key }
        values[key] = (value, cost); order.append(key); bytes += cost
        while values.count > countLimit || bytes > byteLimit {
            let oldest = order.removeFirst()
            bytes -= values.removeValue(forKey: oldest)!.1
        }
    }
    mutating func removeAll() { values.removeAll(); order.removeAll(); bytes = 0 }
}

#if canImport(AVFoundation)
import AVFoundation
import CoreGraphics

/// No player, audio session, downloads or persistent URL cache. All AV work is off-main.
final class PreviewFrameExtractor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "avdb.scrub.frames", qos: .utility)
    private var asset: AVURLAsset?
    private var generator: AVAssetImageGenerator?

    func configure(url: URL, headers: [String: String]) {
        queue.async { [self] in
            generator?.cancelAllCGImageGeneration(); generator = nil
            asset?.cancelLoading()
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
    }
    func cancel() {
        queue.async { [self] in generator?.cancelAllCGImageGeneration(); generator = nil }
    }
    func close() {
        queue.async { [self] in
            generator?.cancelAllCGImageGeneration(); generator = nil
            asset?.cancelLoading(); asset = nil
        }
    }
    func image(at seconds: Double, completion: @escaping @Sendable (CGImage?) -> Void) {
        queue.async { [self] in
            generator?.cancelAllCGImageGeneration()
            guard let asset else { completion(nil); return }
            let next = AVAssetImageGenerator(asset: asset)
            next.appliesPreferredTrackTransform = true
            next.maximumSize = CGSize(width: 320, height: 180)
            next.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
            next.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
            generator = next
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            next.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, actual, result, _ in
                // Reject an unrelated/keyframe-only result outside the requested tolerance.
                let valid = result == .succeeded && actual.seconds.isFinite && abs(actual.seconds - seconds) <= 0.3
                completion(valid ? image : nil)
            }
        }
    }
}
#endif

#if canImport(UIKit)
import UIKit
import Combine

@MainActor
final class SeekPreviewController: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var loading = false
    private var policy = ScrubPreviewPolicy()
    private var cache = PreviewLRU<CGImage>(countLimit: 24, byteLimit: 8 * 1024 * 1024)
    private var scheduled: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private let extractor = PreviewFrameExtractor()
    private var supported = false

    func configure(url: URL, headers: [String: String], supported: Bool) {
        close()
        self.supported = supported && !["m3u8", "m3u"].contains(url.pathExtension.lowercased())
        if self.supported { extractor.configure(url: url, headers: headers) }
    }
    func request(time: Double, duration: Double) {
        guard time.isFinite, duration.isFinite, duration > 0,
              policy.request(time, duration: duration) else { return }
        scheduled?.cancel(); timeout?.cancel(); extractor.cancel()
        image = nil; loading = false
        guard supported, let key = policy.bucket else { return }
        if let hit = cache.value(for: key) { image = hit; return }
        loading = true
        let token = policy.generation
        let delay = policy.delay(now: ProcessInfo.processInfo.systemUptime)
        scheduled = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.policy.accepts(token) else { return }
            self.policy.started(now: ProcessInfo.processInfo.systemUptime)
            self.extractor.image(at: self.policy.sampleTime) { [weak self] frame in
                Task { @MainActor [weak self] in
                    guard let self, self.policy.accepts(token) else { return }
                    self.timeout?.cancel()
                    self.loading = false
                    self.image = frame
                    if let frame { self.cache.insert(frame, key: key, cost: frame.bytesPerRow * frame.height) }
                }
            }
            self.timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, let self, self.policy.accepts(token) else { return }
                self.policy.cancel() // Reject late callbacks even if AVFoundation ignores cancellation.
                self.extractor.cancel(); self.loading = false; self.image = nil
            }
        }
    }
    func cancel() {
        policy.cancel(); scheduled?.cancel(); timeout?.cancel(); extractor.cancel()
        scheduled = nil; timeout = nil; image = nil; loading = false
    }
    func close() {
        cancel(); policy.resetSource(); cache.removeAll(); extractor.close(); supported = false
    }
}
#endif
