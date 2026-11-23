//
//  MPlayPostChain.swift
//  AVDB
//
//  Build 353 full restoration, stage C: the Metal post chain
//  (original: MetalSDRToHDRMapper / MetalHDRVividMapper /
//  MetalSpatialUpscaler / VideoFrameInterpolator /
//  MetalVideoDeinterlacer / MetalPreviewScaler, IOS-FINDINGS §3.2).
//
//  Position in the pipeline: frame-after, exactly where the
//  original's sdr-hdr metallib operates — between the FrameStore
//  and the FrameOutputScheduler, on CVPixelBuffers / Metal textures.
//  It is NOT a vo tone-mapping stage (libplacebo's domain); the
//  original's effective SDR->HDR path is this frame-after LUT pass,
//  and ours mirrors that.
//
//  Equivalence, stated honestly (also in Build353-MPlayKit.md): the
//  architecture, pass positions and parameter surfaces match the
//  original's documented surface; the shader contents are our own.
//  The upscaler is a Lanczos-2 shader upscaler, not the original's
//  system ML spatial upscaler; the interpolator is block-matching
//  motion compensation, not the original's closed algorithm; the
//  SDR->HDR curve is our own soft-knee expansion, not the original's
//  LUT.  MetalVideoDeinterlacer / MetalPreviewScaler equivalents
//  are not implemented (no interlaced-source path in AVDB's
//  playback, and PreviewReader renders through mpv's own scaler).
//
//  Pass scope: biplanar YUV inputs (NV12 / P010 — what VideoToolbox
//  actually delivers).  Other formats pass through untouched.
//  If the chain's queue is busy when a frame arrives, the frame is
//  dropped (counted), never queued up — post-processing must not
//  add latency debt to live playback.
//

import CoreMedia
import CoreVideo
import Foundation
import Metal
import simd

enum MPlaySDRToHDRLevel: Int {
    case off = 0
    case low = 1
    case high = 2
}

enum MPlayUpscalingLevel: Int {
    case off = 0
    case low = 1   // ×1.5
    case high = 2  // ×2

    var scale: Double {
        switch self {
        case .off: return 1.0
        case .low: return 1.5
        case .high: return 2.0
        }
    }
}

/// Settings + execution for the post chain.  The API names mirror
/// the original Player's (setSDRToHDRLevel / setHDRVividEnabled /
/// setVideoUpscalingLevel(_:animated:) /
/// setVideoFrameInterpolationEnabled); values persist in
/// UserDefaults so the Settings UI and the chain share one truth.
final class MPlayPostChain {
    static let shared = MPlayPostChain()

    private enum Key {
        static let sdrToHDR = "avdb.mplaykit.post.sdrToHDR"
        static let hdrVivid = "avdb.mplaykit.post.hdrVivid"
        static let upscaling = "avdb.mplaykit.post.upscaling"
        static let interpolation = "avdb.mplaykit.post.interpolation"
        static let doviP5 = "avdb.mplaykit.post.doviP5"
    }

    private(set) var sdrToHDRLevel: MPlaySDRToHDRLevel
    private(set) var hdrVividEnabled: Bool
    private(set) var upscalingLevel: MPlayUpscalingLevel
    private(set) var frameInterpolationEnabled: Bool

    /// Dolby Vision profile of the stream currently feeding the
    /// chain (0 = not DV).  Set by the display view from the
    /// player's track properties; drives the P5 correction pass.
    var dolbyProfile: Int = 0
    /// Profile 5 correction toggle (default on).  When the stream
    /// is DV profile 5, the P5 pass runs INSTEAD of SDR->HDR: P5
    /// content is already HDR, it needs its IPT colour decoded,
    /// not an SDR expansion.
    private(set) var doviP5CorrectionEnabled: Bool

    var isEnabled: Bool {
        sdrToHDRLevel != .off || upscalingLevel != .off || frameInterpolationEnabled
            || (dolbyProfile == 5 && doviP5CorrectionEnabled)
    }

    // MARK: Metal state

    private let queue = DispatchQueue(label: "avdb.mplaykit.postchain")
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var sdrPipeline: MTLComputePipelineState?
    private var doviPipeline: MTLComputePipelineState?
    private var upscalePipeline: MTLComputePipelineState?
    private var motionPipeline: MTLComputePipelineState?
    private var interpPipeline: MTLComputePipelineState?
    private var toneLUT: MTLTexture?
    private var outputPool: CVPixelBufferPool?
    private var outputPoolFormat: OSType = 0
    private var outputPoolWidth = 0
    private var outputPoolHeight = 0

    private let busyLock = NSLock()
    private var busy = false
    private(set) var droppedBusy = 0
    private(set) var processedFrames = 0

    /// The previous *input* frame, retained for interpolation.
    private var previousInput: MPlayFrame?

    init(defaults: UserDefaults = .standard) {
        sdrToHDRLevel = MPlaySDRToHDRLevel(rawValue: defaults.integer(forKey: Key.sdrToHDR)) ?? .off
        hdrVividEnabled = defaults.bool(forKey: Key.hdrVivid)
        upscalingLevel = MPlayUpscalingLevel(rawValue: defaults.integer(forKey: Key.upscaling)) ?? .off
        frameInterpolationEnabled = defaults.bool(forKey: Key.interpolation)
        doviP5CorrectionEnabled = defaults.object(forKey: Key.doviP5) == nil
            ? true : defaults.bool(forKey: Key.doviP5)

        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        if let device {
            var cache: CVMetalTextureCache?
            if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess {
                textureCache = cache
            }
            buildPipelines()
            buildToneLUT()
        }
    }

    // MARK: - Settings (original Player API names)

    func setSDRToHDRLevel(_ level: MPlaySDRToHDRLevel) {
        sdrToHDRLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: Key.sdrToHDR)
        buildToneLUT()
    }

    func setHDRVividEnabled(_ enabled: Bool) {
        hdrVividEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Key.hdrVivid)
    }

    func setVideoUpscalingLevel(_ level: MPlayUpscalingLevel, animated: Bool) {
        // `animated` in the original cross-fades the scale change;
        // our chain applies from the next frame — the parameter is
        // kept for API shape parity and currently only documented.
        _ = animated
        upscalingLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: Key.upscaling)
    }

    func setVideoFrameInterpolationEnabled(_ enabled: Bool) {
        frameInterpolationEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Key.interpolation)
        if !enabled {
            queue.async { [weak self] in self?.previousInput = nil }
        }
    }

    /// Dolby Vision Profile 5 correction (stage C addition): the
    /// frame-after counterpart of the original's
    /// DolbyP5ColorCorrection; see MPlayDolbyVision.swift.
    func setDolbyVisionP5CorrectionEnabled(_ enabled: Bool) {
        doviP5CorrectionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Key.doviP5)
    }

    // MARK: - Frame processing

    /// Process one video frame; completion receives the frames to
    /// enqueue in order (one normally; two when interpolation
    /// synthesises a midpoint).  Called from the view's frame route;
    /// completion runs on the chain queue.
    func process(_ frame: MPlayFrame, completion: @escaping ([MPlayFrame]) -> Void) {
        busyLock.lock()
        if busy {
            droppedBusy += 1
            busyLock.unlock()
            completion([frame])
            return
        }
        busy = true
        busyLock.unlock()
        queue.async { [weak self] in
            guard let self else {
                completion([frame])
                return
            }
            let out = self.processOnQueue(frame)
            self.busyLock.lock()
            self.busy = false
            self.busyLock.unlock()
            completion(out)
        }
    }

    private func processOnQueue(_ frame: MPlayFrame) -> [MPlayFrame] {
        guard isEnabled, let device, let commandQueue,
              let textureCache else { return [frame] }
        let format = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        let isBiplanar = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        guard isBiplanar else { return [frame] }

        var current = frame
        var outputs: [MPlayFrame] = []

        // Pass 1: upscale (changes geometry).
        if upscalingLevel != .off,
           let scaled = runUpscale(frame: current, scale: upscalingLevel.scale,
                                   device: device, commandQueue: commandQueue,
                                   textureCache: textureCache) {
            current = scaled
        }

        // Pass 2: tone path — mutually exclusive.  DV profile 5
        // takes the P5 correction (IPT decode + PQ), everything
        // else takes SDR -> HDR when enabled.
        if dolbyProfile == 5 && doviP5CorrectionEnabled,
           let mapped = runDoviP5(frame: current, device: device,
                                  commandQueue: commandQueue,
                                  textureCache: textureCache) {
            current = mapped
        } else if sdrToHDRLevel != .off,
           let mapped = runSDRToHDR(frame: current, device: device,
                                    commandQueue: commandQueue,
                                    textureCache: textureCache) {
            current = mapped
        }

        // Pass 3: interpolation synthesises a midpoint between the
        // previous input frame and the (processed) current one.
        if frameInterpolationEnabled, let previous = previousInput,
           previous.width == current.width, previous.height == current.height,
           let midpoint = runInterpolate(previous: previous, current: current,
                                         device: device, commandQueue: commandQueue,
                                         textureCache: textureCache) {
            outputs.append(midpoint)
        }
        previousInput = current
        outputs.append(current)
        processedFrames += 1
        return outputs
    }

    // MARK: - Metal setup

    private func buildPipelines() {
        guard let device, let library = device.makeDefaultLibrary() else {
            MPlayDiagnostics.log("postchain: no default Metal library (shaders not compiled in?)")
            return
        }
        func pipeline(_ name: String) -> MTLComputePipelineState? {
            guard let function = library.makeFunction(name: name) else {
                MPlayDiagnostics.log("postchain: missing kernel \(name)")
                return nil
            }
            return try? device.makeComputePipelineState(function: function)
        }
        sdrPipeline = pipeline("pkSDRToHDRKernel0")
        doviPipeline = pipeline("pkDoviP5Kernel0")
        upscalePipeline = pipeline("pkUpscaleKernel0")
        motionPipeline = pipeline("pkMotionKernel0")
        interpPipeline = pipeline("pkInterpKernel0")
    }

    /// Our own SDR->HDR curve as a 1D LUT: a soft-knee expansion
    /// (identity below the knee, compressive lift above), with the
    /// level scaling the lift.  Not the original's LUT — see header.
    private func buildToneLUT() {
        guard let device else { return }
        let size = 256
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .r16Float
        descriptor.width = size
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return }
        var values = [Float16](repeating: 0, count: size)
        let lift: Float = sdrToHDRLevel == .high ? 0.55 : 0.35
        for i in 0..<size {
            let x = Float(i) / Float(size - 1)
            let knee: Float = 0.55
            let y: Float
            if x < knee {
                y = x * (1.0 + lift * 0.25)
            } else {
                let t = (x - knee) / (1 - knee)
                y = knee * (1.0 + lift * 0.25) + (1 - knee * (1.0 + lift * 0.25)) * (1 - pow(1 - t, 1.0 + lift))
            }
            values[i] = Float16(min(y, 1.0))
        }
        values.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                  size: MTLSize(width: size, height: 1, depth: 1)),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: size * 2
            )
        }
        toneLUT = texture
    }

    // MARK: - Texture / buffer plumbing

    private func texture(from buffer: CVPixelBuffer, plane: Int,
                         format: MTLPixelFormat, cache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(buffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
        var cvTexture: CVMetalTexture?
        let rc = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, buffer, nil, format,
            width, height, plane, &cvTexture
        )
        guard rc == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func outputBuffer(format: OSType, width: Int, height: Int) -> CVPixelBuffer? {
        if outputPool == nil || outputPoolFormat != format
            || outputPoolWidth != width || outputPoolHeight != height {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: format,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            var pool: CVPixelBufferPool?
            guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil,
                                          attrs as CFDictionary, &pool) == kCVReturnSuccess,
                  let pool else { return nil }
            outputPool = pool
            outputPoolFormat = format
            outputPoolWidth = width
            outputPoolHeight = height
        }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPool!, &buffer) == kCVReturnSuccess
        else { return nil }
        return buffer
    }

    private func planeFormats(for format: OSType)
        -> (luma: MTLPixelFormat, chroma: MTLPixelFormat)? {
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return (.r8Unorm, .rg8Unorm)
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            return (.r16Unorm, .rg16Unorm)
        default:
            return nil
        }
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder,
                          pipeline: MTLComputePipelineState,
                          width: Int, height: Int) {
        let threads = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(
            width: (width + threads.width - 1) / threads.width,
            height: (height + threads.height - 1) / threads.height,
            depth: 1
        )
        encoder.setComputePipelineState(pipeline)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
    }

    // MARK: - Passes

    private struct SDRToHDRParams {
        var colorMatrix: simd_float4x4
        var inputMinPQ: Float
        var inputMaxPQ: Float
        var lutSize: UInt32
        var isP010: UInt32
        var isFullRange: UInt32
        var isSRGB: UInt32
        var isBT2020Primaries: UInt32
        var width: UInt32
        var height: UInt32
    }

    private func runSDRToHDR(frame: MPlayFrame, device: MTLDevice,
                             commandQueue: MTLCommandQueue,
                             textureCache: CVMetalTextureCache) -> MPlayFrame? {
        guard let pipeline = sdrPipeline, let toneLUT else { return nil }
        let src = frame.pixelBuffer
        let format = CVPixelBufferGetPixelFormatType(src)
        guard let planes = planeFormats(for: format),
              let out = outputBuffer(format: format, width: frame.width, height: frame.height),
              let srcY = texture(from: src, plane: 0, format: planes.luma, cache: textureCache),
              let srcUV = texture(from: src, plane: 1, format: planes.chroma, cache: textureCache),
              let dstY = texture(from: out, plane: 0, format: planes.luma, cache: textureCache),
              let dstUV = texture(from: out, plane: 1, format: planes.chroma, cache: textureCache),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return nil }

        let isFullRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        // YUV -> RGB (BT.709 standard coefficients), built directly
        // as Metal columns: result = col0*Y + col1*U + col2*V + col3.
        // Limited-range scaling and the U/V centring are folded in:
        //   Y' = yScale*Y + yOff,  U' = uvScale*(U-0.5),  V' = uvScale*(V-0.5)
        //   R = Y' + 1.5748*V',  G = Y' - 0.1873*U' - 0.4681*V',
        //   B = Y' + 1.8556*U'.
        let yScale: Float = isFullRange ? 1.0 : 255.0 / 219.0
        let uvScale: Float = isFullRange ? 1.0 : 255.0 / 224.0
        let yOff: Float = isFullRange ? 0.0 : -(16.0 / 255.0) * yScale
        let col0 = simd_float4(yScale, yScale, yScale, 0)
        let col1 = simd_float4(0, -0.1873 * uvScale, 1.8556 * uvScale, 0)
        let col2 = simd_float4(1.5748 * uvScale, -0.4681 * uvScale, 0, 0)
        let col3 = simd_float4(
            yOff - 0.5 * 1.5748 * uvScale,
            yOff + 0.5 * (0.1873 + 0.4681) * uvScale,
            yOff - 0.5 * 1.8556 * uvScale,
            1
        )
        let matrix = simd_float4x4(columns: (col0, col1, col2, col3))
        var params = SDRToHDRParams(
            colorMatrix: matrix,
            inputMinPQ: 0.0,
            inputMaxPQ: hdrVividEnabled ? 1.0 : 0.85,
            lutSize: 256,
            isP010: format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ? 1 : 0,
            isFullRange: isFullRange ? 1 : 0,
            isSRGB: 1,
            isBT2020Primaries: 0,
            width: UInt32(frame.width),
            height: UInt32(frame.height)
        )
        encoder.setTexture(srcY, index: 0)
        encoder.setTexture(srcUV, index: 1)
        encoder.setTexture(toneLUT, index: 2)
        encoder.setTexture(dstY, index: 3)
        encoder.setTexture(dstUV, index: 4)
        encoder.setBytes(&params, length: MemoryLayout<SDRToHDRParams>.stride, index: 0)
        dispatch(encoder, pipeline: pipeline, width: frame.width, height: frame.height)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        return MPlayFrame(kind: .video, pixelBuffer: out,
                          realtimePTS: frame.realtimePTS,
                          ptsSeconds: frame.ptsSeconds,
                          durationSeconds: frame.durationSeconds,
                          width: frame.width, height: frame.height,
                          isRepeat: frame.isRepeat, frameID: frame.frameID)
    }

    private struct DoviP5Params {
        var iptToRGB: simd_float4x4
        var isP010: UInt32
        var isFullRange: UInt32
        var width: UInt32
        var height: UInt32
    }

    /// Dolby Vision Profile 5 correction pass: same slot and
    /// plumbing as runSDRToHDR, but the matrix is
    /// DolbyP5ColorCorrection.Map.profile5's combined IPT->RGB
    /// (public BT.2124 constants — see MPlayDolbyVision.swift for
    /// the provenance and the honesty note), and the kernel
    /// re-encodes BT.2020 PQ so the output is a standard HDR
    /// signal in the input's buffer format.
    private func runDoviP5(frame: MPlayFrame, device: MTLDevice,
                           commandQueue: MTLCommandQueue,
                           textureCache: CVMetalTextureCache) -> MPlayFrame? {
        guard let pipeline = doviPipeline else { return nil }
        let src = frame.pixelBuffer
        let format = CVPixelBufferGetPixelFormatType(src)
        guard let planes = planeFormats(for: format),
              let out = outputBuffer(format: format, width: frame.width, height: frame.height),
              let srcY = texture(from: src, plane: 0, format: planes.luma, cache: textureCache),
              let srcUV = texture(from: src, plane: 1, format: planes.chroma, cache: textureCache),
              let dstY = texture(from: out, plane: 0, format: planes.luma, cache: textureCache),
              let dstUV = texture(from: out, plane: 1, format: planes.chroma, cache: textureCache),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return nil }
        let map = DolbyP5ColorCorrection.Map.profile5.yccToRGB
        // simd columns are the input basis: result = c0*I + c1*P + c2*T.
        let matrix = simd_float4x4(columns: (
            simd_float4(Float(map.m00), Float(map.m10), Float(map.m20), 0),
            simd_float4(Float(map.m01), Float(map.m11), Float(map.m21), 0),
            simd_float4(Float(map.m02), Float(map.m12), Float(map.m22), 0),
            simd_float4(0, 0, 0, 1)
        ))
        var params = DoviP5Params(
            iptToRGB: matrix,
            isP010: format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ? 1 : 0,
            isFullRange: format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ? 1 : 0,
            width: UInt32(frame.width),
            height: UInt32(frame.height)
        )
        encoder.setTexture(srcY, index: 0)
        encoder.setTexture(srcUV, index: 1)
        encoder.setTexture(dstY, index: 2)
        encoder.setTexture(dstUV, index: 3)
        encoder.setBytes(&params, length: MemoryLayout<DoviP5Params>.stride, index: 0)
        dispatch(encoder, pipeline: pipeline, width: frame.width, height: frame.height)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        return MPlayFrame(kind: .video, pixelBuffer: out,
                          realtimePTS: frame.realtimePTS,
                          ptsSeconds: frame.ptsSeconds,
                          durationSeconds: frame.durationSeconds,
                          width: frame.width, height: frame.height,
                          isRepeat: frame.isRepeat, frameID: frame.frameID)
    }

    private struct UpscaleParams {
        var srcWidth: UInt32
        var srcHeight: UInt32
        var dstWidth: UInt32
        var dstHeight: UInt32
    }

    private func runUpscale(frame: MPlayFrame, scale: Double, device: MTLDevice,
                            commandQueue: MTLCommandQueue,
                            textureCache: CVMetalTextureCache) -> MPlayFrame? {
        guard let pipeline = upscalePipeline else { return nil }
        let src = frame.pixelBuffer
        let format = CVPixelBufferGetPixelFormatType(src)
        guard let planes = planeFormats(for: format) else { return nil }
        let dstWidth = Int((Double(frame.width) * scale).rounded())
        let dstHeight = Int((Double(frame.height) * scale).rounded())
        guard let out = outputBuffer(format: format, width: dstWidth, height: dstHeight),
              let srcY = texture(from: src, plane: 0, format: planes.luma, cache: textureCache),
              let srcUV = texture(from: src, plane: 1, format: planes.chroma, cache: textureCache),
              let dstY = texture(from: out, plane: 0, format: planes.luma, cache: textureCache),
              let dstUV = texture(from: out, plane: 1, format: planes.chroma, cache: textureCache),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return nil }
        var params = UpscaleParams(srcWidth: UInt32(frame.width),
                                   srcHeight: UInt32(frame.height),
                                   dstWidth: UInt32(dstWidth),
                                   dstHeight: UInt32(dstHeight))
        encoder.setTexture(srcY, index: 0)
        encoder.setTexture(srcUV, index: 1)
        encoder.setTexture(dstY, index: 2)
        encoder.setTexture(dstUV, index: 3)
        encoder.setBytes(&params, length: MemoryLayout<UpscaleParams>.stride, index: 0)
        dispatch(encoder, pipeline: pipeline, width: dstWidth, height: dstHeight)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        return MPlayFrame(kind: .video, pixelBuffer: out,
                          realtimePTS: frame.realtimePTS,
                          ptsSeconds: frame.ptsSeconds,
                          durationSeconds: frame.durationSeconds,
                          width: dstWidth, height: dstHeight,
                          isRepeat: frame.isRepeat, frameID: frame.frameID)
    }

    private struct MotionParams {
        var width: UInt32
        var height: UInt32
        var block: UInt32
        var search: UInt32
    }

    private struct InterpParams {
        var width: UInt32
        var height: UInt32
        var block: UInt32
        var phase: Float
    }

    private func runInterpolate(previous: MPlayFrame, current: MPlayFrame,
                                device: MTLDevice, commandQueue: MTLCommandQueue,
                                textureCache: CVMetalTextureCache) -> MPlayFrame? {
        guard let motionPipeline, let interpPipeline else { return nil }
        let format = CVPixelBufferGetPixelFormatType(current.pixelBuffer)
        guard let planes = planeFormats(for: format),
              let prevY = texture(from: previous.pixelBuffer, plane: 0, format: planes.luma, cache: textureCache),
              let currY = texture(from: current.pixelBuffer, plane: 0, format: planes.luma, cache: textureCache),
              let out = outputBuffer(format: format, width: current.width, height: current.height),
              let dstY = texture(from: out, plane: 0, format: planes.luma, cache: textureCache),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return nil }

        // Motion field: one vector per 16x16 full-res block, block
        // matching with a ±4 px search on the luma planes.
        let block = 16
        let blocksX = max(1, current.width / block)
        let blocksY = max(1, current.height / block)
        let motionDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: blocksX, height: blocksY,
            mipmapped: false
        )
        motionDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let motionTexture = device.makeTexture(descriptor: motionDescriptor),
              let motionEncoder = commandBuffer.makeComputeCommandEncoder()
        else { return nil }
        var motionParams = MotionParams(width: UInt32(current.width),
                                        height: UInt32(current.height),
                                        block: UInt32(block),
                                        search: 4)
        motionEncoder.setTexture(prevY, index: 0)
        motionEncoder.setTexture(currY, index: 1)
        motionEncoder.setTexture(motionTexture, index: 2)
        motionEncoder.setBytes(&motionParams, length: MemoryLayout<MotionParams>.stride, index: 0)
        // One thread per block: dispatch exactly the block grid.
        motionEncoder.setComputePipelineState(motionPipeline)
        motionEncoder.dispatchThreadgroups(
            MTLSize(width: blocksX, height: blocksY, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        motionEncoder.endEncoding()

        guard let interpEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        var interpParams = InterpParams(width: UInt32(current.width),
                                        height: UInt32(current.height),
                                        block: UInt32(block),
                                        phase: 0.5)
        interpEncoder.setTexture(prevY, index: 0)
        interpEncoder.setTexture(currY, index: 1)
        interpEncoder.setTexture(motionTexture, index: 2)
        interpEncoder.setTexture(dstY, index: 3)
        interpEncoder.setBytes(&interpParams, length: MemoryLayout<InterpParams>.stride, index: 0)
        dispatch(interpEncoder, pipeline: interpPipeline,
                 width: current.width, height: current.height)
        interpEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        // Chroma for the midpoint: copy the current frame's chroma
        // (midpoint chroma motion is out of scope for this port).
        copyPlane(from: current.pixelBuffer, to: out, plane: 1)
        let midpointPTS = previous.ptsSeconds + (current.ptsSeconds - previous.ptsSeconds) / 2
        return MPlayFrame(kind: .video, pixelBuffer: out,
                          realtimePTS: current.realtimePTS,
                          ptsSeconds: midpointPTS,
                          durationSeconds: current.durationSeconds / 2,
                          width: current.width, height: current.height,
                          isRepeat: false, frameID: current.frameID)
    }

    private func copyPlane(from source: CVPixelBuffer, to destination: CVPixelBuffer, plane: Int) {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }
        guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
              let dst = CVPixelBufferGetBaseAddressOfPlane(destination, plane)
        else { return }
        let srcStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
        let dstStride = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
        let rows = CVPixelBufferGetHeightOfPlane(destination, plane)
        let copy = min(srcStride, dstStride)
        for row in 0..<rows {
            memcpy(dst + row * dstStride, src + row * srcStride, copy)
        }
    }
}
