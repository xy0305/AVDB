import Foundation
import Combine

/// Public metadata only. Ephemeral requests never borrow browser cookies or persist sessions.
@MainActor final class DMMRankingStore: ObservableObject {
    static let weeklyURL = URL(string: "https://video.dmm.co.jp/av/ranking/?term=weekly")!
    @Published private(set) var board: DMMWeeklyBoard?
    @Published private(set) var evidence: [String: DMMManufacturerEvidence] = [:]
    @Published private(set) var messages: [String: String] = [:]
    @Published private(set) var status = "来源访问受限时可导入自行正常取得的周榜HTML；不会使用浏览器会话。"
    @Published private(set) var imported = false
    private var generation = UUID()
    private var queue: [DMMRankingRow] = []
    private var tasks: [String: Task<Void, Never>] = [:]
    private var cache: [String: (DMMManufacturerEvidence, Date)] = [:]
    private let transport: DMMTransport
    var authorizeAdultDeclaration: Bool {
        get { UserDefaults.standard.bool(forKey: "dmm.authorizedAdultDeclaration") }
        set { UserDefaults.standard.set(newValue, forKey: "dmm.authorizedAdultDeclaration") }
    }
    func forgetSession() async { cancel(); await transport.clear() }
    init(transport: DMMTransport = DMMTransport()) { self.transport = transport }
    func cancel() {
        generation = UUID(); queue.removeAll()
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
    }
    private func document(_ url: URL) async throws -> (String, URL) {
        try await transport.document(url, authorizeAdultDeclaration: authorizeAdultDeclaration)
    }
    func refresh() async {
        cancel(); let epoch = generation
        status = "正在请求来源（不带浏览器Cookie）…"
        do {
            let (html, url) = try await document(Self.weeklyURL)
            let result = try DMMRankingCore.weekly(html: html, responseURL: url, observedAt: Date())
            guard epoch == generation else { return }
            board = result; evidence.removeAll(); messages.removeAll(); imported = false
            status = "本次直连读取100个榜位；统计起止未提供。"
        } catch {
            guard epoch == generation else { return }
            status = "来源访问受限或文档未通过完整性验证。可导入自行正常取得的HTML。现有导入不会被冒充实时。"
        }
    }
    /// Imported detail must declare one canonical identity; file names and sku are not evidence.
    func importHTML(_ data: Data) throws {
        guard data.count <= 8_000_000, let html = String(data: data, encoding: .utf8) else { throw DMMRankingError.malformed }
        if let result = try? DMMRankingCore.weekly(html: html, responseURL: Self.weeklyURL, observedAt: Date()) {
            cancel(); board = result; evidence.removeAll(); messages.removeAll(); imported = true
            status = "用户导入100榜位 · 导入时间不是采集时间，来源统计起止未知。"; return
        }
        let re = try NSRegularExpression(pattern: "<link\\b(?=[^>]*\\brel=[\"']canonical[\"'])[^>]*\\bhref=[\"']([^\"']+)[\"'][^>]*>", options: [.caseInsensitive])
        let ns = html as NSString
        let urls = Set(re.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&") })
        guard urls.count == 1, let raw = urls.first, let url = URL(string: raw),
              let cid = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
              board?.rows.contains(where: { $0.cid == cid }) == true else { throw DMMRankingError.conflictingIdentity }
        let item = try DMMRankingCore.manufacturer(html: html, responseURL: url, expectedCID: cid)
        evidence[cid] = item; messages[cid] = "用户导入详情已核对厂家品番"
    }
    func request(_ row: DMMRankingRow) {
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
                    let (html, url) = try await self.document(row.sourceURL)
                    let item = try DMMRankingCore.manufacturer(html: html, responseURL: url, expectedCID: row.cid)
                    guard !Task.isCancelled, epoch == self.generation else { return }
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
