#!/usr/bin/env python3
"""Build 353: the five external boards (DMM, JAV Ranking, MissAV,
JAVLibrary, ZhongZhiTong) match avfan instead of the JavDB
pre-matching feed. Contracts: board list sources are untouched; the
matching layer is the new AvfanClient/AvfanMatchStore (ported from
AVFan's SiteClient/HTMLParser/RankingMatchStore subset); matching
runs 3 lanes at ~0.4 s spacing, visible entries first, results
persisted, misses session-only, 403/429 degrades to serial and
pauses prefetch (Build 354 supersedes the pacing: one serial lane
at 1.2 s, prefetch capped at 40 per enqueue, avfan rate limits
pause everything for ten minutes — see test-avfan-hd-covers354);
matched entries open AvfanMovieDetailView (avfan
magnets pushable to 115 through the existing Pan115Client),
unmatched entries only ever say 「AVFan 暂无此作」; the five boards'
render/scroll/prefetch/tap paths contain no JavDBSDK call and no
VerificationThrottle verification; the settings page has an
「avfan 账号」 section whose login is AVFan's WebView scheme
(credentials only through the real sign-in page, never stored).
Static source contracts on Linux."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '354' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 354;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2
for f in ('AvfanClient.swift', 'AvfanMatchStore.swift', 'AvfanMovieDetailView.swift', 'AvfanLoginView.swift', 'AvfanBoards.swift'):
    assert f + ' in Sources' in pbx and pbx.count(f) >= 4, f

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 354' in wf and 'feat/avfan-boards-353' in wf
assert wf.count('python3 scripts/test-avfan-boards353.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert '  avfan-boards-353:' in wf
assert 'scripts/package-lut354.py' in wf and 'AVDB-354-release' in wf and 'AVDB-352-release' not in wf
pkg = (r/'scripts/package-lut354.py').read_text()
assert "=='354'" in pkg and 'AVDB-unsigned-1.0.2-354-avfanhdcovers.ipa' in pkg

doc = (r/'Build353-AvfanBoards.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '353' in doc and 'unsigned' in doc

# --- 1. The avfan client: subset port, red lines, lanes ---
client = (r/'AVDB/Services/AvfanClient.swift').read_text()
assert 'actor AvfanClient' in client and 'mobileSafariUA' in client
assert 'HTTPCookieStorage.shared' in client and 'AvfanWebViewFetcher' in client  # CF fallback
assert 'static let laneCount = 1' in client and 'static let laneInterval: TimeInterval = 1.2' in client  # Build 354 pacing
assert 'func movieCards(in html: String)' in client and 'func magnets(in html: String)' in client
assert 'func movieDetail(from html: String' in client and 'func castCards(in html: String)' in client
assert '/autocomplete' in client and '/user/' in client  # the red lines are written in the header contract
for banned in ('api.avfan', 'avfan.com/api', 'func jsonRequest'):
    assert banned not in client, banned

# --- 2. The matching engine: concurrency, priority, persistence, degrade ---
store = (r/'AVDB/Services/AvfanMatchStore.swift').read_text()
assert 'private static let maxConcurrent = 1' in store  # Build 354: serial worker
assert 'func prioritize(codes: [String])' in store and 'func enqueue(codes: [String])' in store
assert '"avdb.avfan.match.v1"' in store and 'UserDefaults' in store  # persisted matches
assert 'movieMisses' in store and 'actorMisses' in store  # session-only misses
assert 'func enterDegraded()' in store and 'degraded = true' in store  # 403/429 pause
assert 'missAVMatchCode' in store and '-UNCENSORED-LEAK' in store and '-CHINESE-SUBTITLE' in store
assert 'JavDBSDK' not in store and 'VerificationThrottle' not in store

# --- 3. The detail view: pinned hero, magnets, 115 push, no JavDB ---
detail = (r/'AVDB/Views/AvfanMovieDetailView.swift').read_text()
assert 'struct AvfanMovieDetailView: View' in detail and 'struct AvfanActorView: View' in detail
assert 'struct AvfanRouteView: View' in detail and 'AVFan 暂无此作' in detail
assert 'Pan115Client.shared.addOfflineTask' in detail and 'Pan115Settings.shared' in detail
assert 'canonicalPathID' in detail  # identity guard against wrong-movie pages
assert 'JavDBSDK' not in detail and 'MovieDetailView(movieID:' not in detail and 'VerificationThrottle' not in detail

# --- 4. Boards: feed retired, zero JavDB, list sources untouched ---
boards = {
    'AVDB/Views/Rankings/DMMRankingView.swift': ('DMMRankingStore', 'store.evidence[row.cid]'),
    'AVDB/Views/JavRankingView.swift': ('JavRankingSource', 'JRPosterGrid'),
    'AVDB/Views/MissAVRankingView.swift': ('MissAVSource', 'missAVMatchCode'),
    'AVDB/Views/JAVLibraryRankingView.swift': ('ExternalLibraryClient.shared.javlibrary', 'snapshot'),
    'AVDB/Views/Rankings/ZhongZhiTongRankingView.swift': ('ZZTCatalog', 'current.entries'),
}
for path, (source_marker, extra) in boards.items():
    text = (r/path).read_text()
    assert 'RankingFeed' not in text, path
    assert 'JavDBSDK' not in text, path
    assert 'VerificationThrottle' not in text, path
    assert 'AvfanMatchStore' in text, path
    assert source_marker in text, (path, source_marker)  # list source untouched
    assert extra in text, (path, extra)
jr_source = (r/'AVDB/Services/JavRankingSource.swift').read_text()
assert 'matchedMovie' not in jr_source and 'applyFeed' not in jr_source and 'JavDBSDK' not in jr_source
grids = (r/'AVDB/Views/AvfanBoards.swift').read_text()
assert 'upgradesVisibleHQ: true' in grids  # Build 354: boards run the standard HD poster chain
assert 'missav-detail-' in grids and 'javlibrary-detail-' in grids  # DEBUG fixture destinations preserved
assert 'JavDBSDK' not in grids

# --- 5. Login: settings entry, WebView scheme, no password handling ---
user = (r/'AVDB/Views/User/UserView.swift').read_text()
assert 'Section("avfan 账号")' in user and 'avfan-account-entry' in user and 'AvfanLoginView()' in user
login = (r/'AVDB/Views/AvfanLoginView.swift').read_text()
assert 'WKWebView' in login and 'AvfanSession.signInURL()' in login
assert 'session_email_or_username' in login and 'session[password]' in login  # the page's own fields
assert 'exportWebKitToShared' in login and 'clearSiteCookies' in client
for banned in ('URLSession', 'dataTask', '/sessions'):
    assert banned not in login, banned  # credentials never leave the WebView page

print('PASS test-avfan-boards353: five boards match avfan (persisted, '
      'degrade on 403; pacing superseded by Build 354), zero JavDB on '
      'board paths, avfan detail + 115 push, WebView login in settings, release 354')
