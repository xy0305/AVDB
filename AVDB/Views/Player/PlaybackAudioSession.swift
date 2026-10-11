import Foundation
import AVFoundation
import AVKit
import SwiftUI
import KSPlayer

/// Pure shipping ownership policy, also executed by the CI regression harness.
struct PlaybackAudioOwnership {
    private(set) var owners: Set<UUID> = []
    private(set) var generation = 0
    mutating func acquire(_ id: UUID) {
        owners.insert(id)
        generation += 1
    }
    mutating func release(_ id: UUID) -> Int {
        owners.remove(id)
        generation += 1
        return generation
    }
    func mayDeactivate(_ token: Int) -> Bool {
        owners.isEmpty && generation == token
    }
}

/// Only concrete media playback owns the exclusive session, never app/page visibility.
@MainActor
final class PlaybackAudioSession {
    static let shared = PlaybackAudioSession()
    private var ownership = PlaybackAudioOwnership()
    private var active = false

    func acquire(_ id: UUID) {
        ownership.acquire(id)
        do {
            if !active {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            }
            // Also reassert after an OS interruption. Do not reset a live category on seek/source changes.
            try AVAudioSession.sharedInstance().setActive(true)
            active = true
        } catch {
            NSLog("AVDB playback audio activation failed: %@", error.localizedDescription)
        }
    }

    func release(_ id: UUID) {
        let token = ownership.release(id)
        // Coalesce SwiftUI source/episode replacement, including .id(url), without an audible session bounce.
        deactivateWhenIdle(token: token, attempts: 3)
    }

    private func deactivateWhenIdle(token: Int, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [self] in
            guard ownership.mayDeactivate(token), active else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                active = false
            } catch {
                NSLog("AVDB playback audio deactivation failed: %@", error.localizedDescription)
                if attempts > 1 { deactivateWhenIdle(token: token, attempts: attempts - 1) }
            }
        }
    }
}

@MainActor
final class PlaybackAudioLease: ObservableObject {
    private let id = UUID()
    func begin() { PlaybackAudioSession.shared.acquire(id) }
    func end() { PlaybackAudioSession.shared.release(id) }
    deinit {
        let id = id
        DispatchQueue.main.async { PlaybackAudioSession.shared.release(id) }
    }
}

/// The underlying representable's destruction, not onDisappear, is the terminal boundary.
/// KSAVPlayer/KSMEPlayer activate internally in their constructors and on resume;
/// acquire BEFORE makeView so those activations are accounted for by our owner.
struct AudioOwnedKSVideoPlayer: UIViewRepresentable {
    let player: KSVideoPlayer.Coordinator
    let audio: PlaybackAudioLease
    let url: URL
    let options: KSOptions
    let onStop: () -> Void
    final class Coordinator {
        let player: KSVideoPlayer.Coordinator
        let audio: PlaybackAudioLease
        let onStop: () -> Void
        init(player: KSVideoPlayer.Coordinator, audio: PlaybackAudioLease, onStop: @escaping () -> Void) {
            self.player = player
            self.audio = audio
            self.onStop = onStop
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(player: player, audio: audio, onStop: onStop) }
    func makeUIView(context: Context) -> UIView {
        audio.begin()
        return player.makeView(url: url, options: options)
    }
    func updateUIView(_ view: UIView, context: Context) {
        if player.playerLayer?.url != url {
            audio.begin()
            _ = player.makeView(url: url, options: options)
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        // Retain a detached, legitimate PiP player until PiP actually ends.
        // A mere background transition or temporary covering presentation does not dismantle this view.
        Task { @MainActor in
            while coordinator.player.playerLayer?.player.pipController?.isPictureInPictureActive == true {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            coordinator.onStop()
            coordinator.player.playerLayer?.pause()
            coordinator.player.resetPlayer()
            coordinator.audio.end()
        }
    }
}

/// Stable Apple VideoPlayer storage. Constructing the preview alone does not activate audio.
@MainActor
final class TrailerPlayback: ObservableObject {
    let player: AVPlayer
    private let audio = PlaybackAudioLease()
    private var observation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    init(url: URL) {
        player = AVPlayer(url: url)
        observation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            // Waiting is already a real play request. Pause retains ownership for instant resume.
            guard player.timeControlStatus != .paused else { return }
            Task { @MainActor [weak self] in
                guard let self, self.player.timeControlStatus != .paused,
                      self.player.currentItem?.status != .failed else { return }
                self.audio.begin()
            }
        }
        itemObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.finish() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finish() }
            }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finish() }
            }
    }
    func finish() {
        player.pause()
        audio.end()
    }
    deinit {
        observation?.invalidate()
        itemObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        player.pause()
        // audio lease deinit releases after the final player is stopped; no visibility hook needed.
    }
}

/// AVKit controls (same native controls as VideoPlayer), with an explicit PiP teardown boundary.
struct AudioOwnedTrailerPlayer: UIViewControllerRepresentable {
    let playback: TrailerPlayback
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let playback: TrailerPlayback
        var pictureInPicture = false
        init(_ playback: TrailerPlayback) { self.playback = playback }
        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            pictureInPicture = true
        }
        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            pictureInPicture = false
        }
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  failedToStartPictureInPictureWithError error: Error) {
            pictureInPicture = false
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(playback) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = playback.player
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        Task { @MainActor in
            while coordinator.pictureInPicture {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            coordinator.playback.finish()
            controller.player = nil
            controller.delegate = nil
        }
    }
}
