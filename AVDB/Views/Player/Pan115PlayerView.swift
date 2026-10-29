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
    var historyArtwork: UIImage? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = Pan115PlayerViewModel()
    @State private var showEpisodes = false
    @State private var showQuality = false
    @State private var pendingDelete: Pan115Client.FileItem?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = vm.playURL, vm.errorMessage == nil, !vm.isLoading {
                let metricsGeneration = vm.metricsGeneration
                KSChromePlayer(
                    url: url,
                    title: movie.displayNumber,
                    subtitle: vm.qualityLabel,
                    headers: vm.headers,
                    progressID: movie.id,
                    supportsFramePreview: vm.supportsFramePreview,
                    onPlaybackFailure: {
                        Task {
                            guard vm.metricsGeneration == metricsGeneration else { return }
                            await vm.failed()
                        }
                    },
                    managesOrientation: false,
                    onSelectSource: { showQuality = true },
                    onSelectEpisode: vm.episodes.count > 1 ? { showEpisodes = true } : nil,
                    publicSubtitleQuery: movie.displayNumber,
                    onVideoMetrics: { sourceURL, metrics, settled in
                        vm.receiveMetrics(metrics, settled: settled, url: sourceURL, generation: metricsGeneration)
                    },
                    historyMovie: movie,
                    historyArtwork: historyArtwork,
                    historySource: "115"
                )
                .id(url)
                .id(metricsGeneration)
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

            // Keep the player mounted: this is an in-player overlay, never a sheet.
            if showEpisodes {
                PlaybackVersionMenu(
                    episodes: vm.episodes,
                    currentID: vm.currentEpisode?.fileID,
                    title: episodeTitle,
                    close: { showEpisodes = false },
                    play: { index in Task { await vm.selectEpisode(index) } },
                    deleteCurrent: { pendingDelete = vm.currentEpisode }
                )
                .zIndex(30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        // Stable route owns orientation across .id(url), loading/error branches and HLS refresh.
        .background(PlaybackOrientationHost().allowsHitTesting(false))
        .task { await vm.start(movie: movie, magnetURL: magnetURL) }
        .confirmationDialog("播放源", isPresented: $showQuality, titleVisibility: .visible) {
            ForEach(Array(vm.streams.enumerated()), id: \.offset) { _, stream in
                Button((vm.isCurrent(stream) ? "✓ 正在播放 · " : "") + stream.name) { Task { await vm.select(stream) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(vm.resolutionDetail + "\nHDR/编码支持依设备；LUT 仅支持 SDR。不兼容可选 HLS。分辨率不代表原生画质。")
        }
        .confirmationDialog(
            "删除网盘中的当前版本？",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除此版本", role: .destructive) {
                let file = pendingDelete
                pendingDelete = nil
                guard let file else { return }
                Task { await vm.deleteEpisode(file) }
            }
            .accessibilityIdentifier("pan115.delete.confirm")
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("仅删除“\(pendingDelete?.name ?? "当前文件")”。文件进入 115 回收站且不可从 App 恢复，其他版本不会删除。")
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

struct PlaybackVersionMenu: View {
    let episodes: [Pan115Client.FileItem]
    let currentID: String?
    let title: (Int, String) -> String
    let close: () -> Void
    let play: (Int) -> Void
    let deleteCurrent: () -> Void

    // Bounded Dynamic Type keeps the compact menu usable without disabling scaling.
    @ScaledMetric(relativeTo: .body) private var scaledTitleSize: CGFloat = 15
    private var textScale: CGFloat { min(max(scaledTitleSize / 15, 1), 1.3) }
    private var rowHeight: CGFloat { 56 * textScale }

    private var canDelete: Bool {
        episodes.count > 1 && episodes.contains { $0.fileID == currentID }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(310, max(0, geometry.size.width - 40))
            let availableHeight = max(0, geometry.size.height
                - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom - 32)
            let rowCount = episodes.count + (canDelete ? 1 : 0)
            let contentHeight = CGFloat(episodes.count) * rowHeight + (canDelete ? 44 : 0)
                + CGFloat(max(0, rowCount - 1)) * 6 + 16
            ZStack {
                Button(action: close) {
                    Color.black.opacity(0.24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .accessibilityLabel("关闭版本菜单，返回播放")
                .accessibilityIdentifier("pan115.episode.close")

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(episodes.enumerated()), id: \.element.fileID) { index, file in
                            let selected = file.fileID == currentID
                            Button { close(); play(index) } label: {
                                VStack(spacing: 2) {
                                    Text(selected ? "正在播放 · \(title(index, file.name))" : title(index, file.name))
                                        .font(.system(size: 15 * textScale, weight: .semibold))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(AVDBPlaybackFileSize.text(bytes: file.size))
                                            .font(.system(size: 12 * textScale).monospacedDigit())
                                            .fixedSize(horizontal: true, vertical: false)
                                        Text("·").font(.system(size: 11 * textScale))
                                        Text(file.name)
                                            .font(.system(size: 11 * textScale))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .opacity(0.78)
                                    }
                                    .lineLimit(1)
                                }
                                .foregroundStyle(selected ? .black : Color(red: 0.20, green: 0.48, blue: 0.96))
                                .frame(maxWidth: .infinity, minHeight: rowHeight)
                                .padding(.horizontal, 8)
                                .background(selected ? .white : Color(white: 0.72), in: Capsule())
                                .overlay(Capsule().stroke(.white, lineWidth: selected ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(selected ? "正在播放 · " : "")\(title(index, file.name))，\(AVDBPlaybackFileSize.text(bytes: file.size))，\(file.name)")
                            .accessibilityIdentifier(selected ? "pan115.episode.current" : "pan115.episode")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                        if canDelete {
                            Button("删除当前版本", role: .destructive) { close(); deleteCurrent() }
                                .font(.system(size: 15 * textScale, weight: .semibold)).foregroundStyle(.red)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color(white: 0.72), in: Capsule())
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("pan115.delete.current")
                        }
                    }.padding(8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: width, height: min(contentHeight, availableHeight))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .accessibilityIdentifier("pan115.episode.menu")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
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
        return (is4K ? 1 : 0, isChinese ? 1 : 0, sizeMB, isCracked ? 1 : 0, seeders)
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
    @Published var qualityLabel = "原文件 / 原画"
    @Published private(set) var playbackNotice = ""
    private var noticeTask: Task<Void, Never>?
    private var shownNotices = Set<String>()

    func dismissNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        playbackNotice = ""
    }

    private func resetNotices() {
        dismissNotice()
        shownNotices.removeAll()
    }

    private func showNotice(_ message: String) {
        // Failure callbacks can repeat on player ticks. Never renew a dismissed notice.
        guard shownNotices.insert(message).inserted else { return }
        dismissNotice()
        playbackNotice = message
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 6_000_000_000) }
            catch { return }
            self?.dismissNotice()
        }
    }
    @Published private(set) var activeStream: Pan115Client.PlayStream?
    @Published private var videoMetrics = PlaybackMetricsState()
    var metricsGeneration: Int { videoMetrics.generation }
    var resolutionDetail: String { videoMetrics.detail }

    func isCurrent(_ stream: Pan115Client.PlayStream) -> Bool {
        PlaybackMetricsState.isCurrent(name: stream.name, original: stream.isOriginal,
            activeName: activeStream?.name, activeOriginal: activeStream?.isOriginal)
    }

    func receiveMetrics(_ metrics: PlaybackVideoMetrics?, settled: Bool, url: URL, generation: Int) {
        var next = videoMetrics
        guard next.receive(metrics, settled: settled, url: url, generation: generation) else { return }
        videoMetrics = next
        qualityLabel = next.label(original: activeStream?.isOriginal == true)
    }

    private func clearMetrics(url: URL? = nil) {
        videoMetrics.reset(url: url)
        qualityLabel = videoMetrics.label(original: activeStream?.isOriginal == true)
    }
    private(set) var currentFile: Pan115Client.FileItem?
    var currentEpisode: Pan115Client.FileItem? { currentFile }
    private var refreshing = false
    private var refreshUsed = false
    private var fallbackUsed = false
    private var generation = 0

    var supportsFramePreview: Bool { activeStream?.isOriginal == true }

    var headers: [String: String] {
        activeStream?.headers.isEmpty == false ? activeStream!.headers : Pan115Client.playHeaders(cookie: Pan115Settings.shared.cookie)
    }

    func start(movie: Movie, magnetURL: String?) async {
        resetNotices()
        let settings = Pan115Settings.shared
        guard settings.isConfigured else {
            errorMessage = settings.missingHint
            return
        }
        isLoading = true
        errorMessage = nil
        playURL = nil
        clearMetrics()
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

    func select(_ stream: Pan115Client.PlayStream) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let token = generation
        var chosen = stream
        if Date().timeIntervalSince(stream.resolvedAt) > 120, let file = currentFile {
            do {
                if stream.isOriginal {
                    chosen = try await Pan115Client.shared.originalStream(pickCode: file.pickCode, cookie: Pan115Settings.shared.cookie)
                } else {
                    let list = try await Pan115Client.shared.streamsForVideo(pickCode: file.pickCode, cookie: Pan115Settings.shared.cookie, filename: file.name)
                    guard let match = list.first(where: { $0.name == stream.name }) ?? list.first else { throw Pan115Error.playURLNotFound }
                    chosen = match
                }
            } catch {
                guard token == generation else { return }
                showNotice("地址刷新失败，请重试或选择 HLS")
                return
            }
        }
        guard token == generation else { return }
        activate(chosen)
        refreshUsed = false
        fallbackUsed = false
        dismissNotice()
    }

    private func activate(_ stream: Pan115Client.PlayStream) {
        activeStream = stream
        let url = URL(string: stream.url)
        clearMetrics(url: url)
        playURL = url
    }

    func failed() async {
        guard !refreshing, let file = currentFile, let active = activeStream else { return }
        refreshing = true
        defer { refreshing = false }
        let token = generation
        if active.isOriginal && !refreshUsed {
            refreshUsed = true
            showNotice("原文件播放失败，正在刷新一次地址…")
            if let fresh = try? await Pan115Client.shared.originalStream(pickCode: file.pickCode, cookie: Pan115Settings.shared.cookie) {
                guard token == generation else { return }
                activate(fresh)
                return
            }
        }
        guard token == generation else { return }
        if active.isOriginal && !fallbackUsed {
            fallbackUsed = true
            showNotice("原文件不兼容或不可用，回退 HLS 转码…")
            let list = (try? await Pan115Client.shared.streamsForVideo(pickCode: file.pickCode, cookie: Pan115Settings.shared.cookie, filename: file.name)) ?? []
            guard token == generation else { return }
            if let first = list.first {
                streams = streams.filter { $0.isOriginal } + list
                activate(first)
                return
            }
        }
        errorMessage = "播放失败，原文件及可用 HLS 已尝试；请重新打开或检查 Cookie。"
    }

    func selectEpisode(_ index: Int) async {
        guard episodes.indices.contains(index) else { return }
        isLoading = true
        errorMessage = nil
        playURL = nil
        clearMetrics()
        do {
            try await play(file: episodes[index], cookie: Pan115Settings.shared.cookie)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deleteEpisode(_ file: Pan115Client.FileItem) async {
        guard !file.fileID.isEmpty, !file.cid.isEmpty else {
            showNotice("无法定位网盘文件，未删除")
            return
        }
        isLoading = true
        errorMessage = nil
        status = "正在从 115 删除当前版本…"
        do {
            let deleted = try await Pan115Client.shared.deleteFiles(cid: file.cid, fileIDs: [file.fileID], cookie: Pan115Settings.shared.cookie)
            guard deleted == 1 else { throw Pan115Error.api("115 未确认删除") }
            let remaining = episodes.filter { $0.fileID != file.fileID }
            episodes = remaining
            if remaining.isEmpty {
                playURL = nil
                clearMetrics()
                currentFile = nil
                errorMessage = "当前版本已移入 115 回收站，没有其他可播放版本。"
            } else {
                let next = remaining.first { $0.fileID == currentFile?.fileID } ?? remaining[0]
                try await play(file: next, cookie: Pan115Settings.shared.cookie)
                showNotice("已将当前版本移入 115 回收站")
            }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
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
        resetNotices()
        generation += 1
        currentFile = file
        refreshUsed = false
        fallbackUsed = false
        fileName = file.name
        status = "获取 115 原文件地址…"
        // Only one lookup per opening; no signed URL is persisted.
        let original = try? await Pan115Client.shared.originalStream(pickCode: file.pickCode, cookie: cookie)
        let hls = (try? await Pan115Client.shared.streamsForVideo(pickCode: file.pickCode, cookie: cookie, filename: file.name)) ?? []
        streams = original.map { [$0] + hls } ?? hls
        guard let best = streams.first else { throw Pan115Error.playURLNotFound }
        activate(best)
        if original == nil { showNotice("原文件地址不可用，使用 HLS 转码") }

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
