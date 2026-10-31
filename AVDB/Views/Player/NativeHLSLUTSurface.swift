import AVFoundation
import CoreImage
import MetalKit
import UIKit

/// Same-item, same-clock SDR presentation. The AVPlayerLayer remains the fallback.
/// Own on the main actor; insert `view` above only the AVPlayerLayer, below controls.
@MainActor
final class NativeHLSLUTSurface: NSObject {
    /// Build 279: decoded 32BGRA SDR values are the display-referred pixels AVPlayerLayer shows.
    /// Tag them sRGB so CoreImage does NOT honour the buffer's BT.709 transfer attachment and run a
    /// 709-OETF→sRGB conversion (that lifted shadows ~+0.06, flattened contrast and hazed the picture).
    nonisolated static func sourceImage(_ buffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: buffer, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    }
    let view: MTKView
    private(set) var output: AVPlayerItemVideoOutput?
    var onStatus: ((String) -> Void)?
    var onSourceCheck: ((Bool, String) -> Void)?
    var readyForDecodedFrames: Bool { sourceSafe && output != nil }
    var onPresented: ((CMTime) -> Void)?
#if DEBUG
    // Instrumentation only: the host can append a GPU blit before commit.
    var testEncode: ((MTLTexture, MTLCommandBuffer, CMTime) -> Void)?
    var testGeometry: (([String: Double]) -> Void)?
#endif
    private weak var player: AVPlayer?
    private weak var item: AVPlayerItem?
    private let queue: MTLCommandQueue
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var link: CADisplayLink?
    private var observers: [NSObjectProtocol] = []
    private var filter: ((CIImage) -> CIImage)?
    private var generation = 0
    private var inFlight = false
    private var lastBuffer: CVPixelBuffer?
    private var lastPTS = CMTime.invalid
    private var lastAnalysisHost: CFTimeInterval = -.infinity
    private var dirty = false
    private var forceCopy = false
    private var lastFrameHost = CACurrentMediaTime()
    private var bypassReason: String?
    private var sourceSafe = false
    private var formatTask: Task<Void, Never>?
    private var transform = CGAffineTransform.identity
    private var lastStatus = ""

    init?(player: AVPlayer, container: UIView) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.player = player; self.queue = queue
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        view = MTKView(frame: container.bounds, device: device)
        super.init()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.isPaused = true; view.enableSetNeedsDisplay = false
        view.framebufferOnly = false; view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = true; view.isOpaque = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.isHidden = true
        // Overlay host is noninteractive and sits under chrome/subtitles in PlayerView.
        // Within the host, keep the Metal view on top of any stray siblings; never above controls.
        if view.superview !== container { container.addSubview(view) }
        container.bringSubviewToFront(view)
        view.frame = container.bounds
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willResignActiveNotification,
                     UIApplication.didBecomeActiveNotification, AVPlayerItem.timeJumpedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    guard let self else { return }
                    if note.name == AVPlayerItem.timeJumpedNotification {
                        guard let changed = note.object as? AVPlayerItem, changed === self.item else { return }
                    }
                    self.generation += 1
                    self.lastBuffer = nil; self.dirty = true; self.forceCopy = true
                    self.hide("等待新解码帧；后台/AirPlay/PiP 使用原画")
                    self.lastFrameHost = CACurrentMediaTime()
                }
            })
        }
        let proxy = DisplayProxy(); proxy.owner = self
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayProxy.fire(_:)))
        link.add(to: .main, forMode: .common); self.link = link
    }

    /// User-triggered single-frame analysis may downsample this buffer separately.
    /// It shares the output, never creates a second player or CPU frame readback here.
    /// Prefer the last presented SDR frame so analysis matches what the user saw.
    /// `force` bypasses the 1.2s throttle (开启/重新分析); still shares the output — no second player.
    func copyDecodedFrameForAnalysis(force: Bool = false) -> CVPixelBuffer? {
        guard sourceSafe, let player, let output else { return nil }
        let now = CACurrentMediaTime()
        if !force && now - lastAnalysisHost < 1.2 { return nil }
        var pts = CMTime.invalid
        // Prefer a fresh decode at the playhead; fall back to last presented SDR frame.
        if let buffer = output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: &pts) {
            guard isKnownSDR(buffer) else { lastBuffer = nil; return nil }
            lastBuffer = buffer; lastPTS = pts; dirty = true; lastAnalysisHost = now
            return buffer
        }
        if let previous = lastBuffer, isKnownSDR(previous) {
            lastAnalysisHost = now
            return previous
        }
        return nil
    }

    /// Next analysis may reuse the latest presented buffer immediately after 开启/重新分析.
    func prepareForcedAnalysisFrame() {
        lastAnalysisHost = -.infinity
        forceCopy = true
        dirty = true
    }

    /// Set nil to show the original layer immediately. No AVVideoComposition on HLS.
    func setFilter(_ value: ((CIImage) -> CIImage)?) {
        generation += 1; filter = value; dirty = true
        // Always force one fresh pull so 开启 / 手动应用 / 参数变更不依赖 hasNew 边沿。
        forceCopy = true
        hide(value == nil ? "原画（在线 LUT 关闭）" : "等待 SDR 解码帧及 GPU 完成")
        lastFrameHost = CACurrentMediaTime()
    }

    /// The owner MUST call this on PiP start/stop. PiP uses the original AV layer.
    func setNativeBypass(_ reason: String?) {
        generation += 1; bypassReason = reason
        // Clearing PiP/layout bypass must force a fresh pull so resume after seek
        // does not wait on a stale hasNewPixelBuffer edge.
        forceCopy = true
        dirty = true
        if reason != nil { lastBuffer = nil }
        if let reason {
            hide("原画旁路：\(reason)")
        } else {
            hide("等待前台新帧")
        }
        lastFrameHost = CACurrentMediaTime()
    }

    /// Player scrub: hide Metal immediately and demand a fresh decode after settle.
    func noteSeek() {
        generation += 1
        lastBuffer = nil
        dirty = true
        forceCopy = true
        hide("拖动中：原画")
        lastFrameHost = CACurrentMediaTime()
    }

    func stop() {
        generation += 1; link?.invalidate(); link = nil
        formatTask?.cancel(); formatTask = nil
        if let item, let output { item.remove(output) }
        output = nil; item = nil; filter = nil; lastBuffer = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        view.removeFromSuperview()
    }

    private func hide(_ message: String) {
        view.isHidden = true
        if lastStatus != message { lastStatus = message; onStatus?(message) }
    }

    private func bind(_ next: AVPlayerItem?) {
        generation += 1; formatTask?.cancel(); sourceSafe = false
        lastBuffer = nil; dirty = false; forceCopy = true; lastAnalysisHost = -.infinity
        hide("切换视频：原画等待格式检查")
        if let item, let output { item.remove(output) }
        item = next; output = nil; transform = .identity
        guard let next else { return }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        // Do not set suppressesPlayerRendering: fallback must remain live.
        next.add(output); self.output = output
        formatTask = Task { [weak self, weak next] in
            guard let self, let next else { return }
            do {
                let protected = try await next.asset.load(.hasProtectedContent)
                try Task.checkCancellation()
                guard self.item === next else { return }
                guard !protected else { self.hide("受保护内容使用原画；不绕过 DRM"); return }
                let tracks = try await next.asset.loadTracks(withMediaType: .video)
                var preferred = CGAffineTransform.identity
                if let track = tracks.first {
                    preferred = try await track.load(.preferredTransform)
                    let descriptions = try await track.load(.formatDescriptions)
                    try Task.checkCancellation()
                    guard self.item === next else { return }
                    for description in descriptions {
                        let ext = CMFormatDescriptionGetExtensions(description) as NSDictionary?
                        let transfer = ext?[kCMFormatDescriptionExtension_TransferFunction] as? String
                        if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) || transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
                            self.hide("HDR PQ/HLG 原画旁路"); return
                        }
                        let codec = CMFormatDescriptionGetMediaSubType(description)
                        if codec == 0x64766831 || codec == 0x64766865 { self.hide("Dolby Vision 原画旁路"); return }
                    }
                }
                try Task.checkCancellation()
                guard self.item === next else { return }
                self.transform = preferred
                // Every decoded buffer must still pass the explicit SDR metadata gate.
                self.sourceSafe = true
                self.onSourceCheck?(true, "源检查通过；等待明确 SDR 解码帧")
            } catch {
                guard !Task.isCancelled, self.item === next else { return }
                self.hide("无法验证源格式/保护状态，使用原画")
            }
        }
    }

    private func isKnownSDR(_ buffer: CVPixelBuffer) -> Bool {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return false }
        func attachment(_ key: CFString) -> String? {
            CVBufferCopyAttachment(buffer, key, nil) as? String
        }
        let transfer = attachment(kCVImageBufferTransferFunctionKey)
        let primaries = attachment(kCVImageBufferColorPrimariesKey)
        let matrix = attachment(kCVImageBufferYCbCrMatrixKey)
        let knownTransfer = transfer == (kCVImageBufferTransferFunction_ITU_R_709_2 as String) || transfer == (kCVImageBufferTransferFunction_sRGB as String)
        let knownPrimaries = primaries == (kCVImageBufferColorPrimaries_ITU_R_709_2 as String)
        // RGB outputs may omit the YCbCr matrix; if present it must be BT.709.
        return knownTransfer && knownPrimaries && (matrix == nil || matrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String))
    }

    fileprivate func draw(_ displayLink: CADisplayLink) {
        guard let player else { hide("播放器不可用"); return }
        if item !== player.currentItem { bind(player.currentItem) }
        guard UIApplication.shared.applicationState == .active, !player.isExternalPlaybackActive, bypassReason == nil else {
            hide("后台/AirPlay/PiP 原画旁路"); return
        }
        guard let item, item.status == .readyToPlay, sourceSafe, let output, let filter else { return }
        // Keep the last Metal frame up during brief GPU/back-pressure gaps.
        // Hard-fallback to AVPlayerLayer only after a long stall (HLS segment gaps).
        let stallLimit: CFTimeInterval = 2.0
        guard !inFlight else {
            if player.rate != 0 && view.isHidden && CACurrentMediaTime() - lastFrameHost > stallLimit {
                hide("GPU 等待超时，回原画")
            }
            return
        }
        let hostTime = displayLink.targetTimestamp > 0 ? displayLink.targetTimestamp : CACurrentMediaTime()
        let time = player.rate == 0 ? player.currentTime() : output.itemTime(forHostTime: hostTime)
        var pts = CMTime.invalid
        let buffer: CVPixelBuffer
        // forceCopy works while playing too (seek / bypass clear / filter publish).
        if output.hasNewPixelBuffer(forItemTime: time) || forceCopy {
            guard let fresh = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &pts), isKnownSDR(fresh) else {
                if forceCopy {
                    // One forced miss must not permanently kill the overlay; retry next tick.
                    forceCopy = false
                    if player.rate != 0 && view.isHidden && CACurrentMediaTime() - lastFrameHost > stallLimit {
                        lastBuffer = nil; hide("解码色彩元数据未知或非 SDR，原画旁路")
                    }
                    return
                }
                lastBuffer = nil; hide("解码色彩元数据未知或非 SDR，原画旁路"); return
            }
            buffer = fresh; lastBuffer = fresh; lastPTS = pts; forceCopy = false
            lastFrameHost = CACurrentMediaTime()
        } else if dirty, let previous = lastBuffer {
            // Re-present last SDR frame while paused OR while playing across brief gaps.
            buffer = previous; pts = lastPTS
        } else {
            if player.rate != 0 {
                if view.isHidden {
                    // Overlay already down — pull hard next tick and only hard-fallback after stallLimit.
                    forceCopy = true
                    if CACurrentMediaTime() - lastFrameHost > stallLimit {
                        hide("无新解码帧，已回原画")
                    }
                } else if CACurrentMediaTime() - lastFrameHost > stallLimit {
                    // 295: visible but starved (reopen / seek) — fall back so we never sit on a black MTKView
                    // while audio keeps playing.
                    lastBuffer = nil
                    forceCopy = true
                    hide("解码停滞，已回原画")
                }
                // Otherwise keep last drawable across brief gaps (no flicker).
            }
            return
        }
        dirty = false
        var source = Self.sourceImage(buffer)
        if let aspect = CVBufferCopyAttachment(buffer, kCVImageBufferPixelAspectRatioKey, nil) as? [String: NSNumber],
           let horizontal = aspect[kCVImageBufferPixelAspectRatioHorizontalSpacingKey as String]?.doubleValue,
           let vertical = aspect[kCVImageBufferPixelAspectRatioVerticalSpacingKey as String]?.doubleValue,
           horizontal > 0, vertical > 0 {
            source = source.transformed(by: CGAffineTransform(scaleX: horizontal / vertical, y: 1))
        }
        source = source.transformed(by: transform)
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { hide("无效视频尺寸"); return }
        let filtered = filter(source).cropped(to: extent)
        guard let drawable = view.currentDrawable, let command = queue.makeCommandBuffer() else { hide("Metal drawable 不可用"); return }
        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let scale = min(size.width / extent.width, size.height / extent.height)
        let x = (size.width - extent.width * scale) / 2
        let y = (size.height - extent.height * scale) / 2
        let fit = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
        let bounds = CGRect(origin: .zero, size: size)
        let black = CIImage(color: .black).cropped(to: bounds)
        let contentRect = CGRect(x: x, y: y, width: extent.width * scale, height: extent.height * scale)
        let foreground = filtered.transformed(by: fit).cropped(to: contentRect)
        // Explicit opaque mask: cube filters may map transparent black to opaque RGB.
        let mask = CIImage(color: .white).cropped(to: contentRect).composited(over: black)
        let image = foreground.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: black, kCIInputMaskImageKey: mask]).cropped(to: bounds)
#if DEBUG
        testGeometry?(["bufferWidth": Double(CVPixelBufferGetWidth(buffer)), "bufferHeight": Double(CVPixelBufferGetHeight(buffer)), "sourceWidth": extent.width, "sourceHeight": extent.height, "drawableWidth": size.width, "drawableHeight": size.height, "fitX": x, "fitY": y, "fitWidth": contentRect.width, "fitHeight": contentRect.height])
#endif
        context.render(image, to: drawable.texture, commandBuffer: command, bounds: bounds, colorSpace: colorSpace)
#if DEBUG
        testEncode?(drawable.texture, command, pts)
#endif
        let revision = generation
        inFlight = true
        // Retain the decoded IOSurface and drawable until GPU work finishes.
        command.addCompletedHandler { [weak self, buffer, drawable] completed in
            _ = buffer; _ = drawable
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = false
                guard self.generation == revision else { return }
                guard completed.status == .completed else { self.hide("GPU 提交失败，回原画"); return }
                guard UIApplication.shared.applicationState == .active, self.bypassReason == nil, self.player?.isExternalPlaybackActive == false else { self.hide("原画旁路"); return }
                self.view.isHidden = false
                if self.lastStatus != "在线 SDR LUT：Metal（原版 6.7.8）" { self.lastStatus = "在线 SDR LUT：Metal（原版 6.7.8）"; self.onStatus?(self.lastStatus) }
                self.onPresented?(pts)
            }
        }
        command.present(drawable); command.commit()
    }
}

@MainActor
private final class DisplayProxy: NSObject {
    weak var owner: NativeHLSLUTSurface?
    @objc func fire(_ link: CADisplayLink) { owner?.draw(link) }
}
