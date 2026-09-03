//
//  PlayerView.swift
//  AVDB
//
//  KSPlayer 播放器，控件对齐 CamWeb / AngelLive：16:9、四角毛玻璃、单击显隐。
//

import SwiftUI
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
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
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

/// CamWeb 风格：顶上 16:9、四角毛玻璃、单击显隐 5 秒。
struct KSChromePlayer: View {
    let url: URL
    var title: String = ""
    var subtitle: String = ""
    var headers: [String: String] = [:]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var showChrome = true
    @State private var hideTask: Task<Void, Never>?
    @State private var isLandscape = false
    @State private var options: KSOptions

    init(url: URL, title: String = "", subtitle: String = "", headers: [String: String] = [:]) {
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.headers = headers
        let o = KSOptions()
        if !headers.isEmpty { o.appendHeader(headers) }
        _options = State(initialValue: o)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    ZStack {
                        KSVideoPlayer(coordinator: coordinator, url: url, options: options)
                            .onAppear {
                                coordinator.playerLayer?.play()
                                scheduleHide()
                            }
                        if showChrome {
                            chromeOverlay
                        }
                    }
                    .aspectRatio(landscape ? nil : 16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: landscape ? .infinity : nil)

                    if !landscape {
                        infoBar
                        Spacer(minLength: 0)
                    }
                }
            }
            .onAppear { isLandscape = landscape }
            .onChange(of: landscape) { _, new in isLandscape = new }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onTapGesture { toggleChrome() }
        .onDisappear {
            hideTask?.cancel()
            coordinator.playerLayer?.pause()
        }
    }

    private var infoBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? "正在播放" : title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private var chromeOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.45), .clear, Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack {
                HStack {
                    glassButton("chevron.backward") { dismiss() }
                    Spacer()
                    glassButton("pip.enter") {
                        coordinator.playerLayer?.isPipActive.toggle()
                    }
                }
                Spacer()
                HStack {
                    glassButton(coordinator.state.isPlaying ? "pause.fill" : "play.fill") {
                        if coordinator.state.isPlaying {
                            coordinator.playerLayer?.pause()
                        } else {
                            coordinator.playerLayer?.play()
                        }
                    }
                    Spacer()
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }
            .padding(14)
        }
        .allowsHitTesting(true)
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

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
        if showChrome { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation { showChrome = false }
                }
            }
        }
    }
}
