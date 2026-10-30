#!/usr/bin/env python3
"""Build 281 on-device recommender regression.

1. Executes the pure ranking core (AVDB/Services/Recommender.swift) and the store
   (RecommendationStore.swift) with a fixture source via swiftc: profile building, decay,
   quick-bail / rewatch, TF-IDF, SimClusters-style communities, TwHIN-style embeddings,
   sourcing plan, heavy-ranker scoring, filters, MMR + author diversity, reasons, groups,
   online LR feedback, cold start, storage caps, persistence, reset.
2. Static wiring checks for the app (UI entry points, ingest hook, pbxproj, version, privacy).
"""
import os, platform, plistlib, re, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / 'AVDB/Services'
core = (S / 'Recommender.swift').read_text()
store = (S / 'RecommendationStore.swift').read_text()
source = (S / 'RecommendationJavDBSource.swift').read_text()
view = (ROOT / 'AVDB/Views/User/RecommendationsView.swift').read_text()
user = (ROOT / 'AVDB/Views/User/UserView.swift').read_text()
detail = (ROOT / 'AVDB/Views/Detail/MovieDetailView.swift').read_text()
pbx = (ROOT / 'AVDB.xcodeproj/project.pbxproj').read_text()
plist = plistlib.loads((ROOT / 'AVDB/Resources/Info.plist').read_bytes())

# ---- privacy / locality: the ranking core is pure Foundation, nothing leaves the device
def code(t): return '\n'.join(l.split('//')[0] if not l.strip().startswith('//') else '' for l in t.splitlines())
for banned in ('URLSession', 'URLRequest', 'import SwiftUI', 'import UIKit', 'JavDBSDK', 'upload'):
    assert banned not in code(core), f'core must stay pure/local: {banned}'
assert 'URLSession' not in code(store) and 'upload' not in code(store).lower()
assert 'login' not in code(source).lower() and 'signIn' not in code(source), 'recommender must never prompt for login'
assert 'requestSpacing: Double { 1.0 }' in source, 'JavDB requests are spaced'
assert 'RecommendationLimits.requestBudget' in store and 'RecommendationLimits.detailBudget' in store
assert 'maxConsecutiveFailures' in store, 'network back-off'
assert 'Task.detached' in store, 'profile / ranking computed off the main thread'
assert 'capMetadata' in store and 'metadataCap = 1500' in store, 'capped storage'
assert '.cachesDirectory' in store, 'cache lives in Caches (purgeable)'

# ---- UI wiring
assert user.count('RecommendationSection()') == 2, 'recommendations in both 我的 layouts'
assert user.count('PlaybackHistorySection()') == 2 and user.count('FollowUpdatesSection()') == 2
assert 'RecommendationIngest.remember(movie)' in detail, 'detail payload feeds the recommender'
for ident in ('rec.feed', 'rec.hero', 'rec.prefs', 'rec.prefs.reset', 'rec.coldstart', 'rec.skeleton', 'rec.toast', 'me.rec.section'):
    assert f'"{ident}"' in view, ident
for text in ('为你推荐', '今日首选', '我的偏好', '不感兴趣', '少推该女优', '少推该标签', '重置推荐偏好', '.refreshable', 'contextMenu {', 'preview:',
             '@ScaledMetric', 'accessibilityReduceMotion', 'UIImpactFeedbackGenerator', '.blur('):
    assert text in view, text
assert 'Color(.systemGroupedBackground)' in view and 'Color(.secondarySystemGroupedBackground)' in view, 'dark-mode semantic colours'

# ---- project + version
for name in ('Recommender.swift', 'RecommendationStore.swift', 'RecommendationJavDBSource.swift', 'RecommendationsView.swift'):
    assert pbx.count(f'/* {name} in Sources */') == 2, name
    assert pbx.count(f'path = {name};') == 1, name
ids = re.findall(r'^\t\t([0-9A-Z]{24}) /\*', pbx, re.M)
assert len(ids) == len(set(ids)), 'duplicate pbxproj object ids'
assert plist['CFBundleVersion'] == '281'
assert pbx.count('CURRENT_PROJECT_VERSION = 281;') == 2

# ---- execute the core + store with swiftc
swiftc = shutil.which('swiftc')
if not swiftc:
    if os.environ.get('CI'):
        sys.exit('swiftc missing on CI')
    print('SKIP swift execution (no swiftc)')
else:
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        files = [td / 'Recommender.swift', td / 'RecommendationStore.swift', td / 'StoreRegression.swift', td / 'main.swift']
        files[0].write_text(core)
        st = store
        if platform.system() != 'Darwin':
            st = st.replace('import Combine\n', '')
            shim = td / 'CombineShim.swift'
            shim.write_text('import Foundation\nprotocol ObservableObject: AnyObject {}\n'
                            '@propertyWrapper struct Published<T> { var wrappedValue: T; init(wrappedValue: T) { self.wrappedValue = wrappedValue } }\n')
            files.append(shim)
        files[1].write_text(st)
        files[2].write_text((ROOT / 'scripts/RecommenderStoreRegression281.swift').read_text())
        files[3].write_text((ROOT / 'scripts/RecommenderRegression281.swift').read_text())
        exe = td / 'rec281'
        subprocess.run([swiftc, '-swift-version', '5', '-O', '-o', str(exe)] + [str(f) for f in files], check=True)
        r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=180)
        print(r.stdout, end='')
        if r.returncode != 0 or 'PASS recommender281 store' not in r.stdout:
            print(r.stderr); sys.exit('recommender281 swift regression failed')

print('PASS test-recommender281 wiring: local-only core, rate limits, off-main compute, capped cache, UI entry points, ingest hook, pbxproj, version 281')
