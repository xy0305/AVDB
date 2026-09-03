//
//  PlayerView.swift
//  AVDB
//
//  HLS 播放器（支持多集多清晰度选择）。
//

import SwiftUI
import AVKit

struct PlayerView: View {
    let movieID: String
    let sourceID: Int
    @StateObject private var vm = PlayerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if let playData = vm.playData, let episode = vm.currentEpisode,
               let urls = episode.urls {
                VideoPlayer(player: vm.player)
                    .frame(height: 250)
                    .background(Color.black)

                // 清晰度选择
                qualityPicker(urls: urls)

                // 集数选择
                if let movies = playData.movies, movies.count > 1 {
                    episodePicker(movies)
                }
            } else if vm.isLoading {
                ProgressView("加载播放源...")
                    .frame(maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(err)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("重试") {
                        Task { await vm.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("播放")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .onDisappear {
            vm.player.pause()
        }
    }

    private func qualityPicker(urls: [String: PlayData.StreamURL]) -> some View {
        let qualities = ["1080p", "720p", "480p", "360p"].filter { urls[$0] != nil }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(qualities, id: \.self) { q in
                    Button {
                        vm.selectQuality(q)
                    } label: {
                        Text(q)
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(vm.currentQuality == q ? Color.orange : Color(.systemGray6))
                            .foregroundColor(vm.currentQuality == q ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func episodePicker(_ movies: [PlayData.Episode]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(movies) { ep in
                    Button {
                        vm.selectEpisode(ep.index)
                    } label: {
                        Text(ep.name ?? "第\(ep.index)集")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(vm.currentEpisodeIndex == ep.index ? Color.blue : Color(.systemGray6))
                            .foregroundColor(vm.currentEpisodeIndex == ep.index ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var playData: PlayData?
    @Published var currentEpisodeIndex = 1
    @Published var currentQuality = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var player = AVPlayer()
    @Published var currentStreamURL: String?

    private let sdk = JavDBSDK.shared
    private var allEpisodes: [PlayData.Episode] = []

    var currentEpisode: PlayData.Episode? {
        playData?.movies?.first { $0.index == currentEpisodeIndex }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // 尝试播放，若失败回退续播
        do {
            let data = try await sdk.moviePlay(vmMovieID(), sourceID: sourceID)
            apply(data)
        } catch {
            // 回退续播
            if let data = try? await sdk.movieResumePlay(vmMovieID(), sourceID: sourceID) {
                if data.movies?.isEmpty == false {
                    apply(data)
                } else {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func vmMovieID() -> String { movieID }

    private func apply(_ data: PlayData) {
        playData = data
        allEpisodes = data.movies ?? []
        if let first = allEpisodes.first {
            currentEpisodeIndex = first.index
            let qualities = ["1080p", "720p", "480p", "360p"]
            if let firstQuality = qualities.first(where: { first.urls?[$0] != nil }) {
                selectQuality(firstQuality)
            } else if let any = first.urls?.keys.first {
                selectQuality(any)
            }
        }
    }

    func selectEpisode(_ index: Int) {
        currentEpisodeIndex = index
        guard let ep = currentEpisode else { return }
        let qualities = ["1080p", "720p", "480p", "360p"]
        if let q = qualities.first(where: { ep.urls?[$0] != nil }) {
            selectQuality(q)
        } else if let any = ep.urls?.keys.first {
            selectQuality(any)
        }
    }

    func selectQuality(_ quality: String) {
        currentQuality = quality
        guard let ep = currentEpisode, let url = ep.urls?[quality]?.url,
              let streamURL = URL(string: url) else { return }
        currentStreamURL = url
        let item = AVPlayerItem(url: streamURL)
        player.replaceCurrentItem(with: item)
        player.play()
    }
}
