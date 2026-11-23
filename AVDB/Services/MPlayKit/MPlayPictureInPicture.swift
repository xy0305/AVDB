//
//  MPlayPictureInPicture.swift
//  AVDB
//
//  Build 353 full restoration, stage B: picture-in-picture, ported
//  from the original's design (IOS-FINDINGS §1): a
//  PictureInPictureController wrapped around
//  AVPictureInPictureController with a sample-buffer content source,
//  the full AVPictureInPictureSampleBufferPlaybackDelegate set
//  implemented against the player, Player-side time sync, an
//  audio-interruption recovery path, and subtitle-layer handling
//  around PiP transitions.  This is only possible because stage A
//  made the main display chain a pixel-frame chain
//  (CVPixelBuffer -> AVSampleBufferDisplayLayer); the old GL view
//  had no PiP path at all.
//
//  Ownership: MPlayVideoView owns this controller and binds it to
//  (player, view) on attach().  AVDB's MPlayKit chrome does not yet
//  reach into it (the minimal chrome has no PiP button); a future
//  chrome can hold a weak slot to the view's
//  pictureInPictureController, mirroring how the KSPlayer-era chrome
//  reached KSPlayerLayer's pipController.
//
//  Subtitle migration: in sample-buffer PiP the system renders the
//  display layer itself — there is no host view handed to the app —
//  so the subtitle layer stays parented to the display layer (its
//  default home since stage A) and IS carried into the PiP window.
//  What migrates semantically is the render size: on
//  didTransitionToRenderSize the subtitle render size is re-driven
//  to the PiP render size (the original's
//  updatePictureInPictureSubtitleRenderSize decoupling), and on
//  stop it returns to the inline size via the view's
//  moveSubtitleLayerToInlineHost().  If a host view is ever
//  supplied (pictureInPictureHostView), willStart moves the layer
//  there via moveSubtitleLayerToPictureInPictureHost(_:) instead —
//  the original's literal shape, kept available.
//

import AVFoundation
import AVKit
import CoreMedia
import Foundation
import UIKit

final class MPlayPictureInPictureController: NSObject {
    private weak var player: MPlayPlayer?
    private weak var videoView: MPlayVideoView?
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?

    private(set) var isActive = false
    private(set) var isPossible = false

    /// Latest PiP render size (points), from didTransitionToRenderSize.
    private(set) var latestRenderSize = CGSize.zero

    /// Optional external host for the subtitle layer during PiP
    /// (see the file header); nil in the standard sample-buffer flow.
    weak var pictureInPictureHostView: UIView?

    /// Fired on the main queue after PiP fully stops (the dismantle
    /// path polls isActive instead, like the KSPlayer-era code did;
    /// this hook is for chrome affordances).
    var onDidStop: (() -> Void)?

    // Audio interruption recovery (original: the private
    // PictureInPictureAudioSession actor + audioSessionInterrupted:
    // — merged into this controller here; audio *ownership* lives
    // in the host chrome (AVDB: PlaybackAudioLease on the KSPlayer
    // path), this only mirrors play state
    // across an interruption while PiP is up).
    private var wasPlayingBeforeAudioInterruption = false
    private var pendingAudioResumeTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    // Stage D: set by transfer(to:) when PiP was active on the
    // source instance; the target starts PiP once it becomes
    // possible after binding.
    private var pendingStartAfterTransfer = false
    private var pendingStartTask: Task<Void, Never>?

    // MARK: - Binding

    func bind(player: MPlayPlayer, videoView: MPlayVideoView) {
        unbind()
        self.player = player
        self.videoView = videoView
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: videoView.displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.requiresLinearPlayback = false
        self.controller = controller
        possibleObservation = controller.observe(
            \.isPictureInPicturePossible, options: [.initial, .new]
        ) { [weak self] controller, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPossible = controller.isPictureInPicturePossible
                if self.isPossible, self.pendingStartAfterTransfer {
                    self.pendingStartAfterTransfer = false
                    self.start()
                }
            }
        }
        installInterruptionObserver()
    }

    func unbind() {
        removeInterruptionObserver()
        pendingAudioResumeTask?.cancel()
        pendingAudioResumeTask = nil
        pendingStartTask?.cancel()
        pendingStartTask = nil
        possibleObservation = nil
        if isActive {
            controller?.stopPictureInPicture()
        }
        controller = nil
        isActive = false
        isPossible = false
    }

    // MARK: - Player-side API (original: Player)

    func startPictureInPicture() {
        start()
    }

    func stopPictureInPicture() {
        controller?.stopPictureInPicture()
    }

    var isPictureInPictureActive: Bool {
        controller?.isPictureInPictureActive ?? isActive
    }

    func setCanStartPictureInPictureAutomaticallyFromInline(_ value: Bool) {
        controller?.canStartPictureInPictureAutomaticallyFromInline = value
    }

    func start() {
        guard let controller, controller.isPictureInPicturePossible else {
            MPlayDiagnostics.log("pip: start requested but not possible")
            return
        }
        controller.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    func toggle() {
        if isPictureInPictureActive {
            stop()
        } else {
            start()
        }
    }

    /// Original: syncPictureInPicturePlaybackTime — re-align the
    /// display layer's timebase with the player clock.  Our frame
    /// path already nudges sync per frame; this is the explicit
    /// entry the delegate hooks call on transitions.
    func syncPictureInPicturePlaybackTime() {
        guard let player, let videoView else { return }
        let progress = player.progress()
        let rate = player.state().paused ? 0.0 : 1.0
        videoView.syncPlaybackTime(position: progress.time, rate: rate)
    }

    /// Original: transferPictureInPictureController(to:) — stage D's
    /// preload takeover moves PiP from the outgoing instance's
    /// controller to the incoming one's.  If PiP was active, the
    /// target re-starts it as soon as its own layer reports PiP
    /// possible after binding.
    func transfer(to target: MPlayPictureInPictureController) {
        let wasActive = isPictureInPictureActive
        if wasActive {
            stop()
        }
        target.pendingStartAfterTransfer = wasActive
        unbind()
    }

    /// Same-view player swap (stage D takeover on one view): the
    /// display layer — and therefore the PiP content source — does
    /// not change when the view re-attaches to a promoted preloaded
    /// player, so only the playback-delegate's player reference
    /// moves.  An active PiP session survives the swap untouched;
    /// this is the same-view fast path of transfer(to:).
    func rebindPlayer(_ newPlayer: MPlayPlayer) {
        player = newPlayer
    }

    // MARK: - Audio interruption (original: audioSessionInterrupted:)

    private func installInterruptionObserver() {
        removeInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }
        switch type {
        case .began:
            wasPlayingBeforeAudioInterruption = player.map { !$0.state().paused } ?? false
        case .ended:
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            if shouldResume, wasPlayingBeforeAudioInterruption, isPictureInPictureActive {
                pendingAudioResumeTask?.cancel()
                pendingAudioResumeTask = Task { [weak self] in
                    // Small settle delay: the audio route may still be
                    // re-configuring when the notification lands.
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    self?.player?.setPaused(false)
                }
            }
            wasPlayingBeforeAudioInterruption = false
        @unknown default:
            break
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension MPlayPictureInPictureController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        if let host = pictureInPictureHostView {
            videoView?.moveSubtitleLayerToPictureInPictureHost(host)
        }
        syncPictureInPicturePlaybackTime()
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isActive = true
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        isActive = false
        MPlayDiagnostics.log("pip: failed to start: \(error.localizedDescription)")
        videoView?.moveSubtitleLayerToInlineHost()
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {}

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isActive = false
        // Subtitle layer returns to its inline home and inline
        // render size (a no-op reparent when it never left — the
        // render size restore is the load-bearing part).
        videoView?.moveSubtitleLayerToInlineHost()
        syncPictureInPicturePlaybackTime()
        onDidStop?()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // AVDB's player screen is still in the hierarchy when PiP
        // stops from the PiP window's expand button (the dismantle
        // path defers teardown while PiP is active), so the UI is
        // already restored by construction.
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension MPlayPictureInPictureController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        player?.setPaused(!playing)
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        let duration = player?.progress().duration ?? 0
        if duration > 0 {
            return CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: duration, preferredTimescale: 90_000)
            )
        }
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        player?.state().paused ?? true
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        let size = CGSize(
            width: CGFloat(newRenderSize.width),
            height: CGFloat(newRenderSize.height)
        )
        latestRenderSize = size
        // The decoupled subtitle render size lands here: subtitles
        // re-render at the PiP window's render size, not the video's.
        // Routed through the view's subtitle controller so its
        // tracked size stays the single source of truth — its
        // onRenderSizeChanged forwards to the player's vo override,
        // and the stop path's restore to the inline size is detected
        // as a change against this value.
        videoView?.subtitleLayerController.setRenderSize(size)
        syncPictureInPicturePlaybackTime()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        guard let player else {
            completionHandler()
            return
        }
        let target = player.progress().time + CMTimeGetSeconds(skipInterval)
        player.seek(to: max(0, target)) {
            completionHandler()
        }
    }
}
