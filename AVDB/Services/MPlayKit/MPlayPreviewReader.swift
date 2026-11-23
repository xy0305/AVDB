//
//  MPlayPreviewReader.swift
//  AVDB
//
//  Build 353: 对应原版 com.mplaykit.PreviewReader（RE 报告二.10：
//  n21–n26）——独立于播放实例的抓帧管线：一台自己的 mpv core，
//  seek 到目标时刻渲染一帧后读回 RGBA。渲染后端在全量还原阶段 A
//  由 GL（离屏 FBO + glReadPixels）换成 libmpv 的软件渲染 API
//  （MPV_RENDER_API_TYPE_SW）：主显示管线已关 GL（-Dgl=disabled），
//  render context 只能以 SW 形态创建；SW 渲染直接写进内存缓冲，
//  行序自上而下，不再需要翻行。
//
//  全量还原对齐（IOS-FINDINGS §2.4）：
//  - init 形态：原版 init(url:headers:height:timeout:percent:
//    preferCover:nativeImage:input:) → 我方 MPlayPreviewReaderConfiguration
//    + init(configuration:)；height = 抓帧高度上限（即 still 的
//    maxWidth 口径在本管线按高度约束改由宽度上限承担，见下），
//    timeout 取代写死的 15 秒，percent（0–100）是 image(at:) 无
//    时刻时的默认落点（安卓固定实参 15.0 疑即此值的缺省），
//    preferCover 时封面轨优先抓 0 秒帧，nativeImage 时 Still
//    预填 pixelBuffer。原有的 init() + still(...) 保留兼容。
//  - StillImage 字段逐项对齐：time / duration / rotation /
//    dolbyProfile（Int，0 = 非 DV；自 mpv 的 track-list 子属性
//    dolby-vision-profile 读取，mpv 0.41 player/command.c 直证）/
//    isCover / rgba / metadata + iOS 增量 pixelBuffer / image /
//    frame（抓帧序号）/ stride。
//  - metadata() -> MPlayPreviewMetadata{duration, format,
//    longName, bitrate, media, tags, tracks}（tracks 带逐轨
//    dolbyProfile）。longName 在 mpv 属性面无对应，以 format
//    兜底（文档明示）。
//  - correctDolbyP5（原版 CapturedVideoFrame.jpeg 与 Player
//    .screenshot 的同名开关）：profile 5 时对抓到的 RGBA 逐像素
//    走 DolbyP5ColorCorrection.convert。口径差异如实标注：
//    原版作用在显示转换前的像素缓冲（IPT 平面）上；我方 reader
//    的帧已经过 mpv SW 渲染的 YUV→RGB 转换，通道域不同，本路
//    为近似——全保真路径在显示管线的 pkDoviP5Kernel0 与
//    MPlayCapturedFrame（MPlayCapture.swift）。
//
//  线程模型：全部状态只在自己的串行队列上变更；still/cancel/close
//  从任意线程调用都只是投递到队列。completion 在队列上回调，UI 侧
//  自行切回主线程。可取消：一台 reader 同一时刻只服务一个请求，
//  新请求会先取消旧请求；cancel() 让在途请求以失败完成。
//

import CoreVideo
import Foundation
import Libmpv
import UIKit

/// 原版 PreviewReader$Still / StillImage 的等价物。
struct MPlayStill {
    let width: Int
    let height: Int
    /// 抓帧时刻（秒，文件内实际落点）。
    let time: Double
    let duration: Double
    /// video-params/rotate；无旋转信息时 nil。
    let rotation: Int?
    /// Dolby Vision profile（5/7/8…）；非 DV 为 0。对齐原版
    /// StillImage.dolbyProfile（Int，非可选）。
    let dolbyProfile: Int
    /// 选中视频轨是图片轨（封面）时为 true（原版 isCover）。
    let cover: Bool
    /// RGBA8，行序自上而下（SW 渲染直接按图像方向输出）。
    let rgba: Data
    let metadata: [String: String]
    /// RGBA 的 CVPixelBuffer 形态（原版 StillImage.pixelBuffer）。
    let pixelBuffer: CVPixelBuffer?
    /// 每行字节数（原版 StillImage.stride）= width * 4。
    let stride: Int
    /// 本 reader 的抓帧序号（原版 StillImage.frame）。
    let frameIndex: Int

    /// 原版 StillImage.image 的等价物。
    func cgImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: stride, space: colorSpace,
                       bitmapInfo: bitmapInfo, provider: provider,
                       decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// Still.jpeg() 的等价物：经 UIImage 转 JPEG。
    func jpegData(quality: Double = 0.85) -> Data? {
        guard let image = cgImage() else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: CGFloat(quality))
    }
}

/// 原版 PreviewMetadata 的等价物。
struct MPlayPreviewMetadata {
    struct Track {
        let id: Int64
        let type: String
        let codec: String
        let language: String
        let title: String
        /// 逐轨 DV profile（原版 PreviewMetadata.Track.dolbyProfile）。
        let dolbyProfile: Int?
    }
    let duration: Double
    let format: String
    /// mpv 属性面无格式长名对应，以 format 兜底。
    let longName: String
    let bitrate: Int64
    let media: String
    let tags: [String: String]
    let tracks: [Track]
}

/// 原版 PreviewReader.init 的命名参数组。
struct MPlayPreviewReaderConfiguration {
    var url: String
    var headers: [String: String] = [:]
    /// 抓帧尺寸上限（原版 height；本管线以宽度上限实现，见文件头）。
    var height: Int = 320
    var timeout: Double = 15
    /// image(at:) 无时刻时的默认落点，0–100（原版 percent）。
    var percent: Double = 15
    var preferCover: Bool = false
    var nativeImage: Bool = false
}

/// 文件级 C 回调：mpv 唤醒（只转投 reader 的串行队列）。
private func mplayPreviewWakeupCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let reader = Unmanaged<MPlayPreviewReader>.fromOpaque(context).takeUnretainedValue()
    reader.handleWakeup()
}

/// 文件级 C 回调：render context 有新帧可画。
private func mplayPreviewRenderUpdateCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let reader = Unmanaged<MPlayPreviewReader>.fromOpaque(context).takeUnretainedValue()
    reader.handleFrameUpdate()
}

/// 文件级 C 回调：metadata 探测 core 的唤醒。
private func mplayPreviewMetaWakeupCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let reader = Unmanaged<MPlayPreviewReader>.fromOpaque(context).takeUnretainedValue()
    reader.handleMetaWakeup()
}

final class MPlayPreviewReader {

    private struct Pending {
        let generation: Int
        let targetSeconds: Double
        let maxWidth: Int
        let correctDolbyP5: Bool
        let preferCover: Bool
        let completion: (Result<MPlayStill, MPlayError>) -> Void
    }

    private let queue = DispatchQueue(label: "avdb.mplaykit.preview")
    private var closed = false
    private var generation = 0
    private var pending: Pending?
    private var timeoutItem: DispatchWorkItem?
    private var grabCounter = 0

    private let configuration: MPlayPreviewReaderConfiguration?

    // 以下状态只在 queue 上访问。
    private var core: OpaquePointer?
    private var renderContextPointer: OpaquePointer?
    private var renderWidth: Int32 = 0
    private var renderHeight: Int32 = 0
    private var fileLoaded = false
    private var seekIssued = false

    // metadata 探测（与抓帧互斥：发起探测会先取消在途抓帧）。
    private var metaCore: OpaquePointer?
    private var metaCompletion: ((MPlayPreviewMetadata?) -> Void)?
    private var metaTimeoutItem: DispatchWorkItem?

    init() {
        configuration = nil
    }

    /// 原版 init(url:headers:height:timeout:percent:preferCover:
    /// nativeImage:) 的等价形态。
    init(configuration: MPlayPreviewReaderConfiguration) {
        self.configuration = configuration
    }

    // MARK: - 公共 API（任意线程可调用，内部投递到串行队列）

    /// 抓一帧静帧。hwdec 固定 no（抓帧可靠性优先，与播放实例的
    /// videotoolbox 分工不同，原版 PreviewReader 亦为独立管线）。
    func still(url: String, at seconds: Double, maxWidth: Int,
               headers: [String: String] = [:],
               timeout: Double = 15,
               correctDolbyP5: Bool = false,
               preferCover: Bool = false,
               completion: @escaping (Result<MPlayStill, MPlayError>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.closed else {
                completion(.failure(.loadFailed("preview reader closed")))
                return
            }
            // 一台 reader 只服务一个在途请求：新请求先取消旧的。
            self.finishPending(.failure(.loadFailed("cancelled")))
            self.teardownCore()
            self.generation += 1
            let gen = self.generation
            self.pending = Pending(generation: gen, targetSeconds: seconds,
                                   maxWidth: max(1, maxWidth),
                                   correctDolbyP5: correctDolbyP5,
                                   preferCover: preferCover,
                                   completion: completion)
            self.fileLoaded = false
            self.seekIssued = false
            guard self.startCore(url: url, headers: headers, generation: gen) else {
                self.finishPending(.failure(.loadFailed("preview core create failed")))
                return
            }
            // 总超时（原版抓帧亦是短任务；超时即失败，不挂起）。
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.pending?.generation == gen else { return }
                self.finishPending(.failure(.loadFailed("preview timeout")))
                self.teardownCore()
            }
            self.timeoutItem = item
            self.queue.asyncAfter(deadline: .now() + max(1, timeout), execute: item)
        }
    }

    /// 配置式 reader 的抓帧（原版 image(at:)）：无时刻时落到
    /// configuration.percent 处（先探测时长再抓）。
    func image(at seconds: Double? = nil, correctDolbyP5: Bool = false,
               completion: @escaping (Result<MPlayStill, MPlayError>) -> Void) {
        guard let configuration else {
            completion(.failure(.loadFailed("preview reader has no configuration")))
            return
        }
        if let seconds {
            still(url: configuration.url, at: seconds, maxWidth: configuration.height,
                  headers: configuration.headers, timeout: configuration.timeout,
                  correctDolbyP5: correctDolbyP5, preferCover: configuration.preferCover,
                  completion: completion)
            return
        }
        metadata(url: configuration.url, headers: configuration.headers) { [weak self] meta in
            guard let self else { return }
            guard let meta, meta.duration > 0 else {
                completion(.failure(.loadFailed("preview: duration unknown for percent seek")))
                return
            }
            let target = meta.duration * min(100, max(0, configuration.percent)) / 100
            self.still(url: configuration.url, at: target, maxWidth: configuration.height,
                       headers: configuration.headers, timeout: configuration.timeout,
                       correctDolbyP5: correctDolbyP5, preferCover: configuration.preferCover,
                       completion: completion)
        }
    }

    /// 文件元数据（原版 metadata()）：独立的轻量 core 只加载不
    /// 渲染，FILE_LOADED 后拼 PreviewMetadata。
    func metadata(url: String, headers: [String: String] = [:],
                  completion: @escaping (MPlayPreviewMetadata?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.closed else { completion(nil); return }
            self.finishPending(.failure(.loadFailed("cancelled")))
            self.teardownCore()
            self.teardownMetaCore()
            guard let handle = mpv_create() else { completion(nil); return }
            self.metaCore = handle
            self.metaCompletion = completion
            let options: [String: String] = [
                "vo": "null", "ao": "null", "pause": "yes", "cache": "no",
                "msg-level": "all=warn",
            ]
            for (key, value) in options {
                _ = mpv_set_option_string(handle, key, value)
            }
            if !headers.isEmpty {
                let fields = headers.map { key, value in
                    "\(key): \(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,"))"
                }.joined(separator: ",")
                _ = mpv_set_option_string(handle, "http-header-fields", fields)
            }
            guard mpv_initialize(handle) == 0 else {
                self.teardownMetaCore()
                completion(nil)
                return
            }
            mpv_set_wakeup_callback(handle, mplayPreviewMetaWakeupCallback,
                                    Unmanaged.passUnretained(self).toOpaque())
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.metaCompletion != nil else { return }
                let done = self.metaCompletion
                self.teardownMetaCore()
                done?(nil)
            }
            self.metaTimeoutItem = item
            self.queue.asyncAfter(deadline: .now() + 15, execute: item)
            _ = self.metaCommand(handle, ["loadfile", url, "replace"])
        }
    }

    /// 取消在途请求（以 loadFailed("cancelled") 完成它）。
    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.finishPending(.failure(.loadFailed("cancelled")))
            self.teardownCore()
        }
    }

    /// 关闭 reader；之后 still 一律失败。
    func close() {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.closed = true
            self.finishPending(.failure(.loadFailed("cancelled")))
            self.teardownCore()
            self.teardownMetaCore()
        }
    }

    // MARK: - 回调入口（文件级 C 函数转投）

    func handleWakeup() {
        queue.async { [weak self] in self?.handleEvents() }
    }

    func handleFrameUpdate() {
        queue.async { [weak self] in self?.attemptCapture() }
    }

    func handleMetaWakeup() {
        queue.async { [weak self] in self?.handleMetaEvents() }
    }

    // MARK: - Core 生命周期（只在 queue 上）

    private func startCore(url: String, headers: [String: String], generation gen: Int) -> Bool {
        guard let handle = mpv_create() else { return false }
        core = handle
        let options: [String: String] = [
            "vo": "libmpv",
            "hwdec": "no",
            "pause": "yes",
            "cache": "no",
            "keep-open": "yes",
            "video-sync": "audio",
            "untimed": "yes",
            "hr-seek": "yes",
            "demuxer-max-bytes": "33554432",
            "msg-level": "all=warn",
        ]
        for (key, value) in options {
            _ = mpv_set_option_string(handle, key, value)
        }
        if !headers.isEmpty {
            // http-header-fields 的转义规则与 MPlayPlayer.open 一致。
            let fields = headers.map { key, value in
                "\(key): \(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,"))"
            }.joined(separator: ",")
            _ = mpv_set_option_string(handle, "http-header-fields", fields)
        }
        guard mpv_initialize(handle) == 0 else {
            mpv_terminate_destroy(handle)
            core = nil
            return false
        }
        mpv_set_wakeup_callback(handle, mplayPreviewWakeupCallback,
                                Unmanaged.passUnretained(self).toOpaque())
        let rc = command(handle, ["loadfile", url, "replace"])
        if rc < 0 {
            MPlayDiagnostics.log(level: 4, tag: "MPlayPreviewReader",
                                 "loadfile failed rc=\(rc) gen=\(gen)")
            teardownCore()
            return false
        }
        return true
    }

    private func teardownCore() {
        timeoutItem?.cancel()
        timeoutItem = nil
        if let renderContextPointer {
            mpv_render_context_set_update_callback(renderContextPointer, nil, nil)
            self.renderContextPointer = nil
            mpv_render_context_free(renderContextPointer)
        }
        renderWidth = 0
        renderHeight = 0
        if let core {
            mpv_set_wakeup_callback(core, nil, nil)
            mpv_terminate_destroy(core)
            self.core = nil
        }
        fileLoaded = false
        seekIssued = false
    }

    private func teardownMetaCore() {
        metaTimeoutItem?.cancel()
        metaTimeoutItem = nil
        if let metaCore {
            mpv_set_wakeup_callback(metaCore, nil, nil)
            mpv_terminate_destroy(metaCore)
            self.metaCore = nil
        }
        metaCompletion = nil
    }

    private func finishPending(_ result: Result<MPlayStill, MPlayError>) {
        guard let pending else { return }
        self.pending = nil
        timeoutItem?.cancel()
        timeoutItem = nil
        pending.completion(result)
    }

    // MARK: - 事件（只在 queue 上）

    private func handleEvents() {
        guard let core else { return }
        while true {
            guard let eventPointer = mpv_wait_event(core, 0) else { return }
            let event = eventPointer.pointee
            if event.event_id == MPV_EVENT_NONE {
                return
            } else if event.event_id == MPV_EVENT_FILE_LOADED {
                fileLoaded = true
                prepareRenderTarget()
            } else if event.event_id == MPV_EVENT_END_FILE {
                if let data = event.data {
                    let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    if endFile.reason == MPV_END_FILE_REASON_ERROR {
                        let message = String(cString: mpv_error_string(endFile.error))
                        finishPending(.failure(.loadFailed(message)))
                        teardownCore()
                        return
                    }
                }
            } else if event.event_id == MPV_EVENT_PLAYBACK_RESTART {
                attemptCapture()
            }
            // 其余事件忽略。
        }
    }

    private func handleMetaEvents() {
        guard let metaCore else { return }
        while true {
            guard let eventPointer = mpv_wait_event(metaCore, 0) else { return }
            let event = eventPointer.pointee
            if event.event_id == MPV_EVENT_NONE {
                return
            } else if event.event_id == MPV_EVENT_FILE_LOADED {
                let meta = collectPreviewMetadata(handle: metaCore)
                let done = metaCompletion
                teardownMetaCore()
                done?(meta)
                return
            } else if event.event_id == MPV_EVENT_END_FILE {
                if let data = event.data {
                    let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                    if endFile.reason == MPV_END_FILE_REASON_ERROR {
                        let done = metaCompletion
                        teardownMetaCore()
                        done?(nil)
                        return
                    }
                }
            }
        }
    }

    /// FILE_LOADED 后：按显示尺寸（video-params/dw/dh，已含旋转与
    /// 宽高比）算抓帧尺寸，建 SW render context，并发一次精确 seek
    /// 到目标时刻（暂停态下 seek 后 core 会解出目标帧并触发
    /// PLAYBACK_RESTART / render update）。preferCover 且选中轨是
    /// 封面图时落点改 0。
    private func prepareRenderTarget() {
        guard let core, let pending else { return }
        let displayWidth = intProperty("video-params/dw") ?? intProperty("video-params/w") ?? 0
        let displayHeight = intProperty("video-params/dh") ?? intProperty("video-params/h") ?? 0
        guard displayWidth > 0, displayHeight > 0 else {
            finishPending(.failure(.loadFailed("preview: no video track")))
            teardownCore()
            return
        }
        var width = displayWidth
        var height = displayHeight
        if width > pending.maxWidth {
            height = max(1, Int((Double(height) * Double(pending.maxWidth) / Double(width)).rounded()))
            width = pending.maxWidth
        }
        let apiType = strdup(MPV_RENDER_API_TYPE_SW)
        defer { free(apiType) }
        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                             data: UnsafeMutableRawPointer(apiType)),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        ]
        var newContext: OpaquePointer?
        let rc = mpv_render_context_create(&newContext, core, &params)
        guard rc == 0, let newContext else {
            finishPending(.failure(.loadFailed("preview: render context failed rc=\(rc)")))
            teardownCore()
            return
        }
        renderContextPointer = newContext
        mpv_render_context_set_update_callback(newContext, mplayPreviewRenderUpdateCallback,
                                               Unmanaged.passUnretained(self).toOpaque())
        renderWidth = Int32(width)
        renderHeight = Int32(height)
        if !seekIssued {
            seekIssued = true
            let target = (pending.preferCover && selectedVideoTrackIsImage())
                ? 0 : pending.targetSeconds
            _ = command(core, ["seek", String(target), "absolute", "exact"])
        }
        attemptCapture()
    }

    /// 用 SW 渲染把当前帧写进内存缓冲并读回。FILE_LOADED 直后帧可能
    /// 还没解出——以 PLAYBACK_RESTART 与 render update 回调反复进入
    /// 本方法，直到渲染成功或超时收口。SW 输出的行序自上而下，
    /// 与 MPlayStill.rgba 的约定一致，无需翻行（方向正确性仍列入
    /// 真机首验清单：SW 后端按 dst_params 渲染，含旋转的源以
    /// video-params 的显示尺寸为目标，理论上已是正向画面）。
    private func attemptCapture() {
        guard let pending, fileLoaded,
              let renderContextPointer, renderWidth > 0, renderHeight > 0 else { return }
        let width = Int(renderWidth)
        let height = Int(renderHeight)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var size: [Int32] = [renderWidth, renderHeight]
        let format = strdup("rgba")
        defer { free(format) }
        // MPV_RENDER_PARAM_SW_STRIDE 的 C 侧类型是 size_t*
        // （libmpv_sw.c 实测），故用 Int（arm64 上与 size_t 同宽）。
        var stride = width * 4
        let rc = pixels.withUnsafeMutableBytes { buffer -> Int32 in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: &size),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT,
                                 data: UnsafeMutableRawPointer(format)),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: &stride),
                mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: buffer.baseAddress),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_render(renderContextPointer, &params)
        }
        guard rc == 0 else { return }
        let profile = selectedVideoDolbyProfile()
        var rgba = Data(pixels)
        if pending.correctDolbyP5, profile == 5 {
            rgba = Self.applyP5Correction(to: rgba, width: width, height: height)
        }
        grabCounter += 1
        let time = doubleProperty("time-pos") ?? pending.targetSeconds
        let duration = doubleProperty("duration") ?? 0
        let rotation = intProperty("video-params/rotate")
        let still = MPlayStill(width: width, height: height,
                               time: time, duration: duration,
                               rotation: rotation,
                               dolbyProfile: profile,
                               cover: selectedVideoTrackIsImage(),
                               rgba: rgba,
                               metadata: collectMetadata(),
                               pixelBuffer: Self.makePixelBuffer(rgba: rgba, width: width, height: height),
                               stride: width * 4,
                               frameIndex: grabCounter)
        MPlayDiagnostics.event(tag: "preview", "captured",
                               [("w", "\(width)"), ("h", "\(height)"), ("t", "\(time)"),
                                ("dv", "\(profile)")])
        finishPending(.success(still))
        teardownCore()
    }

    /// correctDolbyP5 的 CPU 路径：把 SW 渲染出的 RGBA 逐像素按
    /// (i, p, t) = (r, g−0.5, b−0.5) 送 DolbyP5ColorCorrection
    /// .convert。通道域与原版不同（见文件头），本路为近似。
    private static func applyP5Correction(to rgba: Data, width: Int, height: Int) -> Data {
        var bytes = [UInt8](rgba)
        let map = DolbyP5ColorCorrection.Map.profile5
        let count = width * height
        for index in 0..<count {
            let offset = index * 4
            let rgb = DolbyP5ColorCorrection.convert(
                i: Double(bytes[offset]) / 255,
                p: Double(bytes[offset + 1]) / 255 - 0.5,
                t: Double(bytes[offset + 2]) / 255 - 0.5,
                map: map
            )
            bytes[offset] = rgb.r
            bytes[offset + 1] = rgb.g
            bytes[offset + 2] = rgb.b
        }
        return Data(bytes)
    }

    private static func makePixelBuffer(rgba: Data, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32RGBA, attrs as CFDictionary,
                                  &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let dstStride = CVPixelBufferGetBytesPerRow(buffer)
        rgba.withUnsafeBytes { source in
            guard let src = source.baseAddress else { return }
            for row in 0..<height {
                memcpy(base + row * dstStride, src + row * width * 4, width * 4)
            }
        }
        return buffer
    }

    // MARK: - 属性读取小助手（只在 queue 上；读不到一律 nil）

    private func command(_ handle: OpaquePointer, _ args: [String]) -> Int32 {
        let allocated: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { for pointer in allocated { free(pointer) } }
        // mpv_command 的导入签名：元素为不可变 C 字符串指针、数组
        // 本身可变 (UnsafeMutablePointer<UnsafePointer<CChar>?>?)。
        var cArgs: [UnsafePointer<CChar>?] = allocated.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        }
        cArgs.append(nil)
        return cArgs.withUnsafeMutableBufferPointer { buffer in
            mpv_command(handle, buffer.baseAddress)
        }
    }

    private func metaCommand(_ handle: OpaquePointer, _ args: [String]) -> Int32 {
        command(handle, args)
    }

    private func stringProperty(_ name: String) -> String? {
        guard let core else { return nil }
        return Self.stringProperty(core, name)
    }

    private static func stringProperty(_ handle: OpaquePointer, _ name: String) -> String? {
        var value: UnsafeMutablePointer<CChar>?
        guard mpv_get_property(handle, name, MPV_FORMAT_STRING, &value) == 0,
              let value else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    private static func doubleProperty(_ handle: OpaquePointer, _ name: String) -> Double? {
        var value: Double = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) == 0 else { return nil }
        return value
    }

    private static func intProperty(_ handle: OpaquePointer, _ name: String) -> Int64? {
        var value: Int64 = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) == 0 else { return nil }
        return value
    }

    private static func flagProperty(_ handle: OpaquePointer, _ name: String) -> Bool? {
        var value: Int32 = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) == 0 else { return nil }
        return value != 0
    }

    private func doubleProperty(_ name: String) -> Double? {
        guard let core else { return nil }
        return Self.doubleProperty(core, name)
    }

    private func intProperty(_ name: String) -> Int? {
        guard let core else { return nil }
        return Self.intProperty(core, name).map(Int.init)
    }

    private func flagProperty(_ name: String) -> Bool? {
        guard let core else { return nil }
        return Self.flagProperty(core, name)
    }

    /// 选中视频轨的 image 标志（封面轨）——逐轨标量读取，与
    /// MPlayPlayer.mediaJSON 的做法一致。
    private func selectedVideoTrackIsImage() -> Bool {
        let count = intProperty("track-list/count") ?? 0
        for index in 0..<count {
            guard stringProperty("track-list/\(index)/type") == "video",
                  flagProperty("track-list/\(index)/selected") == true else { continue }
            return flagProperty("track-list/\(index)/image") ?? false
        }
        return false
    }

    /// 选中视频轨的 DV profile（track-list/N/dolby-vision-profile；
    /// 非 DV 时该子属性 unavailable → 0）。
    private func selectedVideoDolbyProfile() -> Int {
        let count = intProperty("track-list/count") ?? 0
        for index in 0..<count {
            guard stringProperty("track-list/\(index)/type") == "video",
                  flagProperty("track-list/\(index)/selected") == true else { continue }
            return intProperty("track-list/\(index)/dolby-vision-profile") ?? 0
        }
        return 0
    }

    private func collectMetadata() -> [String: String] {
        var metadata: [String: String] = [:]
        if let codec = stringProperty("video-codec") { metadata["videoCodec"] = codec }
        if let format = stringProperty("file-format") { metadata["container"] = format }
        if let title = stringProperty("media-title") { metadata["title"] = title }
        return metadata
    }

    private func collectPreviewMetadata(handle: OpaquePointer) -> MPlayPreviewMetadata {
        var tracks: [MPlayPreviewMetadata.Track] = []
        let count = Self.intProperty(handle, "track-list/count") ?? 0
        for index in 0..<Int(count) {
            let prefix = "track-list/\(index)/"
            tracks.append(MPlayPreviewMetadata.Track(
                id: Self.intProperty(handle, prefix + "id") ?? 0,
                type: Self.stringProperty(handle, prefix + "type") ?? "",
                codec: Self.stringProperty(handle, prefix + "codec") ?? "",
                language: Self.stringProperty(handle, prefix + "lang") ?? "",
                title: Self.stringProperty(handle, prefix + "title") ?? "",
                dolbyProfile: Self.intProperty(handle, prefix + "dolby-vision-profile").map(Int.init)
            ))
        }
        let format = Self.stringProperty(handle, "file-format") ?? ""
        let videoBitrate = Self.doubleProperty(handle, "video-bitrate") ?? 0
        let audioBitrate = Self.doubleProperty(handle, "audio-bitrate") ?? 0
        return MPlayPreviewMetadata(
            duration: Self.doubleProperty(handle, "duration") ?? 0,
            format: format,
            longName: format,
            bitrate: Int64(videoBitrate + audioBitrate),
            media: Self.stringProperty(handle, "media-title") ?? "",
            tags: Self.collectTags(handle: handle),
            tracks: tracks
        )
    }

    /// "metadata" 是 node map：只收字符串叶子（其余类型跳过）。
    private static func collectTags(handle: OpaquePointer) -> [String: String] {
        var node = mpv_node()
        let rc = "metadata".withCString { cName in
            withUnsafeMutablePointer(to: &node) { pointer in
                mpv_get_property(handle, cName, MPV_FORMAT_NODE, UnsafeMutableRawPointer(pointer))
            }
        }
        guard rc == 0 else { return [:] }
        defer { mpv_free_node_contents(&node) }
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list else { return [:] }
        var tags: [String: String] = [:]
        let num = Int(list.pointee.num)
        guard num > 0, let values = list.pointee.values, let keys = list.pointee.keys else { return tags }
        for index in 0..<num {
            let entry = values.advanced(by: index).pointee
            guard entry.format == MPV_FORMAT_STRING, let value = entry.u.string,
                  let keyPointer = keys.advanced(by: index).pointee else { continue }
            tags[String(cString: keyPointer)] = String(cString: value)
        }
        return tags
    }
}
