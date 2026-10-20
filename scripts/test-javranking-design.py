"""Native JR presentation contracts; executable production route labels on macOS.
No remote requests and no duplicated parser/presentation implementation.
"""
from pathlib import Path
import shutil, subprocess, tempfile
R=Path(__file__).resolve().parents[1]
core=(R/'AVDB/Services/JavRankingCore.swift').read_text()
view=(R/'AVDB/Views/JavRankingView.swift').read_text()
source=(R/'AVDB/Services/JavRankingSource.swift').read_text()
backend=view.split('struct JRBackendView: View')[1]
assert 'JRTopicGrid(values: values.filter' in backend
assert 'JRBackendView(route: "home"' in view.split('struct JavRankingSettingsView')[0]
assert 'JRBackendView(route: "topics"' not in view.split('struct JavRankingSettingsView')[0]
assert 'luckyHero(sections)' in backend and 'jr-lucky-start' in backend
assert 'jr-random-refresh' in backend and 'cachedPool(sections)' in backend
assert 'homeFooter' in backend and '来源未提供战力总分' in backend
assert 'ForEach(Array(items.enumerated())' in backend
assert 'ForEach(Array(values.enumerated())' in backend
assert 'items.prefix' not in backend.split('// Runtime fixtures')[0]
assert 'JRHomePresentation.orderedSections(sections)' in backend
assert 'JRHomePresentation.moreLink(section)' in backend
assert '影片封面、演员与片名' in backend
assert 'JRFilmArtwork(item: item, movie: movie' in backend
assert 'JavDBImage(url: movie.coverURL, fallbackURL: movie.thumbURL' in backend
assert 'movie?.actorNames' in backend and 'movie?.title' in backend
assert 'source.matchedMovie(code: item.number' in backend
assert 'MovieDetailView(movieID: movie.id)' in backend
assert 'rankContext' in backend and '来源未提供排名' in backend
assert 'item.rank.map' in backend and 'item.score.map' in backend
assert 'Date()' not in backend and 'Calendar' not in backend
assert 'isAccessibilitySize ? 1 : 2' in backend
assert '.fixedSize(horizontal: false, vertical: true)' in backend
assert '.preferredColorScheme(.dark)' in backend and 'overrideUserInterfaceStyle' not in backend
assert 'WKWebView' not in view
assert 'sourcePath: entity.sourcePath' not in backend # source identities never become native movie IDs
assert '.init(name: "path", value: entity.sourcePath)' in backend
assert 'while !interactive && self.activeMatches >= 3' in source
if not shutil.which('swiftc'):
 print('PASS native visual source invariants; SKIP production Swift route-label runtime (macOS CI)');raise SystemExit(0)
swift=r'''
@main struct DesignRegression {
 static func main() throws {
  func check(_ ok: Bool, _ label: String) { precondition(ok, label); print("PASS "+label) }
  let raw = try Data(contentsOf: URL(fileURLWithPath: "scripts/javranking-fixtures/backend-v1/snapshot-home.json"))
  let real = try JSONDecoder().decode(JRBackendEnvelope.self, from: raw)
  let sections = JRHomePresentation.orderedSections(real.data!.sections!)
  check(sections.map(\.id) == ["pick", "random", "rankings", "weekly", "monthly", "awarded", "actors"], "all source sections in exact source order")
  check(sections.map { $0.items?.count ?? 0 } == [0,8,0,8,8,8,0], "all actual cached previews retained, no screenshot-stale 6/4 clipping")
  check(sections[6].actors!.map { $0.items!.count } == [4,4,4], "all three actor groups and all twelve representative works")
  check(sections[2].links.count == 9, "eight featured tiles and full-directory action")
  check(JRHomePresentation.moreLink(sections[2])?.sourcePath == "/zh-hans/rankings/", "ranking preview More reaches full directory, not first weekly tile")
  check(JRHomePresentation.moreLink(sections[0]) == nil && JRHomePresentation.moreLink(sections[1]) == nil, "local pick and shuffle do not request unsupported source pick routes")
  for index in [3,4,5,6] { check(JRHomePresentation.moreLink(sections[index]) != nil, "collection/actor More route \(index)") }
  let flat = sections.flatMap { ($0.items ?? []) + ($0.actors ?? []).flatMap { $0.items ?? [] } }
  let pool = JRHomePresentation.cachedPool(sections)
  check(Set(pool.map(\.sourcePath)).count == pool.count && Set(pool.map(\.sourcePath)) == Set(flat.map(\.sourcePath)), "bounded cached random pool includes every preview, deduplicates identities only for random")
  let scored = try JSONDecoder().decode(JRBackendVideo.self, from: Data(#"{"sourceID":"neutral","sourcePath":"/neutral/","number":"TEST-001","exactNumber":"TEST001","score":1234,"rank":75,"order":1}"#.utf8))
  check(scored.score == 1234 && scored.rank == 75, "source weighted score independent from source rank and native review rating")
  let monthly = JRTopicStyle(path: "/zh-hans/rankings/dmm-monthly-2021-02/")
  check(monthly.family == "DMM" && monthly.period == "2021 · 02 月", "historical month is source route, not current calendar")
  check(JRTopicStyle(path: "/zh-hans/rankings/javdb-top250-2023/").period == "2023 年度", "year route")
  check(JRTopicStyle(path: "/zh-hans/rankings/javlibrary-top250/").family == "JAVLIBRARY", "native archive family")
  check(JRTopicStyle(path: "/zh-hans/rankings/javdb-fc2-top250/").edition == "FC2 TOP 250", "FC2 edition")
  check(JRTopicStyle(path: "/zh-hans/rankings/javdb-uncensored-top250/").edition == "无码 TOP 250", "uncensored edition")
  check(JRTopicStyle(path: "/zh-hans/rankings/dmm-weekly/").period == "WEEKLY", "weekly edition")
  let pending = JRBackendEnvelope(schemaVersion: 1, sourcePath: "/zh-hans/", fetchedAt: nil, lastAttempt: nil, status: "pending", stale: true, nextAttempt: "排队", refresh: "queued", data: nil)
  check(!pending.notice.contains("旧缓存") && pending.notice.contains("pending"), "no successful snapshot is not old cache")
  let cached = JRBackendEnvelope(schemaVersion: 1, sourcePath: "/zh-hans/", fetchedAt: "2020", lastAttempt: nil, status: "pending", stale: true, nextAttempt: nil, refresh: "queued", data: JRBackendPayload(type: "home", sections: [], topics: nil, items: nil, entities: nil, links: nil, categories: nil, page: nil, nextPage: nil, nextSourcePath: nil, total: nil))
  check(cached.notice.contains("旧缓存"), "real stale snapshot retains stale notice")
 }
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td)/'Design.swift'; p.write_text(core+'\n'+swift)
 binary=Path(td)/'design';subprocess.run(['swiftc','-parse-as-library',str(p),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
