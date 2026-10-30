// Build 281 screenshot host: compiles the production recommender core, store and views
// (Recommender.swift, RecommendationStore.swift, RecommendationsView.swift) with offline stubs for
// Movie / MoviePosterImage / MovieDetailView and a seeded fixture source. Covers are procedural
// artwork (CI is offline); nothing here ships in the App.
import SwiftUI

struct Movie: Hashable {
    var id: String
    var type: String?
    var number: String
    var title: String
    var thumbURL: String?
    var coverURL: String?
    init(id: String, type: String? = nil, number: String, title: String, thumbURL: String? = nil, coverURL: String? = nil) {
        self.id = id; self.type = type; self.number = number; self.title = title; self.thumbURL = thumbURL; self.coverURL = coverURL
    }
}

extension RecItem { var movie: Movie { Movie(id: id, type: type, number: number, title: title, thumbURL: thumbURL ?? coverURL, coverURL: coverURL) } }

/// Procedural "cover" art: deterministic per id, layered gradients + light shapes + typographic 番号.
struct MoviePosterImage: View {
    let movie: Movie
    var maxPixelSize: Int = 1200
    private var seed: UInt64 { movie.id.utf8.reduce(1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 } }
    private func unit(_ shift: UInt64) -> Double { Double((seed >> shift) & 0xFF) / 255 }
    var body: some View {
        let h = unit(0), h2 = (h + 0.08 + 0.2 * unit(8)).truncatingRemainder(dividingBy: 1)
        GeometryReader { geo in
            let w = geo.size.width, ht = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(hue: h, saturation: 0.55, brightness: 0.85), Color(hue: h2, saturation: 0.75, brightness: 0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(hue: h2, saturation: 0.35, brightness: 1).opacity(0.55))
                    .frame(width: w * 0.9).blur(radius: w * 0.12)
                    .offset(x: w * (unit(16) - 0.5) * 0.6, y: -ht * 0.18)
                Ellipse().fill(Color.black.opacity(0.28)).frame(width: w * 0.62, height: ht * 0.74)
                    .offset(x: w * (unit(24) - 0.5) * 0.4, y: ht * 0.24).blur(radius: 2)
                Circle().fill(Color.black.opacity(0.3)).frame(width: w * 0.3)
                    .offset(x: w * (unit(24) - 0.5) * 0.4, y: -ht * 0.12)
                Rectangle().fill(.white.opacity(0.08)).frame(width: w * 2, height: ht * 0.08).rotationEffect(.degrees(-28)).offset(y: ht * 0.05)
                VStack(alignment: .leading, spacing: 2) {
                    Spacer()
                    Text(movie.number.split(separator: "-").first.map(String.init) ?? "AV")
                        .font(.system(size: max(10, w * 0.2), weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.22))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(w * 0.06)
            }
            .frame(width: w, height: ht)
        }
        .clipped()
    }
}

struct MovieDetailView: View {
    let movieID: String
    var seed: Movie?
    var body: some View { Text("详情 \(seed?.number ?? movieID)").navigationTitle(seed?.number ?? "") }
}

// MARK: - Fixture library

enum RecFixture {
    static func f(_ k: RecFeatureKind, _ id: String, _ n: String) -> RecFeature { RecFeature(kind: k, id: id, name: n) }
    static let actresses = [f(.actor, "a1", "星野ひかり"), f(.actor, "a2", "桜井みお"), f(.actor, "a3", "白石なな"), f(.actor, "a4", "七瀬りこ"), f(.actor, "a5", "葉月ゆい"), f(.actor, "a6", "水城あん")]
    static let tags = [f(.tag, "t1", "黑丝"), f(.tag, "t2", "美脚"), f(.tag, "t3", "OL"), f(.tag, "t4", "制服"), f(.tag, "t5", "剧情"), f(.tag, "t6", "高画质"), f(.tag, "t7", "姐姐"), f(.tag, "t8", "温泉")]
    static let series = [f(.series, "s1", "丝袜办公室"), f(.series, "s2", "夏日旅情")]
    static let makers = [f(.maker, "m1", "S1"), f(.maker, "m2", "IDEA POCKET"), f(.maker, "m3", "MOODYZ")]
    static let prefixes = ["SSIS", "IPZZ", "MIDV", "SONE", "STARS", "ABF"]
    static let titles = ["加班后的办公室，只属于两个人的夜晚", "黑丝美脚秘书的贴身指导", "温泉旅馆的意外重逢", "制服少女的夏日回忆", "姐姐的温柔与诱惑", "一整天的约会纪录", "隔壁新搬来的她", "雨夜，末班车之后"]

    static func item(_ i: Int, who: Int, tags tagIdx: [Int], series s: Int? = nil, maker: Int = 0, daysAgo: Int = 10, pop: Double = 600) -> RecItem {
        var fs = [actresses[who]] + tagIdx.map { tags[$0] } + [makers[maker]]
        if let s { fs.append(series[s]) }
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let id = "fx\(i)"
        return RecItem(id: id, number: "\(prefixes[i % prefixes.count])-\(String(format: "%03d", 100 + i * 7 % 900))", title: titles[i % titles.count],
                       type: "0", coverURL: "fixture://\(id)", releaseDate: df.string(from: date), rating: 3.6 + Double(i % 13) / 10,
                       popularity: pop + Double((i * 37) % 900), features: fs, detailed: true, fetchedAt: Date())
    }
    // History: mostly 星野ひかり + 黑丝/美脚, some 桜井みお + 制服, one quick bail.
    static let history: [RecItem] = (0..<14).map { i in
        i < 8 ? item(i, who: 0, tags: [0, 1, i % 2 == 0 ? 2 : 6], series: i < 4 ? 0 : nil, maker: 0, daysAgo: 40 + i)
              : item(i, who: i < 12 ? 1 : 2, tags: i < 12 ? [3, 4] : [7], series: nil, maker: 1, daysAgo: 60 + i)
    }
    static var library: [String: RecItem] = {
        var out: [String: RecItem] = [:]
        for h in history { out[h.id] = h }
        return out
    }()
    static var counter = 100
    static func make(_ n: Int, who: Int? = nil, tags: [Int], series: Int? = nil, maker: Int = 0, pop: Double = 600) -> [RecItem] {
        (0..<n).map { k in
            counter += 1
            let a = who ?? (2 + (counter % 4))
            let it = item(counter, who: a, tags: tags, series: series, maker: maker, daysAgo: 2 + (counter * 3) % 50, pop: pop)
            library[it.id] = it
            return it
        }
    }
}

final class FixtureRecSource: RecommendationSource {
    let cold: Bool, slow: Bool
    init(cold: Bool, slow: Bool) { self.cold = cold; self.slow = slow }
    var requestSpacing: Double { 0 }
    @MainActor func snapshot(feedback: [RecSignal], playCounts: [String: Int], since: Date?) -> RecSnapshot {
        if cold { return RecSnapshot(signals: feedback, follows: [], recentPositives: [], seedItems: []) }
        let now = Date()
        var signals: [RecSignal] = RecFixture.history.enumerated().map { i, it in
            RecSignal(kind: .watch, movieID: it.id, ratio: i == 13 ? 0.05 : (i % 3 == 0 ? 0.95 : 0.6), plays: i == 0 ? 3 : 1, at: now.addingTimeInterval(-Double(i) * 36_000))
        }
        signals.append(RecSignal(kind: .favorite, movieID: RecFixture.history[1].id, at: now))
        signals.append(RecSignal(kind: .follow, featureKey: RecFixture.series[0].key, featureName: RecFixture.series[0].name, at: now))
        return RecSnapshot(signals: signals + feedback, follows: [RecFixture.series[0]],
                           recentPositives: [RecSeed(id: RecFixture.history[0].id, number: RecFixture.history[0].number)],
                           seedItems: RecFixture.history)
    }
    func detail(_ id: String) async throws -> RecItem {
        if slow { try await Task.sleep(nanoseconds: 60_000_000_000) }
        return RecFixture.library[id] ?? RecItem(id: id, number: id, title: "")
    }
    func list(_ r: RecSourcingPlan.Request) async throws -> [RecItem] {
        if slow { try await Task.sleep(nanoseconds: 60_000_000_000) }
        return await MainActor.run {
            switch r.source {
            case .follow, .series: return RecFixture.make(5, who: nil, tags: [0, 2], series: 0, maker: 0)
            case .actor: return RecFixture.make(6, who: Int(r.id.dropFirst())! - 1, tags: [0, 1, 5])
            case .tag: return RecFixture.make(6, tags: [0, 1], maker: 2)
            case .similar: return RecFixture.make(4, tags: [2, 6], maker: 1)
            case .maker: return RecFixture.make(4, tags: [4], maker: 0)
            case .popular, .latest: return RecFixture.make(8, tags: [4, 7], maker: 2, pop: 3500)
            }
        }
    }
}

enum RecommendationSourceRegistry {
    @MainActor static func make() -> RecommendationSource {
        let args = ProcessInfo.processInfo.arguments
        return FixtureRecSource(cold: args.contains("--rec-cold"), slow: args.contains("--rec-slow"))
    }
}

@main struct RecUIHost281: App {
    let screen: String
    let dark: Bool
    init() {
        let args = ProcessInfo.processInfo.arguments
        screen = args.firstIndex(of: "--screen").map { args[$0 + 1] } ?? "feed"
        dark = args.contains("--dark")
        RecFeedbackPresenter.toastSeconds = 30
        // Fresh state per launch: screenshots never depend on a previous test.
        for key in [RecommendationStore.feedbackKey, RecommendationStore.rankerKey, RecommendationStore.resetKey] { UserDefaults.standard.removeObject(forKey: key) }
        if let url = RecommendationStore.defaultFileURL() { try? FileManager.default.removeItem(at: url) }
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                switch screen {
                case "prefs": PreferenceProfileView().task { await RecommendationStore.shared.refreshNow() }
                case "mine":
                    List {
                        RecommendationSection()
                        Section("观看历史") {
                            ForEach(RecFixture.history.prefix(3)) { h in Label(h.number + "  " + h.title, systemImage: "clock").lineLimit(1) }
                        }
                    }
                    .navigationTitle("我的")
                default: RecommendationFeedView()
                }
            }
            .preferredColorScheme(dark ? .dark : nil)
        }
    }
}
