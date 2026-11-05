import SwiftUI
import UIKit

// Build 308: ONE tab UI. Sections/search/detail all run on OneClient (the native
// port of the one-rex.js widget protocol); playback reuses KSChromePlayer.

struct OneKeyword: Hashable, Identifiable {
    let keyword: String
    var id: String { keyword }
}

extension OneArticle {
    /// Minimal seed for navigation entry points that only know an id
    /// (episode rows, playback-history entries); the detail view refetches.
    static func stub(id: Int, title: String, cover: URL?) -> OneArticle {
        OneArticle(id: id, title: title, isLiveReplay: false, kindLabel: "视频", author: nil,
                   publishedAt: nil, durationSeconds: 0, sizeLabel: "", summary: "",
                   cover: cover, metaLine: "视频")
    }
}

@MainActor
final class OneListModel: ObservableObject {
    enum Source: Equatable {
        case section(OneSection)
        case keyword(String)
    }
    @Published private(set) var articles: [OneArticle] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var endReached = false
    private var page = 0
    private var started = false
    private var generation = UUID()
    let source: Source
    init(source: Source) { self.source = source }

    func start() async {
        guard !started else { return }
        started = true
        await loadMore()
    }

    func refresh() async {
        generation = UUID()
        page = 0
        articles = []
        endReached = false
        error = nil
        if case .section = source { await OneClient.shared.resetFeeds() }
        started = true
        await loadMore()
    }

    func loadMore() async {
        guard !loading, !endReached else { return }
        let gen = generation
        let nextPage = page + 1
        loading = true
        error = nil
        do {
            let rows: [OneArticle]
            switch source {
            case .section(let section):
                rows = try await OneClient.shared.sectionPage(section, page: nextPage)
            case .keyword(let keyword):
                rows = try await OneClient.shared.searchPage(keyword: keyword, page: nextPage)
            }
            guard gen == generation else { return }
            page = nextPage
            var seen = Set(articles.map(\.id))
            articles += rows.filter { seen.insert($0.id).inserted }
            if rows.count < 24 { endReached = true }
        } catch {
            guard gen == generation else { return }
            if articles.isEmpty { self.error = error.localizedDescription }
        }
        if gen == generation { loading = false }
    }
}

struct OneRootView: View {
    @State private var section: OneSection = .newest
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionBar
                OneListView(source: .section(section))
                    .id(section)
            }
            .navigationTitle("ONE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        OneSearchView()
                    } label: {
                        Label("搜索 ONE", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("one.search.open")
                }
            }
            .navigationDestination(for: OneArticle.self) { OneDetailView(seed: $0) }
            .navigationDestination(for: OneKeyword.self) { keyword in
                OneListView(source: .keyword(keyword.keyword))
                    .navigationTitle(keyword.keyword)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var sectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OneSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline.weight(section == item ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(section == item ? Color.accentColor : Color(.systemGray5),
                                        in: Capsule())
                            .foregroundStyle(section == item ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("one.section.\(item.rawValue)")
                    .accessibilityAddTraits(section == item ? [.isSelected] : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

struct OneSearchView: View {
    @State private var text = ""
    @State private var keyword = ""
    var body: some View {
        Group {
            if keyword.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                    Text("输入番号、演员或标题，搜索 ONE 全库").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OneListView(source: .keyword(keyword)).id(keyword)
            }
        }
        .navigationTitle("搜索 ONE")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $text, prompt: "番号 / 演员 / 标题")
        .onSubmit(of: .search) {
            keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .modifier(HidesFloatingTabBar())
        .accessibilityIdentifier("one.search")
    }
}

struct OneListView: View {
    @StateObject private var model: OneListModel
    init(source: OneListModel.Source) {
        _model = StateObject(wrappedValue: OneListModel(source: source))
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 18) {
                ForEach(model.articles) { article in
                    NavigationLink(value: article) {
                        VStack(alignment: .leading, spacing: 6) {
                            OneImage(url: article.cover)
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(article.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(article.metaLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("one.video.\(article.id)")
                    .onAppear {
                        if article.id == model.articles.last?.id {
                            Task { await model.loadMore() }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            footer.padding(.horizontal)
        }
        .refreshable { await model.refresh() }
        .task { await model.start() }
        .accessibilityIdentifier("one.list")
    }

    @ViewBuilder private var footer: some View {
        if model.loading {
            ProgressView("正在加载 ONE")
                .frame(maxWidth: .infinity, minHeight: 44)
        } else if let error = model.error {
            VStack(spacing: 8) {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("重试") { Task { await model.refresh() } }
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityIdentifier("one.retry")
        } else if model.articles.isEmpty {
            Text("暂无内容，下拉重试。")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else if model.endReached {
            Text("已加载全部")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("one.end")
        } else {
            Button("加载更多") { Task { await model.loadMore() } }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("one.more")
        }
    }
}

struct OneImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                    Text("封面加载失败").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(6)
            } else {
                Image(systemName: "film").foregroundStyle(.secondary)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            failed = false
            guard let url else { return }
            for attempt in 0..<2 {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    try Task.checkCancellation()
                    guard let decoded = UIImage(data: data) else { failed = true; return }
                    image = decoded
                    return
                } catch is CancellationError { return }
                catch {
                    if Task.isCancelled { return }
                    if attempt == 0 { try? await Task.sleep(nanoseconds: 400_000_000) }
                }
            }
            failed = true
        }
    }
}

private struct OnePlayback: Identifiable {
    let lines: [OnePlayLine]
    var index: Int = 0
    var line: OnePlayLine { lines[min(index, lines.count - 1)] }
    var id: String { line.url.absoluteString + "#\(index)" }
}

struct OneDetailView: View {
    let seed: OneArticle
    @State private var detail: OneDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var playback: OnePlayback?
    @State private var request = UUID()

    private var display: OneArticle { detail?.article ?? seed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                Text(display.title).font(.title2.bold())
                Text(display.metaLine).font(.subheadline).foregroundStyle(.secondary)
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12) }
                if let detail {
                    playBar(detail)
                    if !detail.bodyText.isEmpty {
                        Text(detail.bodyText).font(.body)
                    }
                    linesList(detail)
                    episodesList(detail)
                    tagsChips(detail)
                }
                if let error {
                    Text(error).font(.footnote)
                    Button("重试") { request = UUID() }.frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding()
        }
        .navigationTitle("ONE 详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: request) {
            loading = true
            error = nil
            do {
                let value = try await OneClient.shared.detail(id: seed.id)
                try Task.checkCancellation()
                detail = value
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            loading = false
        }
        .fullScreenCover(item: $playback) { play in
            KSChromePlayer(url: play.line.url,
                           title: display.title,
                           subtitle: "ONE · " + play.line.name,
                           progressID: "one:\(seed.id)",
                           onPlaybackFailure: {
                               // CDN hosts die individually (502 / TLS) while the same
                               // file stays up on the other issued hosts: fall through
                               // to the next line instead of dead-ending on the error.
                               if play.index + 1 < play.lines.count {
                                   playback = OnePlayback(lines: play.lines, index: play.index + 1)
                               }
                           },
                           historyMovie: Movie(id: "one:\(seed.id)", number: "ONE", title: display.title),
                           historySource: "ONE",
                           historyPage: URL(string: "one://a/\(seed.id)"),
                           historyPoster: display.cover)
        }
        .accessibilityIdentifier("one.detail")
    }

    private var hero: some View {
        ZStack {
            OneImage(url: display.cover)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if detail?.lines.first != nil {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
                    .liquidGlassCircle()
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if let lines = detail?.lines, !lines.isEmpty { playback = OnePlayback(lines: lines) }
        }
        .accessibilityLabel("播放")
        .accessibilityIdentifier("one.play.cover")
    }

    private func playBar(_ detail: OneDetail) -> some View {
        Group {
            if let first = detail.lines.first {
                Button { playback = OnePlayback(lines: detail.lines) } label: {
                    Label("播放 · \(first.name)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("one.play")
            } else {
                Text("本条为\(display.kindLabel)，无视频源")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    @ViewBuilder private func linesList(_ detail: OneDetail) -> some View {
        if detail.lines.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("播放线路").font(.headline)
                ForEach(detail.lines.indices, id: \.self) { i in
                    Button { playback = OnePlayback(lines: detail.lines, index: i) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detail.lines[i].name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Text(detail.lines[i].note).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle").foregroundStyle(Color.accentColor)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("one.line")
                }
            }
        }
    }

    @ViewBuilder private func episodesList(_ detail: OneDetail) -> some View {
        if !detail.episodes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("合集场次 · 共 \(detail.episodes.count) 场").font(.headline)
                ForEach(detail.episodes) { episode in
                    NavigationLink(value: OneArticle.stub(id: episode.id, title: episode.title, cover: display.cover)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(episode.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(episode.metaLine).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("one.episode.\(episode.id)")
                }
            }
        }
    }

    @ViewBuilder private func tagsChips(_ detail: OneDetail) -> some View {
        let names = detail.tagNames
        let author = display.author
        if !names.isEmpty || author != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("标签").font(.headline)
                FlowLayout(spacing: 8) {
                    if let author {
                        NavigationLink(value: OneKeyword(keyword: author)) {
                            chip(author, accent: false)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(names, id: \.self) { name in
                        NavigationLink(value: OneKeyword(keyword: name)) {
                            chip(name, accent: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("one.tag")
                    }
                }
            }
        }
    }

    private func chip(_ text: String, accent: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(accent ? Color.accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(accent ? Color.accentColor.opacity(0.12) : Color(.systemGray5), in: Capsule())
            .frame(minHeight: 32)
    }
}
