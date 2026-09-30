//
//  PlayerView.swift
//  AVDB
//
//  KSPlayer：进入横屏、进度条、左侧亮度 / 右侧音量。
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
                    headers: vm.headers
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
        .task { await vm.load() }
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var playData: PlayData?
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
    var progressID: String? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
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
    @State private var dragStart: Double = 0
    @State private var verticalDrag = false
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
            let landscape = geo.size.width > geo.size.height
            let videoHeight = landscape ? geo.size.height : geo.size.width * 9 / 16
            VStack(spacing: 0) {
                videoArea(height: videoHeight, width: geo.size.width)
                if !landscape {
                    infoBar
                    Spacer(minLength: 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // 保留一个可布局的 MPVolumeView；尺寸为 0 时系统可能不创建 UISlider，
        // 导致横屏右侧滑动虽然触发，但音量实际不会变化。
        .background(HiddenVolumeView().frame(width: 2, height: 2).opacity(0.01))
        .onAppear {
            coordinator.isMaskShow = false
            // 激活播放音频会话，确保右侧手势修改的是当前播放器音量。
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            wireCoordinator()
            startTicker()
            scheduleHide()
            OrientationLock.set(.landscapeRight, keepLocked: true)
        }
        .onDisappear {
            hideTask?.cancel()
            tickTask?.cancel()
            coordinator.playerLayer?.pause()
            OrientationLock.set(.portrait, keepLocked: true)
        }
    }

    @ViewBuilder
    private func videoArea(height: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Color.black
            KSVideoPlayer(coordinator: coordinator, url: url, options: playerOptions)
                .onAppear { applyFillMode() }
            if showChrome {
                chromeOverlay
            }
            PlayerGestureLayer(
                onDoubleTap: { x, width in
                    skip(by: x < width * 0.5 ? -10 : 10)
                },
                onSingleTap: { toggleChrome() },
                onDragChanged: { value, size in
                    handlePlayerDrag(value, size: size, ended: false)
                },
                onDragEnded: { value, size in
                    handlePlayerDrag(value, size: size, ended: true)
                }
            )
            if !hasStarted {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)
            }
            if let overlay {
                overlayHUD(overlay)
                    .allowsHitTesting(false)
            }
            if let skipHUD {
                skipOverlay(skipHUD)
                    .allowsHitTesting(false)
            }
            if showChrome {
                chromeOverlay
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
    }

    private func handlePlayerDrag(_ value: PlayerDragValue, size: CGSize, ended: Bool) {
        let width = size.width
        let height = size.height
        let dx = value.translation.width
        let dy = value.translation.height
        let travel = max(140, height * 0.42)
        let scrubWidth = max(160, width * 0.55)
        if ended {
            if horizontalDrag {
                seek(to: seekValue)
                currentTime = seekValue
                isSeeking = false
            }
            verticalDrag = false
            horizontalDrag = false
            overlay = nil
            if showChrome { scheduleHide() }
            return
        }
        if !verticalDrag && !horizontalDrag && overlay == nil {
            if abs(dx) > abs(dy) + 6 {
                horizontalDrag = true
                isSeeking = true
                scrubStart = currentTime
                seekValue = currentTime
                overlay = .seek
                hideTask?.cancel()
            } else if abs(dy) > abs(dx) + 6 {
                verticalDrag = true
                hideTask?.cancel()
                if value.start.x < width * 0.5 {
                    overlay = .brightness
                    dragStart = UIScreen.main.brightness
                } else {
                    overlay = .volume
                    dragStart = Double(SystemVolume.current)
                }
                overlayValue = dragStart
            } else {
                return
            }
        }
        if horizontalDrag {
            let span = max(duration, 1)
            let delta = Double(dx / scrubWidth) * span
            let next = min(span, max(0, scrubStart + delta))
            seekValue = next
            overlayValue = next
            return
        }
        guard verticalDrag, overlay == .brightness || overlay == .volume else { return }
        let next = min(1, max(0, dragStart - dy / travel))
        overlayValue = next
        applyOverlay(next)
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

    private func applyOverlay(_ value: Double) {
        switch overlay {
        case .brightness:
            UIScreen.main.brightness = value
        case .volume:
            SystemVolume.set(Float(value))
        case .seek, nil:
            break
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
        VStack(spacing: 8) {
            Text(formatTime(seekValue))
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(formatTime(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 160, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 160 * min(1, seekValue / max(duration, 0.1)))
                }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    private var infoBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? "正在播放" : title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.12))
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
                Spacer(minLength: 8)

                Menu {
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
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.leading, 12)

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggleChrome() }

            progressBar
                .padding(.horizontal, 16)

            HStack(spacing: 22) {
                Button {
                    if isPlaying {
                        coordinator.playerLayer?.pause()
                    } else {
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
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Button {
                    seek(to: min((isSeeking ? seekValue : currentTime) + 10, max(duration, 0)))
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Spacer()

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
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
            Slider(
                value: Binding(
                    get: { isSeeking ? seekValue : currentTime },
                    set: { newValue in
                        isSeeking = true
                        seekValue = newValue
                    }
                ),
                in: 0...max(duration, 0.1)
            ) { editing in
                if editing {
                    hideTask?.cancel()
                    isSeeking = true
                } else {
                    seek(to: seekValue)
                    currentTime = seekValue
                    isSeeking = false
                    scheduleHide()
                }
            }
            .tint(.white)
            .controlSize(.small)
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

    private func glassButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: 40, height: 40)
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
                .frame(width: 30, height: 30)
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
        coordinator.onStateChanged = { _, state in
            Task { @MainActor in
                isPlaying = state.isPlaying
                isBuffering = state == .buffering || state == .preparing
                if state.isPlaying || state == .readyToPlay || state == .paused {
                    hasStarted = true
                }
                if state == .readyToPlay {
                    if let progressID, let saved = PlaybackProgressStore.progress(for: progressID), saved.time >= 5 {
                        coordinator.playerLayer?.seek(time: saved.time, autoPlay: true) { _ in }
                    }
                    coordinator.playerLayer?.play()
                    applyFillMode()
                    syncTime()
                }
            }
        }
    }

    private func startTicker() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                syncTime()
            }
        }
    }

    private func syncTime() {
        guard !isSeeking, let layer = coordinator.playerLayer else { return }
        currentTime = layer.player.currentPlaybackTime
        let d = layer.player.duration
        if d.isFinite, d > 0 { duration = d }
        if let progressID {
            PlaybackProgressStore.save(movieID: progressID, time: currentTime, duration: duration)
        }
    }

    private func seek(to time: TimeInterval) {
        coordinator.playerLayer?.seek(time: time, autoPlay: coordinator.playerLayer?.options.isSeekedAutoPlay ?? false) { _ in }
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

enum OrientationLock {
    static func set(_ mask: UIInterfaceOrientationMask, keepLocked: Bool = false) {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        // iPad 点 X 关播放器时若 requestGeometryUpdate(.portrait)，窗口会被踢出全屏 / Stage Manager。
        if isPad, mask == .portrait {
            apply(.all, requestGeometry: false, keepLocked: true)
            return
        }
        apply(mask, requestGeometry: true, keepLocked: keepLocked)
    }

    private static func apply(
        _ mask: UIInterfaceOrientationMask,
        requestGeometry: Bool,
        keepLocked: Bool
    ) {
        KSOptions.supportedInterfaceOrientations = mask
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        DispatchQueue.main.async {
            if requestGeometry {
                windowScene.requestGeometryUpdate(
                    UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
                ) { _ in }
            }
            guard !keepLocked else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }
}

private struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        view.isUserInteractionEnabled = false
        captureSlider(from: view)
        // MPVolumeView 的 slider 有时要到下一轮布局才创建。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            captureSlider(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        captureSlider(from: uiView)
    }

    private func captureSlider(from view: UIView) {
        if let slider = findSlider(in: view) { SystemVolume.slider = slider }
    }

    private func findSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        return view.subviews.lazy.compactMap(findSlider(in:)).first
    }
}

enum SystemVolume {
    static weak var slider: UISlider?

    static var current: Float {
        if let slider { return slider.value }
        return AVAudioSession.sharedInstance().outputVolume
    }

    static func set(_ value: Float) {
        let value = max(0, min(1, value))
        if let slider {
            slider.setValue(value, animated: false)
            slider.sendActions(for: .valueChanged)
            return
        }
        // MPVolumeView 还没建好时，先保证手势 HUD 不丢；下一帧再补一次。
        DispatchQueue.main.async {
            slider?.setValue(value, animated: false)
            slider?.sendActions(for: .valueChanged)
        }
    }
}

struct PlayerDragValue {
    var start: CGPoint
    var translation: CGSize
}

struct PlayerGestureLayer: UIViewRepresentable {
    final class GestureView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard bounds.contains(point) else { return false }
            if point.y < 72 || point.y > bounds.height - 108 { return false }
            return true
        }
    }
    var onDoubleTap: (CGFloat, CGFloat) -> Void
    var onSingleTap: () -> Void
    var onDragChanged: (PlayerDragValue, CGSize) -> Void
    var onDragEnded: (PlayerDragValue, CGSize) -> Void

    func makeUIView(context: Context) -> GestureView {
        let view = GestureView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
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
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerGestureLayer
        var dragStart = CGPoint.zero
        init(parent: PlayerGestureLayer) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view else { return true }
            let point = touch.location(in: view)
            let height = view.bounds.height
            let width = view.bounds.width
            if point.y < 72 || point.y > height - 108 { return false }
            return true
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            if gesture.state == .began {
                dragStart = gesture.location(in: view)
            }
            let value = PlayerDragValue(
                start: dragStart,
                translation: gesture.translation(in: view).size
            )
            if gesture.state == .changed || gesture.state == .began {
                parent.onDragChanged(value, view.bounds.size)
            } else if gesture.state == .ended || gesture.state == .cancelled {
                parent.onDragEnded(value, view.bounds.size)
            }
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let point = gesture.location(in: view)
            parent.onDoubleTap(point.x, view.bounds.width)
        }

        @objc func singleTap(_ gesture: UITapGestureRecognizer) {
            parent.onSingleTap()
        }
    }
}

private extension CGPoint {
    var size: CGSize { CGSize(width: x, height: y) }
}
