//
//  MPlayDiagnostics.swift
//  AVDB
//
//  Build 353: 对应原版 com.mplaykit.Diagnostics 的双向诊断桥（RE 报告 1.6）。
//  原版 Java→native 走 n29 写日志、native→Java 走 receive 回调、n28 注册时
//  初始化。这里是纯 Swift 等价物：log/event 写入内存环形缓冲，onEntry 是
//  native→上层方向的等价回调——MPlayPlayer 收到 MPV_EVENT_LOG_MESSAGE 时
//  转发进 log，追加即触发 onEntry。
//

import Foundation

enum MPlayDiagnostics {
    /// level 约定（iOS 侧约定，原版 level 数值语义未证实，见 RE 报告四）：
    /// 0=trace 1=debug 2=info 3=warn 4=error。
    static var onEntry: ((String) -> Void)?

    private static let lock = NSLock()
    private static var buffer: [String] = []
    private static let capacity = 512
    /// 只在 lock 保护下使用（ISO8601DateFormatter 非线程安全）。
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 简便入口：info 级别 + 通用 tag。各调用点多为单行状态打点，
    /// 写的都是这个单参形态；需要区分级别/来源时用全形 log(level:tag:_:)。
    static func log(_ message: String) {
        log(level: 2, tag: "mplaykit", message)
    }

    static func log(level: Int, tag: String, _ message: String) {
        lock.lock()
        let entry = "\(formatter.string(from: Date())) level=\(level) tag=\(tag) \(message)"
        buffer.append(entry)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        let callback = onEntry
        lock.unlock()
        // 锁外回调：回调里再写日志也不会自死锁。
        callback?(entry)
    }

    /// 结构化事件，产出文本与原版一致：event=<name> k1=v1 k2=v2。
    static func event(tag: String, _ name: String, _ fields: [(String, String)] = []) {
        var text = "event=\(name)"
        for (key, value) in fields {
            text += " \(key)=\(value)"
        }
        log(level: 2, tag: tag, text)
    }

    /// 最近 count 条（不足则全部），旧→新。
    static func recent(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return Array(buffer.suffix(count))
    }

    static func reset() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }
}
