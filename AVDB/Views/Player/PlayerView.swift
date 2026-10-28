//
//  PlayerView.swift
//  AVDB
//
//  KSPlayer SwiftUI render layer + AVDB-owned chrome and exclusive pan output.
//

import SwiftUI
import UIKit
import MediaPlayer
import AVFoundation
import KSPlayer

struct PlayerView: View {
    let movieID: String
    let sourceID: Int
    @StateObject private var vm: PlayerViewModel

    init(movieID: String, sourceID: Int) {
        self.movieID = movieID
        self.sourceID = sourceID
        _vm = StateObject(wrappedValue: PlayerViewModel(movieID: movieID, sourceID: sourceID))
    }

    var body: some View {
        Group {
            if let url = vm.streamURL {
                KSChromePlayer(
                    url: url,
                    title: vm.title,
                    subtitle: vm.currentQuality,
                    headers: vm.headers,
                    historyMovie: vm.historyMovie
                )
            } else if vm.isLoading {
                ProgressView("加载播放源…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else if let err = vm.errorMessage {
                ContentUnavailableView {
                    Label("无法播放", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("重试") { Task { await vm.load() } }
                }
            }
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.qualities.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(vm.qualities, id: \.self) { q in
                            Button(q) { vm.selectQuality(q) }
                        }
                    } label: {
                        Text(vm.currentQuality.isEmpty ? "清晰度" : vm.currentQuality)
                    }
                }
            }
        }
        .task { await vm.load(); await vm.loadHistoryMovie() }
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var playData: PlayData?
    @Published private(set) var historyMovie: Movie?

    func loadHistoryMovie() async {
        let account = APIClient.shared.token
        let movie = try? await sdk.movieDetail(movieID)
        guard !Task.isCancelled, APIClient.shared.token == account, movie?.id == movieID else { return }
        historyMovie = movie
    }
    @Published var currentEpisodeIndex = 1
    @Published var currentQuality = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var streamURL: URL?
    @Published var qualities: [String] = []

    let headers: [String: String] = [
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
        "Referer": "https://javdb.com/",
    ]

    private let sdk = JavDBSDK.shared
    let movieID: String
    let sourceID: Int
    var title: String { "第\(currentEpisodeIndex)集" }

    init(movieID: String, sourceID: Int) {
        self.movieID = movieID
        self.sourceID = sourceID
    }

    var currentEpisode: PlayData.Episode? {
        playData?.movies?.first { $0.index == currentEpisodeIndex }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            apply(try await sdk.moviePlay(movieID, sourceID: sourceID))
        } catch {
            if let data = try? await sdk.movieResumePlay(movieID, sourceID: sourceID),
               data.movies?.isEmpty == false {
                apply(data)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ data: PlayData) {
        playData = data
        if let first = data.movies?.first {
            currentEpisodeIndex = first.index
            let order = ["1080p", "720p", "480p", "360p"]
            qualities = order.filter { first.urls?[$0] != nil }
            if qualities.isEmpty { qualities = Array((first.urls ?? [:]).keys) }
            if let q = qualities.first { selectQuality(q) }
        }
    }

    func selectQuality(_ quality: String) {
        currentQuality = quality
        guard let url = currentEpisode?.urls?[quality]?.url, let u = URL(string: url) else { return }
        streamURL = u
    }
}

/// 横屏铺满 + 进度条 + 左亮度右音量。
struct KSChromePlayer: View {
    let url: URL
    var title: String = ""
    var subtitle: String = ""
    var headers: [String: String] = [:]
    /// Online-session opt-in only. Nil leaves AVPlayerItem unconstrained, including 115 and catalog playback.
    var onlineQuality: OnlineQualityChoice? = nil
    var progressID: String? = nil
    var supportsFramePreview: Bool = true
    var onPlaybackFailure: (() -> Void)? = nil
    // A source child must not restore portrait while its owning playback route remains alive.
    var managesOrientation: Bool = true
    var onSelectSource: (() -> Void)? = nil
    var onSelectEpisode: (() -> Void)? = nil
    @State private var failureReported = false
    @State private var playbackDiagnostic: PlaybackDiagnostic?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @StateObject private var audio = PlaybackAudioLease()
    @StateObject private var lut = NativeLUTController()
    @StateObject private var seekPreview = SeekPreviewController()
    var publicSubtitleQuery: String = "" // Explicit public metadata only; never infer from URL/title/path.
    var onVideoMetrics: ((URL, PlaybackVideoMetrics?, Bool) -> Void)? = nil
    var historyMovie: Movie? = nil
    var historyArtwork: UIImage? = nil
    @State private var historyGate = PlaybackHistoryStartGate()
    @State private var historyScope = PlaybackHistoryStore.shared.scope
    @State private var historyToken = APIClient.shared.token
    @State private var lastVideoMetrics: PlaybackVideoMetrics?
    @State private var metricsSettled = false
    @State private var qualityGeneration = 0
    @State private var appliedQuality: OnlineQualityChoice?
    @State private var observedResolution: CGSize = .zero
    @StateObject private var onlineSubtitles = OnlineSubtitleModel()
    @State private var showOnlineSubtitles = false
    @State private var editingSubtitlePosition = false
    @State private var adjustSubtitleAfterDismiss = false
    @State private var showLUT = false
    @State private var playbackActive = false
    @State private var isPlaying = false
    @State private var isBuffering = true
    @State private var hasStarted = false
    @State private var showChrome = true
    @State private var hideTask: Task<Void, Never>?
    @State private var tickTask: Task<Void, Never>?

    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var isSeeking = false
    @State private var seekValue: Double = 0

    @State private var overlay: OverlayKind?
    @State private var overlayValue: Double = 0
    @State private var adjustmentNotice: String?
    @State private var seekPending = false
    @State private var seekGeneration = 0
    @State private var horizontalDrag = false
    @State private var scrubStart: Double = 0
    @State private var skipHUD: SkipHUD?
    @State private var fillMode: FillMode = .fit

    private enum OverlayKind { case brightness, volume, seek }
    private enum FillMode: String, CaseIterable {
        case fit = "适应屏幕"
        case fill = "填满屏幕"
        case stretch = "拉伸填满"
    }
    private struct SkipHUD: Equatable {
        var forward: Bool
        var seconds: Int
    }

    private var playerOptions: KSOptions {
        KSOptions.logger = PlaybackPrivateLogger()
        let o = KSOptions()
        if !headers.isEmpty { o.appendHeader(headers) }
        if let ua = headers["User-Agent"] { o.userAgent = ua }
        if let referer = headers["Referer"] { o.referer = referer }
        KSOptions.isAutoPlay = true
        o.videoAdaptable = fillMode != .stretch
        o.canStartPictureInPictureAutomaticallyFromInline = false
        return o
    }

    var body: some View {
        GeometryReader { geo in
            videoArea(height: geo.size.height, width: geo.size.width, safeArea: geo.safeAreaInsets)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay(alignment: .top) {
            if let playbackDiagnostic {
                Text(playbackDiagnostic.display)
                    .font(.caption).foregroundStyle(.white)
                    .padding(10).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 54).padding(.horizontal)
                    .accessibilityIdentifier("player.safe-diagnostic")
                    .allowsHitTesting(false)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .background { if managesOrientation { PlaybackOrientationHost().allowsHitTesting(false) } }
        .sheet(isPresented: $showOnlineSubtitles, onDismiss: {
            showChrome = true
            startTicker()
            scheduleHide()
            if adjustSubtitleAfterDismiss {
                adjustSubtitleAfterDismiss = false
                editingSubtitlePosition = true
                showChrome = false
                hideTask?.cancel()
            }
        }) { OnlineSubtitlePanel(model: onlineSubtitles, adjustPosition: {
            adjustSubtitleAfterDismiss = true
            showOnlineSubtitles = false
        }) }
        .onChange(of: showOnlineSubtitles) { _, presented in
            if presented { cancelPlayerDrag(); hideTask?.cancel(); showChrome = true }
        }
        .sheet(isPresented: $showLUT, onDismiss: {
            // Sheet dismissal is not a playback-route exit. Preserve item, LUT and orientation.
            lut.setPanelCovered(false)
            showChrome = true
            startTicker()
            scheduleHide()
        }) { NativeLUTPanel(model: lut) }
        .onChange(of: showLUT) { _, presented in
            lut.setPanelCovered(presented)
            if presented { cancelPlayerDrag(); hideTask?.cancel(); showChrome = true }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            configureSeekPreview()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--subtitle-controls-fixture"), !ProcessInfo.processInfo.arguments.contains("--subtitle-no-cue") {
                onlineSubtitles.cues = [.init(start: 0, end: 120, text: "中性字幕样式测试\n第二行保留完整文本")]
            }
            #endif
            guard !playbackActive else {
                showChrome = true
                startTicker()
                return
            }
            playbackActive = true
            coordinator.isMaskShow = false
            // Audio ownership starts in AudioOwnedKSVideoPlayer.makeUIView, before KSPlayer construction.
            wireCoordinator()
            startTicker()
            scheduleHide()
        }
        .onChange(of: progressID) { _, _ in onlineSubtitles.clear() }
        .onChange(of: publicSubtitleQuery) { _, _ in onlineSubtitles.clear() }
        .onChange(of: url) { _, _ in
            qualityGeneration += 1
            appliedQuality = nil
            observedResolution = .zero
            playbackDiagnostic = nil
            failureReported = false
            editingSubtitlePosition = false
            onlineSubtitles.clear()
            seekGeneration += 1
            seekPending = false
            cancelPlayerDrag()
            configureSeekPreview()
        }
        .onChange(of: headers) { _, _ in
            cancelPlayerDrag()
            configureSeekPreview()
        }
        .onChange(of: supportsFramePreview) { _, _ in
            cancelPlayerDrag()
            configureSeekPreview()
        }
        .onDisappear {
            seekPreview.close()
            // UIKit full-screen/adaptive sheet presentations may disappear the presenter.
            // They must not tear down playback or force the whole app to portrait.
            guard !showLUT else { return }
            guard !showOnlineSubtitles else { return }
            // Visibility is not lifetime: background/PiP/covering presentations must keep playing.
            cancelPlayerDrag()
            hideTask?.cancel()
            tickTask?.cancel()
        }
    }

    private func configureSeekPreview() {
        seekPreview.configure(url: url, headers: headers, supported: supportsFramePreview)
    }

    private func stopPlayback() {
        onlineSubtitles.clear()
        seekPreview.close()
        playbackActive = false
        seekGeneration += 1
        seekPending = false
        cancelPlayerDrag()
        hideTask?.cancel()
        tickTask?.cancel()
        lut.detach()
        coordinator.playerLayer?.pause()
    }

    @ViewBuilder
    private func videoArea(height: CGFloat, width: CGFloat, safeArea: EdgeInsets) -> some View {
        ZStack {
            Color.black
            AudioOwnedKSVideoPlayer(player: coordinator, audio: audio, url: url, options: playerOptions, onStop: stopPlayback)
                .onAppear { applyFillMode() }
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let clock = coordinator.playerLayer?.player.currentPlaybackTime ?? 0
                let text = OnlineSubtitleParser.display(onlineSubtitles.cues, at: clock, offset: onlineSubtitles.offset)
                SubtitlePresentationOverlay(text: text, safeArea: safeArea, editing: editingSubtitlePosition) {
                    editingSubtitlePosition = false
                    showChrome = true
                    scheduleHide()
                }
            }.zIndex(editingSubtitlePosition ? 30 : 20) // Captions remain white above the chrome scrim; normal mode is noninteractive.
            if showChrome {
                chromeOverlay.zIndex(10) // Controls are above the transparent gesture receiver.
                    .padding(.top, safeArea.top)
                    .padding(.leading, safeArea.leading)
                    .padding(.trailing, safeArea.trailing)
                    .padding(.bottom, safeArea.bottom)
            }
            // KSVideoPlayer renders only the underlying player view (no official pan).
            // This transparent sibling owns the only pan output; chrome stays above it.
            PlayerGestureLayer(
                excludedTop: safeArea.top + 80,
                excludedBottom: safeArea.bottom + 116,
                blocked: editingSubtitlePosition || showOnlineSubtitles || showLUT || seekPending || (isSeeking && !horizontalDrag),
                sourceID: url,
                onDoubleTap: { x, width in
                    AVDBDoubleTapPolicy.perform(x: x, width: width,
                        toggle: { toggleActualPlayback() }, seek: { skip(by: $0) })
                },
                onSingleTap: { toggleChrome() },
                onAdjustment: { side, value, notice in
                    hideTask?.cancel()
                    adjustmentNotice = notice
                    if let value {
                        overlay = side == .brightness ? .brightness : .volume
                        overlayValue = Double(value)
                    } else { overlay = nil }
                },
                onSeekChanged: { dx in handleHorizontalDrag(dx) },
                onEnded: { cancelled in
                    if horizontalDrag && !cancelled {
                        seek(to: seekValue)
                        currentTime = seekValue
                    }
                    cancelPlayerDrag()
                    if showChrome { scheduleHide() }
                }
            )
            if !hasStarted {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)
                    .allowsHitTesting(false)
            }
            if let overlay {
                overlayHUD(overlay)
                    .allowsHitTesting(false)
            }
            if let adjustmentNotice {
                Text(adjustmentNotice)
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
            }
            if let skipHUD {
                skipOverlay(skipHUD)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
    }

    private func cancelPlayerDrag() {
        seekPreview.cancel()
        isSeeking = false
        horizontalDrag = false
        overlay = nil
        adjustmentNotice = nil
    }

    private func handleHorizontalDrag(_ dx: CGFloat) {
        guard !seekPending, duration.isFinite, duration > 0 else { return }
        if !horizontalDrag {
            horizontalDrag = true
            isSeeking = true
            scrubStart = currentTime
            seekValue = currentTime
            hideTask?.cancel()
        }
        // Preserve AVDB's duration-dependent horizontal seek scale and bounded preview.
        let secondsPerPoint = duration > 3600 ? 0.55 : 0.35
        seekValue = min(duration, max(0, scrubStart + Double(dx) * secondsPerPoint))
        overlayValue = seekValue
        seekPreview.request(time: seekValue, duration: duration)
        overlay = .seek
    }

    /// Read the engine now, not the asynchronously refreshed chrome state.
    private func toggleActualPlayback() {
        guard let layer = coordinator.playerLayer else { return }
        if layer.player.isPlaying {
            layer.pause()
        } else {
            audio.begin()
            layer.play()
        }
        if showChrome { scheduleHide() }
    }

    private func skip(by seconds: Double) {
        let next = min(max(duration, 0), max(0, currentTime + seconds))
        seek(to: next)
        currentTime = next
        let forward = seconds > 0
        if skipHUD?.forward == forward {
            skipHUD?.seconds += Int(abs(seconds))
        } else {
            skipHUD = SkipHUD(forward: forward, seconds: Int(abs(seconds)))
        }
        hideTask?.cancel()
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            skipHUD = nil
            if showChrome { scheduleHide() }
        }
    }

    private func skipOverlay(_ hud: SkipHUD) -> some View {
        HStack {
            if hud.forward { Spacer() }
            VStack(spacing: 6) {
                Image(systemName: hud.forward ? "goforward.10" : "gobackward.10")
                    .font(.system(size: 28, weight: .semibold))
                Text("\(hud.seconds) 秒")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(.black.opacity(0.45), in: Circle())
            .padding(.horizontal, 28)
            if !hud.forward { Spacer() }
        }
    }

    @ViewBuilder
    private func overlayHUD(_ kind: OverlayKind) -> some View {
        if kind == .seek {
            seekHUD
        } else {
            levelHUD(kind)
        }
    }

    private var seekHUD: some View {
        seekPreviewCard.frame(width: 192)
    }

    private var seekPreviewCard: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.black.opacity(0.8)
                if let image = seekPreview.image {
                    Image(decorative: image, scale: 1)
                        .resizable().aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: 5) {
                        if seekPreview.loading { ProgressView().tint(.white) }
                        Text(seekPreview.loading ? "正在提取画面…" : "此位置暂无预览")
                            .font(.caption2)
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            Text("\(formatTime(seekValue)) / \(formatTime(duration))")
                .font(.caption.monospacedDigit().weight(.semibold))
            Text("原始画面 · 不含 LUT")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("player.seek.preview")
        .allowsHitTesting(false)
    }

    private func levelHUD(_ kind: OverlayKind) -> some View {
        VStack(spacing: 10) {
            Image(systemName: kind == .brightness
                  ? (overlayValue > 0.5 ? "sun.max.fill" : "sun.min.fill")
                  : (overlayValue > 0.01 ? "speaker.wave.2.fill" : "speaker.slash.fill"))
                .font(.system(size: 22, weight: .semibold))
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 6, height: 90)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white)
                        .frame(height: 90 * overlayValue)
                }
                .clipShape(Capsule())
            Text("\(Int(overlayValue * 100))%")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .zIndex(20)

                Text(title.isEmpty ? "正在播放" : title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Button {
                    if onlineSubtitles.query.isEmpty { onlineSubtitles.query = String(publicSubtitleQuery.prefix(200)) }
                    showOnlineSubtitles = true
                } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white).frame(width: 48, height: 48)
                        .background(.black.opacity(0.35), in: Capsule())
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .fixedSize().layoutPriority(2).zIndex(20)
                    .accessibilityLabel("在线字幕").accessibilityIdentifier("player.subtitle.settings")
                Button { showLUT = true } label: {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(lut.enabled ? Color.white.opacity(0.22) : Color.black.opacity(0.35), in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(2)
                .zIndex(20)
                .accessibilityLabel("LUT 调色设置")
                .accessibilityIdentifier("player.lut.settings")
                Spacer(minLength: 8)

                Menu {
                    if !AdaptiveLayout.isPad {
                    Button("横屏全屏") {
                        OrientationLock.set(.landscapeRight, keepLocked: true)
                    }
                    Button("竖屏播放") {
                        OrientationLock.set(.portrait, keepLocked: true)
                    }
                    }
                    Divider()
                    ForEach(FillMode.allCases, id: \.self) { mode in
                        Button {
                            fillMode = mode
                            applyFillMode()
                        } label: {
                            if fillMode == mode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Text(mode.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.leading, 12)

            // The UIKit single/double recognizers own the empty video area even with chrome visible.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            progressBar
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button {
                    if isPlaying {
                        coordinator.playerLayer?.pause()
                    } else {
                        audio.begin()
                        coordinator.playerLayer?.play()
                    }
                } label: {
                    Group {
                        if isBuffering {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "暂停" : "播放")
                .accessibilityIdentifier("player.play.toggle")

                Button {
                    seek(to: min((isSeeking ? seekValue : currentTime) + 10, max(duration, 0)))
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)

                Spacer()

                if let onSelectEpisode {
                    Button(action: onSelectEpisode) {
                        Image(systemName: "rectangle.stack.badge.play")
                            .foregroundStyle(.white).frame(width: 48, height: 48)
                    }.buttonStyle(.plain)
                        .foregroundStyle(.white).tint(.white)
                        .accessibilityLabel("选择集数")
                        .accessibilityIdentifier("player.episode.settings")
                }
                if let onSelectSource {
                    Button(action: onSelectSource) {
                        Text(subtitle.isEmpty ? "播放源" : subtitle)
                            .font(.caption.weight(.medium)).lineLimit(1)
                            .frame(maxWidth: 180)
                            .frame(minHeight: 48)
                    }.buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .accessibilityLabel("选择播放源")
                        .accessibilityIdentifier("player.source.settings")
                } else if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                if onlineQuality != nil {
                    Text(onlineQualityStatus)
                        .font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        .accessibilityIdentifier("player.online-quality-status")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .padding(.top, 6)
        }
        .background {
            LinearGradient(
                colors: [Color.black.opacity(0.55), .clear, .clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            Text(formatTime(isSeeking ? seekValue : currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                Slider(
                    value: Binding(
                        get: { isSeeking ? seekValue : currentTime },
                        set: { newValue in
                            guard !seekPending, duration.isFinite, duration > 0 else { return }
                            isSeeking = true
                            seekValue = min(duration, max(0, newValue))
                            seekPreview.request(time: seekValue, duration: duration)
                        }
                    ),
                    in: 0...max(duration, 0.1)
                ) { editing in
                    if editing {
                        guard !seekPending, duration.isFinite, duration > 0 else { return }
                        hideTask?.cancel()
                        if !isSeeking { seekValue = min(duration, max(0, currentTime)) }
                        isSeeking = true
                        seekPreview.request(time: seekValue, duration: duration)
                    } else if isSeeking && !horizontalDrag {
                        seek(to: seekValue)
                        currentTime = seekValue
                        isSeeking = false
                        seekPreview.cancel()
                        scheduleHide()
                    }
                }
                .disabled(seekPending || duration <= 0)
                .contentShape(Rectangle())
                .tint(.white)
                .controlSize(.small)
                .accessibilityIdentifier("player.progress")
                // SwiftUI Slider only seeks via thumb drag; tap the track to jump (UISlider-style).
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { event in
                        tapSeekProgress(atX: event.location.x, width: geo.size.width)
                    }
                )
                .overlay {
                    GeometryReader { geometry in
                        if isSeeking && !horizontalDrag {
                            let cardWidth = min(192.0, max(0, geometry.size.width - 16))
                            let fraction = min(1, max(0, seekValue / max(duration, 0.1)))
                            let half = cardWidth / 2 + 8
                            seekPreviewCard
                                .frame(width: cardWidth)
                                .position(x: min(max(half, geometry.size.width * fraction), geometry.size.width - half), y: -82)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 34)
            Text(formatTime(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(
            in: Capsule(),
            tint: .black,
            tintStrength: 0.18,
            elevation: 0.4
        )
    }

    /// Map a tap on the progress track to an absolute seek. Drag continues to use Slider editing.
    private func tapSeekProgress(atX x: CGFloat, width: CGFloat) {
        guard !seekPending, !horizontalDrag, duration.isFinite, duration > 0, width > 0 else { return }
        let fraction = min(1, max(0, Double(x / width)))
        let target = duration * fraction
        hideTask?.cancel()
        seekValue = target
        seek(to: target)
        currentTime = target
        isSeeking = false
        seekPreview.cancel()
        scheduleHide()
    }

    private func glassButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: 48, height: 48)
                .liquidGlass()
        }
        .pressableGlass(scale: 0.9)
        .contentShape(Circle())
    }

    private func capsuleButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: 48, height: 48)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .liquidGlass()
        }
        .pressableGlass(scale: 0.9)
    }

    private func applyFillMode() {
        guard let player = coordinator.playerLayer?.player else { return }
        switch fillMode {
        case .fit:
            player.contentMode = .scaleAspectFit
        case .fill:
            player.contentMode = .scaleAspectFill
        case .stretch:
            player.contentMode = .scaleToFill
        }
    }

    private func wireCoordinator() {
        coordinator.isMaskShow = false
        coordinator.onFinish = { layer, error in
            guard let error else { return }
            // Reduce synchronously; never move NSError/userInfo into UI state or logs.
            let safe = PlaybackDiagnostic.system(error, stage: .decode, url: url)
            Task { @MainActor in
                guard playbackActive, coordinator.playerLayer === layer else { return }
                playbackDiagnostic = safe
            }
        }
        coordinator.onStateChanged = { layer, state in
            Task { @MainActor in
                // Ignore stale completion from a source that has already been replaced.
                guard coordinator.playerLayer === layer else { return }
                if state.isPlaying { audio.begin() } // Includes system remote/PiP resume after completion.
                if state == .playedToTheEnd || state == .error {
                    guard layer.state == state else { return } // A newer source/retry already superseded this terminal event.
                    // Stop output without overwriting KSPlayerLayer's terminal state: play() must
                    // still see playedToTheEnd (seek to zero) / error (prepare retry).
                    layer.player.pause()
                    audio.end()
                }
                if state == .error, !failureReported {
                    if playbackDiagnostic == nil {
                        playbackDiagnostic = PlaybackDiagnostic(stage: .decode, category: .unknown,
                            host: PlaybackDiagnostic.resourceHost(url))
                    }
                    failureReported = true
                    onPlaybackFailure?()
                }
                isPlaying = state.isPlaying
                isBuffering = state == .buffering || state == .preparing
                if state.isPlaying || state == .readyToPlay || state == .paused {
                    hasStarted = true
                }
                if state == .readyToPlay {
                    if let progressID, let saved = PlaybackProgressStore.progress(for: progressID), saved.time >= 5 {
                        seekGeneration += 1
                        let token = seekGeneration
                        seekPending = true
                        coordinator.playerLayer?.seek(time: saved.time, autoPlay: true) { _ in
                            Task { @MainActor in
                                guard seekGeneration == token else { return }
                                seekPending = false
                            }
                        }
                    }
                    audio.begin()
                    coordinator.playerLayer?.play()
                    applyOnlineQuality()
                    applyFillMode()
                    syncTime()
                }
            }
        }
    }

    private func startTicker() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                syncTime()
                if let movie = historyMovie, APIClient.shared.token == historyToken,
                   historyGate.sample(time: currentTime, playing: coordinator.playerLayer?.player.isPlaying == true,
                                      seeking: isSeeking || seekPending, failed: failureReported) {
                    PlaybackHistoryStore.shared.record(movie, artwork: historyArtwork, scope: historyScope)
                }
                applyOnlineQuality()
                publishVideoMetrics(timedOut: Date().timeIntervalSince(start) > 30)
                if !hasStarted, !failureReported, Date().timeIntervalSince(start) > 30, onPlaybackFailure != nil {
                    failureReported = true
                    onPlaybackFailure?()
                }
                lut.tick(coordinator.playerLayer?.player as? KSAVPlayer)
            }
        }
    }

    @MainActor
    private func applyOnlineQuality() {
        guard let choice = onlineQuality, let av = coordinator.playerLayer?.player as? KSAVPlayer,
              let item = av.player.currentItem else { return }
        let generation = qualityGeneration
        let applied = OnlineQualitySession.apply(peakBitRate: choice.peakBitRate, maximumResolution: choice.maximumResolution, label: choice.label, generation: generation, to: item)
        guard generation == qualityGeneration else { return }
        appliedQuality = choice
        _ = applied
        let presented = item.presentationSize
        if presented.width > 1, presented.height > 1 { observedResolution = presented }
    }

    var onlineQualityStatus: String {
        OnlinePlaybackQualityStatus.display(mode: (appliedQuality ?? onlineQuality)?.mode.rawValue ?? "automatic", label: (appliedQuality ?? onlineQuality)?.label ?? "自动", cap: (appliedQuality ?? onlineQuality)?.maximumResolution, observed: observedResolution)
    }

    @MainActor
    private func publishVideoMetrics(timedOut: Bool) {
        guard onVideoMetrics != nil, playbackActive else { return }
        var value: PlaybackVideoMetrics?
        if let engine = coordinator.playerLayer?.player {
            if let av = engine as? KSAVPlayer {
                // Public KSAVPlayer.player is AVQueuePlayer. Unlike KS naturalSize
                // (loaded asset track), presentationSize follows the playing HLS rendition.
                let size = av.player.currentItem?.presentationSize ?? .zero
                value = PlaybackVideoMetrics(width: Double(size.width), height: Double(size.height), evidence: .presentation)
            } else {
                // KSMEPlayer exposes selected-track naturalSize, not per-frame evidence.
                let size = engine.naturalSize
                value = PlaybackVideoMetrics(width: Double(size.width), height: Double(size.height), evidence: .track)
            }
        }
        let settled = hasStarted || timedOut || failureReported
        guard value != lastVideoMetrics || settled != metricsSettled else { return }
        lastVideoMetrics = value
        metricsSettled = settled
        onVideoMetrics?(url, value, settled)
    }

    private func syncTime() {
        guard !isSeeking, !seekPending, let layer = coordinator.playerLayer else { return }
        currentTime = layer.player.currentPlaybackTime
        let d = layer.player.duration
        if d.isFinite, d > 0 { duration = d }
        if let progressID {
            PlaybackProgressStore.save(movieID: progressID, time: currentTime, duration: duration)
        }
    }

    private func seek(to time: TimeInterval) {
        guard let layer = coordinator.playerLayer, time.isFinite else { return }
        seekGeneration += 1
        let token = seekGeneration
        seekPending = true
        if layer.options.isSeekedAutoPlay { audio.begin() }
        layer.seek(time: time, autoPlay: layer.options.isSeekedAutoPlay) { _ in
            Task { @MainActor in
                guard seekGeneration == token else { return }
                seekPending = false
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "00:00" }
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func toggleChrome() {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
        if showChrome { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showChrome = false }
        }
    }
}

/// Route lifetime, not source-item or sheet visibility, owns orientation.
struct PlaybackOrientationHost: UIViewControllerRepresentable {
    final class Controller: UIViewController {
        var entered = false
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !entered else { return }
            entered = true
            OrientationLock.set(.landscapeRight, keepLocked: true)
        }
    }
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        if controller.entered { OrientationLock.set(.portrait, keepLocked: true) }
    }
}

@MainActor
enum OrientationLock {
    private static var generation = 0
    static func set(_ mask: UIInterfaceOrientationMask, keepLocked: Bool = false) {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        generation += 1
        let token = generation
        let target: UIInterfaceOrientationMask = UIDevice.current.userInterfaceIdiom == .pad && mask == .portrait ? .all : mask
        KSOptions.supportedInterfaceOrientations = target
        request(target, token: token, attempt: 0)
    }
    private static func request(_ mask: UIInterfaceOrientationMask, token: Int, attempt: Int) {
        guard token == generation else { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var host = root
        while let presented = host.presentedViewController, !presented.isBeingDismissed { host = presented }
        // Refresh the entire presentation chain: SwiftUI's presenting controller also votes.
        root.setNeedsUpdateOfSupportedInterfaceOrientations()
        host.setNeedsUpdateOfSupportedInterfaceOrientations()
        if let parent = host.parent { parent.setNeedsUpdateOfSupportedInterfaceOrientations() }
        if mask != .all, host.viewIfLoaded?.window != nil, !host.isBeingDismissed, !host.isBeingPresented {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
        // Presentation may still be animating on entry. Bounded retries are cancelled by exit.
        guard attempt < 5, !mask.contains(UIInterfaceOrientationMask(rawValue: 1 << scene.interfaceOrientation.rawValue)) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            request(mask, token: token, attempt: attempt + 1)
        }
    }
}

/// Best-effort public UIKit adapter, not an Apple-guaranteed system-volume API.
/// Keep the real MPVolumeView nonhidden, alpha 1, in this player's live scene.
private final class PlayerVolumeView: MPVolumeView {
    init() {
        super.init(frame: CGRect(x: -120, y: 0, width: 100, height: 44))
        showsRouteButton = false
        showsVolumeSlider = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout(); layoutIfNeeded()
    }
    private func slider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        return view.subviews.lazy.compactMap { self.slider(in: $0) }.first
    }
    func submit(_ value: CGFloat) -> Bool {
        guard window != nil, !isHidden, alpha == 1 else { return false }
        setNeedsLayout(); layoutIfNeeded()
        guard let slider = slider(in: self), slider.window === window, slider.isEnabled else { return false }
        slider.setValue(Float(min(1, max(0, value))), animated: false)
        slider.sendActions(for: .valueChanged)
        return true // submitted request, not an independent hardware measurement
    }
}

struct PlayerGestureLayer: UIViewRepresentable {
    final class GestureView: UIView {
        fileprivate let volume = PlayerVolumeView()
        var cancelPan: (() -> Void)?
        var excludedTop: CGFloat = 80
        var excludedBottom: CGFloat = 116
        var blocked = false
        private var previousBounds = CGRect.zero
        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(volume) // mounted before the first touch; same UIWindowScene as player
            NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: UIApplication.willResignActiveNotification, object: nil)
        }
        @objc private func environmentChanged() { cancelPan?() }
        deinit { NotificationCenter.default.removeObserver(self) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            if previousBounds != .zero, previousBounds != bounds { cancelPan?() }
            previousBounds = bounds
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { cancelPan?() }
        }
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard bounds.contains(point) else { return false }
            return !blocked && point.y >= excludedTop && point.y <= bounds.height - excludedBottom
        }
    }
    var excludedTop: CGFloat
    var excludedBottom: CGFloat
    var blocked: Bool
    var sourceID: URL
    var onDoubleTap: (CGFloat, CGFloat) -> Void
    var onSingleTap: () -> Void
    var onAdjustment: (AVDBAdjustmentPan.Side, CGFloat?, String?) -> Void
    var onSeekChanged: (CGFloat) -> Void
    var onEnded: (Bool) -> Void

    func makeUIView(context: Context) -> GestureView {
        let view = GestureView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        context.coordinator.recognizer = pan
        view.cancelPan = { [weak coordinator = context.coordinator] in coordinator?.cancel() }
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap(_:)))
        singleTap.require(toFail: doubleTap)
        singleTap.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(singleTap)
        return view
    }
    func updateUIView(_ uiView: GestureView, context: Context) {
        let c = context.coordinator
        if sourceID != c.parent.sourceID || (blocked && !c.parent.blocked) { c.cancel() }
        c.parent = self
        uiView.excludedTop = excludedTop
        uiView.excludedBottom = excludedBottom
        uiView.blocked = blocked
    }
    static func dismantleUIView(_ uiView: GestureView, coordinator: Coordinator) {
        coordinator.cancel()
        uiView.cancelPan = nil
    }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerGestureLayer
        weak var recognizer: UIPanGestureRecognizer?
        var state = AVDBAdjustmentPan()
        var dragStart = CGPoint.zero
        init(parent: PlayerGestureLayer) { self.parent = parent }
        func cancel() {
            let active = state.active
            state.end()
            if active { parent.onEnded(true) }
            if let recognizer, recognizer.state == .began || recognizer.state == .changed {
                recognizer.isEnabled = false; recognizer.isEnabled = true
            }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            !parent.blocked && gestureRecognizer.view?.window != nil
            // Do not test velocity/displacement here: UIKit does not retry a slow start.
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard !parent.blocked, let view = gestureRecognizer.view else { return false }
            var target = touch.view
            while let node = target {
                if node is UIControl { return false }
                if node === view { break }
                target = node.superview
            }
            let point = touch.location(in: view)
            guard point.y >= parent.excludedTop, point.y <= view.bounds.height - parent.excludedBottom else { return false }
            if gestureRecognizer === recognizer { dragStart = point } // original touchdown half
            return true
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view as? GestureView else { return }
            if gesture.state == .cancelled || gesture.state == .failed { cancel(); return }
            if gesture.state == .began {
                guard !parent.blocked else { cancel(); return }
                state.begin(origin: dragStart, size: view.bounds.size)
            }
            guard state.active else { return }
            guard !parent.blocked, state.size == view.bounds.size else { cancel(); return }
            let point = gesture.translation(in: view)
            if state.axis == nil {
                let initial = state.side == .brightness ? (view.window?.screen.brightness ?? UIScreen.main.brightness) : CGFloat(AVAudioSession.sharedInstance().outputVolume)
                _ = state.lock(translation: point, initial: initial)
            }
            if state.axis == .vertical {
                // Horizontal seek remains available in portrait; adjustments are landscape-only.
                guard view.bounds.width > view.bounds.height else { cancel(); return }
                if let value = state.update(translation: point, size: view.bounds.size) {
                    if state.side == .brightness {
                        guard let screen = view.window?.screen else { cancel(); return }
                        screen.brightness = value
                        parent.onAdjustment(.brightness, value, nil)
                    } else if view.volume.submit(value) {
                        parent.onAdjustment(.volume, value, nil)
                    } else {
                        parent.onAdjustment(.volume, nil, "当前音频路由无法调节音量，请使用硬件音量键")
                    }
                }
            } else if let dx = state.horizontal(translation: point, size: view.bounds.size) {
                parent.onSeekChanged(dx)
            }
            if gesture.state == .ended {
                state.end()
                parent.onEnded(false)
            }
        }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard !parent.blocked, let view = gesture.view else { return }
            let point = gesture.location(in: view)
            parent.onDoubleTap(point.x, view.bounds.width)
        }
        @objc func singleTap(_ gesture: UITapGestureRecognizer) { parent.onSingleTap() }
    }
}

// KSPlayer emits full request/errors to its logger. App diagnostics are typed;
// third-party free-text messages must not become our diagnostic log stream.
private struct PlaybackPrivateLogger: LogHandler {
    func log(level: LogLevel, message: CustomStringConvertible, file: String, function: String, line: UInt) {}
}
