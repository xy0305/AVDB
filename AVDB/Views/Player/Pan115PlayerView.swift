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
                Button(episodeTitle(index: index, name: file.name)) {
                    Task { await vm.selectEpisode(index) }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    /// 4K、文件名含 -c（中文）、restored（破解）标在集数后面。
    private func episodeTitle(index: Int, name: String) -> String {
        let lower = name.lowercased()
        var marks: [String] = []
        if lower.contains("4k") || lower.contains("2160") { marks.append("4K") }
        if lower.range(of: #"(^|[^a-z0-9])-c([^a-z0-9]|$)"#, options: .regularExpression) != nil
            || lower.contains("-c.")
            || lower.contains("中字")
            || lower.contains("中文") {
            marks.append("-c")
        }
        if lower.contains("restored") { marks.append("restored") }
        let base = "第 \(index + 1) 集"
        return marks.isEmpty ? base : base + "  " + marks.joined(separator: " ")
    }
}

private struct OfflineCandidate {
    let url: String
    let name: String
    let sizeMB: Double
    let seeders: Int

    init?(magnet: Magnet) {
        guard let url = magnet.magnetURL, !url.isEmpty else { return nil }
        self.url = url
        name = magnet.displayName
        sizeMB = Double(magnet.size ?? 0) / 1_000_000
        seeders = 0
    }

    init(link: ExternalLink) {
        url = link.downloadURL
        name = link.title ?? link.downloadURL
        sizeMB = link.sizeMB ?? 0
        seeders = link.seeders ?? 0
    }

    init(url: String, name: String, sizeMB: Double, seeders: Int) {
        self.url = url
        self.name = name
        self.sizeMB = sizeMB
        self.seeders = seeders
    }

    var rank: (Int, Int, Double, Int, Int) {
        let text = (name + " " + url).lowercased()
        let is4K = text.contains("4k") || text.contains("2160")
        let isChinese = text.contains("-c") || text.contains("中字") || text.contains("中文") || text.contains("字幕")
        let isCracked = text.contains("破解") || text.contains("无码破解") || text.contains("uncensored") || text.contains("restored")
        return (is4K ? 1 : 0, isChinese ? 1 : 0, sizeMB, seeders, isCracked ? 1 : 0)
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
            if let existing = try? await Pan115Client.shared.findMatchedVideos(
                keyword: keyword, cookie: cookie, limit: 100
            ) {
                episodes = existing
                try await play(file: existing[0], cookie: cookie)
                return
            }

            if magnet.isEmpty {
                status = "网盘没有文件，正在从磁力库选择…"
            }
            let chosen = await chooseOfflineLink(movie: movie, fallback: magnet)
            guard !chosen.isEmpty else {
                throw Pan115Error.fileNotFound
            }

            status = "正在推送到 115 离线…"
            let result = try await Pan115Client.shared.addOfflineTask(
                url: chosen, cookie: cookie, folderCID: cid)
            Pan115PlaybackCache.save(movieID: movie.id, magnet: chosen)
            switch result {
            case .failed(let msg):
                throw Pan115Error.api(msg)
            case .exists:
                status = "任务已存在，正在打开已下载文件…"
            case .success:
                status = "已推送，等待离线完成…"
            }

            let files = try await waitUntilPlayable(
                keyword: keyword, cookie: cookie, folderCID: cid,
                timeout: result == .exists ? 45 : 90)
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

    private func chooseOfflineLink(movie: Movie, fallback: String) async -> String {
        var candidates: [OfflineCandidate] = []
        if let magnets = try? await JavDBSDK.shared.movieMagnets(movie.id) {
            candidates.append(contentsOf: magnets.compactMap(OfflineCandidate.init))
        }
        let external = await ExternalLibraryClient.shared.links(for: movie.displayNumber)
        candidates.append(contentsOf: external.map(OfflineCandidate.init))
        if !fallback.isEmpty {
            candidates.append(OfflineCandidate(url: fallback, name: fallback, sizeMB: 0, seeders: 0))
        }
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.url).inserted }
        return candidates.sorted { $0.rank > $1.rank }.first?.url ?? ""
    }

    private func waitUntilPlayable(
        keyword: String, cookie: String, folderCID: String, timeout: TimeInterval
    ) async throws -> [Pan115Client.FileItem] {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
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
            let tasks = (try? await Pan115Client.shared.listOfflineTasks(cookie: cookie)) ?? []
            if let hit = tasks.first(where: {
                $0.name.localizedCaseInsensitiveContains(keyword)
                    || $0.url.localizedCaseInsensitiveContains(keyword)
            }) {
                if hit.isFailed { throw Pan115Error.taskFailed(hit.name) }
                if hit.isRunning {
                    status = "离线中 \(Int(hit.percent))%…"
                }
            } else {
                status = "任务已完成，正在匹配文件…"
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        if let files = try? await Pan115Client.shared.findMatchedVideos(
            keyword: keyword, cookie: cookie, limit: 100
        ), !files.isEmpty {
            return files
        }
        throw Pan115Error.timeout
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
