import SwiftUI

// Neutral, offline Simulator boundary stubs. Production DMM view/store/core are linked unchanged.
struct Movie { let id: String; let number: String?; var title: String? = "中性AVDB匹配"; var coverURL: String? = nil; var thumbURL: String? = nil }
struct Actor: Identifiable { let id: String; var name: String? = nil; var displayName: String { name ?? id } }
struct JavVerseEntry { let rank: Int; let kind: String; let label: String; let sourceURL: String; let code: String?; var id: String { "\(rank)|\(sourceURL)" } }
enum JavVerseIdentity { static func code(_ value: String) -> String? { value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() } }
enum JavVerseFailure: Error { case message(String) }
@MainActor final class JavVerseMapper: ObservableObject {
    @Published var movies: [String: Movie] = [:]
    @Published var messages: [String: String] = [:]
    @Published var busy = false
    init(scope: String) {}
    func movie(for entry: JavVerseEntry) -> Movie? { movies[entry.id] }
    func cancel() {}
    func resolve(_ rows: [JavVerseEntry], retry: Bool) {
        Task { @MainActor in
            for item in rows {
                guard let code = item.code else { continue }
                movies[item.id] = try? await JavVerseMovieResolver.resolve(code: code, search: { code, _ in [Movie(id: "avdb-real-fixture-id", number: code)] })
            }
        }
    }
}
struct ActorAliasCatalog { static func bundled() -> ActorAliasCatalog { ActorAliasCatalog() } }
struct ExternalActorIdentity {
    static func resolve(sourceName: String, aliases: [String], catalog: ActorAliasCatalog) -> ExternalActorIdentity { ExternalActorIdentity() }
}
enum ExternalActorResolver {
    enum Resolution { case matched(Match); case notFound; case ambiguous([Actor]); case incomplete(candidates: [Actor], queries: [String]) }
    struct Match { let actor: Actor }
    static func inspect(identity: ExternalActorIdentity, search: @escaping (String, Int) async throws -> [Actor]) async throws -> Resolution { .notFound }
}
final class JavDBSDK {
    static let shared = JavDBSDK()
    private init() {}
    func searchActors(keyword: String, page: Int) async throws -> [Actor] { [] }
}
struct LiquidGlassBackground: View { var body: some View { Color.clear } }
struct JavDBImage: View {
    init(url: String, fallbackURL: String?, contentMode: ContentMode, frontPoster: Bool) {}
    var body: some View { Color.gray }
}
struct SearchView: View { var body: some View { Text("人工核对") } }
struct MovieDetailView: View {
    let movieID: String
    var body: some View { Text("详情ID: \(movieID)").accessibilityIdentifier("dmm-fixture-detail-id") }
}
struct ActorDetailView: View {
    let actorID: String
    var body: some View { Text("演员ID: \(actorID)").accessibilityIdentifier("dmm-fixture-actor-id") }
}
@main struct DMMUIHost266: App {
    @StateObject private var store: DMMRankingStore
    init() {
        let value = DMMRankingStore()
        let root = URL(fileURLWithPath: DMMFixturePath.root)
        try! value.importHTML(Data(contentsOf: root.appendingPathComponent("weekly-neutral.html")))
        let cid = value.board!.contentRows[0].cid
        let html = "<link rel=\"canonical\" href=\"https://video.dmm.co.jp/av/content/?id=\(cid)\"><tr><th>配信品番</th><td>\(cid)</td></tr><tr><th>メーカー品番</th><td>TEST-001</td></tr>"
        try! value.importHTML(Data(html.utf8))
        _store = StateObject(wrappedValue: value)
    }
    var body: some Scene { WindowGroup { NavigationStack { DMMRankingView(store: store) } } }
}
