//
//  MPlayRenderContext.swift
//  AVDB
//
//  Build 353: 共享渲染上下文，对应原版 n30 取出的共享渲染上下文句柄
//  （RE 报告 1.2/1.3：首个实例创建后回填，后续播放器复用、创建日志带 reused=）。
//  Android 侧是 Surface/GL 上下文共享；iOS 侧用一个共享 EAGLContext，
//  让多个 MPlayPlayer 共用同一份 GL 资源。所有 render API 调用都必须在这条
//  串行队列上、且 setCurrent 本上下文之后进行。
//

import Foundation
import OpenGLES
import UIKit

final class MPlayRenderContext {
    let glContext: EAGLContext
    let queue: DispatchQueue

    /// GL 上下文建不出来时返回 nil，调用方降级为无画面播放（见 MPlayPlayer）。
    init?() {
        guard let context = EAGLContext(api: .openGLES3) else { return nil }
        glContext = context
        queue = DispatchQueue(label: "avdb.mplaykit.render")
    }
}
