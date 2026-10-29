//
//  LibraryFeaturesView.swift
//  AVDB
//
//  稍后再看、下载队列、新作提醒、抽签历史和三连挑战。
//

import SwiftUI

struct WatchLaterView: View {
    @ObservedObject private var store = WatchLaterStore.shared

    var body: some View {
        MoviePosterGrid(movies: store.items.map(\.movie))
            .navigationTitle("稍后再看")
            .overlay {
                if store.items.isEmpty {
                    ContentUnavailableView("还没有稍后再看", systemImage: "clock", description: Text("在详情页加入后会出现在这里"))
                }
            }
    }
}

struct UpdateNoticesView: View {
    @ObservedObject private var store = UpdateNoticeStore.shared

    var body: some View {
        List(store.notices) { notice in
            NavigationLink {
                MovieDetailView(movieID: notice.movieID)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.tagName).font(.caption).foregroundStyle(.secondary)
                    Text(notice.number).font(.headline)
                    Text(notice.title).font(.caption).lineLimit(2)
                }
            }
            .swipeActions {
                Button("已读", role: .destructive) { store.dismiss(notice.id) }
            }
        }
        .navigationTitle("新作提醒")
        .overlay {
            if store.notices.isEmpty {
                ContentUnavailableView("暂无新作", systemImage: "bell", description: Text("关注演员、厂牌或系列后会在这里提示"))
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }
}

// MARK: - 观看历史（Build 277）

/// Cover for one history entry: saved detail poster → HQ list pipeline (avbase/DMM/Amazon tip → JavDB);
/// Tangxin entries load their own poster through TangxinClient. Same 0.7 card aspect as MoviePosterCard.
struct PlaybackHistoryCover: View {
    let item: PlaybackHistoryItem
    var maxPixelSize: Int = 700
    @ObservedObject private var store = PlaybackHistoryStore.shared
    @AppStorage("tangxin.systemProxyCompatibility") private var tangxinCompatibility = false

    var body: some View {
        ClippedAspectFill(aspectRatio: 0.7, cornerRadius: 12) {
            artwork
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let source = item.source, !source.isEmpty {
                            GlassChip(text: source, tint: .black, font: .caption2.weight(.semibold),
                                      foreground: .white, compact: true, tintStrength: 0.35)
                        }
                        if let fraction = item.fraction {
                            PlaybackHistoryProgressBar(fraction: fraction)
                        }
                    }
                    .padding(6)
                    .allowsHitTesting(false)
                }
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        if item.isTangxin {
            TangxinImage(url: item.posterURL.flatMap { URL(string: $0) },
                         client: TangxinClient().withDNSMode(tangxinCompatibility ? .systemProxy : .strict))
        } else if let image = store.artwork(for: item.movieID) {
            Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
        } else {
            MoviePosterImage(movie: item.movie, maxPixelSize: maxPixelSize)
        }
    }
}

struct PlaybackHistoryProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.35))
                Capsule().fill(Color.accentColor)
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(height: 3)
    }
}

/// Destination for one entry: catalog detail (resume via the detail's play buttons / saved progress),
/// or the Tangxin detail for 糖心 entries.
struct PlaybackHistoryDestination: View {
    let item: PlaybackHistoryItem
    @AppStorage("tangxin.systemProxyCompatibility") private var tangxinCompatibility = false
    var body: some View {
        if item.isTangxin, let page = item.pageURL.flatMap { URL(string: $0) } {
            TangxinDetailView(video: TangxinVideo(url: page, title: item.title,
                                                  poster: item.posterURL.flatMap { URL(string: $0) }, author: nil),
                              client: TangxinClient().withDNSMode(tangxinCompatibility ? .systemProxy : .strict))
        } else {
            MovieDetailView(movieID: item.movieID, seed: item.movie)
        }
    }
}

/// Tangxin detail pushes author / tag / video values; the 我的 stack must resolve them too.
struct TangxinHistoryDestinations: ViewModifier {
    @AppStorage("tangxin.systemProxyCompatibility") private var tangxinCompatibility = false
    func body(content: Content) -> some View {
        let client = TangxinClient().withDNSMode(tangxinCompatibility ? .systemProxy : .strict)
        content
            .navigationDestination(for: TangxinVideo.self) { TangxinDetailView(video: $0, client: client) }
            .navigationDestination(for: TangxinAuthor.self) { author in
                TangxinListView(root: author.url, title: author.name, client: client, isAuthor: true)
            }
            .navigationDestination(for: TangxinTag.self) { tag in
                TangxinListView(root: tag.url, title: tag.name, client: client)
            }
    }
}

/// 「我的」页：最近观看横向封面条 + 全部入口。
struct PlaybackHistorySection: View {
    @ObservedObject private var store = PlaybackHistoryStore.shared
    @State private var pendingDelete: PlaybackHistoryItem?

    var body: some View {
        Section {
            NavigationLink { PlaybackHistoryView() } label: {
                HStack {
                    Label("观看历史", systemImage: "play.rectangle.on.rectangle")
                    Spacer()
                    Text(store.items.isEmpty ? "全部" : "全部 \(store.items.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("me.history.all")
            if store.items.isEmpty {
                Text("还没有观看记录，开始播放后会显示在这里")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("me.history.empty")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(store.items.prefix(20))) { item in
                            NavigationLink { PlaybackHistoryDestination(item: item) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    PlaybackHistoryCover(item: item, maxPixelSize: 500)
                                        .frame(width: 96)
                                    Text(item.isTangxin ? item.title : item.number)
                                        .font(.caption.weight(.semibold)).foregroundStyle(.tint).lineLimit(1)
                                    Text(PlaybackHistoryFormat.relative(item.playedAt))
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(width: 96, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("me.history.item.\(item.id)")
                            .contextMenu {
                                Button(role: .destructive) { store.remove(item.id) } label: { Label("删除这条记录", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
    }
}

struct PlaybackHistoryView: View {
    @ObservedObject private var store = PlaybackHistoryStore.shared
    @State private var confirmClear = false
    @Environment(\.availableLayoutSize) private var layoutSize
    @State private var measuredWidth: CGFloat = 0

    private var columns: [GridItem] {
        let count = AdaptiveLayout.columnCount(width: measuredWidth > 0 ? measuredWidth : layoutSize.width,
                                               padding: AdaptiveLayout.gridPadding, spacing: 12)
        return Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: count)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(store.items) { item in
                    NavigationLink { PlaybackHistoryDestination(item: item) } label: {
                        card(item)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .clipped()
                    .accessibilityIdentifier("history.item.\(item.id)")
                    .contextMenu {
                        Button(role: .destructive) { store.remove(item.id) } label: { Label("删除这条记录", systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, AdaptiveLayout.gridPadding)
            .padding(.vertical, 12)
            .background {
                GeometryReader { geo in
                    Color.clear.onAppear { measuredWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in measuredWidth = w }
                }
            }
            if !store.items.isEmpty {
                Text("长按封面可删除单条 · 仅保存在本机，不含视频链接")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
        }
        .navigationTitle("观看历史")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空", role: .destructive) { confirmClear = true }
                    .disabled(store.items.isEmpty)
                    .accessibilityIdentifier("history.clear")
            }
        }
        .confirmationDialog("清空本机的全部观看历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空观看历史", role: .destructive) { store.clear() }
            Button("取消", role: .cancel) {}
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView("还没有观看历史", systemImage: "play.rectangle",
                                       description: Text("实际开始播放作品后记录，仅保存在本机，不含视频链接。"))
            }
        }
    }

    private func subtitle(_ item: PlaybackHistoryItem) -> String {
        let when = PlaybackHistoryFormat.relative(item.playedAt)
        guard let progress = PlaybackHistoryFormat.progressText(item) else { return when }
        return when + " · " + progress
    }

    private func card(_ item: PlaybackHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PlaybackHistoryCover(item: item)
            if !item.isTangxin {
                Text(item.number)
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint).lineLimit(1)
            }
            Text(item.title)
                .font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 36, alignment: .top)
            Text(subtitle(item))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct DrawHistoryView: View {
    @ObservedObject private var store = DrawHistoryStore.shared

    var body: some View {
        List(store.records) { record in
            NavigationLink {
                MovieDetailView(movieID: record.movieID)
            } label: {
                HStack {
                    MoviePosterImage(movie: Movie(id: record.movieID, type: record.type, number: record.number,
                                                 thumbURL: record.thumbURL ?? record.coverURL, coverURL: record.coverURL), maxPixelSize: 480)
                        .frame(width: 48, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.number).font(.headline)
                        Text(record.day).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("抽签历史")
        .overlay {
            if store.records.isEmpty {
                ContentUnavailableView("还没有抽签记录", systemImage: "sparkles")
            }
        }
    }
}

struct DownloadQueueView: View {
    @StateObject private var queue = DownloadQueueStore()

    var body: some View {
        List {
            if !queue.pending.isEmpty {
                Section("等待") {
                    ForEach(queue.pending) { item in
                        queueRow(item.number, item.title, "等待推送")
                    }
                }
            }
            if !queue.finished.isEmpty {
                Section("完成") {
                    ForEach(queue.finished) { item in
                        queueRow(item.number, item.message, "完成")
                    }
                }
            }
            if !queue.failed.isEmpty {
                Section("失败") {
                    ForEach(queue.failed) { item in
                        queueRow(item.number, item.message, "失败")
                    }
                }
            }
        }
        .navigationTitle("下载队列")
        .overlay {
            if queue.pending.isEmpty && queue.finished.isEmpty && queue.failed.isEmpty {
                ContentUnavailableView("队列是空的", systemImage: "arrow.down.circle", description: Text("详情页可批量推送磁力或 ed2k"))
            }
        }
    }

    private func queueRow(_ title: String, _ subtitle: String, _ state: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Text(state).font(.caption2).foregroundStyle(.blue)
        }
    }
}

@MainActor
final class DownloadQueueStore: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let number: String
        let title: String
        var message: String
    }

    @Published var pending: [Item] = []
    @Published var finished: [Item] = []
    @Published var failed: [Item] = []
    static let shared = DownloadQueueStore()

    func enqueue(movie: Movie, links: [String]) {
        let settings = Pan115Settings.shared
        guard settings.isConfigured else {
            failed.insert(Item(number: movie.displayNumber, title: movie.displayTitle, message: settings.missingHint), at: 0)
            return
        }
        let items = links.map { Item(number: movie.displayNumber, title: $0, message: "等待推送") }
        pending.append(contentsOf: items)
        Task {
            for item in items {
                pending.removeAll { $0.id == item.id }
                do {
                    let result = try await Pan115Client.shared.addOfflineTask(
                        url: item.title,
                        cookie: settings.cookie,
                        folderCID: settings.folderCID
                    )
                    finished.insert(Item(number: item.number, title: item.title, message: result.message), at: 0)
                } catch {
                    failed.insert(Item(number: item.number, title: item.title, message: error.localizedDescription), at: 0)
                }
            }
        }
    }
}

struct TripleDrawView: View {
    @State private var picks: [Movie] = []
    @State private var savedID: String?

    var body: some View {
        VStack(spacing: 18) {
            if picks.isEmpty {
                ContentUnavailableView("准备三张卡牌", systemImage: "rectangle.stack")
            } else {
                HStack(spacing: 10) {
                    ForEach(picks) { movie in
                        Button {
                            WatchLaterStore.shared.toggle(movie)
                            savedID = movie.id
                            GlassHaptic.success()
                        } label: {
                            VStack(spacing: 6) {
                                MoviePosterImage(movie: movie, maxPixelSize: 900)
                                    .frame(width: 108, height: 152)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(savedID == movie.id ? "已想看" : movie.displayNumber)
                                    .font(.caption2.weight(.bold))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button("再抽三张") { Task { await load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("随机挑战")
        .task { if picks.isEmpty { await load() } }
    }

    private func load() async {
        let page = Int.random(in: 1...8)
        let movies = (try? await JavDBSDK.shared.latestMovies(page: page, limit: 12, type: "all")) ?? []
        picks = Array(movies.shuffled().prefix(3))
        savedID = nil
    }
}
