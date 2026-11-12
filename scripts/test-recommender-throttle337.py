#!/usr/bin/env python3
"""Build 337 recommender throttle. Contracts: opening the recommendations
page never fetches (local recompute from cache only; the auto-refresh
interval is gone); pull-to-refresh is the only network path and one run
is capped at 10 requests in total across seed details, sourcing lists
and hydration; request gaps are a fresh random 2.5–5 s draw, never a
fixed metronome. Static source contracts on Linux; behaviour verified
on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '348' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 348;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 348' in wf and 'feat/recommender-throttle-337' in wf
assert 'feat/remove-javverse-336' in wf and 'feat/detail-api-335' in wf
assert wf.count('python3 scripts/test-recommender-throttle337.py') == 5  # dedicated job + the three jobs that run the 336 gate + release regressions
assert 'scripts/package-lut348.py' in wf and 'AVDB-348-release' in wf and 'AVDB-336-release' not in wf
pkg = (r/'scripts/package-lut348.py').read_text()
assert "=='348'" in pkg and 'AVDB-unsigned-1.0.2-348-actor-grid-scroll.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  recommender-throttle-337:' in wf and '  remove-javverse-336:' in wf

doc = (r/'Build337-RecommenderThrottle.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '337' in doc
assert 'unsigned' in doc.lower()

store = (r/'AVDB/Services/RecommendationStore.swift').read_text()
source = (r/'AVDB/Services/RecommendationJavDBSource.swift').read_text()

# --- 1. Manual-only network ---
assert 'autoRefreshInterval' not in store
assert 'static func requestBudget(manual: Bool) -> Int { manual ? 6 : 0 }' in store
assert 'static func detailBudget(manual: Bool) -> Int { manual ? 6 : 0 }' in store
view = (r/'AVDB/Views/User/RecommendationsView.swift').read_text()
assert 'store.refresh(manual: false)' in view and 'store.refreshNow()' in view  # appear = cache recompute; pull = manual fetch

# --- 2. Random slow spacing ---
assert 'var requestSpacing: Double { Double.random(in: 2.5...5.0) }' in source
assert 'requestSpacing: Double { 1.0 }' not in source

# --- 3. Hard total cap, enforced at every fetch loop ---
assert 'static let totalRequestBudget = 10' in store
assert store.count('guard requests < RecommendationLimits.totalRequestBudget else { break }') == 2
assert 'requests < RecommendationLimits.totalRequestBudget else { break }' in store  # list loop guard

# --- 4. Shared verification throttle on all three ranking engines ---
throttle = (r/'AVDB/Services/VerificationThrottle.swift').read_text()
assert 'static let perMinute = 20' in throttle and 'Double.random(in: 1.5...3.5)' in throttle
assert 'VerificationThrottle.swift' in pbx
jr = (r/'AVDB/Services/JavRankingSource.swift').read_text()
assert 'VerificationThrottle.acquire(deadline: deadline)' in jr and 'activeMatches' not in jr
assert 'if !interactive' in jr  # interactive taps keep bypassing
miss = (r/'AVDB/Services/MissAVMetadata.swift').read_text()
assert 'VerificationThrottle.acquire()' in miss and 'tasks.count < 1' in miss
mapper = (r/'AVDB/Services/JavVerseSource.swift').read_text()
assert 'throttled: !retry' in mapper and 'VerificationThrottle.acquire()' in mapper

follow = (r/'AVDB/Services/FollowUpdates.swift').read_text()
assert 'VerificationThrottle.acquire()' in follow and 'requestSpacingSeconds' not in follow

print('PASS test-recommender-throttle337: recommender is manual-only, randomly slow-spaced, '
      'hard-capped at 10 requests per run; all ranking verifications pass the shared '
      '1-wide / 20-per-minute / random-gap throttle, release 348')
