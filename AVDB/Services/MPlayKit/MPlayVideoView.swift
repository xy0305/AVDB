//
//  MPlayVideoView.swift
//  AVDB
//
//  Build 353: MPlayKit 的画面视图，对应原版 SenPlayerView 的视频 Surface
//  （RE 报告 1.1/二.1；原版双 Surface 中的字幕面是 Android 自研扩展，
//  iOS/libmpv 无对应物，这里只有视频一面，字幕由 mpv 在同一帧内合成）。
//  渲染走 libmpv render API 的标准 iOS 用法（render.h / render_gl.h）：
//  CAEAGLLayer + 自建 FBO，update 回调只负责唤醒主线程的重绘调度，
//  所有 mpv_render_* 与 GL 调用都在共享的 render 队列上、setCurrent
//  共享 EAGLContext 之后执行。
//
//  生命周期：detach() 必须先于 player.close() 调用——render context
//  要在 mpv core 销毁之前 free（render.h 的明确要求）。
//

import Darwin
import Foundation
import Libmpv
import OpenGLES
import UIKit

/// mpv_opengl_init_params.get_proc_address 的实现（文件级 @convention(c)
/// 相容函数，不能捕获上下文）：RTLD_DEFAULT 在 Darwin 上是 (void *)-2，
/// 即在已加载的全部镜像里按名查符号（OpenGLES 的函数都在其中）。
private func mplayGLGetProcAddress(_ context: UnsafeMutableRawPointer?,
                                   _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
}

/// render update 回调：只转投主线程触发一次重绘调度，不在回调里调 mpv。
private func mplayRenderUpdateCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let view = Unmanaged<MPlayVideoView>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { [weak view] in
        view?.scheduleRender()
    }
}

/// CADisplayLink 的弱代理，避免 link 强持有视图造成循环引用。
private final class MPlayDisplayLinkProxy: NSObject {
    weak var view: MPlayVideoView?

    @objc func tick(_ link: CADisplayLink) {
        view?.displayLinkTicked()
    }
}

final class MPlayVideoView: UIView {
    override class var layerClass: AnyClass { CAEAGLLayer.self }

    private var glLayer: CAEAGLLayer { layer as! CAEAGLLayer }

    private let proxy = MPlayDisplayLinkProxy()
    private var displayLink: CADisplayLink?

    // 以下渲染状态只在 renderContext.queue 上读写（attach/detach 把值
    // 快照进队列块里带走，避免跨线程直接碰）。
    private var attachedPlayer: MPlayPlayer?
    private var renderQueue: DispatchQueue?
    private var glContext: EAGLContext?
    private var renderContextPointer: OpaquePointer?
    private var framebuffer: GLuint = 0
    private var renderbuffer: GLuint = 0
    private var lastPixelWidth: Int32 = 0
    private var lastPixelHeight: Int32 = 0
    private var surfaceErrorReported = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        proxy.view = self
        contentScaleFactor = UIScreen.main.scale
        layer.contentsScale = UIScreen.main.scale
        glLayer.isOpaque = true
        glLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8,
        ] as [String: Any]
    }

    deinit {
        detach()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 尺寸变了就请求一帧；renderFrame 里按像素尺寸决定是否重建 FBO。
        scheduleRender()
    }

    // MARK: - Attach / detach

    func attach(player: MPlayPlayer) {
        if attachedPlayer != nil {
            detach()
        }
        attachedPlayer = player
        surfaceErrorReported = false
        guard let shared = player.renderContext, let core = player.core else {
            player.noteSurfaceError("MPlayKit render context unavailable")
            return
        }
        renderQueue = shared.queue
        glContext = shared.glContext

        let setupLink = { [weak self] in
            guard let self, self.displayLink == nil else { return }
            let link = CADisplayLink(target: self.proxy,
                                     selector: #selector(MPlayDisplayLinkProxy.tick(_:)))
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
        if Thread.isMainThread {
            setupLink()
        } else {
            DispatchQueue.main.async(execute: setupLink)
        }

        shared.queue.async { [weak self] in
            guard let self, self.attachedPlayer === player else { return }
            _ = EAGLContext.setCurrent(shared.glContext)
            // API_TYPE 的 data 按 render.h 约定直接是 char* 本身（C 示例
            // 即把 MPV_RENDER_API_TYPE_OPENGL 字面量指针放进 data）。
            let apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)
            defer { free(apiType) }
            var initParams = mpv_opengl_init_params(
                get_proc_address: mplayGLGetProcAddress,
                get_proc_address_ctx: nil)
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                 data: UnsafeMutableRawPointer(apiType)),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                                 data: &initParams),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            var newContext: OpaquePointer?
            let rc = mpv_render_context_create(&newContext, core, &params)
            guard rc == 0, let newContext else {
                player.noteSurfaceError("mpv_render_context_create failed rc=\(rc)")
                return
            }
            self.renderContextPointer = newContext
            mpv_render_context_set_update_callback(
                newContext, mplayRenderUpdateCallback,
                Unmanaged.passUnretained(self).toOpaque())
            self.scheduleRender()
        }
    }

    func detach() {
        let link = displayLink
        displayLink = nil
        if Thread.isMainThread {
            link?.invalidate()
        } else if let link {
            DispatchQueue.main.async { link.invalidate() }
        }
        attachedPlayer = nil
        // 把指针快照带进 render 队列收尾：先清 update 回调，再删 GL 对象，
        // 最后 free render context。此后队列上排着的 attach 创建块会因
        // attachedPlayer 已变而自行放弃。
        let contextPointer = renderContextPointer
        renderContextPointer = nil
        let queue = renderQueue
        renderQueue = nil
        glContext = nil
        guard let contextPointer, let queue else { return }
        let framebufferToDelete = framebuffer
        let renderbufferToDelete = renderbuffer
        framebuffer = 0
        renderbuffer = 0
        lastPixelWidth = 0
        lastPixelHeight = 0
        queue.async {
            mpv_render_context_set_update_callback(contextPointer, nil, nil)
            if framebufferToDelete != 0 {
                var value = framebufferToDelete
                glDeleteFramebuffers(1, &value)
            }
            if renderbufferToDelete != 0 {
                var value = renderbufferToDelete
                glDeleteRenderbuffers(1, &value)
            }
            mpv_render_context_free(contextPointer)
        }
    }

    // MARK: - 重绘调度（主线程）

    /// update 回调与 layoutSubviews 的统一入口：唤醒 display link 画一帧。
    func scheduleRender() {
        if Thread.isMainThread {
            displayLink?.isPaused = false
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.displayLink?.isPaused = false
            }
        }
    }

    func displayLinkTicked() {
        displayLink?.isPaused = true
        let width = bounds.width * contentScaleFactor
        let height = bounds.height * contentScaleFactor
        guard width >= 1, height >= 1, let queue = renderQueue else { return }
        let pixelWidth = Int32(width)
        let pixelHeight = Int32(height)
        queue.async { [weak self] in
            self?.renderFrame(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        }
    }

    // MARK: - 渲染（render 队列）

    private func renderFrame(pixelWidth: Int32, pixelHeight: Int32) {
        guard pixelWidth > 0, pixelHeight > 0,
              let renderContextPointer, let glContext,
              let player = attachedPlayer else { return }
        _ = EAGLContext.setCurrent(glContext)

        if framebuffer == 0 || pixelWidth != lastPixelWidth || pixelHeight != lastPixelHeight {
            rebuildFramebuffer(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        }
        guard framebuffer != 0, renderbuffer != 0 else { return }
        // FBO 实际像素尺寸以 renderbuffer 的回读值为准（drawable 可能
        // 按 contentsScale 取整，与请求值差一两像素）。
        var actualWidth: GLint = 0
        var actualHeight: GLint = 0
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &actualWidth)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &actualHeight)
        let width = actualWidth > 0 ? actualWidth : pixelWidth
        let height = actualHeight > 0 ? actualHeight : pixelHeight

        var fbo = mpv_opengl_fbo(fbo: Int32(framebuffer), w: width, h: height, internal_format: 0)
        var flipY: Int32 = 1
        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: &fbo),
            mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: &flipY),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
        ]
        let rc = mpv_render_context_render(renderContextPointer, &params)
        if rc < 0 {
            reportSurfaceError(player: player, message: "mpv_render_context_render failed rc=\(rc)")
            return
        }
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderbuffer)
        _ = glContext.presentRenderbuffer(Int(EAGL_RENDER_BUFFER))
    }

    /// 尺寸变化时重建 renderbuffer + framebuffer 对（render 队列上调用，
    /// 当前 GL 上下文已 setCurrent）。
    private func rebuildFramebuffer(pixelWidth: Int32, pixelHeight: Int32) {
        if framebuffer != 0 {
            var value = framebuffer
            glDeleteFramebuffers(1, &value)
            framebuffer = 0
        }
        if renderbuffer != 0 {
            var value = renderbuffer
            glDeleteRenderbuffers(1, &value)
            renderbuffer = 0
        }
        glGenRenderbuffers(1, &renderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderbuffer)
        _ = glContext?.renderbufferStorage(Int(EAGL_RENDER_BUFFER), from: glLayer)
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                  GLenum(GL_RENDERBUFFER), renderbuffer)
        lastPixelWidth = pixelWidth
        lastPixelHeight = pixelHeight
    }

    /// 渲染错误只记首次，避免每帧刷一条 surfaceError。
    private func reportSurfaceError(player: MPlayPlayer, message: String) {
        guard !surfaceErrorReported else { return }
        surfaceErrorReported = true
        player.noteSurfaceError(message)
    }
}
