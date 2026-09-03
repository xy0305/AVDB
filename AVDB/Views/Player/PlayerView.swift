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

    private enum OverlayKind { case brightness, volume }

    private var playerOptions: KSOptions {
        let o = KSOptions()
        if !headers.isEmpty { o.appendHeader(headers) }
        if let ua = headers["User-Agent"] { o.userAgent = ua }
        if let referer = headers["Referer"] { o.referer = referer }
        KSOptions.isAutoPlay = true
        o.videoAdaptable = false
        o.canStartPictureInPictureAutomaticallyFromInline = true
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
        .background(HiddenVolumeView().frame(width: 0, height: 0))
        .onAppear {
            coordinator.isMaskShow = false
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
            if !hasStarted {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)
            }
            if let overlay {
                overlayHUD(overlay)
            }
            if showChrome {
                chromeOverlay
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { toggleChrome() }
        .simultaneousGesture(sideDrag(width: width))
    }

    private func sideDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = abs(value.translation.height)
                if !verticalDrag && overlay == nil {
                    guard dy > dx, dy > 12 else { return }
                    verticalDrag = true
                    if value.startLocation.x < width / 2 {
                        overlay = .brightness
                        dragStart = UIScreen.main.brightness
                    } else {
                        overlay = .volume
                        dragStart = Double(AVAudioSession.sharedInstance().outputVolume)
                    }
                    overlayValue = dragStart
                }
                guard verticalDrag, overlay != nil else { return }
                let delta = -value.translation.height / 240
                let next = min(1, max(0, dragStart + delta))
                overlayValue = next
                applyOverlay(next)
            }
            .onEnded { _ in
                verticalDrag = false
                overlay = nil
            }
    }

    private func applyOverlay(_ value: Double) {
        switch overlay {
        case .brightness:
            UIScreen.main.brightness = value
        case .volume:
            SystemVolume.set(Float(value))
        case nil:
            break
        }
    }

    private func overlayHUD(_ kind: OverlayKind) -> some View {
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
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.5), .clear, Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                HStack {
                    glassButton("chevron.backward") { dismiss() }
                    Spacer()
                    glassButton("pip.enter") {
                        coordinator.playerLayer?.isPipActive.toggle()
                    }
                }
                Spacer()
                HStack {
                    glassButton(isPlaying ? "pause.fill" : "play.fill") {
                        if isPlaying {
                            coordinator.playerLayer?.pause()
                        } else {
                            coordinator.playerLayer?.play()
                        }
                    }
                    Spacer()
                    if isBuffering {
                        ProgressView().tint(.white)
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                progressBar
                    .padding(.top, 12)
            }
            .padding(14)
        }
        .allowsHitTesting(true)
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            Text(formatTime(isSeeking ? seekValue : currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
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
            Text(formatTime(duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func glassButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
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
                    coordinator.playerLayer?.play()
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
        currentTime = layer.currentPlaybackTime
        let d = layer.duration
        if d.isFinite, d > 0 { duration = d }
    }

    private func seek(to time: TimeInterval) {
        coordinator.playerLayer?.seek(time: time)
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
        KSOptions.supportedInterfaceOrientations = mask
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        DispatchQueue.main.async {
            windowScene.requestGeometryUpdate(
                UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            ) { _ in }
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
        let v = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        v.alpha = 0.0001
        v.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            SystemVolume.slider = v.subviews.compactMap { $0 as? UISlider }.first
        }
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        SystemVolume.slider = uiView.subviews.compactMap { $0 as? UISlider }.first
    }
}

enum SystemVolume {
    static weak var slider: UISlider?

    static func set(_ value: Float) {
        slider?.value = max(0, min(1, value))
    }
}
