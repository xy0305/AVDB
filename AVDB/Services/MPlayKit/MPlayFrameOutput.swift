//
//  MPlayFrameOutput.swift
//  AVDB
//
//  Build 353 full restoration, stage A: the pixel-frame display
//  pipeline that replaces the GL render-API path (the original's
//  architecture, IOS-FINDINGS §1/§3: private frame_output vo ->
//  CVPixelBuffer -> CMSampleBuffer -> AVSampleBufferDisplayLayer).
//
//  Three pieces live here, named after the original's classes:
//
//  - MPlayFrameSink: the host side of the vo's C ABI
//    (include/mpv/frame_output.h, added by
//    scripts/mplaykit59/patches/0001-vo-frame-output.patch).  One
//    sink per player, registered under the player's sink name; the
//    vo hands over one owned retain per frame and this side releases
//    it exactly once (takeRetainedValue).
//  - MPlayFrameStore: latest-frame store + counters (the original's
//    FrameStore role).  Video frames flow straight to the scheduler,
//    subtitle frames to the subtitle layer controller; the store
//    keeps the newest of each for inspection/recovery.
//  - MPlayFrameOutputScheduler: wraps frames into CMSampleBuffers
//    and enqueues them on an AVSampleBufferDisplayLayer whose
//    control timebase is kept in sync with the player clock (the
//    original's FrameOutputScheduler + configureTimebase() /
//    syncPlaybackTime(_:rate:) roles).
//
//  Threading: the vo callback runs on mpv's VO thread and must not
//  block — the sink only builds the value type and forwards.  The
//  scheduler serialises all layer access on its own queue.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Libmpv
import QuartzCore

// Kind values from include/mpv/frame_output.h
// (enum mp_frame_output_kind; the info struct carries them as int).
private let mplayFrameKindVideo: Int32 = 0    // MP_FRAME_OUTPUT_VIDEO
private let mplayFrameKindSubtitle: Int32 = 1 // MP_FRAME_OUTPUT_SUBTITLE

/// One frame delivered by the frame_output vo.  For hardware-decoded
/// frames the pixel buffer IS the VideoToolbox decoder's buffer
/// (zero copy); for software frames the vo packed the planes into a
/// fresh buffer.  Either way this object owns the transferred
/// retain and releases it on deinit.
final class MPlayFrame {
    enum Kind {
        case video
        case subtitle
    }

    let kind: Kind
    let pixelBuffer: CVPixelBuffer
    /// Realtime presentation timestamp on the vo clock (mp_time_ns);
    /// 0 = present as soon as possible.
    let realtimePTS: Int64
    /// Stream timestamp in seconds; negative when the frame has none.
    let ptsSeconds: Double
    let durationSeconds: Double
    let width: Int
    let height: Int
    let isRepeat: Bool
    let frameID: UInt64

    init(info: mp_frame_output_info) {
        kind = info.kind == mplayFrameKindSubtitle ? .subtitle : .video
        // The vo transferred exactly one retain with the callback.
        pixelBuffer = Unmanaged<CVPixelBuffer>
            .fromOpaque(info.pixel_buffer!)
            .takeRetainedValue()
        realtimePTS = info.pts_ns
        ptsSeconds = info.pts_seconds
        durationSeconds = info.duration_seconds
        width = Int(info.width)
        height = Int(info.height)
        isRepeat = info.repeat != 0
        frameID = info.frame_id
    }

    /// Memberwise initializer for host-synthesised frames (the
    /// scheduler's black frame); vo-delivered frames use init(info:).
    init(kind: Kind, pixelBuffer: CVPixelBuffer, realtimePTS: Int64,
         ptsSeconds: Double, durationSeconds: Double,
         width: Int, height: Int, isRepeat: Bool, frameID: UInt64) {
        self.kind = kind
        self.pixelBuffer = pixelBuffer
        self.realtimePTS = realtimePTS
        self.ptsSeconds = ptsSeconds
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.isRepeat = isRepeat
        self.frameID = frameID
    }
}

// The vo's C callback.  Runs on the VO thread: retain nothing beyond
// the value type, never block, never call into the same player.
private func mplayFrameOutputCallback(
    _ opaque: UnsafeMutableRawPointer?,
    _ info: UnsafePointer<mp_frame_output_info>?
) {
    guard let opaque, let info else { return }
    let sink = Unmanaged<MPlayFrameSink>
        .fromOpaque(opaque)
        .takeUnretainedValue()
    sink.receive(info.pointee)
}

/// Host endpoint of one frame_output sink.  The owner (MPlayVideoView)
/// holds it strongly from attach() to detach(); registration passes
/// an unretained pointer, so unregister() MUST happen in detach()
/// before the owner lets go — detach() does exactly that.
final class MPlayFrameSink {
    let name: String
    /// Called on the VO thread for every delivered frame.
    var onFrame: ((MPlayFrame) -> Void)?

    init(name: String) {
        self.name = name
    }

    func register() {
        let rc = mp_frame_output_register(
            name,
            Unmanaged.passUnretained(self).toOpaque(),
            mplayFrameOutputCallback
        )
        MPlayDiagnostics.log("frame_output register sink=\(name) rc=\(rc)")
    }

    func unregister() {
        mp_frame_output_unregister(name)
    }

    /// Runtime subtitle render-size override (the decoupled PiP
    /// subtitle size lands here); 0 restores "same as video".
    func setSubtitleRenderSize(width: Int, height: Int) {
        mp_frame_output_set_subtitle_size(name, Int32(width), Int32(height))
    }

    func receive(_ info: mp_frame_output_info) {
        onFrame?(MPlayFrame(info: info))
    }
}

/// Latest-frame store (original: FrameStore).  Lock-protected; the
/// callbacks fire outside the lock, on the caller's thread (the VO
/// thread), and consumers hop queues themselves where needed.
final class MPlayFrameStore {
    private let lock = NSLock()
    private var latestVideoFrame: MPlayFrame?
    private var latestSubtitleFrame: MPlayFrame?
    private var receivedVideo = 0
    private var receivedSubtitles = 0

    var onVideoFrame: ((MPlayFrame) -> Void)?
    var onSubtitleFrame: ((MPlayFrame) -> Void)?

    func update(_ frame: MPlayFrame) {
        lock.lock()
        switch frame.kind {
        case .video:
            latestVideoFrame = frame
            receivedVideo += 1
        case .subtitle:
            latestSubtitleFrame = frame
            receivedSubtitles += 1
        }
        lock.unlock()
        switch frame.kind {
        case .video: onVideoFrame?(frame)
        case .subtitle: onSubtitleFrame?(frame)
        }
    }

    func currentVideoFrame() -> MPlayFrame? {
        lock.lock()
        defer { lock.unlock() }
        return latestVideoFrame
    }

    func currentSubtitleFrame() -> MPlayFrame? {
        lock.lock()
        defer { lock.unlock() }
        return latestSubtitleFrame
    }

    func counts() -> (video: Int, subtitles: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (receivedVideo, receivedSubtitles)
    }

    func flush() {
        lock.lock()
        latestVideoFrame = nil
        latestSubtitleFrame = nil
        lock.unlock()
    }
}

/// Enqueues frames on an AVSampleBufferDisplayLayer (original:
/// FrameOutputScheduler).  All layer access is serialised on `queue`.
final class MPlayFrameOutputScheduler {
    let displayLayer: AVSampleBufferDisplayLayer
    private let queue = DispatchQueue(label: "avdb.mplaykit.frameoutput")

    private var formatDescription: CMVideoFormatDescription?
    private var formatKeyWidth = 0
    private var formatKeyHeight = 0
    private var formatKeyType: OSType = 0

    private var enqueuedFrames = 0
    private var notReadyDrops = 0
    private var layerErrorReported = false

    /// Reported (once per failure episode) when the display layer
    /// enters .failed; MPlayVideoView forwards it to the player's
    /// surface-error channel, mirroring the GL view's behaviour.
    var onLayerError: ((String) -> Void)?

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        // Control timebase on the host clock; syncPlaybackTime keeps
        // it aligned with the player clock (original:
        // configureTimebase()).
        var timebase: CMTimebase?
        let rc = CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if rc == noErr, let timebase {
            displayLayer.controlTimebase = timebase
        } else {
            MPlayDiagnostics.log("frame_output: control timebase creation failed rc=\(rc)")
        }
    }

    // MARK: - Enqueue

    func enqueue(_ frame: MPlayFrame) {
        queue.async { [weak self] in
            self?.enqueueOnQueue(frame)
        }
    }

    private func enqueueOnQueue(_ frame: MPlayFrame) {
        if displayLayer.status == .failed {
            recoverFromFailureOnQueue()
        }
        guard displayLayer.isReadyForMoreMediaData else {
            // Display-layer backpressure: drop rather than stall the
            // VO thread's delivery chain (the vo itself never blocks;
            // this is the host-side drop policy).
            notReadyDrops += 1
            return
        }
        let buffer = frame.pixelBuffer
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let type = CVPixelBufferGetPixelFormatType(buffer)
        if formatDescription == nil || formatKeyWidth != width
            || formatKeyHeight != height || formatKeyType != type {
            var description: CMVideoFormatDescription?
            let rc = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: buffer,
                formatDescriptionOut: &description
            )
            guard rc == noErr, let description else {
                MPlayDiagnostics.log("frame_output: format description failed rc=\(rc)")
                return
            }
            formatDescription = description
            formatKeyWidth = width
            formatKeyHeight = height
            formatKeyType = type
        }
        guard let formatDescription else { return }
        let timescale: Int32 = 90_000
        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: max(frame.durationSeconds, 0),
                             preferredTimescale: timescale),
            presentationTimeStamp: CMTime(seconds: max(frame.ptsSeconds, 0),
                                          preferredTimescale: timescale),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let rc = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard rc == noErr, let sampleBuffer else {
            MPlayDiagnostics.log("frame_output: sample buffer creation failed rc=\(rc)")
            return
        }
        displayLayer.enqueue(sampleBuffer)
        enqueuedFrames += 1
        if displayLayer.status == .failed {
            recoverFromFailureOnQueue()
        }
    }

    // MARK: - Time sync (original: syncPlaybackTime(_:rate:))

    /// Align the layer's control timebase with the player clock.
    /// Called by the view on transport changes and periodically from
    /// the frame path, so drift never accumulates.
    func syncPlaybackTime(position: Double, rate: Double) {
        queue.async { [weak self] in
            guard let self, let timebase = self.displayLayer.controlTimebase else { return }
            CMTimebaseSetTime(
                timebase,
                time: CMTime(seconds: max(position, 0), preferredTimescale: 90_000)
            )
            CMTimebaseSetRate(timebase, rate: rate)
        }
    }

    // MARK: - Flush / black frame (original: flush(), enqueueBlackFrame(size:))

    func flush() {
        queue.async { [weak self] in
            self?.displayLayer.flush()
        }
    }

    /// Enqueue one black frame of the given size, clearing any stale
    /// picture (used when playback stops).  Best effort: the fill is
    /// format-aware for the common layouts (packed BGRA, planar YUV).
    func enqueueBlackFrame(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        var rawBuffer: CVPixelBuffer?
        let rc = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, nil, &rawBuffer
        )
        guard rc == kCVReturnSuccess, let buffer = rawBuffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let total = bytesPerRow * height
            memset(base, 0, total)
            // BGRA black must be opaque, else it composites as clear.
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var offset = 3
            while offset < total {
                bytes[offset] = 0xFF
                offset += 4
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let frame = MPlayFrame(
            kind: .video, pixelBuffer: buffer, realtimePTS: 0,
            ptsSeconds: 0, durationSeconds: 0,
            width: width, height: height, isRepeat: false, frameID: 0
        )
        enqueue(frame)
    }

    // MARK: - Failure recovery

    private func recoverFromFailureOnQueue() {
        // AVSampleBufferDisplayLayer failure recovery is flush and
        // carry on; the next enqueue rebuilds state.  Report once per
        // episode so a persistent failure doesn't spam the surface
        // error channel.
        displayLayer.flush()
        if !layerErrorReported {
            layerErrorReported = true
            let error = displayLayer.error?.localizedDescription ?? "unknown"
            MPlayDiagnostics.log("frame_output: display layer failed: \(error)")
            onLayerError?(error)
        }
    }

    func stats() -> (enqueued: Int, notReadyDrops: Int) {
        (enqueuedFrames, notReadyDrops)
    }
}
