import Foundation
import CoreML
import CoreGraphics
import Accelerate

/// Build 285: on-device AI super-resolution for low-resolution covers.
/// Portable (CoreML + CoreGraphics + Accelerate only, no UIKit) so the exact same tiling
/// code runs in the macOS CI benchmark harness and in the app.
enum AICoverSRError: Error, Equatable {
    case modelMissing, badInput, cancelled, predictionFailed(String)
}

final class AICoverSREngine: @unchecked Sendable {
    /// Bump when the bundled model changes: invalidates the disk cache.
    static let modelVersion = "4xNomosWebPhoto_esrgan-x4-t128-fp16-v1"
    static let resourceName = "CoverSR"

    let model: MLModel
    let tile: Int
    let scale: Int
    let overlap: Int
    private let lock = NSLock()

    init(modelURL: URL, computeUnits: MLComputeUnits = .all, overlap: Int = 12) throws {
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        model = try MLModel(contentsOf: modelURL, configuration: config)
        let shape = model.modelDescription.inputDescriptionsByName["input"]?.multiArrayConstraint?.shape.map(\.intValue) ?? []
        tile = shape.count == 4 ? shape[3] : 128
        let meta = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        scale = Int(meta?["scale"] ?? "") ?? 4
        self.overlap = overlap
    }

    static func bundledModelURL(_ bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "mlmodelc")
    }

    /// Upscales a full image. `progress` gets 0…1 after each tile; `isCancelled` is polled per tile.
    func upscale(_ image: CGImage, progress: (Double) -> Void = { _ in },
                 isCancelled: () -> Bool = { false }) throws -> CGImage {
        lock.lock(); defer { lock.unlock() }
        let w = image.width, h = image.height
        guard w >= 16, h >= 16, w <= 1400, h <= 1400 else { throw AICoverSRError.badInput }
        // Opaque RGBA8 source raster.
        var src = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &src, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw AICoverSRError.badInput }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let T = tile, S = scale, OW = w * S, OH = h * S
        let xs = AICoverTilePlan.make(length: w, tile: T, overlap: overlap).origins
        let ys = AICoverTilePlan.make(length: h, tile: T, overlap: overlap).origins
        var acc = [Float](repeating: 0, count: OW * OH * 3)
        var wsum = [Float](repeating: 0, count: OW * OH)
        let input = try MLMultiArray(shape: [1, 3, NSNumber(value: T), NSNumber(value: T)], dataType: .float16)
        var plane = [Float](repeating: 0, count: T * T)
        let total = Double(xs.count * ys.count)
        var done = 0.0
        let ramp = overlap * S
        var row = [Float](repeating: 0, count: T * S)

        for oy in ys {
            for ox in xs {
                if isCancelled() { throw AICoverSRError.cancelled }
                // Fill planar fp16 input with edge clamping (pads images smaller than a tile).
                try input.withUnsafeMutableBytes { raw, strides in
                    let dst = raw.baseAddress!.assumingMemoryBound(to: UInt16.self)
                    for c in 0..<3 {
                        for y in 0..<T {
                            let sy = min(oy + y, h - 1)
                            let base = sy * w * 4
                            for x in 0..<T {
                                let sx = min(ox + x, w - 1)
                                plane[y * T + x] = Float(src[base + sx * 4 + c]) / 255
                            }
                        }
                        var ok: vImage_Error = 0
                        plane.withUnsafeMutableBufferPointer { p in
                            var s = vImage_Buffer(data: p.baseAddress, height: vImagePixelCount(T), width: vImagePixelCount(T), rowBytes: T * 4)
                            var d = vImage_Buffer(data: dst + c * strides[1], height: vImagePixelCount(T), width: vImagePixelCount(T), rowBytes: strides[2] * 2)
                            ok = vImageConvert_PlanarFtoPlanar16F(&s, &d, 0)
                        }
                        if ok != kvImageNoError { throw AICoverSRError.predictionFailed("fp16 input \(ok)") }
                    }
                }
                let features = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: input)])
                let result: MLFeatureProvider
                do { result = try model.prediction(from: features) }
                catch { throw AICoverSRError.predictionFailed(error.localizedDescription) }
                guard let out = result.featureValue(for: "output")?.multiArrayValue,
                      out.shape.count == 4, out.shape[2].intValue == T * S, out.shape[3].intValue == T * S else {
                    throw AICoverSRError.predictionFailed("output shape")
                }
                let st = out.strides.map(\.intValue)
                let TS = T * S
                // Valid region of this tile inside the image (padding is discarded).
                let vh = min(T, h - oy) * S, vw = min(T, w - ox) * S
                let top = oy > 0, bottom = oy + T < h, left = ox > 0, right = ox + T < w
                func fy(_ y: Int) -> Float {
                    var f: Float = 1
                    if top && y < ramp { f = min(f, Float(y) / Float(ramp)) }
                    if bottom && y >= TS - ramp { f = min(f, Float(TS - 1 - y) / Float(ramp)) }
                    return max(f, 1e-4)
                }
                func fx(_ x: Int) -> Float {
                    var f: Float = 1
                    if left && x < ramp { f = min(f, Float(x) / Float(ramp)) }
                    if right && x >= TS - ramp { f = min(f, Float(TS - 1 - x) / Float(ramp)) }
                    return max(f, 1e-4)
                }
                let wx = (0..<vw).map(fx)
                var fp16Failed = false
                out.withUnsafeBytes { raw in
                    let p = raw.baseAddress!.assumingMemoryBound(to: UInt16.self)
                    for c in 0..<3 {
                        for y in 0..<vh {
                            let wy = fy(y)
                            let oyy = oy * S + y
                            if st[3] == 1 {
                                row.withUnsafeMutableBufferPointer { r in
                                    var s = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: p + c * st[1] + y * st[2]), height: 1, width: vImagePixelCount(vw), rowBytes: vw * 2)
                                    var d = vImage_Buffer(data: r.baseAddress, height: 1, width: vImagePixelCount(vw), rowBytes: vw * 4)
                                    if vImageConvert_Planar16FtoPlanarF(&s, &d, 0) != kvImageNoError { fp16Failed = true }
                                }
                            } else {
                                for x in 0..<vw {
                                    var hv = p[c * st[1] + y * st[2] + x * st[3]]; var f: Float = 0
                                    var s = vImage_Buffer(data: &hv, height: 1, width: 1, rowBytes: 2)
                                    var d = vImage_Buffer(data: &f, height: 1, width: 1, rowBytes: 4)
                                    _ = vImageConvert_Planar16FtoPlanarF(&s, &d, 0); row[x] = f
                                }
                            }
                            let rowBase = (oyy * OW + ox * S)
                            let cBase = c * OW * OH
                            for x in 0..<vw {
                                let wgt = wy * wx[x]
                                acc[cBase + rowBase + x] += row[x] * wgt
                                if c == 0 { wsum[rowBase + x] += wgt }
                            }
                        }
                    }
                }
                if fp16Failed { throw AICoverSRError.predictionFailed("fp16 output") }
                done += 1
                progress(done / total)
            }
        }
        // Normalise → RGBA8.
        var rgba = [UInt8](repeating: 255, count: OW * OH * 4)
        let plane2 = OW * OH
        for i in 0..<plane2 {
            let inv = 1 / max(wsum[i], 1e-6)
            for c in 0..<3 {
                let v = acc[c * plane2 + i] * inv * 255 + 0.5
                rgba[i * 4 + c] = UInt8(max(0, min(255, v)))
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let full = CGImage(width: OW, height: OH, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: OW * 4,
                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw AICoverSRError.predictionFailed("output image")
        }
        let target = AICoverSRSize.output(width: w, height: h, scale: S)
        guard target.width != OW || target.height != OH else { return full }
        guard let down = CGContext(data: nil, width: target.width, height: target.height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return full }
        down.interpolationQuality = .high
        down.draw(full, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        return down.makeImage() ?? full
    }
}
