import SwiftUI

// Neutral, offline Simulator boundary stubs. Production DMM view/store/core are linked unchanged.
struct Movie { let id: String; let number: String?; var title: String? = "中性AVDB匹配"; var coverURL: String? = nil; var thumbURL: String? = nil }
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
@main struct DMMUIHost266: App {
    @StateObject private var store: DMMRankingStore
    init() {
        let value = DMMRankingStore()
        let root = URL(fileURLWithPath: DMMFixturePath.root)
        try! value.importHTML(Data(contentsOf: root.appendingPathComponent("weekly-neutral.html")))
        let cid = value.board!.rows[0].cid
        let html = "<link rel=\"canonical\" href=\"https://video.dmm.co.jp/av/content/?id=\(cid)\"><tr><th>配信品番</th><td>\(cid)</td></tr><tr><th>メーカー品番</th><td>TEST-001</td></tr>"
        try! value.importHTML(Data(html.utf8))
        _store = StateObject(wrappedValue: value)
    }
    var body: some Scene { WindowGroup { NavigationStack { DMMRankingView(store: store) } } }
}
