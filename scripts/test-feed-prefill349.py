#!/usr/bin/env python3
"""Build 349 ranking feed pre-fill (board wiring superseded by
Build 353: the five boards no longer read the feed — they match
avfan through AvfanMatchStore with zero JavDB requests; the feed
client itself remains in the app for other consumers, so section 1
and the untouched-neighbour contracts still hold, while sections
2-4 now assert the 353 retirement on the boards). Original 349
contracts: the five ranking
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
assert plist['CFBundleVersion'] == '354' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 354;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2
assert 'RankingFeedClient.swift in Sources' in pbx and pbx.count('RankingFeedClient.swift') >= 4

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 354' in wf and 'feat/feed-prefill-349' in wf
assert 'feat/actor-grid-scroll-348' in wf and 'feat/actor-ranking-period-347' in wf
assert wf.count('python3 scripts/test-feed-prefill349.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-actor-grid-scroll348.py') == 5  # the 348 gate keeps its 5 run lines
assert 'scripts/package-lut354.py' in wf and 'AVDB-354-release' in wf and 'AVDB-348-release' not in wf
pkg = (r/'scripts/package-lut354.py').read_text()
assert "=='354'" in pkg and 'AVDB-unsigned-1.0.2-354-avfanhdcovers.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
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

# --- 2. JAV Ranking: Build 353 retired the feed + JavDB matcher here ---
jr = (r/'AVDB/Services/JavRankingSource.swift').read_text()
assert 'func applyFeed' not in jr and 'matchedMovie' not in jr and 'cachedMovie' not in jr
assert 'JavDBSDK' not in jr and 'VerificationThrottle' not in jr  # source layer is list-only now
view_jr = (r/'AVDB/Views/JavRankingView.swift').read_text()
assert 'RankingFeed' not in view_jr and 'JavDBSDK' not in view_jr and 'VerificationThrottle' not in view_jr
assert 'AvfanMatchStore' in view_jr and 'AvfanRouteView' in view_jr and 'AvfanMovieDetailView' in view_jr

# --- 3. DMM: JavVerseMapper/DMMActressMapper retired from the board ---
mapper = (r/'AVDB/Services/JavVerseSource.swift').read_text()
assert 'func applyFeed(_ feed: RankingFeed, for entries: [JavVerseEntry])' in mapper  # type kept; the DMM board no longer uses it
view_dmm = (r/'AVDB/Views/Rankings/DMMRankingView.swift').read_text()
assert 'JavVerseMapper' not in view_dmm and 'DMMActressMapper' not in view_dmm
assert 'RankingFeed' not in view_dmm and 'JavDBSDK' not in view_dmm and 'VerificationThrottle' not in view_dmm
assert 'AvfanMatchStore' in view_dmm and 'AvfanRouteView' in view_dmm and 'AvfanActorRouteView' in view_dmm
assert 'store.evidence[row.cid]' in view_dmm  # maker code still comes from DMMRankingStore evidence, never from the CID

# --- 4. MissAV / JAVLibrary / ZhongZhiTong: metadata queue retired from the boards ---
meta = (r/'AVDB/Services/MissAVMetadata.swift').read_text()
assert 'func applyFeed(_ feed: RankingFeed)' in meta  # the type remains in the app; boards no longer instantiate it
view_missav = (r/'AVDB/Views/MissAVRankingView.swift').read_text()
assert 'RankingFeed' not in view_missav and 'MissAVMetadata' not in view_missav
assert 'JavDBSDK' not in view_missav and 'VerificationThrottle' not in view_missav
assert 'AvfanBoardGrid' in view_missav and 'missAVMatchCode' in view_missav  # MissAV suffixes stripped before matching
view_jl = (r/'AVDB/Views/JAVLibraryRankingView.swift').read_text()
assert 'RankingFeed' not in view_jl and 'MissAVMetadata' not in view_jl and 'AvfanBoardGrid' in view_jl
view_zzt = (r/'AVDB/Views/Rankings/ZhongZhiTongRankingView.swift').read_text()
assert 'RankingFeed' not in view_zzt and 'MissAVMetadata' not in view_zzt and 'AvfanBoardGrid' in view_zzt
zzt = (r/'AVDB/Services/ZhongZhiTongCatalog.swift').read_text()
assert 'raw.githubusercontent.com/xy0305/AVDB/main/AVDB/Resources/ZhongZhiTongMonthly.json' in zzt  # bundled catalog still provides the code list itself

# --- 5. Untouched neighbours ---
throttle = (r/'AVDB/Services/VerificationThrottle.swift').read_text()
assert 'RankingFeed' not in throttle
follow = (r/'AVDB/Services/FollowUpdates.swift').read_text()
assert 'RankingFeed' not in follow

print('PASS test-feed-prefill349: feed client intact for other '
      'consumers; the five boards retired it in Build 353 and match '
      'avfan with zero JavDB requests, release 354')
