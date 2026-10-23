#if canImport(SwiftUI)
import Foundation
import SwiftUI
@MainActor final class OnlineSubtitleModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { cancelPending(); results = []; languages = [:]; detailStates = [:] } } }
    @Published var results: [OnlineSubtitleCandidate] = []
    @Published var status = "尚未搜索"
    @Published var sourceStates: [OnlineSubtitleSource: String] = [:]
    @Published var languages: [String: [OnlineSubtitleCandidate]] = [:]
    @Published var detailStates: [String: String] = [:]
    @Published var selected: OnlineSubtitleCandidate?
    @Published var cues: [OnlineSubtitleCue] = []
    @Published var offset: Double = 0
    @Published var encodingHint = "auto"
    @Published var busy = false
    @Published var rowStates: [String: String] = [:]
    @Published private(set) var pendingID: String?
    private var selectionStatus: String?
    private var details: [String: Task<Void, Never>] = [:]
    private var state = OnlineSubtitleSearchState()
    private var work: Task<Void, Never>?
    private var choice: Task<Void, Never>?
    private var selectionGeneration = 0
    private var downloading = false
    private struct CacheEntry { let date: Date; let rows: [OnlineSubtitleCandidate] }
    private var cache: [String: CacheEntry] = [:]
    private let fetch: OnlineSubtitleParallelSearch.Fetch
    init(fetch: @escaping OnlineSubtitleParallelSearch.Fetch = { url, kind in
        try await OnlineSubtitleRequest(kind: kind, boundDownloadURL: kind == .download ? url : nil).run(url)
    }) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--subtitle-controls-fixture") {
            self.fetch = { url, kind in
                switch kind {
                case .xunleiSearch:
                    return Data(#"{"code":0,"data":[{"name":"自创合法测试字幕","ext":"srt","languages":[],"url":"https://subtitle.v.geilijiasu.com/AA/BB/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.srt"}]}"#.utf8)
                case .catSearch:
                    return Data("<table class='sub-table'><tr><td><a href='/subs/1/fixture.html'>自创 SubtitleCat 字幕</a></td></tr></table>".utf8)
                case .catDetail:
                    return Data("<div class='sub-single'><a id='download_zh-CN' href='/subs/2/fixture-zh-CN.srt'>Download</a><a id='download_zh-TW' href='/subs/1/fixture-zh-TW.srt'>Download</a></div>".utf8)
                case .download:
                    return Data("1\n00:00:00,000 --> 00:00:06,000\n自创外置字幕第一段\n\n2\n00:00:06,000 --> 00:02:00,000\n自创外置字幕第二段\n".utf8)
                }
            }
            return
        }
        #endif
        self.fetch = fetch
    }
    private func cancelChoice() {
        if let id = pendingID { rowStates[id] = "已取消；点按重试（旧字幕保留）"; selectionStatus = rowStates[id]; status = selectionStatus! }
        pendingID = nil
        selectionGeneration += 1; choice?.cancel(); choice = nil; downloading = false; busy = !state.pending.isEmpty
    }
    func cancelPending() {
        state.invalidate(); work?.cancel(); work = nil; cancelChoice()
        for task in details.values { task.cancel() }; details = [:]
        for key in Array(detailStates.keys) where detailStates[key] == "读取语言中…" { detailStates[key] = "已取消；点按展开语言重试" }
        for source in OnlineSubtitleSource.allCases where sourceStates[source] == "搜索中…" { sourceStates[source] = "已取消" }
        busy = false
        if status == "下载选中字幕…" || status == "搜索中…" { status = "已取消未完成请求；已加载字幕保留" }
    }
    func clear() {
        cancelPending(); cues = []; selected = nil; results = []; languages = [:]; detailStates = [:]
        offset = 0; cache = [:]; query = ""; encodingHint = "auto"; sourceStates = [:]; status = "尚未搜索"
    }
    func disable() {
        cancelPending(); cues = []; selected = nil; offset = 0; status = "字幕已关闭"
    }
    func search() {
        cancelPending()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do { _ = try OnlineSubtitlePolicy.searchURL(q) } catch { status = error.localizedDescription; return }
        let token = state.begin(); results = []; languages = [:]; detailStates = [:]
        sourceStates = state.states; busy = true; selectionStatus = nil; rowStates = [:]; status = "搜索中…"
        // Bounded cache: source + visible query; expired entries cannot cross providers.
        cache = cache.filter { Date().timeIntervalSince($0.value.date) < 120 }
        if cache.count > 40 { cache = [:] }
        var cached: [OnlineSubtitleSource: [OnlineSubtitleCandidate]] = [:]
        for source in OnlineSubtitleSource.allCases { cached[source] = cache[source.rawValue + ":" + q]?.rows }
        let fetch = self.fetch
        work = Task { [weak self] in
            await OnlineSubtitleParallelSearch.run(query: q, cached: cached, fetch: fetch) { outcome in
                await self?.accept(outcome, query: q, token: token)
            }
        }
    }
    private func accept(_ outcome: OnlineSubtitleSearchOutcome, query q: String, token: Int) {
        guard state.receive(outcome.source, token: token, result: outcome.result) else { return }
        if case .success(let rows) = outcome.result { cache[outcome.source.rawValue + ":" + q] = .init(date: Date(), rows: rows) }
        results = state.results; sourceStates = state.states; busy = !state.pending.isEmpty || downloading
        if let selectionStatus { status = selectionStatus }
        else { status = !state.pending.isEmpty ? "部分结果已到达，另一来源搜索中…" : "搜索完成；请手选字幕。名称匹配不代表时间轴匹配" }
    }
    func choose(_ row: OnlineSubtitleCandidate) {
        // A metadata row may ONLY fetch languages. Downloads require explicit variant selection.
        guard results.contains(where: { $0.id == row.id }) || languages.values.contains(where: { $0.contains(row) }) else { return }
        let epoch = state.generation
        let fetch = self.fetch; let hint = encodingHint
        if row.ext == "html" {
            // Expansion is independent of selection: cached/repeated parent taps never cancel a download.
            if languages[row.id] != nil || details[row.id] != nil { return }
            detailStates[row.id] = "读取语言中…"
            details[row.id] = Task { [weak self] in
                do {
                    let data = try await fetch(row.url, .catDetail)
                    let variants = try SubtitleCatProvider.languages(data, row: row)
                    guard let self, self.state.generation == epoch, !Task.isCancelled else { return }
                    self.languages[row.id] = variants
                    self.detailStates[row.id] = variants.isEmpty ? "尚无现成字幕，请到原站处理；不会自动翻译" : "请选择语言（仅现成下载）"
                    self.details[row.id] = nil
                } catch {
                    guard let self, self.state.generation == epoch, !Task.isCancelled else { return }
                    self.detailStates[row.id] = "读取失败：\(error.localizedDescription)；点按展开语言重试"
                    self.details[row.id] = nil
                }
            }
            return
        }
        guard pendingID != row.id else { return }
        cancelChoice(); let token = selectionGeneration
        pendingID = row.id; rowStates[row.id] = "下载中…（旧字幕保留）"
        downloading = true; busy = true; status = "下载选中字幕…"; selectionStatus = status
        choice = Task { [weak self] in
            do {
                let data = try await fetch(row.url, .download)
                guard let self, self.selectionGeneration == token, self.state.generation == epoch, !Task.isCancelled else { return }
                self.rowStates[row.id] = "解析中…（旧字幕保留）"
                self.status = "解析选中字幕…"; self.selectionStatus = self.status
                let cues = try await Task.detached(priority: .userInitiated) { try OnlineSubtitleParser.parse(data, ext: row.ext, encodingHint: hint) }.value
                guard self.selectionGeneration == token, self.state.generation == epoch, !Task.isCancelled else { return }
                self.pendingID = nil; self.choice = nil
                self.rowStates[row.id] = nil
                self.downloading = false; self.busy = !self.state.pending.isEmpty
                self.cues = cues; self.selected = row; self.offset = 0
                self.status = "已加载（来源：\(row.source.title) · \(row.language)）"; self.selectionStatus = self.status
                #if os(iOS) && !SUBTITLE_CORE_TEST
                GlassHaptic.tap()
                #endif
            } catch {
                guard let self, self.selectionGeneration == token, self.state.generation == epoch, !Task.isCancelled else { return }
                self.downloading = false; self.busy = !self.state.pending.isEmpty
                self.pendingID = nil; self.choice = nil
                self.rowStates[row.id] = "加载失败：\(error.localizedDescription)；点按重试（旧字幕保留）"
                self.status = self.rowStates[row.id]!; self.selectionStatus = self.status
            }
        }
    }
}
#endif
