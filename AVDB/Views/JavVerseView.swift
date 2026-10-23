import SwiftUI

// Independent destination: NavigationLink { JavVerseView() } label: { Text("JavVerse · 原站名单") }
// Does not replace Home or AVDB rankings. Register all three Swift files and bundled JSON in Xcode.
@MainActor struct JavVerseView: View {
    @State private var snapshot: JavVerseSnapshot?
    @State private var failure: String?
    @State private var probe = "未测试设备HTTP；当前仅显示离线快照"
    @State private var probing = false
    @State private var probeGeneration = UUID()
    var body: some View {
        List {
            Section {
                Text("静态快照，非实时").font(.headline).foregroundStyle(.orange)
                Text("原站名单及顺序来自 JavVerse 公开文字；图片、资料和播放只通过 AVDB 核验。无网站账户或社区同步。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(probe).font(.caption)
                Button(probing ? "检测中…" : "检测普通HTTP（不刷新快照）") { probing = true }
                    .disabled(probing)
                    .accessibilityIdentifier("javverse-http-probe")
            }
            if let snapshot {
                Section("首页 · 原站当日内容") {
                    ForEach(snapshot.boards.filter { ["featured", "recent"].contains($0.id) }) { board in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink { JavVerseBoardView(board: board) } label: { boardLabel(board) }
                                .accessibilityIdentifier("javverse-board-\(board.id)")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(board.entries) { entry in
                                        VStack(spacing: 6) {
                                            Image(systemName: entry.kind == "movie" ? "film" : "person.crop.square")
                                                .font(.title2).foregroundStyle(.secondary)
                                            Text(entry.label).font(.caption).lineLimit(3)
                                        }
                                        .frame(width: 100, height: 110, alignment: .top)
                                        .padding(8)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            Text("采集 UTC：\(board.capturedAt) · 仅原站首页横栏")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("原站榜单 · 已完整核对的当期名单") {
                    ForEach(snapshot.boards.filter { !["featured", "recent"].contains($0.id) }) { board in
                        NavigationLink { JavVerseBoardView(board: board) } label: { boardLabel(board) }
                            .accessibilityIdentifier("javverse-board-\(board.id)")
                    }
                }
                Section("尚未接入") {
                    Text("Grok250：公开文档含250人六维静态数据，但42页完整名次及同分顺序尚未逐页核对；本版不呈现推断名次。历史期、其他目录、社区、账户内容未接入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .navigationTitle("JavVerse · 原站名单")
        .accessibilityIdentifier("javverse-home")
        .task(id: probing) {
            guard probing else { return }
            #if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") else { probing = false; return }
            #endif
            let epoch = probeGeneration
            defer { if probeGeneration == epoch { probing = false } }
            do {
                var statuses: [Int] = []
                for _ in 0..<3 {
                    try Task.checkCancellation()
                    let status = try await JavVerseHTTPProbe.status()
                    statuses.append(status)
                    if status == 403 { break } // Respect refusal; never retry a WAF rejection.
                }
                try Task.checkCancellation()
                guard probeGeneration == epoch else { return }
                probe = "设备普通HTTP诊断（\(statuses.count)次，最多3次）：\(statuses.map(String.init).joined(separator: ", "))。" + (statuses.contains(403) ? "原站拒绝请求，仍为静态快照。" : "状态不证明有可用实时名单接口，仍为静态快照。")
            } catch {
                if !Task.isCancelled && probeGeneration == epoch { probe = "检测失败：\(error.localizedDescription)。仍为静态快照。" }
            }
        }
        .onDisappear { probeGeneration = UUID(); probing = false }
        .task {
            guard snapshot == nil else { return }
            do {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
                    snapshot = try JavVerseNeutralFixture.snapshot()
                    return
                }
                #endif
                snapshot = try JavVerseSnapshot.bundled()
            } catch { failure = error.localizedDescription }
        }
    }
    private func boardLabel(_ board: JavVerseBoard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(board.title)
            Text("\(board.entries.count)条 · \(board.period)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor private struct JavVerseBoardView: View {
    let board: JavVerseBoard
    @StateObject private var mapper = JavVerseMapper()
    @State private var page = 0
    private var rows: [JavVerseEntry] { JavVersePagination.rows(board.entries, page: page) }
    init(board: JavVerseBoard) {
        self.board = board
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
            _mapper = StateObject(wrappedValue: JavVerseMapper(search: { _, _ in [] }, accountProvider: { nil }))
        }
        #endif
    }
    var body: some View {
        List {
            Section {
                Text("静态快照，非实时").foregroundStyle(.orange)
                Text("期间：\(board.period)")
                Text("采集时间 UTC：\(board.capturedAt)").font(.caption)
                Text("来源：\(board.sourceURL)").font(.caption).textSelection(.enabled)
                Text("名次是原站名次，未匹配项保留、不补位。演员/系列仅保留原站名字，未验证AVDB实体，不可直接跳转。")
                    .font(.caption).foregroundStyle(.secondary)
                if rows.contains(where: { $0.kind == "movie" }) {
                    Button(mapper.busy ? "正在核验…" : "核验本页下一小批（最多4部）") {
                        mapper.resolve(rows.filter { mapper.messages[$0.id] == nil })
                    }.disabled(mapper.busy)
                    if mapper.busy { Button("取消核验") { mapper.cancel() } }
                }
            }
            Section {
                ForEach(rows) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", entry.rank)).font(.headline.monospacedDigit()).frame(width: 34)
                        if let movie = mapper.movie(for: entry), let rawURL = movie.coverURL ?? movie.thumbURL,
                           let url = URL(string: rawURL), url.scheme == "https" {
                            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: {
                                Image(systemName: "film").foregroundStyle(.secondary)
                            }.frame(width: 48, height: 64)
                        } else {
                            Image(systemName: entry.kind == "movie" ? "film" : "person.crop.square")
                                .foregroundStyle(.secondary).frame(width: 48, height: 64)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.label).textSelection(.enabled).accessibilityIdentifier("javverse-row-\(entry.rank)")
                            if let movie = mapper.movie(for: entry) {
                                NavigationLink("AVDB 资料与播放") { MovieDetailView(movieID: movie.id) }
                            } else if entry.kind == "movie" {
                                Text(mapper.messages[entry.id] ?? "未匹配 · 中性占位").font(.caption).foregroundStyle(.secondary)
                                Button("单独核验 / 重试") { mapper.resolve([entry]) }.disabled(mapper.busy)
                            } else {
                                Text("实体未匹配 · 不使用网站数字ID直达AVDB").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                HStack {
                    Button("上一页") { mapper.cancel(); page -= 1 }.disabled(page == 0)
                    Spacer()
                    Text("\(page + 1) / \(JavVersePagination.count(board.entries))").font(.caption)
                    Spacer()
                    Button("下一页") { mapper.cancel(); page += 1 }.disabled((page + 1) * 20 >= board.entries.count)
                }
            }
        }
        .navigationTitle(board.title)
        .onDisappear { mapper.cancel() }
    }
}
