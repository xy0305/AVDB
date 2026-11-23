//
//  MPlayPlayer.swift
//  AVDB
//
//  Build 353: 用 libmpv C API 复刻原版 com.mplaykit.Player 的接口形状
//  （RE 报告一、二：n3 命令通道 / n4 预加载派生 / n5 创建 / n7 setProp /
//  n9 暂停 / n14 状态 / n15 进度 / n16 异步 seek / n19 销毁）。原版
//  n30 的共享渲染上下文在阶段 A 的像素帧管线下没有对应物（实例间不
//  共享渲染状态，帧经 frame_output sink 按名路由，见 frameSinkName）。
//  原版内核本身就是 libmpv + FFmpeg 的融合构建（报告三），属性
//  词汇与 mpv 同构，所以这里直接以 mpv client API 落地；C 函数签名与事件
//  结构体以 mpv 0.41 的头文件为准（管线钉版 0.41.0，依据 IOS-FINDINGS §5
//  的原版版本串直证）。0.41 ↔ 0.42 头文件已逐项 diff 核对（client.h /
//  render.h / render_gl.h / stream_cb.h）：本层用到的全部 MPV_* 常量在
//  两版均存在且取值一致——mpv_end_file_reason（EOF=0/STOP=2/QUIT=3/
//  ERROR=4/REDIRECT=5，含此前靠与 ERROR 对称推得的 MPV_END_FILE_REASON_
//  EOF）、事件 id（END_FILE=7/SEEK=20/PLAYBACK_RESTART=21）、
//  MPV_FORMAT_* 与 MPV_RENDER_PARAM_*（0.42 只在 render.h 尾部追加
//  D3D11 的 21/22 两项，Windows 专用，无重编号）；差异仅
//  MPV_CLIENT_API_VERSION 2.5（0.41）↔ 2.6（0.42）与 0.42 的
//  node 命令命名参数改用 "_name" 键——本层不发 node 形态命令
//  （mpv_node 只用于解析 demuxer-cache-state 属性值），不受影响。
//  结论：降钉 0.41.0 后本层无需改代码。
//
//  线程模型（对应原版「每实例一个单线程 ExecutorService」，报告二.2）：
//  每实例一条串行队列，事件处理与可变状态只在该队列上读写；属性同步读取
//  经 onPlayerQueue 收口。生命周期：调用方须保证先让 attach 的
//  MPlayVideoView detach、再 close()，且 close() 后不再使用本实例——
//  wakeup 回调用 Unmanaged.passUnretained 持有 self，靠 close() 里
//  「先清回调、再销毁 core」的顺序保证回调不会进入已释放实例。
//

import Foundation
import Libmpv

enum MPlayError: Error {
    /// 无效句柄约定码 -3（原版 Player 在句柄为 0 时多处返回 -3，报告 1.2）。
    case invalidHandle
    case createFailed
    case initializeFailed(Int32)
    case optionFailed(String, Int32)
    case commandFailed(String, Int32)
    case loadFailed(String)
}

enum MPlayTrackKind {
    case video, audio, subtitle, subtitleSecondary
}

/// AVDB chrome 消费的播放事件（AVFan Build 59 扩展，已同步至 AVDB）：
/// 由 MPlayPlayer.onPlaybackEvent 在 player 串行队列上发出，
/// 消费方需自行切到所需队列（如主线程）再更新 UI。
enum MPlayPlaybackEvent {
    case fileLoaded
    case endFileError(String)
    case endFileEOF
    case playbackRestart
}

/// mpv wakeup 回调（文件级 @convention(c) 相容函数，不能捕获上下文）：
/// 只把事件处理转投到实例自己的串行队列，不在回调里调任何 mpv API。
private func mplayWakeupCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let player = Unmanaged<MPlayPlayer>.fromOpaque(context).takeUnretainedValue()
    player.handleWakeup()
}

final class MPlayPlayer {
    /// libmpv 句柄（mpv_handle）。init 时创建一次、close() 时置 nil。
    var core: OpaquePointer? = nil
    /// frame_output vo 的 sink 名（全量还原阶段 A 的像素帧管线）：
    /// 视图按这个名字注册帧回调（mp_frame_output_register），init
    /// 把它作为 vo-frame-output-sink 选项强制写给 core——入参
    /// options 不能覆盖，否则 vo 找不到消费者、画面全丢。原版
    /// n30 的「共享渲染上下文」在像素帧架构下没有对应物：实例间
    /// 不再共享任何渲染状态，帧经 sink 注册表按名路由。
    let frameSinkName: String

    /// 播放事件回调（AVFan Build 59 扩展，已同步）：在 player 串行队列上发出，
    /// 消费方自行切队列。事件时机见 handleEvents / handleEndFile。
    var onPlaybackEvent: ((MPlayPlaybackEvent) -> Void)?

    /// 本实例的源 id（对应 State.source / Progress.source），进程内递增分配。
    let source: Int64

    private let queue: DispatchQueue
    private let specificKey = DispatchSpecificKey<UInt8>()
    private let mergedOptions: [String: String]

    // 以下可变状态只在 queue 上读写。
    private var closed = false
    private var fileLoaded = false
    private var lastFailure = ""
    private var lastSurfaceError = ""
    private var lastEndFileError: Int = 0
    private var nextReplyTag: UInt64 = 1
    private var pendingOpens: [UInt64: (Result<Void, MPlayError>) -> Void] = [:]
    private var pendingSeeks: [(id: UInt64, completion: () -> Void)] = []
    private var nextSeekID: UInt64 = 1
    /// Custom stream protocol factory contexts (MPlayStreamProtocol):
    /// retained at registration, released in closeOnQueue().
    private var streamContexts: [UnsafeMutableRawPointer] = []

    // MARK: - Extension-surface state (MPlayPlayerExtras / MPlaySubtitles)
    //
    // Stored here because Swift extensions cannot hold state; all
    // access hops onto the player queue like the rest of the core.

    /// Subtitle HDR gain sink, registered by MPlayVideoView (drives
    /// the independent subtitle layer's brightness gain).
    var onSubtitleGainChange: ((Double) -> Void)?

    /// Subtitle opacity sink, registered by MPlayVideoView (mpv has
    /// no global subtitle opacity property; the layer carries it).
    var onSubtitleOpacityChange: ((Double) -> Void)?

    /// Last SubtitleSettings applied (MPlaySubtitles) and the edge
    /// processing flag (recorded; no libass equivalent).
    var subtitleSettingsStorage = SubtitleSettings()
    var subtitleEdgeProcessingEnabled = false

    private var frameRateMatching = false
    private var displayCriteriaGen: UInt64 = 0
    var frameRateMatchingEnabled: Bool {
        get { onPlayerQueue { frameRateMatching } }
        set {
            queue.async { [weak self] in
                guard let self, !self.closed else { return }
                self.frameRateMatching = newValue
                self.displayCriteriaGen &+= 1
            }
        }
    }
    var displayCriteriaGeneration: UInt64 {
        onPlayerQueue { displayCriteriaGen }
    }
    func bumpDisplayCriteriaGeneration() {
        queue.async { [weak self] in self?.displayCriteriaGen &+= 1 }
    }

    private var decoderSwitchCounter: UInt64 = 0
    private var decoderSwitchState: (token: UInt64, hardware: Bool, completed: Bool) =
        (token: 0, hardware: true, completed: true)
    func beginDecoderSwitchRecord(hardware: Bool) -> UInt64 {
        onPlayerQueue {
            decoderSwitchCounter &+= 1
            decoderSwitchState = (token: decoderSwitchCounter,
                                  hardware: hardware, completed: false)
            return decoderSwitchCounter
        }
    }
    func markDecoderSwitchCompleted(token: UInt64) {
        queue.async { [weak self] in
            guard let self, self.decoderSwitchState.token == token else { return }
            self.decoderSwitchState.completed = true
        }
    }
    func decoderSwitchCompleted(token: UInt64) -> Bool {
        onPlayerQueue {
            decoderSwitchState.token == token && decoderSwitchState.completed
        }
    }

    /// Retains a stream factory context until close().  Callable
    /// from any thread; the append hops onto the player queue.
    func retainStreamContext(_ context: UnsafeMutableRawPointer) {
        let work = { self.streamContexts.append(context) }
        if DispatchQueue.getSpecific(key: specificKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    /// Runs `work` with the live core on the player queue; nil after
    /// close().  For extension files that must not touch the private
    /// queue directly (stream registration, decoder switching).
    func withCore<T>(_ work: (OpaquePointer) -> T) -> T? {
        onPlayerQueue { core.map(work) }
    }

    private static let sourceLock = NSLock()
    private static var sourceCounter: Int64 = 0
    private static func nextSource() -> Int64 {
        sourceLock.lock()
        defer { sourceLock.unlock() }
        sourceCounter += 1
        return sourceCounter
    }

    init(options: [String: String] = [:],
         cachePolicy: MPlayCachePolicy = .standard) throws {
        let assignedSource = Self.nextSource()
        source = assignedSource
        frameSinkName = "avdb-\(assignedSource)"
        queue = DispatchQueue(label: "avdb.mplaykit.player.\(assignedSource)")
        queue.setSpecific(key: specificKey, value: 1)

        // 默认选项与原版创建选项的对应（报告 1.3）：
        //   hwdec：原版 Android 注入 mediacodec；iOS 对应 videotoolbox。
        //   hwdec-software-fallback：原版注入 yes，此处一致。
        // vo=frame_output 是阶段 A 像素帧管线（与原版 iOS 同构：
        // frame_output vo → CVPixelBuffer → AVSampleBufferDisplayLayer，
        // IOS-FINDINGS §1/§3）；keep-open 是播放器侧的常规取值；
        // cache 自阶段 D 起走 MPlayCachePolicy 分段模型（结构与字段名
        // 对齐原版 CachePolicy，具体数值是我方取值、不可恢复，见
        // MPlayCachePolicy.swift 的映射说明）。
        // 入参 options 覆盖默认值，但 vo-frame-output-sink 在合并后
        // 强制写回本实例的 sink 名（见 frameSinkName 的注释）。
        var merged: [String: String] = [
            "vo": "frame_output",
            "hwdec": "videotoolbox",
            "hwdec-software-fallback": "yes",
            "keep-open": "yes",
        ]
        for (key, value) in cachePolicy.mpvOptions { merged[key] = value }
        for (key, value) in options { merged[key] = value }
        merged["vo-frame-output-sink"] = frameSinkName
        mergedOptions = merged

        guard let handle = mpv_create() else { throw MPlayError.createFailed }
        core = handle
        // 选项设置失败只记诊断不抛：单个坏选项不该挡住整个播放器创建。
        for key in merged.keys.sorted() {
            guard let value = merged[key] else { continue }
            let rc = mpv_set_option_string(handle, key, value)
            if rc < 0 {
                MPlayDiagnostics.log(level: 3, tag: "MPlayPlayer",
                                     "event=option_failed name=\(key) code=\(rc)")
            }
        }
        let initRC = mpv_initialize(handle)
        guard initRC == 0 else {
            mpv_terminate_destroy(handle)
            core = nil
            throw MPlayError.initializeFailed(initRC)
        }
        _ = mpv_request_log_messages(handle, "info")
        mpv_set_wakeup_callback(handle, mplayWakeupCallback,
                                Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        close()
    }

    // MARK: - 打开 / 播放控制

    /// 对应原版 open 命令（报告 1.4 的 ri3）：URL / 起始秒（ri3.d）/ 布尔
    /// （ri3.e，此处 autoplay）/ 附加 Map（ri3.f，此处 headers）。
    /// completion 在串行队列上回调：FILE_LOADED 成功，END_FILE(ERROR) 失败。
    func open(url: String, startSeconds: Double = 0, headers: [String: String] = [:],
              autoplay: Bool = true, completion: ((Result<Void, MPlayError>) -> Void)? = nil) {
        if closed {
            completion?(.failure(.invalidHandle))
            return
        }
        queue.async { [weak self] in
            guard let self, !self.closed, let core = self.core else {
                completion?(.failure(.invalidHandle))
                return
            }
            if !headers.isEmpty {
                // http-header-fields 是 mpv 的逗号分隔列表属性：每个
                // "Key: Value" 条目整体先转义反斜杠与逗号，再以逗号连接。
                let fieldList = headers.keys.sorted().map { key -> String in
                    let entry = "\(key): \(headers[key] ?? "")"
                    return entry
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: ",", with: "\\,")
                }.joined(separator: ",")
                _ = mpv_set_property_string(core, "http-header-fields", fieldList)
            }
            if !autoplay {
                _ = mpv_set_property_string(core, "pause", "yes")
            }
            if startSeconds > 0 {
                _ = mpv_set_property_string(core, "start", "+\(startSeconds)")
            }
            let tag = self.nextReplyTag
            self.nextReplyTag += 1
            if let completion {
                self.pendingOpens[tag] = completion
            }
            let rc = self.runCommandAsync(core: core, tag: tag, args: ["loadfile", url, "replace"])
            if rc < 0 {
                self.pendingOpens.removeValue(forKey: tag)
                completion?(.failure(.commandFailed("loadfile", rc)))
            }
        }
    }

    /// n9 等价：暂停开关。返回 mpv 的结果码；已关闭返回约定码 -3。
    @discardableResult
    func setPaused(_ paused: Bool) -> Int32 {
        guard let core, !closed else { return -3 }
        return mpv_set_property_string(core, "pause", paused ? "yes" : "no")
    }

    /// n16 等价：异步 seek。原版把 Future 交给 native 完成；这里 completion
    /// 登记后由 MPV_EVENT_PLAYBACK_RESTART（seek 真正落地）统一触发。
    func seek(to seconds: Double, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, !self.closed, let core = self.core else {
                completion?()
                return
            }
            var seekID: UInt64 = 0
            if let completion {
                seekID = self.nextSeekID
                self.nextSeekID += 1
                self.pendingSeeks.append((id: seekID, completion: completion))
            }
            let rc = self.runCommandAsync(core: core, tag: 0,
                                          args: ["seek", String(seconds), "absolute"])
            if rc < 0, let completion {
                self.pendingSeeks.removeAll { $0.id == seekID }
                completion()
            }
        }
    }

    /// n7 等价：设置单个字符串属性，返回 mpv 结果码；已关闭返回 -3。
    @discardableResult
    func setProp(_ name: String, _ value: String) -> Int32 {
        guard let core, !closed else { return -3 }
        return mpv_set_property_string(core, name, value)
    }

    /// 播放倍速（AVFan Build 59 扩展，已同步）：setProp("speed", …) 的薄封装。
    func setRate(_ rate: Double) {
        setProp("speed", String(rate))
    }

    /// 通用命令（n3 rawCommand 在 Swift 层的等价形态）：同步执行。
    /// 参数为空返回 MPV_ERROR_INVALID_PARAMETER（client.h：-4）。
    @discardableResult
    func command(_ args: [String]) -> Int32 {
        guard !args.isEmpty else { return Int32(MPV_ERROR_INVALID_PARAMETER.rawValue) }
        guard let core, !closed else { return -3 }
        return withCArgs(args) { mpv_command(core, $0) }
    }

    /// select 命令等价（报告 1.4）：按轨道类型写 vid/aid/sid/secondary-sid
    /// 属性；id < 0 表示取消选择（"no"）。
    func selectTrack(kind: MPlayTrackKind, id: Int64) {
        let property: String
        switch kind {
        case .video: property = "vid"
        case .audio: property = "aid"
        case .subtitle: property = "sid"
        case .subtitleSecondary: property = "secondary-sid"
        }
        setProp(property, id >= 0 ? String(id) : "no")
    }

    /// subtitles 命令的可识别子集（报告 1.4）：原版一次性封送双字幕条目，
    /// 每条 5 个字符串 + 11 个 double、后跟全局 3 字符串 + 6 double（共 28 个
    /// double），其原始封送布局未被 RE 逐字段定名，这里不复刻该布局，
    /// 只实现能明确对应的部分：mpv sub-add 的位置参数本身就支持
    /// url / flags(select|auto) / title / lang，单条外挂字幕走这一条；
    /// 双字幕的主/次关系由调用方再调一次并配合 secondary-sid 选择完成。
    func addSubtitle(url: String, title: String? = nil, lang: String? = nil, select: Bool = true) {
        var args = ["sub-add", url, select ? "select" : "auto"]
        if title != nil || lang != nil {
            args.append(title ?? "")
            args.append(lang ?? "")
        }
        command(args)
    }

    // MARK: - 媒体信息（media 命令等价）

    /// 用逐轨标量属性拼出与原版 media 命令相同的 JSON 键（报告 1.4）：
    /// tracks 条目键为 id/kind/language/title/codec/codecDescription/
    /// channelLayout/imageSubtitle/external/selected。
    /// codecDescription 在 mpv 属性面没有逐轨对应，以 codec 兜底；
    /// channelLayout 只对当前音频轨有 "audio-params/channel-layout"，
    /// 选中音频轨用它兜底，其余为 ""。
    func mediaJSON() -> String {
        onPlayerQueue { () -> String in
            var tracks: [[String: Any]] = []
            let count = Int(getInt64("track-list/count") ?? 0)
            if count > 0 {
                for index in 0..<count {
                    let prefix = "track-list/\(index)/"
                    let type = getString(prefix + "type") ?? ""
                    let kind: String
                    switch type {
                    case "video": kind = "video"
                    case "audio": kind = "audio"
                    case "sub": kind = "subtitle"
                    default: kind = type
                    }
                    let codec = getString(prefix + "codec") ?? ""
                    let selected = getFlag(prefix + "selected") ?? false
                    var channelLayout = ""
                    if type == "audio", selected {
                        channelLayout = getString("audio-params/channel-layout") ?? ""
                    }
                    tracks.append([
                        "id": getInt64(prefix + "id") ?? 0,
                        "kind": kind,
                        "language": getString(prefix + "lang") ?? "",
                        "title": getString(prefix + "title") ?? "",
                        "codec": codec,
                        "codecDescription": codec,
                        "channelLayout": channelLayout,
                        "imageSubtitle": getFlag(prefix + "image") ?? false,
                        "external": getFlag(prefix + "external") ?? false,
                        "externalFilename": getString(prefix + "external-filename") ?? "",
                        "selected": selected,
                    ])
                }
            }
            let root: [String: Any] = [
                "tracks": tracks,
                "duration": getDouble("duration") ?? 0,
                "title": getString("media-title") ?? "",
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else {
                return "{\"tracks\":[]}"
            }
            return text
        }
    }

    // MARK: - 状态 / 进度（n14 / n15 等价）

    func state() -> MPlayState {
        onPlayerQueue { readState() }
    }

    /// 由 state() 按报告 1.5 的下标表回填三数组；未命名下标保持 0/0.0/""。
    func stateRaw() -> MPlayStateRaw {
        let state = state()
        var raw = MPlayStateRaw()
        raw.longs[0] = state.source
        raw.longs[2] = Int64(state.errorCode)
        raw.longs[5] = state.paused ? 1 : 0
        raw.longs[6] = state.seekable ? 1 : 0
        raw.doubles[0] = state.position
        raw.doubles[1] = state.duration
        raw.strings[0] = state.phase
        raw.strings[5] = state.failure
        raw.strings[6] = state.surfaceError
        return raw
    }

    func progress() -> MPlayProgress {
        onPlayerQueue { readProgress() }
    }

    /// 当前视频尺寸（AVFan Build 59 扩展，已同步）：读 mpv 的 width / height 属性；
    /// 任一缺失或为 0 时返回 nil。
    func videoSize() -> (width: Double, height: Double)? {
        onPlayerQueue { () -> (width: Double, height: Double)? in
            guard let width = getInt64("width"), let height = getInt64("height"),
                  width != 0, height != 0 else { return nil }
            return (width: Double(width), height: Double(height))
        }
    }

    // MARK: - 属性访问面（原版 intProperty / doubleProperty / stringProperty）

    /// 原版 Player.intProperty 的等价物（IOS-FINDINGS §2.3：安卓
    /// n8 的正式对应 API）。读不到返回 nil。
    func intProperty(_ name: String) -> Int64? {
        onPlayerQueue { getInt64(name) }
    }

    func doubleProperty(_ name: String) -> Double? {
        onPlayerQueue { getDouble(name) }
    }

    func stringProperty(_ name: String) -> String? {
        onPlayerQueue { getString(name) }
    }

    /// 原版 Player.cacheRanges() 的等价物。
    func cacheRanges() -> [MPlayCacheRange] {
        progress().cacheRanges
    }

    // MARK: - Dolby Vision（全量还原：DV 并入阶段 C）

    /// 当前选中视频轨的 DV profile / level：读 mpv 0.41 的
    /// track-list/N/dolby-vision-profile 与 -level（player/command.c
    /// 直证存在；非 DV 轨该子属性 unavailable、读不到）。非 DV 或
    /// 未加载时返回 nil。
    func dolbyVisionProfile() -> (profile: Int, level: Int)? {
        onPlayerQueue { () -> (profile: Int, level: Int)? in
            let count = Int(getInt64("track-list/count") ?? 0)
            for index in 0..<count {
                let prefix = "track-list/\(index)/"
                guard getString(prefix + "type") == "video",
                      getFlag(prefix + "selected") == true,
                      let profile = getInt64(prefix + "dolby-vision-profile")
                else { continue }
                return (Int(profile), Int(getInt64(prefix + "dolby-vision-level") ?? 0))
            }
            return nil
        }
    }

    private let felLock = NSLock()
    private var felHWDecRequested = false

    /// CoreCustom `dovi-fel-hwdec` 标记位的等价物：请求 FEL 走硬解
    /// 路径。落地形态是播放器级标记 + 把 hwdec 钉在 videotoolbox
    /// （FEL 码流若掉到软解，双层合成在原版亦不可行）；双层合成本
    /// 身依赖原版 fork 的 demux/dovi_split，stock mpv 无此能力，
    /// 见 MPlayDolbyVision.swift 头部与 Build59 文档。
    func setDolbyVisionFELHardwareDecode(_ enabled: Bool) {
        felLock.lock()
        felHWDecRequested = enabled
        felLock.unlock()
        if enabled {
            setProp("hwdec", "videotoolbox")
        }
        MPlayDiagnostics.log("dovi-fel-hwdec \(enabled ? "requested" : "cleared")")
    }

    /// 当前流的 DV 状态快照（profile/level/FEL 推断/标记位）。
    var dolbyVisionState: MPlayDolbyVisionState {
        let dv = dolbyVisionProfile()
        felLock.lock()
        let fel = felHWDecRequested
        felLock.unlock()
        return MPlayDolbyVisionState(profile: dv?.profile, level: dv?.level,
                                     felHardwareDecodeRequested: fel)
    }

    /// phase 是 iOS 侧推导规则（原版 phase 的确切值域未被 RE 定名）：
    /// closed → 已关闭；有失败记录且文件还没加载出来 → failed；
    /// 未 FILE_LOADED → preparing；eof-reached → ended；
    /// pause → paused；其余 → playing。
    private func readState() -> MPlayState {
        var result = MPlayState()
        result.source = source
        let paused = getFlag("pause") ?? false
        if closed {
            result.phase = "closed"
        } else if !lastFailure.isEmpty && !fileLoaded {
            result.phase = "failed"
        } else if !fileLoaded {
            result.phase = "preparing"
        } else if getFlag("eof-reached") == true {
            result.phase = "ended"
        } else if paused {
            result.phase = "paused"
        } else {
            result.phase = "playing"
        }
        result.paused = paused
        result.seekable = getFlag("seekable") ?? false
        result.errorCode = lastEndFileError
        result.failure = lastFailure
        result.surfaceError = lastSurfaceError
        result.position = getDouble("time-pos") ?? 0
        result.duration = getDouble("duration") ?? 0
        return result
    }

    private func readProgress() -> MPlayProgress {
        var result = MPlayProgress()
        result.source = source
        result.time = getDouble("time-pos") ?? 0
        result.duration = getDouble("duration") ?? 0
        result.fileSize = getInt64("file-size") ?? 0
        if let cache = readCacheState() {
            result.cacheDuration = cache.cacheDuration
            result.cacheEnd = cache.cacheEnd
            result.cacheEOF = cache.eofCached
            result.cacheRanges = cache.ranges
        } else {
            // node 读不到时退化到标量属性。
            result.cacheDuration = getDouble("demuxer-cache-duration") ?? 0
            result.cacheEnd = 0
        }
        result.cacheSpeed = getInt64("cache-speed") ?? 0
        result.estimatedFrameRate = getDouble("estimated-vf-fps") ?? 0
        result.pausedForCache = getFlag("paused-for-cache") ?? false
        result.hwdecCurrent = getString("hwdec-current") ?? ""
        // lastFailure 只由 END_FILE(ERROR) 写入（加载/网络类失败），
        // 非此类失败时它为空串，正好对应 networkErrorMessage 的口径。
        result.networkErrorMessage = lastFailure
        return result
    }

    // MARK: - 预加载 / 关闭

    /// n4 等价：派生一个预加载实例（与本实例相同 options 的完整新实例）。
    /// 阶段 D 起是接管制：预加载实例经 promotePreloadedPlayback 打开
    /// 目标媒体并停在接管点，协调者接管时把视图与 PiP 控制器转绑到
    /// 它、退役旧实例（接管语义见 promotePreloadedPlayback、
    /// MPlayVideoView.attach 的 PiP 分支与
    /// MPlayPictureInPictureController 的 transfer / rebindPlayer）。
    /// 这与原版 iOS 的完整实例 + promote 接管制同构
    /// （IOS-FINDINGS §2.5）；阶段 A 已去掉原先的 GL 上下文共享
    /// （像素帧管线下不存在共享渲染上下文）。
    func makePreloadedPlayer() throws -> MPlayPlayer {
        try MPlayPlayer(options: mergedOptions)
    }

    /// 原版 promotePreloadedPlayback 的等价物：在（预加载）实例上打开
    /// 目标媒体并停在接管点——起始位置 + 暂停态，等待协调者接管。
    /// 原版签名中的 aid/sid/volume/useHardwareDecode 在我方分别由
    /// selectTrack、音量属性与实例 options 承担，不重复进本签名；
    /// takeRenderViewOwnership 对应视图 attach 的接管路径
    /// （MPlayVideoView.attach 在 PiP 活跃时走 rebind 而非重建）。
    func promotePreloadedPlayback(url: String, headers: [String: String] = [:],
                                  startSeconds: Double = 0, paused: Bool = true,
                                  completion: ((Result<Void, MPlayError>) -> Void)? = nil) {
        open(url: url, startSeconds: startSeconds, headers: headers,
             autoplay: !paused, completion: completion)
    }

    /// 本实例是否已完成文件加载（接管时协调者据此点亮 ready 边）。
    var isFileLoaded: Bool {
        onPlayerQueue { fileLoaded }
    }

    /// n19 等价，幂等。先清 wakeup 回调再销毁 core，保证 passUnretained
    /// 的回调不会在实例释放后进入；pending 的 open 回调以 .invalidHandle
    /// 收尾，pending 的 seek 回调直接触发（避免调用方永久等待）。
    func close() {
        let work = { self.closeOnQueue() }
        if DispatchQueue.getSpecific(key: specificKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }

    private func closeOnQueue() {
        guard !closed else { return }
        closed = true
        if let core {
            mpv_set_wakeup_callback(core, nil, nil)
            mpv_terminate_destroy(core)
            self.core = nil
        }
        // Stream protocol factories: callbacks can no longer fire
        // once the core is destroyed, so the retains taken at
        // registration time are balanced here.
        let contexts = streamContexts
        streamContexts.removeAll()
        for context in contexts {
            Unmanaged<MPlayStreamFactoryBox>.fromOpaque(context).release()
        }
        let opens = pendingOpens
        pendingOpens.removeAll()
        for (_, completion) in opens {
            completion(.failure(.invalidHandle))
        }
        let seeks = pendingSeeks
        pendingSeeks.removeAll()
        for entry in seeks {
            entry.completion()
        }
    }

    /// 渲染面出错时由 MPlayVideoView 写入（对应 State.surfaceError）。
    func noteSurfaceError(_ message: String) {
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            self.lastSurfaceError = message
        }
    }

    /// 字幕渲染尺寸（阶段 A）：转发给 frame_output vo 的 sink 覆盖值。
    /// 对应原版 Player 的 updatePictureInPictureSubtitleRenderSize
    /// 语义——字幕渲染分辨率与视频帧尺寸解耦，跟随宿主（行内视图
    /// bounds 或 PiP 窗口 render size）。0 表示回到视频尺寸。
    /// mp_frame_output_set_subtitle_size 本身线程安全，不经 queue。
    func setSubtitleRenderSize(width: Int, height: Int) {
        mp_frame_output_set_subtitle_size(frameSinkName, Int32(width), Int32(height))
    }

    // MARK: - 事件处理（只在 queue 上运行）

    func handleWakeup() {
        queue.async { [weak self] in
            self?.handleEvents()
        }
    }

    private func handleEvents() {
        guard !closed, let core else { return }
        while true {
            guard let eventPointer = mpv_wait_event(core, 0) else { return }
            let event = eventPointer.pointee
            if event.event_id == MPV_EVENT_NONE {
                return
            } else if event.event_id == MPV_EVENT_SHUTDOWN {
                fileLoaded = false
            } else if event.event_id == MPV_EVENT_LOG_MESSAGE {
                handleLogMessage(event.data)
            } else if event.event_id == MPV_EVENT_START_FILE {
                fileLoaded = false
            } else if event.event_id == MPV_EVENT_FILE_LOADED {
                fileLoaded = true
                lastFailure = ""
                lastEndFileError = 0
                // open 时设置的起始位置只对本次 loadfile 有效，加载完成后
                // 清回 none，避免影响后续条目。
                _ = mpv_set_property_string(core, "start", "none")
                let opens = pendingOpens
                pendingOpens.removeAll()
                for (_, completion) in opens {
                    completion(.success(()))
                }
                onPlaybackEvent?(.fileLoaded)
            } else if event.event_id == MPV_EVENT_END_FILE {
                handleEndFile(event.data)
            } else if event.event_id == MPV_EVENT_SEEK {
                // seek 已被 core 接受，完成回调等 PLAYBACK_RESTART。
            } else if event.event_id == MPV_EVENT_PLAYBACK_RESTART {
                let seeks = pendingSeeks
                pendingSeeks.removeAll()
                for entry in seeks {
                    entry.completion()
                }
                onPlaybackEvent?(.playbackRestart)
            }
            // 其余事件忽略。
        }
    }

    /// MPV_EVENT_LOG_MESSAGE：data 按 client.h 的 mpv_event_log_message
    /// 结构读（prefix/level/text/log_level），转发进诊断桥——这就是原版
    /// Diagnostics 的 native→上层方向。
    private func handleLogMessage(_ data: UnsafeMutableRawPointer?) {
        guard let data else { return }
        let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
        let tag = message.prefix.map { String(cString: $0) } ?? "mpv"
        let text = message.text.map { String(cString: $0) } ?? ""
        let levelText = message.level.map { String(cString: $0) } ?? ""
        // mpv 日志级别字符串 → MPlayDiagnostics 的 iOS 侧 level 约定。
        let level: Int
        switch levelText {
        case "fatal", "error": level = 4
        case "warn": level = 3
        case "info": level = 2
        case "v", "debug": level = 1
        case "trace": level = 0
        default: level = 2
        }
        MPlayDiagnostics.log(level: level, tag: tag,
                             text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// MPV_EVENT_END_FILE：data 按 client.h 的 mpv_event_end_file 结构读
    /// （reason/error/playlist_entry_id…）。
    private func handleEndFile(_ data: UnsafeMutableRawPointer?) {
        fileLoaded = false
        guard let data else { return }
        let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
        if endFile.reason == MPV_END_FILE_REASON_EOF {
            onPlaybackEvent?(.endFileEOF)
        }
        guard endFile.reason == MPV_END_FILE_REASON_ERROR else { return }
        lastEndFileError = Int(endFile.error)
        let message = String(cString: mpv_error_string(endFile.error))
        lastFailure = message
        onPlaybackEvent?(.endFileError(message))
        // "start" 同样要在失败后清回，避免污染下一次 open。
        if let core {
            _ = mpv_set_property_string(core, "start", "none")
        }
        if !pendingOpens.isEmpty {
            let opens = pendingOpens
            pendingOpens.removeAll()
            for (_, completion) in opens {
                completion(.failure(.loadFailed(message)))
            }
        }
    }

    // MARK: - 属性读取小助手（只在 queue 上调用；读不到一律 nil）

    private func onPlayerQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: specificKey) != nil {
            return work()
        }
        return queue.sync(execute: work)
    }

    /// 统一走 mpv_get_property_string + mpv_free 释放。
    private func getString(_ name: String) -> String? {
        guard let core, !closed else { return nil }
        guard let pointer = mpv_get_property_string(core, name) else { return nil }
        let value = String(cString: pointer)
        mpv_free(pointer)
        return value
    }

    private func getDouble(_ name: String) -> Double? {
        guard let core, !closed else { return nil }
        var value: Double = 0
        let rc = name.withCString { cName in
            withUnsafeMutablePointer(to: &value) { pointer in
                mpv_get_property(core, cName, MPV_FORMAT_DOUBLE, UnsafeMutableRawPointer(pointer))
            }
        }
        return rc == 0 ? value : nil
    }

    private func getInt64(_ name: String) -> Int64? {
        guard let core, !closed else { return nil }
        var value: Int64 = 0
        let rc = name.withCString { cName in
            withUnsafeMutablePointer(to: &value) { pointer in
                mpv_get_property(core, cName, MPV_FORMAT_INT64, UnsafeMutableRawPointer(pointer))
            }
        }
        return rc == 0 ? value : nil
    }

    private func getFlag(_ name: String) -> Bool? {
        guard let core, !closed else { return nil }
        var value: Int32 = 0
        let rc = name.withCString { cName in
            withUnsafeMutablePointer(to: &value) { pointer in
                mpv_get_property(core, cName, MPV_FORMAT_FLAG, UnsafeMutableRawPointer(pointer))
            }
        }
        return rc == 0 ? (value != 0) : nil
    }

    // MARK: - demuxer-cache-state 的 node 解析

    private struct CacheState {
        var cacheDuration: Double = 0
        var cacheEnd: Double = 0
        var eofCached: Bool = false
        var ranges: [MPlayCacheRange] = []
    }

    /// "demuxer-cache-state" 是 node map：cache-end / cache-duration /
    /// eof-cached / seekable-ranges([{start,end},…])。用 MPV_FORMAT_NODE
    /// 读出后严格按 client.h 的 mpv_node/mpv_node_list 布局解析，
    /// 读完 mpv_free_node_contents 释放。
    private func readCacheState() -> CacheState? {
        guard let core, !closed else { return nil }
        var node = mpv_node()
        let rc = "demuxer-cache-state".withCString { cName in
            withUnsafeMutablePointer(to: &node) { pointer in
                mpv_get_property(core, cName, MPV_FORMAT_NODE, UnsafeMutableRawPointer(pointer))
            }
        }
        guard rc == 0 else { return nil }
        defer { mpv_free_node_contents(&node) }
        guard case .map(let entries) = MPlayNodeParser.parse(node) else { return nil }
        var state = CacheState()
        for (key, value) in entries {
            switch key {
            case "cache-duration":
                state.cacheDuration = value.doubleValue ?? 0
            case "cache-end":
                state.cacheEnd = value.doubleValue ?? 0
            case "eof-cached":
                state.eofCached = value.flagValue ?? false
            case "seekable-ranges":
                if case .array(let items) = value {
                    for item in items {
                        if case .map(let rangeEntries) = item {
                            var range = MPlayCacheRange()
                            for (rangeKey, rangeValue) in rangeEntries {
                                if rangeKey == "start" { range.start = rangeValue.doubleValue ?? 0 }
                                if rangeKey == "end" { range.end = rangeValue.doubleValue ?? 0 }
                            }
                            state.ranges.append(range)
                        }
                    }
                }
            default:
                continue
            }
        }
        return state
    }

    // MARK: - C 命令参数构造

    /// mpv_command / mpv_command_async 需要 NULL 结尾的 C 字符串数组：
    /// 每条用 strdup 分配（不能用 withCString 的临时指针逃逸），调用完 free。
    private func withCArgs<T>(_ args: [String], _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> T) -> T {
        let allocated: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer {
            for pointer in allocated {
                if let pointer { free(UnsafeMutableRawPointer(pointer)) }
            }
        }
        var pointers: [UnsafePointer<CChar>?] = allocated.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        }
        pointers.append(nil)
        // mpv_command 的导入签名要的是可变外层指针
        // (UnsafeMutablePointer<UnsafePointer<CChar>?>?)：元素是不可变
        // C 字符串指针、数组本身可变，正是 withUnsafeMutableBufferPointer。
        return pointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress)
        }
    }

    private func runCommandAsync(core: OpaquePointer, tag: UInt64, args: [String]) -> Int32 {
        withCArgs(args) { mpv_command_async(core, tag, $0) }
    }
}

/// mpv_node 的 Swift 值形态（只覆盖 client.h 列出的 format）。
private indirect enum MPlayNodeValue {
    case none
    case string(String)
    case flag(Bool)
    case int64(Int64)
    case double(Double)
    case array([MPlayNodeValue])
    case map([(String, MPlayNodeValue)])
    case byteArray

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int64(let value): return Double(value)
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var flagValue: Bool? {
        switch self {
        case .flag(let value): return value
        case .int64(let value): return value != 0
        default: return nil
        }
    }
}

/// 严格按 client.h 的 mpv_node（union u + format）与 mpv_node_list
/// （num/values/keys）布局走 unsafe 指针解析。
private enum MPlayNodeParser {
    static func parse(_ node: mpv_node) -> MPlayNodeValue {
        if node.format == MPV_FORMAT_STRING {
            guard let string = node.u.string else { return .none }
            return .string(String(cString: string))
        } else if node.format == MPV_FORMAT_FLAG {
            return .flag(node.u.flag != 0)
        } else if node.format == MPV_FORMAT_INT64 {
            return .int64(node.u.int64)
        } else if node.format == MPV_FORMAT_DOUBLE {
            return .double(node.u.double_)
        } else if node.format == MPV_FORMAT_NODE_ARRAY || node.format == MPV_FORMAT_NODE_MAP {
            guard let listPointer = node.u.list else {
                return node.format == MPV_FORMAT_NODE_ARRAY ? .array([]) : .map([])
            }
            let list = listPointer.pointee
            let count = Int(list.num)
            guard count > 0, let values = list.values else {
                return node.format == MPV_FORMAT_NODE_ARRAY ? .array([]) : .map([])
            }
            if node.format == MPV_FORMAT_NODE_ARRAY {
                var items: [MPlayNodeValue] = []
                items.reserveCapacity(count)
                for index in 0..<count {
                    items.append(parse(values.advanced(by: index).pointee))
                }
                return .array(items)
            }
            var entries: [(String, MPlayNodeValue)] = []
            entries.reserveCapacity(count)
            for index in 0..<count {
                var key = ""
                if let keys = list.keys, let keyPointer = keys.advanced(by: index).pointee {
                    key = String(cString: keyPointer)
                }
                entries.append((key, parse(values.advanced(by: index).pointee)))
            }
            return .map(entries)
        } else if node.format == MPV_FORMAT_BYTE_ARRAY {
            return .byteArray
        }
        return .none
    }
}
