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
assert 'JRTopicGrid(values: values)' in backend
assert 'JRFilmArtwork(item: item, movie: movie' in backend
assert 'MoviePosterImage(movie: movie, maxPixelSize: 600)' in backend
assert 'movie?.actorNames' in backend and 'movie?.title' in backend
assert 'source.matchedMovie(code: item.number' in backend
assert 'MovieDetailView(movieID: movie.id)' in backend
assert 'rankContext' in backend and '来源未提供排名' in backend
assert 'item.rank.map' in backend and 'item.score' not in backend
assert 'Date()' not in backend and 'Calendar' not in backend
assert 'isAccessibilitySize ? 1 : 2' in backend
assert '.fixedSize(horizontal: false, vertical: true)' in backend
assert '.environment(\\.colorScheme, .dark)' in backend and '.preferredColorScheme' not in backend
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
