//
//  MPlayCapture.swift
//  AVDB
//
//  Build 353 (full restoration): the frame-capture surface of the
//  original Player — captureVideoFrame() / CapturedVideoFrame
//  .jpeg(height:quality:correctDolbyP5:) / screenshot(...) /
//  renderBlackFrame().  In the original, the Player owns the
//  FrameStore; in our architecture the view owns it (stage A), so
//  these live on MPlayVideoView — same data, different owner,
//  recorded in Build353-MPlayKit.md.
//
//  correctDolbyP5 on this path is the FULL-fidelity domain (unlike
//  the PreviewReader approximation): the captured frame is the
//  vo's biplanar buffer, so the P5 correction runs per-pixel over
//  the YUV planes — (i, p, t) = (Y, U−0.5, V−0.5) in limited-range
//  normalised form, the same convention as the Metal pass — and
//  produces an sRGB image.  It is O(pixels) CPU work with a pow()
//  per pixel; fine for a screenshot, wrong for a video path.
//

import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import UIKit

/// The original's CapturedVideoFrame.
struct MPlayCapturedVideoFrame {
    let pixelBuffer: CVPixelBuffer
    let width: Int
    let height: Int
    /// Presentation time of the frame (seconds).
    let time: Double
    /// DV profile of the playing file (0 = not DV).
    let dolbyProfile: Int

    /// jpeg(height:quality:correctDolbyP5:) — optionally P5-corrects
    /// (profile 5 only), scales to the requested height preserving
    /// aspect, and encodes JPEG.
    func jpeg(height targetHeight: Int, quality: Double,
              correctDolbyP5: Bool) -> Data? {
        var image: CGImage?
        if correctDolbyP5, dolbyProfile == 5 {
            image = Self.p5CorrectedImage(from: pixelBuffer)
        }
        if image == nil {
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            image = context.createCGImage(ci, from: ci.extent)
        }
        guard let image else { return nil }
        var uiImage = UIImage(cgImage: image)
        if targetHeight > 0, height > 0, targetHeight != height {
            let scale = Double(targetHeight) / Double(height)
            let targetWidth = max(1, Int((Double(width) * scale).rounded()))
            let renderer = UIGraphicsImageRenderer(
                size: CGSize(width: targetWidth, height: targetHeight))
            uiImage = renderer.image { _ in
                uiImage.draw(in: CGRect(x: 0, y: 0,
                                        width: targetWidth,
                                        height: targetHeight))
            }
        }
        return uiImage.jpegData(
            compressionQuality: CGFloat(min(1, max(0, quality))))
    }

    /// Per-pixel P5 correction over a biplanar (NV12-style) buffer.
    /// Returns nil for packed formats (the caller falls back to the
    /// uncorrected image — the playing pipeline's frames are
    /// biplanar by construction of the vo).
    private static func p5CorrectedImage(from buffer: CVPixelBuffer) -> CGImage? {
        guard CVPixelBufferIsPlanar(buffer),
              CVPixelBufferGetPlaneCount(buffer) >= 2 else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
        else { return nil }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let yPlane = yBase.assumingMemoryBound(to: UInt8.self)
        let uvPlane = uvBase.assumingMemoryBound(to: UInt8.self)
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let map = DolbyP5ColorCorrection.Map.profile5
        for row in 0..<height {
            let yRow = row * yStride
            let uvRow = (row / 2) * uvStride
            for column in 0..<width {
                let y = Double(yPlane[yRow + column]) / 255
                let uvOffset = uvRow + (column / 2) * 2
                let u = Double(uvPlane[uvOffset]) / 255 - 0.5
                let v = Double(uvPlane[uvOffset + 1]) / 255 - 0.5
                let rgb = DolbyP5ColorCorrection.convert(
                    i: y, p: u, t: v, map: map)
                let offset = (row * width + column) * 4
                rgba[offset] = rgb.r
                rgba[offset + 1] = rgb.g
                rgba[offset + 2] = rgb.b
            }
        }
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)
    }
}

extension MPlayVideoView {
    /// captureVideoFrame() — the latest frame the store holds, with
    /// the player's current DV profile stamped on it.
    func captureVideoFrame(player: MPlayPlayer) -> MPlayCapturedVideoFrame? {
        guard let frame = frameStore.currentVideoFrame() else { return nil }
        return MPlayCapturedVideoFrame(
            pixelBuffer: frame.pixelBuffer,
            width: frame.width,
            height: frame.height,
            time: frame.ptsSeconds,
            dolbyProfile: player.dolbyVisionProfile()?.profile ?? 0
        )
    }

    /// screenshot(to:format:jpegQuality:correctDolbyP5:completion:)
    /// — captures and writes the JPEG to the given path.
    func screenshot(
        player: MPlayPlayer, to path: String, format: String,
        jpegQuality: Double, correctDolbyP5: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard format.lowercased() == "jpeg" || format.lowercased() == "jpg",
              let frame = captureVideoFrame(player: player),
              let data = frame.jpeg(height: 0, quality: jpegQuality,
                                    correctDolbyP5: correctDolbyP5)
        else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                completion(true)
            } catch {
                MPlayDiagnostics.log("screenshot write failed: \(error)")
                completion(false)
            }
        }
    }

    /// renderBlackFrame() — one black frame through the scheduler
    /// (clears any stale picture when playback stops).
    func renderBlackFrame() {
        let width = Int(bounds.width * UIScreen.main.scale)
        let height = Int(bounds.height * UIScreen.main.scale)
        scheduler.enqueueBlackFrame(width: max(2, width),
                                    height: max(2, height))
    }

    /// clearRenderView() — flush both the display layer queue and
    /// the subtitle layer.
    func clearRenderView() {
        scheduler.flush()
        subtitleLayerController.clear()
    }

    /// setVideoGravity / restoreVideoGravity — the display layer's
    /// own videoGravity property is the direct equivalent.
    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        displayLayer.videoGravity = gravity
    }

    func restoreVideoGravity(_ gravity: AVLayerVideoGravity) -> Bool {
        displayLayer.videoGravity = gravity
        return true
    }
}
