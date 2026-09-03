//
//  Pan115PlayerView.swift
//  AVDB
//
//  按番号全盘搜索 115 文件（对齐 Forward 模块 files/search），KSPlayer 播最高清晰度。
//

import SwiftUI
import KSPlayer

struct Pan115PlayerView: View {
    let movie: Movie
    var magnetURL: String? = nil
    @StateObject private var vm = Pan115PlayerViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = vm.playURL, vm.errorMessage == nil, !vm.isLoading {
                KSChromePlayer(
                    url: url,
                    title: movie.displayNumber,
                    subtitle: vm.qualityLabel,
                    headers: vm.headers
                )
            } else if let err = vm.errorMessage {
                ContentUnavailableView {
                    Label("无法播放", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("重试") {
                        Task { await vm.start(movie: movie, magnetURL: magnetURL) }
                    }
                }
                .foregroundStyle(.white)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text(vm.status)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("115 原画")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vm.streams.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(Array(vm.streams.enumerated()), id: \.offset) { _, s in
                            Button(s.name) { vm.select(s) }
                        }
                    } label: {
                        Text(vm.qualityLabel)
                    }
                }
            }
        }
        .task { await vm.start(movie: movie, magnetURL: magnetURL) }
    }
}

@MainActor
final class Pan115PlayerViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var status = "准备中…"
    @Published var errorMessage: String?
    @Published var fileName = ""
    @Published var playURL: URL?
    @Published var streams: [Pan115Client.PlayStream] = []
    @Published var qualityLabel = "原画"

    var headers: [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15",
            "Referer": "https://115.com/",
            "Origin": "https://115.com",
            "Cookie": Pan115Settings.shared.cookie,
        ]
    }

    func start(movie: Movie, magnetURL: String?) async {
        let settings = Pan115Settings.shared
        guard settings.isConfigured else {
            errorMessage = settings.missingHint
            return
        }
        isLoading = true
        errorMessage = nil
        playURL = nil
        streams = []
        defer { isLoading = false }

        let cookie = settings.cookie
        let cid = settings.folderCID
        let keyword = movie.displayNumber
        let magnet = magnetURL
            ?? Pan115PlaybackCache.magnet(for: movie.id)
            ?? ""

        do {
            status = "正在 115 中搜索 \(keyword)…"
            if let existing = try? await Pan115Client.shared.findMatchedVideo(
                keyword: keyword, cookie: cookie, folderCID: cid, requireMatch: true
            ) {
                try await play(file: existing, cookie: cookie)
                return
            }

            if magnet.isEmpty {
                throw Pan115Error.fileNotFound
            }

            status = "正在推送到 115 离线…"
            let result = try await Pan115Client.shared.addOfflineTask(
                url: magnet, cookie: cookie, folderCID: cid)
            Pan115PlaybackCache.save(movieID: movie.id, magnet: magnet)
            status = result.message + "，等待离线完成…"

            _ = try await Pan115Client.shared.waitOfflineReady(
                keyword: keyword, cookie: cookie, timeout: 90)

            status = "离线完成，正在匹配 \(keyword)…"
            let file = try await Pan115Client.shared.findMatchedVideo(
                keyword: keyword, cookie: cookie, folderCID: cid, requireMatch: true)
            try await play(file: file, cookie: cookie)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ stream: Pan115Client.PlayStream) {
        qualityLabel = stream.name
        playURL = URL(string: stream.url)
    }

    private func play(file: Pan115Client.FileItem, cookie: String) async throws {
        fileName = file.name
        status = "获取 115 播放地址…"
        let list = try await Pan115Client.shared.streamsForVideo(
            pickCode: file.pickCode, cookie: cookie, filename: file.name)
        streams = list
        guard let best = list.first, let url = URL(string: best.url) else {
            throw Pan115Error.playURLNotFound
        }
        qualityLabel = best.name
        playURL = url
    }
}

enum Pan115PlaybackCache {
    private static func key(_ movieID: String) -> String { "avdb.115.lastMagnet.\(movieID)" }

    static func save(movieID: String, magnet: String) {
        UserDefaults.standard.set(magnet, forKey: key(movieID))
    }

    static func magnet(for movieID: String) -> String? {
        UserDefaults.standard.string(forKey: key(movieID))
    }
}
