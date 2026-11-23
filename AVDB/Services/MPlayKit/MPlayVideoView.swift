//
//  MPlayVideoView.swift
//  AVDB
//
//  Build 353 full restoration, stage A: the display view of the
//  pixel-frame pipeline.  This replaces the GL implementation that
//  used to live here (libmpv render API + CAEAGLLayer) — that path
//  is retired and deleted, per the original's architecture
//  (IOS-FINDINGS §1/§3: the original builds mpv with -Dgl=disabled
//  and displays through a private frame_output vo feeding an
//  AVSampleBufferDisplayLayer; there is no GL anywhere in its main
//  display chain).
//
//  Shape (mirrors the original's FrameOutputView):
//  - The view's backing layer IS an AVSampleBufferDisplayLayer.
//  - Frames arrive from the player's frame_output vo through an
//    MPlayFrameSink registered under the player's sink name; the
//    FrameStore routes video frames to the FrameOutputScheduler
//    (which wraps them as CMSampleBuffers) and subtitle frames to
//    the independent subtitle layer.
//  - The subtitle layer is a sublayer of the display layer by
//    default — that is what lets sample-buffer PiP carry subtitles
//    with the picture — and can be reparented to an external host
//    view via moveSubtitleLayerToPictureInPictureHost(_:) /
//    moveSubtitleLayerToInlineHost() (the original's method names;
//    stage B drives them around PiP transitions).
//  - Time sync: the scheduler's control timebase is re-aligned from
//    the frame path (each enqueued frame nudges it when drift
//    exceeds a quarter second) and on explicit syncPlaybackTime
//    calls from the chrome's transport handling.
//

import AVFoundation
import CoreVideo
import Foundation
import QuartzCore
import UIKit

final class MPlayVideoView: UIView {
    override class var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    let frameStore = MPlayFrameStore()
    let subtitleLayerController = MPlaySubtitleLayerController()
    private(set) var scheduler: MPlayFrameOutputScheduler!

    /// Stage B: PiP controller bound to (player, view) on attach.
    let pictureInPictureController = MPlayPictureInPictureController()

    private var sink: MPlayFrameSink?
    private weak var attachedPlayer: MPlayPlayer?
    private var lastSyncedRate: Double = -1
    private var lastSyncHostTime: CFTimeInterval = 0

    /// Mirrored output (the original's setMirroredRenderView): a
    /// second view fed the same post-chain frames this view enqueues.
    /// Weak — the host owns the mirror.
    private weak var mirrorView: MPlayVideoView?

    /// Display matching state (see refreshDisplayCriteria).
    private var displayLink: CADisplayLink?
    private var displayCriteriaAppliedGeneration: UInt64 = .max

    /// Host view that receives the subtitle layer when it is moved
    /// out of the display layer (stage B: the PiP host).  Nil means
    /// the layer's external home is this view itself (an overlay
    /// above the display layer, same bounds).
    private weak var externalSubtitleHost: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scheduler = MPlayFrameOutputScheduler(displayLayer: displayLayer)
        scheduler.onLayerError = { [weak self] message in
            self?.attachedPlayer?.noteSurfaceError(message)
        }
        frameStore.onVideoFrame = { [weak self] frame in
            guard let self else { return }
            // Stage C: the Metal post chain sits between the store
            // and the scheduler (frame-after domain).  Disabled =
            // direct enqueue, zero added latency.
            let chain = MPlayPostChain.shared
            if chain.isEnabled {
                chain.process(frame) { [weak self] frames in
                    guard let self else { return }
                    for processed in frames {
                        self.scheduler.enqueue(processed)
                        self.mirrorView?.receiveMirroredFrame(processed)
                    }
                    if let last = frames.last {
                        self.nudgeTimeSync(with: last)
                    }
                }
            } else {
                self.scheduler.enqueue(frame)
                self.mirrorView?.receiveMirroredFrame(frame)
                self.nudgeTimeSync(with: frame)
            }
        }
        frameStore.onSubtitleFrame = { [weak self] frame in
            self?.subtitleLayerController.update(frame)
        }
        subtitleLayerController.onRenderSizeChanged = { [weak self] size in
            self?.attachedPlayer?.setSubtitleRenderSize(
                width: Int(size.width), height: Int(size.height)
            )
        }
        // Default parent: the display layer itself (PiP-visible).
        displayLayer.addSublayer(subtitleLayerController.layer)
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Attach / detach (contract kept from the GL view)

    /// Bind to a player: register the frame sink under the player's
    /// sink name so its frame_output vo starts delivering here.
    /// Idempotent for the same player; switching players detaches
    /// the old binding first — except during an active PiP session,
    /// where the stage D takeover path applies: the PiP session and
    /// the queued frames survive, only the sink registration and the
    /// PiP controller's player reference move to the promoted
    /// preloaded player (the display layer never changes hands).
    func attach(player: MPlayPlayer) {
        if attachedPlayer === player, sink != nil {
            return
        }
        if attachedPlayer != nil, pictureInPictureController.isPictureInPictureActive {
            sink?.unregister()
            attachedPlayer = player
            installSink(for: player)
            wireSubtitleGain(player)
            pictureInPictureController.rebindPlayer(player)
            return
        }
        detach()
        attachedPlayer = player
        installSink(for: player)
        wireSubtitleGain(player)
        // Initial subtitle render size follows the current bounds.
        subtitleLayerController.setRenderSize(bounds.size)
        player.setSubtitleRenderSize(
            width: Int(bounds.width), height: Int(bounds.height)
        )
        pictureInPictureController.bind(player: player, videoView: self)
    }

    private func wireSubtitleGain(_ player: MPlayPlayer) {
        player.onSubtitleGainChange = { [weak self] gain in
            self?.subtitleLayerController.brightnessGain = gain
        }
        player.onSubtitleOpacityChange = { [weak self] opacity in
            self?.subtitleLayerController.layer.opacity = Float(opacity)
        }
    }

    private func installSink(for player: MPlayPlayer) {
        let newSink = MPlayFrameSink(name: player.frameSinkName)
        newSink.onFrame = { [weak self] frame in
            self?.frameStore.update(frame)
        }
        newSink.register()
        sink = newSink
    }

    /// Unbind: unregister the sink FIRST (the vo must stop calling
    /// into this view), then flush pending frames.  The player core
    /// itself is closed by the owner after detach, as before.
    /// PiP: the dismantle path defers detach() until PiP has stopped,
    /// so an active PiP is never torn down from here in the normal
    /// flow; if detach is called while PiP is active anyway (player
    /// switch), unbind stops PiP first.
    func detach() {
        pictureInPictureController.unbind()
        sink?.unregister()
        sink = nil
        scheduler.flush()
        frameStore.flush()
        subtitleLayerController.clear()
        attachedPlayer?.onSubtitleGainChange = nil
        attachedPlayer?.onSubtitleOpacityChange = nil
        attachedPlayer = nil
        displayLink?.invalidate()
        displayLink = nil
        displayCriteriaAppliedGeneration = .max
        lastSyncedRate = -1
    }

    // MARK: - Time sync

    /// Explicit re-sync from the chrome (transport events, seeks).
    func syncPlaybackTime(position: Double, rate: Double) {
        scheduler.syncPlaybackTime(position: position, rate: rate)
        lastSyncedRate = rate
        lastSyncHostTime = CACurrentMediaTime()
    }

    /// Per-frame drift control: re-align the timebase when the
    /// player's rate changed since the last sync, or when a second
    /// has passed (cheap drift correction without a separate timer).
    private func nudgeTimeSync(with frame: MPlayFrame) {
        guard let player = attachedPlayer, frame.ptsSeconds >= 0 else { return }
        let state = player.state()
        let rate = state.paused ? 0 : 1.0
        let now = CACurrentMediaTime()
        if rate != lastSyncedRate || now - lastSyncHostTime > 1.0 {
            scheduler.syncPlaybackTime(position: frame.ptsSeconds, rate: rate)
            lastSyncedRate = rate
            lastSyncHostTime = now
            // Keep the post chain's DV profile current (drives the
            // Profile 5 correction pass; changes only per file).
            MPlayPostChain.shared.dolbyProfile = player.dolbyVisionProfile()?.profile ?? 0
            refreshDisplayCriteria()
        }
    }

    // MARK: - Mirrored output / display matching

    /// Feed this view's post-chain frames to a second view as well
    /// (the original's setMirroredRenderView(FrameOutputView?)).
    func setMirroredRenderView(_ view: MPlayVideoView?) {
        mirrorView = view
    }

    /// Intake for mirrored frames; enqueues directly (the mirror
    /// shows the primary's already-processed output).
    func receiveMirroredFrame(_ frame: MPlayFrame) {
        scheduler.enqueue(frame)
    }

    /// Display matching (the original's setFrameRateMatchingEnabled
    /// + clearDisplayCriteriaImmediately): when the player has
    /// matching enabled, a CADisplayLink carries the content frame
    /// rate as its preferred range — the iOS/ProMotion form of the
    /// original's display-criteria application (tvOS's
    /// AVDisplayCriteria has no iOS equivalent).  The criteria
    /// generation counter is the invalidation channel: changing the
    /// flag or clearing criteria bumps it, and the next 1-second
    /// nudge re-applies.  The link's tick also gives display-layer
    /// failure recovery a cadence independent of frame arrival.
    private func refreshDisplayCriteria() {
        guard let player = attachedPlayer else { return }
        let generation = player.displayCriteriaGeneration
        guard generation != displayCriteriaAppliedGeneration else { return }
        displayCriteriaAppliedGeneration = generation
        let fps = player.doubleProperty("container-fps") ?? 0
        if player.frameRateMatchingEnabled, fps > 0 {
            let link = displayLink ?? CADisplayLink(
                target: self, selector: #selector(displayLinkTick))
            displayLink = link
            let maxFPS = Double(UIScreen.main.maximumFramesPerSecond)
            let clamped = maxFPS > 0 ? min(fps, maxFPS) : fps
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(clamped), maximum: Float(clamped),
                preferred: Float(clamped))
            if link.isPaused {
                link.add(to: .main, forMode: .common)
                link.isPaused = false
            }
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    @objc private func displayLinkTick() {
        if displayLayer.status == .failed {
            scheduler.flush()
        }
    }

    // MARK: - Subtitle layer hosting (original: FrameOutputView)

    /// The view subtitles render into when the layer is not parented
    /// to the display layer.  Exposed for stage B (PiP host wiring).
    var subtitleLayer: CALayer {
        subtitleLayerController.layer
    }

    /// Move the subtitle layer into an external host view (PiP).
    /// The render size follows the host's bounds from here on.
    func moveSubtitleLayerToPictureInPictureHost(_ host: UIView) {
        externalSubtitleHost = host
        subtitleLayerController.layer.removeFromSuperlayer()
        host.layer.addSublayer(subtitleLayerController.layer)
        subtitleLayerController.layer.frame = host.bounds
        subtitleLayerController.setRenderSize(host.bounds.size)
    }

    /// Move the subtitle layer back to its inline home (the display
    /// layer) and restore the inline render size.
    func moveSubtitleLayerToInlineHost() {
        externalSubtitleHost = nil
        subtitleLayerController.layer.removeFromSuperlayer()
        displayLayer.addSublayer(subtitleLayerController.layer)
        subtitleLayerController.layer.frame = displayLayer.bounds
        subtitleLayerController.setRenderSize(bounds.size)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if externalSubtitleHost == nil {
            // Parented to the display layer: track its bounds.
            subtitleLayerController.layer.frame = displayLayer.bounds
            subtitleLayerController.setRenderSize(bounds.size)
        }
    }
}
