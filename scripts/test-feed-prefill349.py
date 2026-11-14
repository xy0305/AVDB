#!/usr/bin/env python3
"""Build 349 ranking feed pre-fill. Contracts: the five ranking
boards (JAV Ranking explore, DMM daily/weekly/monthly/actress,
MissAV today/weekly/monthly-hot, JAVLibrary mostwanted/bestrated/
actors, ZhongZhiTong per-month) read the server pre-matching feed
first. The pipeline publishes one JSON per board/term on the repo's
`feed` branch ("<board>-<term>.json", the pipeline.py write_feed
rule); RankingFeedClient fetches it from the GitHub raw base,
validates board/term/generated_at, keeps the last good copy in
Caches, and never lets an older generated_at rewind a newer one.
Matched entries pre-fill the boards' existing result tables
(JavRankingSource.matches, JavVerseMapper.movies/actors,
MissAVMetadata.results, DMMActressMapper.actors) so views and tap
navigation are unchanged and covered entries never trigger a
verification request. The fallback is the user's rule, not the
original plan's: entries the feed does not cover, a feed that
cannot be fetched, and uncovered entries of a feed older than
48 hours all keep the existing on-device verification through
VerificationThrottle. Two verdicts are final while the feed is
fresh: miss ends the lookup (an explicit manual refresh still
falls through), and ambiguous is fail-closed — shown unmatched
and never re-resolved automatically. Pending entries (server
daily budget exhausted) are not seeded at all. Every board shows
"数据更新于 X" from the feed's generated_at, with a "可能过期"
note past 48 hours. FollowUpdates and VerificationThrottle are
untouched. Static source contracts on Linux."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '350' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 350;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2
assert 'RankingFeedClient.swift in Sources' in pbx and pbx.count('RankingFeedClient.swift') >= 4

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 350' in wf and 'feat/feed-prefill-349' in wf
assert 'feat/actor-grid-scroll-348' in wf and 'feat/actor-ranking-period-347' in wf
assert wf.count('python3 scripts/test-feed-prefill349.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-actor-grid-scroll348.py') == 5  # the 348 gate keeps its 5 run lines
assert 'scripts/package-lut350.py' in wf and 'AVDB-350-release' in wf and 'AVDB-348-release' not in wf
pkg = (r/'scripts/package-lut350.py').read_text()
assert "=='350'" in pkg and 'AVDB-unsigned-1.0.2-350-rankings-auth.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  feed-prefill-349:' in wf and '  actor-grid-scroll-348:' in wf

doc = (r/'Build349-FeedPrefill.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '349' in doc
assert 'unsigned' in doc.lower()


def func_body(src, signature):
    start = src.index(signature)
    brace = src.index('{', start)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    raise AssertionError('unbalanced: ' + signature)


# --- 1. The feed client: raw base, naming rule, validation, monotonic cache ---
client = (r/'AVDB/Services/RankingFeedClient.swift').read_text()
assert 'static let rawBase = "https://raw.githubusercontent.com/xy0305/AVDB/feed/feed"' in client
assert '"\\(board)-\\($0).json"' in client  # pipeline write_feed naming: "<board>-<term>.json"
assert 'feed.board == board' in client and 'feed.term == term' in client and 'feed.generatedDate != nil' in client
assert 'if let local, let old = local.generatedDate, let new = remote.generatedDate, new < old' in client  # monotonic generated_at
assert 'static let staleInterval: TimeInterval = 48 * 3600' in client
assert 'struct RankingFeedNote: View' in client and '数据更新于' in client and '可能过期' in client
assert 'func makeMovie() -> Movie?' in client and 'func makeActor() -> Actor?' in client

# --- 2. JAV Ranking: feed pre-fills matches; fresh verdicts end lookups ---
jr = (r/'AVDB/Services/JavRankingSource.swift').read_text()
assert 'func applyFeed(_ feed: RankingFeed)' in jr
assert 'matches[key] = Match(movie: movie, date: Date())' in jr
matched = func_body(jr, 'func matchedMovie(code: String')
assert 'feedMarksFresh, let mark = feedMarks[key]' in matched
assert 'case .ambiguous: throw JRError.message("同一番号对应多个有效影片 ID，请在原生搜索中核对。")' in matched  # fail-closed
assert 'case .miss: if !refresh { return nil }' in matched  # manual refresh still falls through
assert matched.index('feedMarksFresh') < matched.index('VerificationThrottle.acquire')  # feed checked before any throttled request
view_jr = (r/'AVDB/Views/JavRankingView.swift').read_text()
assert 'RankingFeedState.shared.ensure(board: "javranking", term: "explore")' in view_jr
assert 'source.applyFeed(feed)' in view_jr and 'RankingFeedNote(board: "javranking", term: "explore")' in view_jr

# --- 3. DMM via JavVerseMapper + the actress mapper ---
mapper = (r/'AVDB/Services/JavVerseSource.swift').read_text()
assert 'func applyFeed(_ feed: RankingFeed, for entries: [JavVerseEntry])' in mapper
assert 'movies[entry.id] = movie' in mapper and 'actors[entry.id] = actor' in mapper
assert 'case "ambiguous": messages[entry.id] = "服务器预匹配：同一番号对应多个有效影片 ID，未匹配"' in mapper
assert 'found.match.pending != true' in mapper  # pending entries are left to the fallback
view_dmm = (r/'AVDB/Views/Rankings/DMMRankingView.swift').read_text()
assert 'RankingFeedState.shared.ensure(board: "dmm", term: term)' in view_dmm
assert 'mapper.applyFeed(feed, for: items)' in view_dmm and 'mapper.resolve(items, retry: false)' in view_dmm
assert 'func applyFeed(_ feed: RankingFeed, rows: [DMMActressRow])' in view_dmm
assert 'RankingFeedState.shared.ensure(board: "dmm", term: "actress")' in view_dmm
assert 'RankingFeedNote(board: "dmm", term: store.kind.rawValue)' in view_dmm

# --- 4. MissAV / JAVLibrary / ZhongZhiTong via the shared metadata queue ---
meta = (r/'AVDB/Services/MissAVMetadata.swift').read_text()
apply_body = func_body(meta, 'func applyFeed(_ feed: RankingFeed)')
assert 'entry.match.pending != true' in apply_body and 'VerificationThrottle' not in apply_body  # seeding is network-free
assert '"movie:" + (JRPolicy.exactCode(code) ?? code)' in meta and '"actor:" + url' in meta
assert 'guard results[key] == nil' in meta  # never overwrite a device result
assert 'VerificationThrottle.acquire' in meta  # the uncovered-entry fallback queue is unchanged
view_missav = (r/'AVDB/Views/MissAVRankingView.swift').read_text()
assert 'RankingFeedState.shared.ensure(board: "missav", term: state.period)' in view_missav
assert 'metadata.applyFeed(feed)' in view_missav and 'RankingFeedNote(board: "missav", term: state.period)' in view_missav
view_jl = (r/'AVDB/Views/JAVLibraryRankingView.swift').read_text()
assert 'RankingFeedState.shared.ensure(board: "javlibrary", term: selected.rawValue)' in view_jl
assert 'metadata.applyFeed(feed)' in view_jl and 'RankingFeedNote(board: "javlibrary", term: kind.rawValue)' in view_jl
view_zzt = (r/'AVDB/Views/Rankings/ZhongZhiTongRankingView.swift').read_text()
assert 'RankingFeedState.shared.ensure(board: "zhongzhitong", term: month)' in view_zzt
assert 'RankingFeedState.shared.ensure(board: "zhongzhitong", term: selectedMonth)' in view_zzt
assert 'RankingFeedNote(board: "zhongzhitong", term: month.month)' in view_zzt
zzt = (r/'AVDB/Services/ZhongZhiTongCatalog.swift').read_text()
assert 'raw.githubusercontent.com/xy0305/AVDB/main/AVDB/Resources/ZhongZhiTongMonthly.json' in zzt  # feed branch carries no same-name catalog file (checked 2026-11-13); constant kept, feed matching takes priority

# --- 5. Untouched neighbours ---
throttle = (r/'AVDB/Services/VerificationThrottle.swift').read_text()
assert 'RankingFeed' not in throttle
follow = (r/'AVDB/Services/FollowUpdates.swift').read_text()
assert 'RankingFeed' not in follow

print('PASS test-feed-prefill349: boards read the server '
      'pre-matching feed first and pre-fill their result tables; '
      'uncovered, unfetchable and stale cases keep the throttled '
      'on-device fallback, ambiguous stays fail-closed, release 350')
