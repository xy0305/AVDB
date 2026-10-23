import Foundation
import Combine

struct JavVerseSnapshot: Decodable {
    let schemaVersion: Int
    let mode: String
    let origin: String
    let preparedAt: String
    let boards: [JavVerseBoard]
    static func bundled(in bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "JavVerseSnapshot", withExtension: "json") else {
            throw JavVerseFailure.message("缺少 JavVerseSnapshot.json 离线资源")
        }
        return try decode(Data(contentsOf: url))
    }
    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    func validate() throws {
        guard schemaVersion == 1, mode == "staticSnapshot", origin == "https://javverse.com",
              Self.timestamp(preparedAt), !boards.isEmpty,
              Set(boards.map(\.id)).count == boards.count else {
            throw JavVerseFailure.message("不支持的快照格式或时间")
        }
        for board in boards {
            guard !board.id.isEmpty, !board.title.isEmpty, !board.period.isEmpty,
                  board.coverage == "complete", Self.timestamp(board.capturedAt),
                  Self.sourceURL(board.sourceURL), !board.entries.isEmpty,
                  board.entries.map(\.rank) == Array(1...board.entries.count),
                  Set(board.entries.map(\.id)).count == board.entries.count else {
                throw JavVerseFailure.message("快照来源、时间或名次无效；拒绝补位")
            }
            for entry in board.entries {
                guard ["movie", "actor", "series"].contains(entry.kind), !entry.label.isEmpty,
                      Self.sourceURL(entry.sourceURL),
                      entry.kind != "movie" || entry.code.flatMap(JavVerseIdentity.code) != nil else {
                    throw JavVerseFailure.message("快照条目身份或来源无效")
                }
            }
        }
    }
    private static func timestamp(_ text: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: text) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) != nil
    }
    private static func sourceURL(_ text: String) -> Bool {
        guard let url = URLComponents(string: text) else { return false }
        return url.scheme == "https" && url.host == "javverse.com" && url.user == nil
            && url.password == nil && url.port == nil
    }
}
struct JavVerseBoard: Decodable, Identifiable {
    let id: String
    let title: String
    let period: String
    let capturedAt: String
    let sourceURL: String
    let coverage: String
    let entries: [JavVerseEntry]
}
struct JavVerseEntry: Decodable, Identifiable {
    let rank: Int
    let kind: String
    let label: String
    let sourceURL: String
    let code: String?
    var id: String { "\(rank)|\(kind)|\(sourceURL)|\(label)" }
}
enum JavVerseFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
// Strict number identity: uppercase and surrounding whitespace ONLY.
// Never remove zeros, hyphens, suffixes or infer a number from a title/source numeric ID.
enum JavVerseIdentity {
    static func code(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        let key = trimmed.uppercased()
        guard key.range(of: #"^[A-Z0-9]+-[A-Z0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return key
    }
}

@MainActor final class JavVerseMapper: ObservableObject {
    @Published private(set) var movies: [String: Movie] = [:]
    @Published private(set) var messages: [String: String] = [:]
    @Published private(set) var busy = false
    private var account: String?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var observation: AnyCancellable?
    private let search: JavVerseMovieResolver.Search
    private let accountProvider: @MainActor () -> String?
    init(search: JavVerseMovieResolver.Search? = nil,
         accountProvider: @escaping @MainActor () -> String? = { APIClient.shared.token }) {
        self.search = search ?? { source, page in
            try await JavDBSDK.shared.search(keyword: source, page: page, type: "movie", limit: 20)
        }
        self.accountProvider = accountProvider
        account = accountProvider()
        observation = NotificationCenter.default.publisher(for: Notification.Name("avdb.catalog.accountChanged"))
            .sink { [weak self] _ in Task { @MainActor in self?.clear() } }
    }
    func clear() {
        cancel(); movies.removeAll(); messages.removeAll(); account = accountProvider()
    }
    // Await the currently scheduled batch; used by neutral hosted regression tests.
    func waitUntilIdle() async { await task?.value }
    func cancel() { task?.cancel(); task = nil; generation = UUID(); busy = false }
    func movie(for entry: JavVerseEntry) -> Movie? {
        guard account == accountProvider() else { return nil }
        return movies[entry.id]
    }
    @discardableResult
    func resolve(_ entries: [JavVerseEntry]) -> Task<Void, Never>? {
        guard !busy else { return nil }
        if account != accountProvider() { clear() }
        let epoch = generation, token = account
        // Explicit button only; never called from row onAppear or scrolling.
        let batch = Array(entries.filter { $0.kind == "movie" && movies[$0.id] == nil }.prefix(4))
        guard !batch.isEmpty else { return nil }
        busy = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == epoch { self.busy = false; self.task = nil } }
            for entry in batch {
                do {
                    try Task.checkCancellation()
                    guard let source = entry.code else {
                        throw JavVerseFailure.message("原始完整番号不可核验")
                    }
                    // SDK global cachedExactMovie intentionally not used: normalization may be broader.
                    let movie = try await JavVerseMovieResolver.resolve(code: source) { source, page in
                        try Task.checkCancellation()
                        guard self.generation == epoch, self.accountProvider() == token else { throw CancellationError() }
                        let rows = try await self.search(source, page)
                        try Task.checkCancellation()
                        guard self.generation == epoch, self.accountProvider() == token else { throw CancellationError() }
                        return rows
                    }
                    try Task.checkCancellation()
                    guard self.generation == epoch, self.accountProvider() == token else { throw CancellationError() }
                    if let movie {
                        self.movies[entry.id] = movie
                        self.messages[entry.id] = "已核验 AVDB 完整番号及唯一 ID"
                    } else { self.messages[entry.id] = "AVDB 暂无完整番号匹配" }
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, self.generation == epoch, self.accountProvider() == token else { return }
                    self.messages[entry.id] = error.localizedDescription
                }
            }
        }
        return task
    }
}

// Diagnostic only, never interpreted as a live data API. No cookies, authentication or challenge solver.
enum JavVerseHTTPProbe {
    static func status() async throws -> Int {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://javverse.com/rankings")!)
        request.httpShouldHandleCookies = false
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JavVerseFailure.message("非HTTP响应") }
        return http.statusCode
    }
}
