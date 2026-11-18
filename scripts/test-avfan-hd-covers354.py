#!/usr/bin/env python3
"""Build 354: the five external boards and the avfan detail stop
pinning avfan's raw (watermarked, landscape) covers. Contracts:
posters are built by AvfanMatchStore.posterMovie (censored-catalog
typing so FrontPosterPolicy applies the standard HD/front-crop
rules) and rendered with the visible-HQ upgrade on — tier 1 the
DMM/MGS HD portrait by number, tier 2 the stored JavDB feed cover
(match.cover lifted once from the published feed files into the
match store's persistence; image CDN only, no JavDB API request,
no feed routing restored), tier 3 the avfan original cover. Pacing
supersedes 353: AvfanClient one serial lane at 1.2 s, match store
one serial worker, bulk enqueue capped at 40 new entries per call,
and an avfan rate limit (HTTP 429 or the wait-page) trips a shared
10-minute gate that pauses everything and resumes by itself.
The avfan detail's magnet rows gain the normal detail's play
action (Pan115PlayerView with the magnet in hand) and explicit
empty states. Zero JavDB requests on board/detail paths, as 353.
Static source contracts on Linux."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '354' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 354;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 354' in wf and 'feat/avfan-hd-covers-354' in wf
assert wf.count('python3 scripts/test-avfan-hd-covers354.py') == 6  # dedicated job + avfan-boards-353 job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert '  avfan-hd-covers-354:' in wf
assert 'scripts/package-lut354.py' in wf and 'AVDB-354-release' in wf
pkg = (r/'scripts/package-lut354.py').read_text()
assert "=='354'" in pkg and 'AVDB-unsigned-1.0.2-354-avfanhdcovers.ipa' in pkg

doc = (r/'Build354-AvfanHDCovers.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '354' in doc and 'unsigned' in doc

# --- 1. Poster chain: store-side movie builder + stored feed covers ---
store = (r/'AVDB/Services/AvfanMatchStore.swift').read_text()
assert 'func posterMovie(' in store and 'type: "0"' in store  # censored typing -> HD/front-crop rules
assert 'feedCover(forCode: code) ?? match?.coverURL ?? fallbackCover' in store  # tier order: feed cover, avfan match, board fallback (HQ upgrade paints tier 1 over the base)
assert 'var feedCovers' in store and 'feedCoversLoaded' in store and '"avdb.avfan.match.v1"' in store  # lifted covers persist with the matches
assert 'func ensureFeedCovers()' in store and 'func feedCover(forCode code: String)' in store
for pair in ('("dmm", "daily")', '("dmm", "weekly")', '("javranking", "explore")', '("zhongzhitong", "2026-09")', '("zhongzhitong", "2026-10")'):
    assert pair in store, pair  # exactly the feed files that were ever published
assert 'entry.match.status == "matched"' in store and 'entry.match.cover' in store  # only stored matched covers are lifted
assert 'RankingFeedClient.load' in store  # the feed is read in the store only...

# --- 2. Pacing: one serial lane, prefetch cap, 10-minute rate gate ---
client = (r/'AVDB/Services/AvfanClient.swift').read_text()
assert 'static let laneCount = 1' in client and 'static let laneInterval: TimeInterval = 1.2' in client
assert 'case rateLimited' in client and 'rateLimitCooldown: TimeInterval = 600' in client
assert 'func isRateLimitPage' in client and '十分钟后再试' in client and 'status == 429' in client
assert 'if isRateLimited()' in client  # the gate refuses before any request is sent
assert 'private static let maxConcurrent = 1' in store
assert 'maxPrefetchPerEnqueue = 40' in store  # bulk pre-match cap; the rest joins via prioritize on scroll
assert 'func enterRateLimitPause()' in store and 'rateLimitResumeAt' in store  # queue kept, self-resuming
assert '限流中' in store and '自动恢复' in store  # board status line explains the wait
assert 'case .rateLimited = error' in store  # a rate-limited resolve is never recorded as a miss

# --- 3. Boards + detail render through the chain; feed stays store-only ---
boards = (r/'AVDB/Views/AvfanBoards.swift').read_text()
dmm = (r/'AVDB/Views/Rankings/DMMRankingView.swift').read_text()
jr = (r/'AVDB/Views/JavRankingView.swift').read_text()
detail = (r/'AVDB/Views/AvfanMovieDetailView.swift').read_text()
for name, text in (('AvfanBoards', boards), ('DMMRankingView', dmm), ('JavRankingView', jr), ('AvfanMovieDetailView', detail)):
    assert 'posterMovie(' in text, name
    assert 'upgradesVisibleHQ: true' in text, name
    assert 'RankingFeedClient' not in text, name  # ...never in a view
    assert 'JavDBSDK' not in text and 'VerificationThrottle' not in text, name
assert 'ClippedAspectFill(aspectRatio: 0.7' in detail and 'MoviePosterImage' in detail  # portrait HD hero
assert 'matcher.ensureFeedCovers()' in detail

# --- 4. Detail magnets: full action set incl. play, explicit empty states ---
assert 'Pan115PlayerView(movie: playerMovie, magnetURL: magnet.url)' in detail
assert 'playingMagnet' in detail and 'Pan115PlaybackCache.save' in detail
assert '登录 avfan 后查看' in detail and '本站暂无磁链' in detail
assert 'avfan 限流中，请约十分钟后再试' in detail

print('PASS test-avfan-hd-covers354: HD poster chain (DMM/MGS over stored '
      'JavDB feed cover over avfan original), serial 1.2 s pacing with a '
      '10-minute rate-limit gate, detail magnets push + play, release 354')
