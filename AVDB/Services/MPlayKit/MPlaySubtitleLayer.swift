//
//  MPlaySubtitleLayer.swift
//  AVDB
//
//  Build 353 full restoration, stage A: the independent subtitle
//  layer (IOS-FINDINGS §1/§2: the original's FrameOutputView carries
//  subtitleLayer / subtitleMetalLayer, the Player exposes
//  pictureInPictureSubtitleLayer, and the layer migrates between the
//  inline host and the PiP host with its own render size —
//  updatePictureInPictureSubtitleRenderSize).
//
//  Our renderer division (recorded choice): the frame_output vo
//  renders subtitle bitmaps with mpv's own OSD layer (libass) into a
//  transparent BGRA image, delivered on the sink's subtitle channel;
//  this controller turns those images into CALayer contents.  The
//  original's division between its core renderer and its Metal
//  subtitle layer is not determinable from symbols (IOS-FINDINGS
//  §6), so no claim is made either way; what is reproduced is the
//  architecture: subtitles live in their own layer, decoupled from
//  video frames, migratable between hosts, rendered at a size that
//  follows the host (inline bounds or PiP render size), not the
//  video frame size.
//
//  The layer's default parent is the display layer itself (as a
//  sublayer), which is what makes sample-buffer PiP carry the
//  subtitles with the picture.  moveSubtitleLayer(toHost:) /
//  moveSubtitleLayerToInlineHost() reparent it when the UI wants it
//  somewhere else (stage B uses these around PiP transitions).
//

import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore

final class MPlaySubtitleLayerController {
    /// The layer whose contents are the current subtitle image.
    let layer = CALayer()

    /// Size the subtitle images are rendered at (host-driven; the
    /// view forwards changes to the player's vo subtitle size so the
    /// next rendered image matches).  Zero = unset (vo falls back to
    /// the video size).
    private(set) var renderSize = CGSize.zero

    private var lastFrameID: UInt64 = .max
    private var lastPTS = -1.0
    private var lastFrame: MPlayFrame?

    /// HDR brightness gain for the subtitle bitmaps (the original's
    /// setSubtitleHDR surface: on HDR content, SDR-authored subtitle
    /// bitmaps are re-exposed so they don't render dim against the
    /// HDR picture).  1.0 = identity.  Applied by scaling the
    /// premultiplied RGB bytes during image conversion — the correct
    /// domain for premultiplied bitmaps.  Changing the gain forces
    /// the current frame to re-render.
    var brightnessGain: Double = 1 {
        didSet {
            guard brightnessGain != oldValue else { return }
            lastFrameID = .max
            if let lastFrame { update(lastFrame) }
        }
    }

    /// Invoked when renderSize changes; MPlayVideoView wires this to
    /// the player's setSubtitleRenderSize so the vo re-renders at the
    /// new size (the original's updatePictureInPictureSubtitleRenderSize
    /// semantics: render resolution follows the host, not the video).
    var onRenderSizeChanged: ((CGSize) -> Void)?

    init() {
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.isOpaque = false
    }

    // MARK: - Frame intake

    /// Consume one subtitle-channel frame.  Called from the frame
    /// store's callback (VO thread); the layer mutation hops to the
    /// main queue.  Identical frames (same id + pts, e.g. a redraw)
    /// are dropped.
    func update(_ frame: MPlayFrame) {
        if frame.frameID == lastFrameID, frame.ptsSeconds == lastPTS {
            return
        }
        lastFrameID = frame.frameID
        lastPTS = frame.ptsSeconds
        lastFrame = frame
        guard let image = Self.makeImage(from: frame.pixelBuffer,
                                         gain: brightnessGain) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.layer.contents = image
        }
    }

    func clear() {
        lastFrameID = .max
        lastPTS = -1
        lastFrame = nil
        DispatchQueue.main.async { [weak self] in
            self?.layer.contents = nil
        }
    }

    // MARK: - Render size

    func setRenderSize(_ size: CGSize) {
        let clamped = CGSize(width: max(size.width, 0), height: max(size.height, 0))
        guard clamped != renderSize else { return }
        renderSize = clamped
        onRenderSizeChanged?(clamped)
    }

    // MARK: - Image conversion

    /// BGRA pixel buffer -> CGImage.  The vo's subtitle images are
    /// libass-style premultiplied BGRA; byteOrder32Little +
    /// premultipliedFirst is the matching CGImage layout.  The bytes
    /// are copied out while the buffer is locked so the image never
    /// aliases the (short-lived) pixel buffer.
    private static func makeImage(from buffer: CVPixelBuffer,
                                  gain: Double = 1) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }
        var data = Data(bytes: base, count: bytesPerRow * height)
        if gain != 1 {
            // Premultiplied BGRA: scaling RGB by the gain re-exposes
            // the bitmap without touching alpha relationships.
            let factor = max(0, gain)
            data.withUnsafeMutableBytes { raw in
                guard let bytes = raw.baseAddress?
                    .assumingMemoryBound(to: UInt8.self) else { return }
                for row in 0..<height {
                    var offset = row * bytesPerRow
                    for _ in 0..<width {
                        for channel in 0..<3 {
                            let value = Double(bytes[offset + channel]) * factor
                            bytes[offset + channel] =
                                UInt8(min(255, max(0, value.rounded())))
                        }
                        offset += 4
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
