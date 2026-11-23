//
//  MPlayState.swift
//  AVDB
//
//  Build 353: 状态/进度快照模型，字段与原版 com.mplaykit.Playback$State /
//  Playback$Progress 已命名项一一对应（RE 报告 1.5）。原版 State 由 native
//  以 long[23]/double[3]/String[7] 三个数组回填、Java 构造器按固定下标拆分；
//  这里 MPlayState 是命名视图，MPlayStateRaw 是下标等价的原始三数组。
//

import Foundation

/// 播放状态快照（对应原版 Playback$State 已命名项，下标为原版数组下标）。
struct MPlayState {
    var source: Int64 = 0        // L[0]  source（源 id）
    var phase: String = ""       // S[0]  phase（播放阶段字符串）
    var paused: Bool = false     // L[5]  paused
    var seekable: Bool = false   // L[6]  seekable
    var errorCode: Int = 0       // L[2]  errorCode
    var failure: String = ""     // S[5]  failure（失败描述）
    var surfaceError: String = "" // S[6] surfaceError（渲染面错误描述）
    var position: Double = 0     // D[0]  statePosition
    var duration: Double = 0     // D[1]  stateDuration
}

/// 原版三数组的下标等价形态：固定 23/3/7 长度。
/// 只有 RE 报告 1.5 已命名的下标有语义；其余下标按报告四.3 不起名，
/// 恒填 0 / 0.0 / ""，不要凭猜测给未命名项赋含义。
struct MPlayStateRaw {
    var longs: [Int64] = [Int64](repeating: 0, count: 23)
    var doubles: [Double] = [Double](repeating: 0, count: 3)
    var strings: [String] = [String](repeating: "", count: 7)
}

/// 缓存区间（原版 Progress.cacheRanges 的元素 pi3：start/end 一对 double）。
struct MPlayCacheRange {
    var start: Double = 0
    var end: Double = 0
}

/// 缓存/进度快照（对应原版 Playback$Progress，RE 报告 1.5）。
struct MPlayProgress {
    var source: Int64 = 0
    var time: Double = 0
    var duration: Double = 0
    var fileSize: Int64 = 0
    var cacheDuration: Double = 0
    var cacheEnd: Double = 0
    var estimatedFrameRate: Double = 0
    var cacheEOF: Bool = false
    var pausedForCache: Bool = false
    var hwdecCurrent: String = ""
    var networkErrorMessage: String = ""
    var cacheRanges: [MPlayCacheRange] = []

    /// 键名与原版 Progress 的 JSON 构造器逐字一致（j64 解密值）。
    func jsonObject() -> [String: Any] {
        [
            "source": source,
            "time": time,
            "duration": duration,
            "fileSize": fileSize,
            "cacheDuration": cacheDuration,
            "cacheEnd": cacheEnd,
            "estimatedFrameRate": estimatedFrameRate,
            "cacheEOF": cacheEOF,
            "pausedForCache": pausedForCache,
            "hwdecCurrent": hwdecCurrent,
            "networkErrorMessage": networkErrorMessage,
            "cacheRanges": cacheRanges.map { ["start": $0.start, "end": $0.end] },
        ]
    }
}
