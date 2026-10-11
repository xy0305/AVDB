import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

@main struct SeekPreviewRegression {
    static func main() async throws {
        // A hung AVFoundation request must fail CI, not leave an indefinite spinner/test.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { fatalError("preview test timeout") }
        var policy = ScrubPreviewPolicy()
        assert(policy.request(1.2, duration: 10))
        let first = policy.generation
        policy.started(now: 100)
        assert(!policy.request(1.4, duration: 10))
        assert(policy.request(2.1, duration: 10))
        assert(!policy.accepts(first))
        assert(abs(policy.delay(now: 100.05) - 0.15) < 0.001)
        assert(policy.delay(now: 100.3) == 0)
        let latest = policy.generation
        assert(policy.accepts(latest))
        policy.cancel(); assert(!policy.accepts(latest))
        policy.resetSource(); assert(policy.delay(now: 100.05) == 0)
        assert(policy.request(100, duration: 10)); assert(policy.sampleTime == 10)
        policy.cancel(); assert(policy.request(-8, duration: 10)); assert(policy.sampleTime == 0)
        var cache = PreviewLRU<String>(countLimit: 2, byteLimit: 8)
        cache.insert("a", key: 1, cost: 3); cache.insert("b", key: 2, cost: 3)
        assert(cache.value(for: 1) == "a")
        cache.insert("c", key: 3, cost: 3); assert(cache.value(for: 2) == nil)
        cache.insert("d", key: 4, cost: 7); assert(cache.bytes == 7)
        cache.removeAll(); assert(cache.value(for: 4) == nil && cache.bytes == 0)
        print("PASS: latest-wins, 200ms throttle, cancellation, source epoch, clamp, LRU/byte eviction")

        // Neutral synthetic fixture, generated locally by CI; no service account/network media.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeVideo(url)
        let extractor = PreviewFrameExtractor()
        extractor.configure(url: url, headers: [:])
        let red = await frame(extractor, at: 0.5)
        let blue = await frame(extractor, at: 1.5)
        assert(red != nil && blue != nil)
        assert(red!.height > red!.width && red!.width <= 320 && red!.height <= 180, "preferred transform / cap")
        let r = pixel(red!), b = pixel(blue!)
        assert(r[0] > 180 && r[2] < 60 && b[2] > 180 && b[0] < 60, "target times must be different real frames")
        extractor.configure(url: url.deletingLastPathComponent().appendingPathComponent("missing.mov"), headers: [:])
        let missing = await frame(extractor, at: 0.5)
        assert(missing == nil)
        extractor.close()
        print("PASS: actual AVFoundation red/blue target samples, rotated video, max size and invalid source")
    }
    static func frame(_ extractor: PreviewFrameExtractor, at time: Double) async -> CGImage? {
        await withCheckedContinuation { continuation in
            extractor.image(at: time) { continuation.resume(returning: $0) }
        }
    }
    static func pixel(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { ptr in
            let context = CGContext(data: ptr.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
    static func makeVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                         AVVideoWidthKey: 160, AVVideoHeightKey: 90])
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 90])
        writer.add(input); assert(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for index in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            assert(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess)
            CVPixelBufferLockBaseAddress(buffer!, [])
            let ptr = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(buffer!)
            for y in 0..<90 { for x in 0..<160 {
                let offset = y * row + x * 4
                ptr[offset] = index < 30 ? 0 : 255
                ptr[offset + 1] = 0; ptr[offset + 2] = index < 30 ? 255 : 0; ptr[offset + 3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            assert(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished(); await writer.finishWriting()
        assert(writer.status == .completed)
    }
}
