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

struct DrawHistoryView: View {
    @ObservedObject private var store = DrawHistoryStore.shared

    var body: some View {
        List(store.records) { record in
            NavigationLink {
                MovieDetailView(movieID: record.movieID)
            } label: {
                HStack {
                    JavDBImage(url: record.coverURL, maxPixelSize: 240)
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
                                JavDBImage(url: movie.coverURL ?? movie.thumbURL, maxPixelSize: 480)
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
