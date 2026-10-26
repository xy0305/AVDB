import SwiftUI
import UniformTypeIdentifiers

@MainActor struct DMMRankingView: View {
    @StateObject private var store = DMMRankingStore()
    @State private var importing = false
    @State private var importError: String?
    @State private var page = 0
    var body: some View {
        VStack(spacing: 8) {
            Text("周榜 · 100榜位 · 统计起止未知").font(.headline)
            Text(store.status).font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("dmm-source-status")
            HStack {
                Button("尝试直连") { Task { await store.refresh() } }
                Button("导入HTML") { importing = true }.accessibilityIdentifier("dmm-import")
                Link("正常访问来源", destination: DMMRankingStore.weeklyURL)
            }.font(.caption)
            if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
            if let board = store.board {
                HStack {
                    Button("上一页") { store.cancel(); page -= 1 }.disabled(page == 0)
                    Spacer()
                    Text("\(page + 1) / 5 · \(store.imported ? "用户导入" : "本次直连")").font(.caption)
                    Spacer()
                    Button("下一页") { store.cancel(); page += 1 }.disabled(page == 4)
                }
                DMMRankingPage(store: store, rows: Array(board.rows.dropFirst(page * 20).prefix(20)))
                    .id("\(board.observedAt.timeIntervalSince1970)|\(page)")
            } else {
                ContentUnavailableView("来源访问受限", systemImage: "doc.badge.arrow.up", description: Text("未加载实时榜单。可导入合法取得的完整周榜HTML；详情HTML需包含同CID的canonical及厂家品番表格。日/月/实时/女优/系列尚未接入。"))
            }
        }
        .padding(.horizontal)
        .background { LiquidGlassBackground() }
        .navigationTitle("DMM 周榜 · Preview")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.html], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try store.importHTML(Data(contentsOf: url))
                }
                page = 0; importError = nil
            } catch { importError = "未导入：需要完整100榜位，或具有唯一canonical、同CID配信品番和唯一厂家品番的详情HTML。" }
        }
        .onDisappear { store.cancel() }
    }
}

@MainActor private struct DMMRankingPage: View {
    @ObservedObject var store: DMMRankingStore
    let rows: [DMMRankingRow]
    @StateObject private var mapper = JavVerseMapper(scope: "dmm|weekly|manufacturer-verified")
    private func entry(_ row: DMMRankingRow) -> JavVerseEntry? {
        guard let item = store.evidence[row.cid], item.cid == row.cid else { return nil }
        return JavVerseEntry(rank: row.rank, kind: "movie", label: item.code, sourceURL: row.sourceURL.absoluteString, code: item.code)
    }
    var body: some View {
        List(rows) { row in
            VStack(alignment: .leading, spacing: 6) {
                Text("#\(row.rank) · DMM · \(row.cid)").font(.caption).foregroundStyle(.secondary)
                if let item = entry(row) {
                    Text(item.label).font(.headline)
                    if let movie = mapper.movie(for: item) {
                        NavigationLink { MovieDetailView(movieID: movie.id) } label: {
                            HStack {
                                if let cover = movie.coverURL {
                                    JavDBImage(url: cover, fallbackURL: movie.thumbURL, contentMode: .fit, frontPoster: true)
                                        .frame(width: 64, height: 90)
                                }
                                Text(movie.title ?? item.label)
                            }
                        }.accessibilityIdentifier("dmm-movie-\(row.rank)")
                    } else {
                        Text(mapper.messages[item.id] ?? "未匹配 · 保留源榜位").font(.caption)
                        Button("精确核对AVDB") { mapper.resolve([item], retry: true) }
                            .disabled(mapper.busy)
                    }
                } else {
                    Text("厂家品番未知 · 未匹配").font(.headline)
                    Text(store.messages[row.cid] ?? "按需核对，不从CID推号").font(.caption)
                    Button("获取 / 重试详情") { store.request(row) }
                }
                NavigationLink("手动搜索核对（不自动认领）") { SearchView() }.font(.caption)
            }.padding(.vertical, 4).accessibilityIdentifier("dmm-rank-\(row.rank)")
        }.listStyle(.plain)
        .onDisappear { mapper.cancel() }
    }
}
