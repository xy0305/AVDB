//
//  MPlayKernel.swift
//  AVDB
//
//  Build 353: 播放内核选择。默认仍是 KSPlayer；MPlayKit 是按
//  ~/workspace/p115-player-re/RE-REPORT.md 逆向出的接口形状、用 libmpv C API
//  在本目录复刻的第二内核。集成层只通过 PlaybackKernelSettings.current 读选择，
//  切换写 UserDefaults 后下次建播放器生效。
//

import Foundation

/// 播放内核。rawValue 同时是设置页展示名与持久化值，不要改名。
enum PlaybackKernel: String, CaseIterable, Identifiable {
    case ksPlayer = "KSPlayer"
    case mplayKit = "MPlayKit"
    var id: String { rawValue }
}

enum PlaybackKernelSettings {
    static let defaultsKey = "avdb.playback.kernel"
    /// 当前选择；从未写过或值无法识别时回落到 KSPlayer（现行行为不变）。
    static var current: PlaybackKernel {
        PlaybackKernel(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .ksPlayer
    }
}
