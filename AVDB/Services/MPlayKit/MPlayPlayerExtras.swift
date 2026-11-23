//
//  MPlayPlayerExtras.swift
//  AVDB
//
//  Build 353 (full restoration): the remainder of the original
//  Player's 99-method public surface that has a landing point in
//  AVDB's architecture, item by item.  Methods whose semantics
//  belong to the view or the preview reader live there instead
//  (MPlayCapture.swift, MPlayPreviewReader.swift) and are listed in
//  Build353-MPlayKit.md with their landing points; methods with no
//  landing at all are documented there with evidence, not stubbed
//  here.
//
//  Conventions: the original's async, source-scoped variants return
//  Int32 mpv-style codes.  Our core is single-source per instance,
//  so a `source` argument that does not match this instance returns
//  MPV_ERROR_INVALID_PARAMETER (-2); matching calls perform the
//  operation synchronously on the player queue and return 0.
//

import Foundation
import CoreGraphics

/// The original's PlaybackSource shape (load/open with subtitles).
struct MPlayPlaybackSource {
    var url: String
    var headers: [String: String] = [:]
    var startSeconds: Double = 0
}

/// The original's PlayerConfiguration (init(options:) equivalent).
struct MPlayPlayerConfiguration {
    var options: [String: String] = [:]
}

struct MPlayChapter {
    var index: Int
    var title: String
    var time: Double
}

struct MPlayTrackInfo {
    var id: Int64
    var kind: String
    var language: String
    var title: String
    var codec: String
    var external: Bool
    var selected: Bool
    var dolbyProfile: Int = 0
}

struct MPlayDiscInfo {
    var present: Bool
    var kind: String        // "bluray" / "dvd" / ""
    var titleCount: Int     // chapters as the enumerable proxy (see MPlayDisc)
}

/// The original's MediaInfo aggregate (source/tracks/chapters/
/// cache/disc), assembled from the live core.
struct MPlayMediaInfo {
    var source: Int64
    var duration: Double
    var title: String
    var tracks: [MPlayTrackInfo]
    var chapters: [MPlayChapter]
    var cache: [MPlayCacheRange]
    var dolbyVision: MPlayDolbyVisionState?
    var disc: MPlayDiscInfo
}

/// The original's EngineState shape (playbackState()).
struct MPlayEngineState {
    var source: Int64 = 0
    var state: String = ""
    var paused: Bool = false
    var seekable: Bool = false
    var duration: Double = 0
    var position: Double = 0
    var error: Int32 = 0
    var message: String = ""
    var backendError: Int32 = 0
    var commandError: Int32 = 0
    var decoder: String = ""
    var hwdec: String = ""
    var videoOutput: String = ""
    var audioOutput: String = ""
    var width: Int = 0
    var height: Int = 0
    var frames: Int64 = 0
    var hasAudio: Bool = false
    var cache: [MPlayCacheRange] = []
    var end: Bool = false
}

enum MPlayTrackSlot {
    case video, audio, subtitle, subtitleSecondary
}

enum MPlayTrackChoice {
    case auto, none, id(Int64)
}

// File-scope bookkeeping for the extension surface (extensions
// cannot hold stored properties).
private let extrasLock = NSLock()
private var decoderSwitchTargets: [UInt64: Bool] = [:]
private var activePreviewReaders: [ObjectIdentifier: MPlayPreviewReader] = [:]

extension MPlayPlayer {
    // MARK: - Construction / loading shapes

    convenience init(configuration: MPlayPlayerConfiguration) throws {
        try self.init(options: configuration.options)
    }

    /// load(URL) — fire-and-forget open.
    func load(_ url: URL) {
        open(url: url.absoluteString)
    }

    /// load(PlaybackSource, subtitles:) — open, then apply the
    /// subtitle settings once the file is loaded.
    func load(_ source: MPlayPlaybackSource,
              subtitles: SubtitleSettings? = nil) {
        open(url: source.url, startSeconds: source.startSeconds,
             headers: source.headers, autoplay: true) { [weak self] result in
            if case .success = result, let subtitles {
                self?.setSubtitleSettings(subtitles)
            }
        }
    }

    /// open(PlaybackSource, subtitles:) — returns this instance's
    /// source id immediately; loading proceeds like load().
    @discardableResult
    func open(_ source: MPlayPlaybackSource,
              subtitles: SubtitleSettings? = nil) async -> UInt64 {
        load(source, subtitles: subtitles)
        return UInt64(bitPattern: self.source)
    }

    /// pause(Bool) shape.
    func pause(_ paused: Bool) {
        setPaused(paused)
    }

    /// stop() — unload the current file (the core stays alive).
    func stop() {
        command(["stop"])
    }

    /// stopRendering() — in the pixel architecture, rendering is
    /// stopped by detaching the view (the sink unregisters and the
    /// vo goes idle); there is no player-side render loop to stop.
    /// Recorded as a diagnostics marker only — see the docs table.
    func stopRendering() {
        MPlayDiagnostics.log("stopRendering: view detach is the render stop in this architecture")
    }

    /// shutdown(flushRenderView:) — close() equivalent; the flush
    /// flag maps to the view's detach-time flush, which the owner
    /// performs before close.
    func shutdown(flushRenderView: Bool) {
        close()
    }

    // MARK: - Source-scoped async variants

    private func sourceMatches(_ candidate: Int64) -> Bool {
        candidate == 0 || candidate == source
    }

    func seek(to seconds: Double, accurate: Bool,
              source candidate: Int64) async -> Int32 {
        guard sourceMatches(candidate) else { return -2 }
        setProp("hr-seek", accurate ? "yes" : "no")
        return await withCheckedContinuation { continuation in
            seek(to: seconds) { continuation.resume(returning: 0) }
        }
    }

    func setSpeed(_ speed: Double, fps: Double,
                  source candidate: Int64) async -> Int32 {
        guard sourceMatches(candidate) else { return -2 }
        // The original's fps parameter is the display-rate hint used
        // by its speed compensation; our rate maps straight onto
        // mpv's speed property.  The hint is recorded for the
        // display-matching surface.
        if fps > 0 { setProp("display-fps-override", String(fps)) }
        setRate(speed)
        return 0
    }

    func setVolume(_ volume: Double, source candidate: Int64) async -> Int32 {
        guard sourceMatches(candidate) else { return -2 }
        setVolume(volume)
        return 0
    }

    func option(_ name: String, value: String,
                source candidate: Int64) async -> Int32 {
        guard sourceMatches(candidate) else { return -2 }
        return setProp(name, value)
    }

    // MARK: - Transport configuration

    /// configure(rate:volume:muted:audioDelay:source:) in one call.
    @discardableResult
    func configure(rate: Double, volume: Double, muted: Bool,
                   audioDelay: Double, source candidate: Int64) async -> Int32 {
        guard sourceMatches(candidate) else { return -2 }
        setRate(rate)
        setVolume(volume)
        setProp("mute", muted ? "yes" : "no")
        setAudioDelay(audioDelay)
        return 0
    }

    /// mpv volume scale (0–100, may exceed).
    func setVolume(_ volume: Double) {
        setProp("volume", String(volume))
    }

    func setAudioDelay(_ delay: Double) {
        setProp("audio-delay", String(delay))
    }

    /// setAudioOutputVolume: with updateCurrentOutput, the AO-side
    /// volume (ao-volume) is set as well as the stream volume.
    func setAudioOutputVolume(_ volume: Double, updateCurrentOutput: Bool) {
        setVolume(volume)
        if updateCurrentOutput {
            setProp("ao-volume", String(volume))
        }
    }

    /// option(_:value:) -> Bool and setOption(name:value:) shapes.
    @discardableResult
    func option(_ name: String, value: String) async -> Bool {
        setProp(name, value) == 0
    }

    func setOption(name: String, value: String) {
        setProp(name, value)
    }

    // MARK: - Hardware decode / VideoToolbox fault handling

    func setHardwareDecode(_ enabled: Bool) {
        setProp("hwdec", enabled ? "videotoolbox" : "no")
    }

    /// hwdec-software-fallback is an init-time option in mpv;
    /// setting it at runtime is attempted and the result logged
    /// (mpv may reject it until the next file).
    func setHardwareDecodeSoftwareFallback(_ enabled: Bool) {
        let rc = setProp("hwdec-software-fallback", enabled ? "yes" : "no")
        if rc != 0 {
            MPlayDiagnostics.log("hwdec-software-fallback runtime set rc=\(rc) (applies at next load at the latest)")
        }
    }

    /// beginDecoderSwitch(hardware:timeoutMS:) — switches the hwdec
    /// property (mpv applies it to the running decoder) and returns
    /// a token for decoderSwitchResult.  The original performs the
    /// switch inside its fork and reports completion itself; ours
    /// observes hwdec-current, which is the strongest signal stock
    /// mpv exposes (documented approximation).
    func beginDecoderSwitch(hardware: Bool, timeoutMS: Double) -> UInt64 {
        let token = beginDecoderSwitchRecord(hardware: hardware)
        extrasLock.lock()
        decoderSwitchTargets[token] = hardware
        extrasLock.unlock()
        setProp("hwdec", hardware ? "videotoolbox" : "no")
        _ = timeoutMS // the result poll below caps its own wait
        return token
    }

    func decoderSwitchResult(source token: UInt64) async -> Int32 {
        extrasLock.lock()
        let hardware = decoderSwitchTargets[token]
        extrasLock.unlock()
        guard let hardware else { return -2 }
        if decoderSwitchCompleted(token: token) { return 0 }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let current = progress().hwdecCurrent
            let reached = hardware
                ? current.contains("videotoolbox")
                : (current == "no" || current.isEmpty)
            if reached {
                markDecoderSwitchCompleted(token: token)
                return 0
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return -19
    }

    /// recoverVideoToolbox(to:) — the equivalent of the original's
    /// senplayer-recover-videotoolbox command: drop to software
    /// decode, reload the current file at the current position,
    /// then restore VideoToolbox once the reload lands.
    func recoverVideoToolbox(to timeoutSeconds: Double = 10) {
        guard let path = stringProperty("path"), !path.isEmpty else {
            MPlayDiagnostics.log("recoverVideoToolbox: no current file")
            return
        }
        let position = progress().time
        let wasPaused = state().paused
        setProp("hwdec", "no")
        open(url: path, startSeconds: position, headers: [:],
             autoplay: !wasPaused) { [weak self] result in
            if case .success = result {
                self?.setProp("hwdec", "videotoolbox")
            }
        }
        _ = timeoutSeconds
    }

    // MARK: - Display matching

    /// setFrameRateMatchingEnabled — state lives on the player; the
    /// attached view applies it (see MPlayVideoView
    /// refreshDisplayCriteria for the iOS form and its limits).
    func setFrameRateMatchingEnabled(_ enabled: Bool) {
        frameRateMatchingEnabled = enabled
    }

    /// clearDisplayCriteriaImmediately(reason:) — bumps the criteria
    /// generation so the view drops/rebuilds its display link on the
    /// next cadence tick.
    func clearDisplayCriteriaImmediately(reason: String) {
        MPlayDiagnostics.log("display criteria cleared: \(reason)")
        bumpDisplayCriteriaGeneration()
    }

    // MARK: - Chapters / media info / snapshots

    func chapters() -> [MPlayChapter] {
        let count = intProperty("chapter-list/count") ?? 0
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            MPlayChapter(
                index: Int(index),
                title: stringProperty("chapter-list/\(index)/title") ?? "",
                time: doubleProperty("chapter-list/\(index)/time") ?? 0
            )
        }
    }

    /// mediaInfo() — the aggregate surface; navigationInfo() is the
    /// same aggregate viewed for disc navigation in the original,
    /// and returns the same value here.
    func mediaInfo() -> MPlayMediaInfo {
        var tracks: [MPlayTrackInfo] = []
        let json = mediaJSON()
        var title = ""
        var duration = 0.0
        if let data = json.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data)
             as? [String: Any] {
            title = root["title"] as? String ?? ""
            duration = (root["duration"] as? NSNumber)?.doubleValue ?? 0
            if let rawTracks = root["tracks"] as? [[String: Any]] {
                tracks = rawTracks.map { entry in
                    MPlayTrackInfo(
                        id: (entry["id"] as? NSNumber)?.int64Value ?? 0,
                        kind: entry["kind"] as? String ?? "",
                        language: entry["language"] as? String ?? "",
                        title: entry["title"] as? String ?? "",
                        codec: entry["codec"] as? String ?? "",
                        external: entry["external"] as? Bool ?? false,
                        selected: entry["selected"] as? Bool ?? false
                    )
                }
            }
        }
        // Per-track DV profile rides the track-list properties, not
        // mediaJSON; stamp the selected video track's value.
        if let profile = dolbyVisionState.profile, let index = tracks.firstIndex(
            where: { $0.kind == "video" && $0.selected }) {
            tracks[index].dolbyProfile = profile
        }
        let path = stringProperty("path") ?? ""
        let discKind = path.hasPrefix("bd://") ? "bluray"
            : (path.hasPrefix("dvd://") ? "dvd" : "")
        let chapterList = chapters()
        return MPlayMediaInfo(
            source: source,
            duration: duration,
            title: title,
            tracks: tracks,
            chapters: chapterList,
            cache: cacheRanges(),
            dolbyVision: dolbyVisionState,
            disc: MPlayDiscInfo(
                present: !discKind.isEmpty,
                kind: discKind,
                titleCount: chapterList.count
            )
        )
    }

    func navigationInfo() -> MPlayMediaInfo {
        mediaInfo()
    }

    /// playbackState() — the EngineState aggregate.
    func playbackState() -> MPlayEngineState {
        let state = state()
        let progress = progress()
        let size = videoSize()
        var info = MPlayEngineState()
        info.source = source
        info.state = state.phase
        info.paused = state.paused
        info.seekable = state.seekable
        info.duration = progress.duration
        info.position = progress.time
        info.error = Int32(state.errorCode)
        info.message = state.failure
        info.hwdec = progress.hwdecCurrent
        info.decoder = stringProperty("video-codec") ?? ""
        info.videoOutput = stringProperty("current-vo") ?? ""
        info.audioOutput = stringProperty("current-ao") ?? ""
        info.width = Int(size?.width ?? 0)
        info.height = Int(size?.height ?? 0)
        info.frames = intProperty("estimated-frame-count") ?? 0
        info.cache = progress.cacheRanges
        info.end = state.phase == "ended"
        if let data = mediaJSON().data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data)
             as? [String: Any],
           let rawTracks = root["tracks"] as? [[String: Any]] {
            info.hasAudio = rawTracks.contains {
                ($0["kind"] as? String) == "audio"
            }
        }
        return info
    }

    /// playbackSnapshot() — the Progress aggregate (the original's
    /// PlaybackSnapshot's first twelve fields are exactly this).
    func playbackSnapshot() -> MPlayProgress {
        progress()
    }

    /// trackSnapshot() — the parsed track list.
    func trackSnapshot() -> [MPlayTrackInfo] {
        mediaInfo().tracks
    }

    /// select(_:slot:) — TrackChoice/TrackSlot selection over
    /// selectTrack ("auto" is a property value, not a track id, so
    /// it is written directly).
    func select(_ choice: MPlayTrackChoice, slot: MPlayTrackSlot) {
        let kind: MPlayTrackKind
        let property: String
        switch slot {
        case .video: kind = .video; property = "vid"
        case .audio: kind = .audio; property = "aid"
        case .subtitle: kind = .subtitle; property = "sid"
        case .subtitleSecondary: kind = .subtitleSecondary; property = "secondary-sid"
        }
        switch choice {
        case .auto: setProp(property, "auto")
        case .none: selectTrack(kind: kind, id: -1)
        case .id(let id): selectTrack(kind: kind, id: id)
        }
    }

    // MARK: - External subtitle files

    /// The managed external-subtitle directory (caches).
    static var externalSubtitleDirectory: URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MPlayKit/Subtitles",
                                              isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// prepareExternalSubtitleURL(data:id:name:fileExtension:) —
    /// writes the data into the managed directory and returns the
    /// file URL (the original's two URL overloads collapse here:
    /// AVDB's rule is the engine never fetches remote subtitle
    /// URLs itself, so URL inputs are the caller's downloaded file).
    func prepareExternalSubtitleURL(
        data: Data, id: String, name: String, fileExtension: String
    ) -> URL? {
        let safeID = id.replacingOccurrences(of: "/", with: "_")
        let url = Self.externalSubtitleDirectory
            .appendingPathComponent("\(safeID)-\(name)")
            .appendingPathExtension(fileExtension)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            MPlayDiagnostics.log("prepareExternalSubtitleURL failed: \(error)")
            return nil
        }
    }

    /// addSubtitle(data:id:name:fileExtension:select:) — prepare +
    /// sub-add.
    func addSubtitle(data: Data, id: String, name: String,
                     fileExtension: String, select: Bool) {
        guard let url = prepareExternalSubtitleURL(
            data: data, id: id, name: name, fileExtension: fileExtension)
        else { return }
        addSubtitle(url: url.path, select: select)
    }

    /// addSubtitle(url:title:source:) async -> the new track's id
    /// (the highest subtitle track id after the add), or -1.
    func addSubtitle(url: String, title: String?,
                     source candidate: Int64) async -> Int64 {
        guard sourceMatches(candidate) else { return -1 }
        addSubtitle(url: url, title: title, select: true)
        let ids = trackSnapshot()
            .filter { $0.kind == "subtitle" }.map(\.id)
        return ids.max() ?? -1
    }

    /// clearExternalSubtitleCache() — empties the managed directory.
    func clearExternalSubtitleCache() {
        let dir = Self.externalSubtitleDirectory
        guard let items = try? FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for item in items {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// removeSubtitle(_:source:) — sub-remove by track id.
    @discardableResult
    func removeSubtitle(_ id: Int64, source candidate: Int64) -> Int32 {
        guard sourceMatches(candidate) else { return -2 }
        return command(["sub-remove", String(id)])
    }

    // MARK: - Cache

    /// configureAuxiliaryCache() — re-applies the standard
    /// CachePolicy's mpv options to the running core.
    func configureAuxiliaryCache() {
        for (key, value) in MPlayCachePolicy.standard.mpvOptions {
            setProp(key, value)
        }
    }

    // MARK: - Preview (delegates to MPlayPreviewReader)

    /// preview(at:) — a still from the current file at the given
    /// time, via a short-lived configured reader over the same URL.
    func preview(at seconds: Double) async -> CGImage? {
        guard let reader = makePreviewReader() else { return nil }
        let id = ObjectIdentifier(self)
        extrasLock.lock()
        activePreviewReaders[id] = reader
        extrasLock.unlock()
        defer {
            extrasLock.lock()
            activePreviewReaders.removeValue(forKey: id)
            extrasLock.unlock()
        }
        return await withCheckedContinuation { continuation in
            reader.image(at: seconds) { result in
                continuation.resume(returning: try? result.get().cgImage())
            }
        }
    }

    /// requestThumbnail(at:fullScreen:completion:) — the still
    /// variant; fullScreen selects the taller reader height.
    func requestThumbnail(
        at seconds: Double, fullScreen: Bool,
        completion: @escaping (MPlayStill?) -> Void
    ) {
        guard let path = stringProperty("path"), !path.isEmpty else {
            completion(nil)
            return
        }
        let reader = MPlayPreviewReader()
        let id = ObjectIdentifier(self)
        extrasLock.lock()
        activePreviewReaders[id] = reader
        extrasLock.unlock()
        reader.still(url: path, at: seconds,
                     maxWidth: fullScreen ? 720 : 320,
                     correctDolbyP5: false, preferCover: false) { [weak self] result in
            if let self {
                extrasLock.lock()
                activePreviewReaders.removeValue(forKey: ObjectIdentifier(self))
                extrasLock.unlock()
            }
            completion(try? result.get())
        }
    }

    /// cancelPreview() — tears down this player's in-flight reader.
    func cancelPreview() {
        let id = ObjectIdentifier(self)
        extrasLock.lock()
        let reader = activePreviewReaders.removeValue(forKey: id)
        extrasLock.unlock()
        reader?.cancel()
    }

    private func makePreviewReader() -> MPlayPreviewReader? {
        guard let path = stringProperty("path"), !path.isEmpty
        else { return nil }
        let configuration = MPlayPreviewReaderConfiguration(
            url: path,
            headers: [:],
            height: 320,
            timeout: 15,
            percent: 15,
            preferCover: false,
            nativeImage: false
        )
        return MPlayPreviewReader(configuration: configuration)
    }
}
