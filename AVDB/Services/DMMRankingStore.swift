import Foundation
import Combine

enum DMMRankingFetchSource: String, Sendable {
    case webView, graphql, direct, imported
}

/// Public metadata only. Ephemeral requests never borrow Safari cookies or persist sessions.
@MainActor final class DMMRankingStore: ObservableObject {
    @Published var kind: DMMRankingKind = .weekly
    @Published private(set) var board: DMMRankingBoard?
    @Published private(set) var evidence: [String: DMMManufacturerEvidence] = [:]
    @Published private(set) var messages: [String: String] = [:]
    @Published private(set) var status = "授权成年自声明后可自动刷新日/周/月榜与月间女优榜；HTML导入仅作手动后备。"
    @Published private(set) var imported = false
    @Published private(set) var fetchSource: DMMRankingFetchSource?
    private var generation = UUID()
    private var queue: [DMMContentRow] = []
    private var tasks: [String: Task<Void, Never>] = [:]
    private var cache: [String: (DMMManufacturerEvidence, Date)] = [:]
    private let transport: DMMTransport
    /// Optional overrides for regressions (macOS / offline).
    var hydrateOverride: ((DMMRankingKind, Bool) async throws -> (String, URL))?
    var graphqlOverride: ((DMMRankingKind) async throws -> DMMRankingBoard)?
    /// Offline/macOS harness: CID -> official makerContentId / メーカー品番.
    var makerCodeOverride: (([String]) async throws -> [String: String])?

    var authorizeAdultDeclaration: Bool {
        get { UserDefaults.standard.bool(forKey: "dmm.authorizedAdultDeclaration") }
        set { UserDefaults.standard.set(newValue, forKey: "dmm.authorizedAdultDeclaration") }
    }
    func forgetSession() async {
        cancel()
        await transport.clear()
        DMMRankingHydrator.cancelActive()
    }
    init(transport: DMMTransport = DMMTransport()) { self.transport = transport }
    func cancel() {
        generation = UUID(); queue.removeAll()
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
        DMMRankingHydrator.cancelActive()
    }
    /// Cancel on-demand detail/maker retries without aborting board-level makerContentId resolve.
    func cancelDetails() {
        queue.removeAll()
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
    }
    private func document(_ url: URL) async throws -> (String, URL) {
        try await transport.document(url, authorizeAdultDeclaration: authorizeAdultDeclaration)
    }
    func select(_ next: DMMRankingKind) {
        guard next != kind else { return }
        cancel()
        kind = next
        board = nil; evidence.removeAll(); messages.removeAll(); imported = false; fetchSource = nil
        status = "已切换到\(next.periodLabel)。可刷新或导入对应完整榜单HTML。"
    }

    /// Refresh order: WKWebView hydrate → verified GraphQL → URLSession document. HTML import stays manual.
    func refresh() async {
        cancel(); let epoch = generation
        let target = kind
        guard authorizeAdultDeclaration else {
            board = nil; evidence.removeAll(); messages.removeAll(); imported = false; fetchSource = nil
            status = "请先开启成年自声明授权，才能自动刷新官方榜单。"
            return
        }
        status = "正在通过页面渲染读取\(target.periodLabel)…"
        if let board = await refreshViaWebView(target, epoch: epoch) { return apply(board, source: .webView, epoch: epoch) }
        guard epoch == generation else { return }
        status = "页面渲染未取得完整榜单，改用 GraphQL…"
        if let board = await refreshViaGraphQL(target, epoch: epoch) { return apply(board, source: .graphql, epoch: epoch) }
        guard epoch == generation else { return }
        status = "正在尝试直连文档（不带浏览器Cookie）…"
        do {
            let (html, url) = try await document(target.sourceURL)
            let result = try DMMRankingCore.board(html: html, responseURL: url, observedAt: Date())
            guard epoch == generation, result.kind == target else { return }
            apply(result, source: .direct, epoch: epoch)
        } catch {
            guard epoch == generation else { return }
            board = nil; evidence.removeAll(); messages.removeAll(); imported = false; fetchSource = nil
            status = "LIVE_BLOCKED：自动刷新未取得完整\(target.periodLabel)。可稍后重试，或导入自行正常取得的HTML。不编造榜行。"
        }
    }

    private func apply(_ result: DMMRankingBoard, source: DMMRankingFetchSource, epoch: UUID) {
        guard epoch == generation, result.kind == kind else { return }
        board = result; evidence.removeAll(); messages.removeAll(); imported = (source == .imported); fetchSource = source
        let label: String
        switch source {
        case .webView: label = "页面渲染"
        case .graphql: label = "GraphQL"
        case .direct: label = "直连文档"
        case .imported: label = "用户导入"
        }
        status = "\(label)读取\(result.count)个榜位（\(result.periodLabel)）；统计起止未提供。"
        if !result.kind.isActress, source != .imported {
            Task { await self.resolveMakerCodes(rows: result.contentRows, epoch: epoch) }
        }
    }

    /// Prefer official GraphQL makerContentId (メーカー品番). Never invent from CID.
    private func resolveMakerCodes(rows: [DMMContentRow], epoch: UUID) async {
        let missing = rows.filter { evidence[$0.cid] == nil }
        guard epoch == generation, !missing.isEmpty else { return }
        status = "正在读取厂家品番（makerContentId）…"
        do {
            let map: [String: String]
            if let makerCodeOverride {
                map = try await makerCodeOverride(missing.map(\.cid))
            } else {
                map = try await DMMRankingGraphQL.makerCodes(cids: missing.map(\.cid))
            }
            guard epoch == generation else { return }
            var got = 0
            for row in missing {
                guard let raw = map[row.cid], let code = DMMRankingCore.manufacturerCode(raw) else { continue }
                evidence[row.cid] = DMMManufacturerEvidence(cid: row.cid, code: code, sourceURL: row.sourceURL)
                messages[row.cid] = "厂家品番已核对"
                got += 1
            }
            guard epoch == generation else { return }
            if got == missing.count {
                status = "厂家品番已全部核对（\(got)/\(missing.count)），未从CID推号。"
            } else if got > 0 {
                status = "厂家品番已核对 \(got)/\(missing.count)；其余保留未知，可点详情重试。未从CID推号。"
            } else {
                status = "厂家品番暂未取得；可点「获取 / 重试详情」。未从CID推号。"
            }
        } catch {
            guard epoch == generation else { return }
            status = "厂家品番读取受限；可点「获取 / 重试详情」或导入详情HTML。未从CID推号。"
        }
    }

    private func refreshViaWebView(_ target: DMMRankingKind, epoch: UUID) async -> DMMRankingBoard? {
        do {
            let (html, url): (String, URL)
            if let hydrateOverride {
                (html, url) = try await hydrateOverride(target, authorizeAdultDeclaration)
            } else {
                #if canImport(UIKit) && canImport(WebKit)
                (html, url) = try await DMMRankingHydrator.shared.document(kind: target, authorizeAdultDeclaration: authorizeAdultDeclaration)
                #else
                throw DMMRankingError.accessGate
                #endif
            }
            guard epoch == generation else { return nil }
            let result = try DMMRankingCore.board(html: html, responseURL: url, observedAt: Date())
            guard result.kind == target else { return nil }
            return result
        } catch {
            return nil
        }
    }

    private func refreshViaGraphQL(_ target: DMMRankingKind, epoch: UUID) async -> DMMRankingBoard? {
        do {
            let result: DMMRankingBoard
            if let graphqlOverride {
                result = try await graphqlOverride(target)
            } else {
                result = try await DMMRankingGraphQL.fetch(target)
            }
            guard epoch == generation, result.kind == target else { return nil }
            return result
        } catch {
            return nil
        }
    }

    /// Imported detail must declare one canonical identity; file names and sku are not evidence.
    func importHTML(_ data: Data) throws {
        guard data.count <= 8_000_000, let html = String(data: data, encoding: .utf8) else { throw DMMRankingError.malformed }
        let candidates = [kind] + DMMRankingKind.allCases.filter { $0 != kind }
        for candidate in candidates {
            if let result = try? DMMRankingCore.board(html: html, responseURL: candidate.sourceURL, observedAt: Date()) {
                                cancel(); kind = result.kind; board = result
                evidence.removeAll(); messages.removeAll(); imported = true; fetchSource = .imported
                status = "用户导入\(result.count)榜位 · \(result.periodLabel) · 导入时间不是采集时间，来源统计起止未知。"
                return
            }
        }
        let re = try NSRegularExpression(pattern: "<link\\b(?=[^>]*\\brel=[\"']canonical[\"'])[^>]*\\bhref=[\"']([^\"']+)[\"'][^>]*>", options: [.caseInsensitive])
        let ns = html as NSString
        let urls = Set(re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&") })
        guard urls.count == 1, let raw = urls.first, let url = URL(string: raw),
              let cid = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              board?.contentRows.contains(where: { $0.cid == cid }) == true else { throw DMMRankingError.conflictingIdentity }
        let item = try DMMRankingCore.manufacturer(html: html, responseURL: url, expectedCID: cid)
        evidence[cid] = item; messages[cid] = "用户导入详情已核对厂家品番"
    }
    func request(_ row: DMMContentRow) {
        guard evidence[row.cid] == nil, tasks[row.cid] == nil, !queue.contains(where: { $0.cid == row.cid }) else { return }
        if let saved = cache[row.cid], Date().timeIntervalSince(saved.1) < 86400 { evidence[row.cid] = saved.0; return }
        guard queue.count < 100 else { return }
        queue.append(row); messages[row.cid] = "排队核对厂家品番"; pump()
    }
    private func pump() {
        while tasks.count < 2, !queue.isEmpty {
            let row = queue.removeFirst(), epoch = generation
            tasks[row.cid] = Task { [weak self] in
                guard let self else { return }
                do {
                    var item: DMMManufacturerEvidence?
                    if let override = self.makerCodeOverride {
                        if let raw = try await override([row.cid])[row.cid], let code = DMMRankingCore.manufacturerCode(raw) {
                            item = DMMManufacturerEvidence(cid: row.cid, code: code, sourceURL: row.sourceURL)
                        }
                    } else if let raw = try await DMMRankingGraphQL.makerCodes(cids: [row.cid])[row.cid], let code = DMMRankingCore.manufacturerCode(raw) {
                        item = DMMManufacturerEvidence(cid: row.cid, code: code, sourceURL: row.sourceURL)
                    }
                    if item == nil {
                        let (html, url) = try await self.document(row.sourceURL)
                        item = try DMMRankingCore.manufacturer(html: html, responseURL: url, expectedCID: row.cid)
                    }
                    guard let item, !Task.isCancelled, epoch == self.generation else { return }
                    self.evidence[row.cid] = item; self.cache[row.cid] = (item, Date())
                    if self.cache.count > 160, let oldest = self.cache.min(by: { $0.value.1 < $1.value.1 })?.key { self.cache.removeValue(forKey: oldest) }
                    self.messages[row.cid] = "厂家品番已核对"
                } catch {
                    guard !Task.isCancelled, epoch == self.generation else { return }
                    self.messages[row.cid] = "来源访问受限或身份冲突 · 可重试/导入详情HTML；不猜番号"
                }
                guard epoch == self.generation else { return }
                self.tasks.removeValue(forKey: row.cid); self.pump()
            }
        }
    }
}
