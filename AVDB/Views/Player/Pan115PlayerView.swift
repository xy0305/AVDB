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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = Pan115PlayerViewModel()
    @State private var showEpisodes = false

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                    Button("关闭") { dismiss() }
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
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white)
                }
            }

            if vm.playURL != nil, vm.episodes.count > 1 {
                HStack {
                    Spacer()
                    Button { showEpisodes = true } label: {
                        Image(systemName: "rectangle.stack.badge.play")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
            }

            if vm.playURL == nil || vm.errorMessage != nil {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.start(movie: movie, magnetURL: magnetURL) }
        .confirmationDialog("选择集数", isPresented: $showEpisodes) {
            ForEach(Array(vm.episodes.enumerated()), id: \.element.fileID) { index, file in
                Button("第 \(index + 1) 集") {
                    Task { await vm.selectEpisode(index) }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

@MainActor
final class Pan115PlayerViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var status = "准备中…"
    @Published var errorMessage: String?
    @Published var fileName = ""
    @Published var episodes: [Pan115Client.FileItem] = []
    @Published var playURL: URL?
    @Published var streams: [Pan115Client.PlayStream] = []
    @Published var qualityLabel = "原画"

    var headers: [String: String] {
        Pan115Client.playHeaders(cookie: Pan115Settings.shared.cookie)
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
            if let existing = await searchExisting(keyword: keyword, cookie: cookie, folderCID: cid) {
                episodes = existing
                try await play(file: existing[0], cookie: cookie)
                return
            }

            if magnet.isEmpty {
                throw Pan115Error.fileNotFound
            }

            status = "正在推送到 115 离线…"
            let result = try await Pan115Client.shared.addOfflineTask(
                url: magnet, cookie: cookie, folderCID: cid)
            Pan115PlaybackCache.save(movieID: movie.id, magnet: magnet)

            switch result {
            case .failed(let msg):
                throw Pan115Error.api(msg)
            case .exists:
                status = "任务已存在，正在打开已下载文件…"
            case .success:
                status = "已推送，等待离线完成…"
            }

            let files = try await waitUntilPlayable(
                keyword: keyword, cookie: cookie, folderCID: cid, timeout: result == .exists ? 20 : 90)
            episodes = files
            try await play(file: files[0], cookie: cookie)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ stream: Pan115Client.PlayStream) {
        qualityLabel = stream.name
        playURL = URL(string: stream.url)
    }

    func selectEpisode(_ index: Int) async {
        guard episodes.indices.contains(index) else { return }
        isLoading = true
        errorMessage = nil
        playURL = nil
        do {
            try await play(file: episodes[index], cookie: Pan115Settings.shared.cookie)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func searchExisting(keyword: String, cookie: String, folderCID: String) async -> [Pan115Client.FileItem]? {
        if let files = try? await Pan115Client.shared.findMatchedVideos(
            keyword: keyword, cookie: cookie, limit: 100
        ), !files.isEmpty {
            return files
        }
        if let file = try? await Pan115Client.shared.findMatchedVideo(
            keyword: keyword, cookie: cookie, folderCID: folderCID, requireMatch: true
        ) {
            return [file]
        }
        return nil
    }

    private func waitUntilPlayable(
        keyword: String, cookie: String, folderCID: String, timeout: TimeInterval
    ) async throws -> [Pan115Client.FileItem] {
        let start = Date()
        var lastError: Error = Pan115Error.timeout
        while Date().timeIntervalSince(start) < timeout {
            if let files = await searchExisting(keyword: keyword, cookie: cookie, folderCID: folderCID) {
                return files
            }
            let tasks = (try? await Pan115Client.shared.listOfflineTasks(cookie: cookie)) ?? []
            if let hit = tasks.first(where: {
                $0.name.localizedCaseInsensitiveContains(keyword)
                    || $0.url.localizedCaseInsensitiveContains(keyword)
            }) {
                if hit.isFailed { throw Pan115Error.taskFailed(hit.name) }
                status = hit.isRunning ? "离线中 \(Int(hit.percent))%…" : "任务已存在，正在匹配文件…"
            }
            lastError = Pan115Error.timeout
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        if let files = await searchExisting(keyword: keyword, cookie: cookie, folderCID: folderCID) {
            return files
        }
        throw lastError
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
