//
//  MPlayNowPlaying.swift
//  AVDB
//
//  Build 353 (full restoration): system Now Playing integration —
//  the surface the original exposes through its Apple-side helpers
//  (MPNowPlayingInfoCenter + MPRemoteCommandCenter).  The
//  coordinator owns one controller: it publishes title / duration /
//  position / rate on the poll cadence and routes remote commands
//  back into the coordinator's transport.  Next/previous track
//  commands are enabled only when the host provides handlers (the
//  chrome's episode/source pickers).
//

import Foundation
import MediaPlayer

@MainActor
final class MPlayNowPlayingController {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onNextTrack: (() -> Void)? {
        didSet { refreshCommandEnablement() }
    }
    var onPreviousTrack: (() -> Void)? {
        didSet { refreshCommandEnablement() }
    }

    private var tokens: [Any] = []
    private var active = false

    func activate() {
        guard !active else { return }
        active = true
        let center = MPRemoteCommandCenter.shared()
        tokens.append(center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPlay?() }
            return .success
        })
        tokens.append(center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPause?() }
            return .success
        })
        tokens.append(center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onTogglePlayPause?() }
            return .success
        })
        tokens.append(center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak self] in self?.onSeek?(position) }
            return .success
        })
        tokens.append(center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let handler = self?.onNextTrack else { return }
                handler()
            }
            return .success
        })
        tokens.append(center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let handler = self?.onPreviousTrack else { return }
                handler()
            }
            return .success
        })
        refreshCommandEnablement()
    }

    func deactivate() {
        guard active else { return }
        active = false
        let center = MPRemoteCommandCenter.shared()
        for token in tokens {
            center.playCommand.removeTarget(token)
            center.pauseCommand.removeTarget(token)
            center.togglePlayPauseCommand.removeTarget(token)
            center.changePlaybackPositionCommand.removeTarget(token)
            center.nextTrackCommand.removeTarget(token)
            center.previousTrackCommand.removeTarget(token)
        }
        tokens.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func refreshCommandEnablement() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = onNextTrack != nil
        center.previousTrackCommand.isEnabled = onPreviousTrack != nil
    }

    /// Publishes the current snapshot.  Called from the
    /// coordinator's poll (500 ms cadence) — cheap dictionary write.
    func update(title: String, duration: Double, position: Double,
                rate: Double, isPaused: Bool) {
        guard active else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, position),
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0 : rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
